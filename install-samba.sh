#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# install-samba.sh
# Despliega Samba de cero con un recurso compartido y permisos
# colaborativos para admins. Instala scripts de gestión:
#   - /usr/local/sbin/samba-user.sh         (crear/actualizar usuarios)
#   - /usr/local/sbin/samba-del-user.sh     (eliminar usuarios)
#   - /usr/local/sbin/samba-list-users.sh   (listar usuarios y roles)
#   - /usr/local/sbin/samba-active-users.sh (sesiones activas)
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

# ---------- Script: crear/actualizar usuarios ----------
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
  printf '%s\n%s\n' "$USER_PASS" "$USER_PASS" | smbpasswd -s "$USER_NAME" || err "Fallo al actualizar contraseña Samba."
  ok "Contraseña Samba actualizada."
else
  printf '%s\n%s\n' "$USER_PASS" "$USER_PASS" | smbpasswd -a -s "$USER_NAME" || err "Fallo en alta Samba (-a)."
  smbpasswd -e "$USER_NAME" || err "No pude habilitar la cuenta Samba."
  ok "Usuario Samba creado y habilitado."
fi

# Resumen
id "$USER_NAME" || true
pdbedit -L | grep -E "^$USER_NAME:" >/dev/null && ok "Verificación OK en Samba." || err "No aparece en pdbedit -L."
EOS
chmod +x /usr/local/sbin/samba-user.sh

# ---------- Script: eliminar usuarios ----------
GRN "Instalando /usr/local/sbin/samba-del-user.sh ..."
cat > /usr/local/sbin/samba-del-user.sh <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail

# Elimina un usuario de Samba y, opcionalmente, del sistema Linux.
# - Pide reconfirmación escribiendo el nombre exacto del usuario.
# - Advierte si hay sesiones SMB activas (usa smbstatus si está disponible).
# Uso:
#   sudo samba-del-user.sh <usuario>
#   (si se omite, lo pide interactivo)

err(){ echo -e "\e[31mERROR:\e[0m $*" >&2; exit 1; }
ok(){  echo -e "\e[32m$*\e[0m"; }
info(){ echo -e "\e[33m$*\e[0m"; }

[[ $EUID -eq 0 ]] || err "Ejecutá como root (sudo)."

USER_NAME="${1:-}"
if [[ -z "${USER_NAME}" ]]; then
  read -r -p "Usuario a eliminar: " USER_NAME
fi

# Sanidad básica
if ! [[ "$USER_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  err "Nombre de usuario inválido: '$USER_NAME'"
fi

echo
info "Vas a eliminar al usuario: $USER_NAME"
read -r -p "Para confirmar, escribí EXACTAMENTE el nombre del usuario: " CONFIRM
[[ "$CONFIRM" == "$USER_NAME" ]] || err "No coincide la confirmación. Abortado."
echo

# Avisar si hay sesiones activas (si smbstatus existe)
if command -v smbstatus >/dev/null 2>&1; then
  ACTIVE="$(LC_ALL=C smbstatus 2>/dev/null | awk -v u="$USER_NAME" '
    $0 ~ /^PID[[:space:]]+Username[[:space:]]+Group[[:space:]]+Machine/ {in=1; next}
    in && NF==0 {in=0}
    in && $2==u {print; found=1}
    END{ if(found) exit 0; else exit 1 }
  ')" || true

  if [[ -n "${ACTIVE:-}" ]]; then
    info "Se detectaron sesiones SMB activas de '$USER_NAME':"
    echo "$ACTIVE" | sed 's/^/  /'
    read -r -p "¿Continuar de todas formas? [s/N]: " ans
    case "${ans,,}" in
      s|si|sí|y|yes) : ;;
      *) err "Abortado por sesiones activas." ;;
    esac
  fi
fi

# 1) Eliminar de Samba si existe
if command -v pdbedit >/dev/null 2>&1 && pdbedit -L | cut -d: -f1 | grep -qx "$USER_NAME"; then
  info "Eliminando cuenta Samba de '$USER_NAME'..."
  smbpasswd -d "$USER_NAME" >/dev/null 2>&1 || true
  if pdbedit -x -u "$USER_NAME"; then
    ok "Cuenta Samba eliminada."
  else
    err "No pude eliminar la cuenta Samba (pdbedit -x)."
  fi
else
  info "No se encontró cuenta Samba de '$USER_NAME' (pdbedit -L)."
fi

# 2) Quitar de grupos si existe usuario POSIX
if id -u "$USER_NAME" >/dev/null 2>&1; then
  info "Quitando de grupos sambadmins/sambusers (si corresponde)..."
  gpasswd -d "$USER_NAME" sambadmins >/dev/null 2>&1 || true
  gpasswd -d "$USER_NAME" sambusers  >/dev/null 2>&1 || true
fi

# 3) ¿Eliminar usuario de Linux?
if id -u "$USER_NAME" >/dev/null 2>&1; then
  echo
  read -r -p "¿Eliminar también el usuario de Linux '$USER_NAME'? [s/N]: " delsys
  case "${delsys,,}" in
    s|si|sí|y|yes)
      read -r -p "¿Eliminar TAMBIÉN su directorio HOME y correos? (userdel -r) [s/N]: " delhome
      if [[ "${delhome,,}" =~ ^(s|si|sí|y|yes)$ ]]; then
        if command -v userdel >/dev/null 2>&1; then
          userdel -r "$USER_NAME" 2>/dev/null || true
        else
          deluser --remove-home "$USER_NAME" 2>/dev/null || true
        fi
        ok "Usuario de Linux y HOME eliminados."
      else
        if command -v userdel >/dev/null 2>&1; then
          userdel "$USER_NAME" 2>/dev/null || true
        else
          deluser "$USER_NAME" 2>/dev/null || true
        fi
        ok "Usuario de Linux eliminado (HOME conservado)."
      fi
      ;;
    *) info "Conservado el usuario de Linux." ;;
  esac
else
  info "No existe usuario de Linux '$USER_NAME' (solo Samba, si existía)."
fi

echo
ok "Listo. '$USER_NAME' eliminado de Samba y ajustes aplicados."
EOS
chmod +x /usr/local/sbin/samba-del-user.sh

# ---------- Script: listar usuarios y roles ----------
GRN "Instalando /usr/local/sbin/samba-list-users.sh ..."
cat > /usr/local/sbin/samba-list-users.sh <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail

# Lista usuarios de Samba y su rol (admin/user) según pertenencia a sambadmins.
# También muestra si la cuenta Samba está habilitada (flags) y grupos POSIX.
# Requiere: samba-common-bin (pdbedit), coreutils, awk

ADM_GROUP="sambadmins"
USR_GROUP="sambusers"

err(){ echo "ERROR: $*" >&2; exit 1; }

command -v pdbedit >/dev/null 2>&1 || err "pdbedit no encontrado. Instalá: sudo apt install -y samba-common-bin"
command -v id >/dev/null 2>&1 || err "'id' no encontrado."

# Obtener lista de cuentas Samba (nombres)
mapfile -t USERS < <(pdbedit -L 2>/dev/null | cut -d: -f1 | sort)

if [[ ${#USERS[@]} -eq 0 ]]; then
  echo "No hay cuentas Samba en la base (pdbedit -L vacío)."
  exit 0
fi

printf "%-20s %-8s %-10s %s\n" "USER" "ROLE" "STATE" "GROUPS"
printf "%-20s %-8s %-10s %s\n" "--------------------" "--------" "----------" "----------------------------------------"

for U in "${USERS[@]}"; do
  # Flags de la cuenta Samba (para ver si está deshabilitada)
  FLAGS="$(pdbedit -u "$U" -v 2>/dev/null | awk -F'[][]' '/Account Flags/ {print $2; exit}')"
  STATE="enabled"
  [[ "$FLAGS" == *D* ]] && STATE="disabled"

  # Grupos POSIX (puede no existir el usuario del sistema si la cuenta fue importada a mano)
  if id -nG "$U" >/dev/null 2>&1; then
    GRPS="$(id -nG "$U" | tr ' ' ',')"
  else
    GRPS="(sin usuario POSIX)"
  fi

  # Rol: admin si pertenece a sambadmins; si no, "user"
  ROLE="user"
  if id -nG "$U" 2>/dev/null | tr ' ' '\n' | grep -qx "$ADM_GROUP"; then
    ROLE="admin"
  fi

  printf "%-20s %-8s %-10s %s\n" "$U" "$ROLE" "$STATE" "$GRPS"
done
EOS
chmod +x /usr/local/sbin/samba-list-users.sh

# ---------- Script: sesiones activas ----------
GRN "Instalando /usr/local/sbin/samba-active-users.sh ..."
cat > /usr/local/sbin/samba-active-users.sh <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail

# Muestra sesiones activas de Samba en una línea:
# USER | IP | SHARE | CONNECTED_AT | AGE | PID | PROTO
# Requiere: smbstatus (samba-common-bin), awk, date (GNU coreutils)

command -v smbstatus >/dev/null 2>&1 || { echo "ERROR: smbstatus no encontrado. Instala samba-common-bin."; exit 1; }

TMP1="$(mktemp)"; TMP2="$(mktemp)"
trap 'rm -f "$TMP1" "$TMP2"' EXIT

# Capturamos:
# - "smbstatus" (sesiones con PID/Username/Group/Machine/Protocol/Encryption/Signing)
# - "smbstatus -S" (shares con Service/PID/Machine/Connected at/Encryption/Signing)
smbstatus      >"$TMP1" 2>/dev/null || true
smbstatus -S   >"$TMP2" 2>/dev/null || true

awk -v NOW="$(date +%s)" -v T1="$TMP1" -v T2="$TMP2" '
  function trim(s){ sub(/^[ \t\r\n]+/,"",s); sub(/[ \t\r\n]+$/,"",s); return s }
  function get_ip(s,   m){ if (match(s, /([0-9]{1,3}\.){3}[0-9]{1,3}/, m)) return m[0]; return "?" }
  function human_age(sec,   d,h,m){ if (sec<0) sec=0; d=int(sec/86400); sec%=86400; h=int(sec/3600); sec%=3600; m=int(sec/60);
                                    if (d>0) return d "d " h "h"; if (h>0) return h "h " m "m"; return m "m" }

  FNR==1 { mode = (FILENAME==T1 ? 1 : 2) }

  # --------- PASO 1: sesiones (T1) -> mapear PID -> user, ip, proto
  mode==1 {
    if ($0 ~ /^PID[ \t]+Username[ \t]+Group[ \t]+Machine/) { in1=1; next }
    if (in1 && $0 ~ /^-+/) { next }
    if (in1 && $0 ~ /^[[:space:]]*$/) { in1=0; next }
    if (in1) {
      # Ejemplo: "12345  admin  sambusers  host (ipv4:1.2.3.4:54022)  SMB3_11  -  -"
      pid=$1; user=$2; ip=get_ip($0)
      proto=""; if (match($0, /(SMB[0-9]_[0-9]+)/, mm)) proto=mm[1]
      if (pid ~ /^[0-9]+$/) {
        user_by_pid[pid]=user
        ip_by_pid[pid]=ip
        proto_by_pid[pid]=proto
      }
    }
    next
  }

  # --------- PASO 2: shares (T2) -> imprimir juntando por PID
  mode==2 {
    if (!header_printed) { print "USER","IP","SHARE","CONNECTED_AT","AGE","PID","PROTO"; header_printed=1 }
    if ($0 ~ /^Service[ \t]+pid[ \t]+Machine[ \t]+Connected at/) { in2=1; next }
    if (in2 && $0 ~ /^-+/) { next }
    if (in2 && $0 ~ /^[[:space:]]*$/) { next }
    if (in2) {
      service=$1; pid=$2
      if (pid !~ /^[0-9]+$/) next

      # Connected at: campos 4..NF-2 (los 2 últimos son Encryption/Signing)
      connected=""
      for (i=4; i<=NF-2; i++) connected = connected (i==4?"":" ") $i
      connected=trim(connected)

      ip=get_ip($0)

      # Edad
      ts=""; cmd="date -d \"" connected "\" +%s 2>/dev/null"
      cmd | getline ts; close(cmd)
      age=(ts ~ /^[0-9]+$/) ? human_age(NOW - ts) : "?"

      user=(pid in user_by_pid)? user_by_pid[pid] : "?"
      proto=(pid in proto_by_pid)? proto_by_pid[pid] : ""

      print user, ip, service, connected, age, pid, proto
      any=1
    }
    next
  }

  END{
    if (!any) print "—","—","—","No hay sesiones activas","—","—","—"
  }
' "$TMP1" "$TMP2"
EOS
chmod +x /usr/local/sbin/samba-active-users.sh

# ---------- Usuarios iniciales (opcionales) ----------
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
GRN "Comandos útiles:"
echo "  sudo samba-user.sh <usuario> <contraseña> <admin|user>     # crear/actualizar usuario"
echo "  sudo samba-del-user.sh <usuario>                           # eliminar usuario"
echo "  sudo samba-list-users.sh                                   # listar usuarios y roles"
echo "  sudo samba-active-users.sh                                 # ver sesiones activas"
echo
GRN "Probar desde el servidor:"
echo "  smbclient //localhost/${SHARE_NAME} -U USUARIO -m SMB3 -c 'ls'"
