#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# install-samba.sh
# Despliega Samba de cero con un recurso compartido y permisos
# colaborativos para admins. Crea también /usr/local/sbin/samba-user.sh
# para gestionar usuarios de forma simple:
#   sudo samba-user.sh <usuario> <contraseña> <admin|user>
# ============================================================

RED(){ printf "\e[31m%s\e[0m\n" "$*"; }
YEL(){ printf "\e[33m%s\e[0m\n" "$*"; }
GRN(){ printf "\e[32m%s\e[0m\n" "$*"; }
die(){ RED "ERROR: $*"; exit 1; }

[[ $EUID -eq 0 ]] || die "Ejecutá como root (sudo)."

# ---------- Helpers de input ----------
ask_default () { # $1=prompt  $2=default
  local p="$1" d="$2" ans
  read -r -p "$p [$d]: " ans || true
  echo "${ans:-$d}"
}
ask_yes_no () { # $1=prompt  -> returns 0 (yes) / 1 (no)
  local p="$1" ans
  while true; do
    read -r -p "$p [s/N]: " ans || true
    case "${ans,,}" in
      s|si|sí|y|yes) return 0;;
      n|no|"") return 1;;
      *) echo "Responde s/N";;
    esac
  done
}

# ---------- Paquetes base ----------
GRN "Instalando paquetes base..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y samba samba-common-bin acl smbclient curl gnupg || die "No pude instalar Samba/ACL."

# ---------- Grupos de roles ----------
getent group sambadmins >/dev/null || { groupadd sambadmins; GRN "Grupo sambadmins creado."; }
getent group sambusers  >/dev/null || { groupadd sambusers;  GRN "Grupo sambusers creado.";  }

# ---------- Preguntas sobre el share ----------
SHARE_NAME="$(ask_default 'Nombre del recurso compartido' 'Compartida')"
SHARE_PATH_DEFAULT="/srv/samba/${SHARE_NAME}"
SHARE_PATH="$(ask_default 'Ruta absoluta de la carpeta a compartir' "$SHARE_PATH_DEFAULT")"

# Crear carpeta y permisos colaborativos (setgid + ACL de grupo)
mkdir -p "$SHARE_PATH"
chgrp -R sambusers "$SHARE_PATH"
chmod -R 2770 "$SHARE_PATH"     # setgid en carpetas + rwx para dueño/grupo
# ACL para asegurar rwx al grupo y como default en subcarpetas/archivos
setfacl -R  -m g:sambusers:rwx "$SHARE_PATH" || true
setfacl -R  -d -m g:sambusers:rwx "$SHARE_PATH" || true

# ---------- smb.conf ----------
timestamp="$(date +%F_%H%M%S)"
if [[ -f /etc/samba/smb.conf ]]; then
  cp -a /etc/samba/smb.conf "/etc/samba/smb.conf.bak.$timestamp"
  YEL "Respaldé /etc/samba/smb.conf en smb.conf.bak.$timestamp"
fi

cat > /etc/samba/smb.conf <<EOF
# ==========================
# /etc/samba/smb.conf
# Config simple con dos roles:
#  - sambadmins: lectura/escritura
#  - sambusers : solo lectura (a nivel Samba)
# y permisos de FS colaborativos para admins (0660/2770)
# ==========================

[global]
    workgroup = WORKGROUP
    server role = standalone server
    server string = %h Samba Server

    security = user
    map to guest = never
    passdb backend = tdbsam

    # Protocolos modernos
    server min protocol = SMB2_02
    client min protocol = SMB2
    ntlm auth = ntlmv2-only

    # Logging básico
    log file = /var/log/samba/log.%m
    max log size = 1000

    # Sin impresión
    load printers = no
    printing = bsd
    printcap name = /dev/null
    disable spoolss = yes

    # ACL estilo Windows
    vfs objects = acl_xattr
    map acl inherit = yes
    store dos attributes = yes

    usershare allow guests = no

[${SHARE_NAME}]
    path = ${SHARE_PATH}
    browseable = yes
    guest ok = no

    # Acceso limitado a los grupos designados
    valid users = @sambadmins, @sambusers

    # Política Samba: por defecto solo lectura...
    read only = yes
    # ...pero admins escriben:
    write list = @sambadmins

    # Colaboración: todo con grupo sambusers (admins también pertenecen a ese grupo)
    force group = sambusers

    # Permisos de creación forzados (FS colaborativo)
    create mask = 0660
    directory mask = 2770
    force create mode = 0660
    force directory mode = 2770

    inherit permissions = no
EOF

# Validación y arranque
testparm -s || die "testparm detectó errores en smb.conf."
systemctl enable --now smbd || true
systemctl restart smbd

GRN "Samba configurado. Recurso: [${SHARE_NAME}] → ${SHARE_PATH}"

# ---------- Script de usuarios ----------
GRN "Instalando /usr/local/sbin/samba-user.sh ..."
cat > /usr/local/sbin/samba-user.sh <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
# Uso:
#   sudo samba-user.sh <usuario> <contraseña> <admin|user>

err(){ echo -e "\e[31mERROR:\e[0m $*" >&2; exit 1; }
ok(){  echo -e "\e[32m$*\e[0m"; }
info(){ echo -e "\e[33m$*\e[0m"; }

[[ $EUID -eq 0 ]] || err "Ejecutá como root (sudo)."
USER_NAME="${1:-}"; USER_PASS="${2:-}"; ROLE="${3:-}"
[[ -n "${USER_NAME}" && -n "${USER_PASS}" && -n "${ROLE}" ]] || err "Uso: $0 <usuario> <contraseña> <admin|user>"
ROLE="$(echo "$ROLE" | tr '[:upper:]' '[:lower:]')"
[[ "$ROLE" == "admin" || "$ROLE" == "user" ]] || err "Rol inválido: $ROLE (usa admin|user)"

# Herramientas
if ! command -v smbpasswd >/dev/null 2>&1; then
  info "Instalando Samba..."
  apt-get update -y
  apt-get install -y samba samba-common-bin >/dev/null
fi

# Grupos
getent group sambadmins >/dev/null || groupadd sambadmins
getent group sambusers  >/dev/null || groupadd sambusers

# Usuario Linux (sin shell interactiva)
if id -u "$USER_NAME" >/dev/null 2>&1; then
  info "Usuario Linux '$USER_NAME' ya existe."
else
  useradd -m -s /usr/sbin/nologin "$USER_NAME" || err "No pude crear usuario Linux."
  ok "Usuario Linux '$USER_NAME' creado."
fi

# Grupos según rol
if [[ "$ROLE" == "admin" ]]; then
  usermod -aG sambadmins,sambusers "$USER_NAME"
  info "Grupos: sambadmins, sambusers."
else
  usermod -aG sambusers "$USER_NAME"
  info "Grupo: sambusers."
fi

# Alta/actualización en Samba (+ habilitar)
if pdbedit -L | cut -d: -f1 | grep -qx "$USER_NAME"; then
  printf '%s\n%s\n' "$USER_PASS" "$USER_PASS" | smbpasswd -s "$USER_NAME"         || err "Fallo al actualizar contraseña Samba."
  ok "Contraseña Samba actualizada."
else
  printf '%s\n%s\n' "$USER_PASS" "$USER_PASS" | smbpasswd -a -s "$USER_NAME"         || err "Fallo en alta Samba (-a)."
  smbpasswd -e "$USER_NAME" || err "No pude habilitar la cuenta Samba."
  ok "Usuario Samba creado y habilitado."
fi

# Resumen
id "$USER_NAME" || true
pdbedit -L | grep -E "^$USER_NAME:" >/dev/null && ok "Verificación OK en Samba." || err "No aparece en pdbedit -L."
EOS
chmod +x /usr/local/sbin/samba-user.sh

# ---------- Crear usuarios iniciales ----------
if ask_yes_no "¿Crear ahora un usuario ADMIN (lectura/escritura)?"; then
  read -r -p "Nombre de usuario admin: " UADMIN
  read -r -s -p "Contraseña: " PADMIN; echo
  /usr/local/sbin/samba-user.sh "$UADMIN" "$PADMIN" admin
fi

if ask_yes_no "¿Crear ahora un usuario BÁSICO (solo lectura)?"; then
  read -r -p "Nombre de usuario básico: " UUSER
  read -r -s -p "Contraseña: " PUSER; echo
  /usr/local/sbin/samba-user.sh "$UUSER" "$PUSER" user
fi

# ---------- WS-Discovery (opcional) ----------
if ask_yes_no "¿Instalar wsdd para que Windows te vea en la pestaña 'Red'?"; then
  apt-get install -y wsdd
  systemctl enable --now wsdd
  GRN "wsdd instalado y ejecutándose."
fi

# ---------- Webmin (opcional) ----------
if ask_yes_no "¿Instalar Webmin para administrar por web?"; then
  curl -fsSL https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh -o /tmp/webmin-setup-repo.sh
  sh /tmp/webmin-setup-repo.sh
  apt-get update -y
  apt-get install -y --install-recommends webmin
  systemctl status webmin --no-pager || true
  GRN "Webmin instalado. Acceso: https://IP_DEL_SERVIDOR:10000 (certificado autofirmado)."
fi

# ---------- UFW (opcional) ----------
if ask_yes_no "¿Configurar UFW (firewall) para SMB?"; then
  apt-get install -y ufw
  ufw allow OpenSSH
  if ask_yes_no "¿Permitir SMB SOLO desde una IP origen?"; then
    read -r -p "IP de origen permitida (ej. 1.2.3.4): " SRCIP
    [[ -n "$SRCIP" ]] || die "IP inválida."
    ufw allow from "$SRCIP" to any port 445 proto tcp
    ufw allow from "$SRCIP" to any port 139 proto tcp
  else
    ufw allow 445/tcp
    ufw allow 139/tcp
  fi
  ufw --force enable
  ufw status verbose
fi

# ---------- Info final ----------
IPV4="$(ip -4 addr show scope global up | sed -n 's/.* inet \([0-9.]\+\)\/.*/\1/p' | head -n1 || true)"
echo
GRN "¡Listo! Recurso \\${IPV4:-IP_DEL_SERVIDOR}\\${SHARE_NAME}"
echo "  Desde Windows (PowerShell):"
echo "    net use * \\\\${IPV4:-IP_DEL_SERVIDOR}\\${SHARE_NAME} /user:.\\USUARIO * /persistent:no"
echo
GRN "Para crear más usuarios:"
echo "  sudo samba-user.sh <usuario> <contraseña> <admin|user>"
echo
GRN "Probar desde el servidor:"
echo "  smbclient //localhost/${SHARE_NAME} -U USUARIO -m SMB3 -c 'ls'"
