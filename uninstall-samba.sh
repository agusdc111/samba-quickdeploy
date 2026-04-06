#!/usr/bin/env bash
# =============================================================
# uninstall-samba.sh  —  Rollback completo de install-samba.sh
# Ejecutar como root: sudo bash uninstall-samba.sh
# =============================================================
set -euo pipefail

RED(){ printf "\e[31m%s\e[0m\n" "$*"; }
YEL(){ printf "\e[33m%s\e[0m\n" "$*"; }
GRN(){ printf "\e[32m%s\e[0m\n" "$*"; }

[[ $EUID -eq 0 ]] || { RED "Ejecutá como root (sudo)."; exit 1; }

echo
YEL "=========================================="
YEL "  ROLLBACK COMPLETO DE SAMBA-QUICKDEPLOY"
YEL "=========================================="
echo
RED "ATENCIÓN: Esto eliminará Samba, todos los usuarios Samba,"
RED "grupos sambadmins/sambusers, y los scripts instalados."
echo
read -r -p "¿Confirmás que querés borrar TODO? Escribí CONFIRMAR: " CONF
[[ "$CONF" == "CONFIRMAR" ]] || { YEL "Abortado."; exit 0; }
echo

# ---------- 1. Detener servicios ----------
GRN "[1/8] Deteniendo servicios..."
for svc in smbd nmbd winbind wsdd wsdd2; do
  systemctl stop    "$svc" 2>/dev/null || true
  systemctl disable "$svc" 2>/dev/null || true
done

# ---------- 2. Eliminar usuarios Samba ----------
GRN "[2/8] Eliminando usuarios Samba..."
if command -v pdbedit >/dev/null 2>&1; then
  SAMBA_USERS=$(pdbedit -L 2>/dev/null | cut -d: -f1 || true)
  for U in $SAMBA_USERS; do
    smbpasswd -d "$U" 2>/dev/null || true
    pdbedit -x -u "$U" 2>/dev/null && YEL "  Cuenta Samba eliminada: $U" || true
  done
fi

# ---------- 3. Desinstalar paquetes ----------
GRN "[3/8] Desinstalando paquetes..."
DEBIAN_FRONTEND=noninteractive apt-get purge -y \
  samba samba-common samba-common-bin samba-libs \
  smbclient wsdd wsdd2 webmin gawk 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
apt-get autoclean  -y 2>/dev/null || true

# ---------- 4. Eliminar archivos de configuración y datos ----------
GRN "[4/8] Eliminando configuración y datos de Samba..."
rm -rf /etc/samba
rm -rf /var/lib/samba
rm -rf /var/log/samba
rm -rf /var/cache/samba
rm -rf /run/samba

# ---------- 5. Eliminar scripts instalados ----------
GRN "[5/8] Eliminando scripts de gestión..."
for f in samba-user.sh samba-del-user.sh samba-list-users.sh samba-active-users.sh; do
  rm -f "/usr/local/sbin/$f" && YEL "  Eliminado: /usr/local/sbin/$f" || true
done

# ---------- 6. Eliminar grupos ----------
GRN "[6/8] Eliminando grupos sambadmins y sambusers..."
groupdel sambadmins 2>/dev/null && YEL "  Grupo sambadmins eliminado." || true
groupdel sambusers  2>/dev/null && YEL "  Grupo sambusers eliminado."  || true

# ---------- 7. Eliminar carpeta compartida (opcional) ----------
GRN "[7/8] Carpeta compartida..."
echo
read -r -p "¿Eliminar también la carpeta compartida /srv/samba? [s/N]: " DEL_SHARE
if [[ "${DEL_SHARE,,}" =~ ^(s|si|sí|y|yes)$ ]]; then
  rm -rf /srv/samba && GRN "  /srv/samba eliminado." || true
else
  YEL "  /srv/samba conservado."
fi

# ---------- 8. Eliminar usuarios Linux creados por el instalador (opcional) ----------
GRN "[8/8] Usuarios Linux..."
echo
read -r -p "¿Querés eliminar usuarios Linux que hayas creado con el instalador? [s/N]: " DEL_USERS
if [[ "${DEL_USERS,,}" =~ ^(s|si|sí|y|yes)$ ]]; then
  read -r -p "Ingresá los nombres separados por espacio (ej: agusadmin maria): " -a USER_LIST
  for U in "${USER_LIST[@]}"; do
    if id -u "$U" >/dev/null 2>&1; then
      read -r -p "  ¿Eliminar HOME de '$U' también? [s/N]: " DEL_HOME
      if [[ "${DEL_HOME,,}" =~ ^(s|si|sí|y|yes)$ ]]; then
        userdel -r "$U" 2>/dev/null && YEL "  Usuario '$U' y HOME eliminados." || true
      else
        userdel "$U" 2>/dev/null && YEL "  Usuario '$U' eliminado (HOME conservado)." || true
      fi
    else
      YEL "  Usuario '$U' no existe, omitiendo."
    fi
  done
fi

echo
GRN "=========================================="
GRN "  Rollback completo. Sistema limpio."
GRN "  Podés volver a correr install-samba.sh."
GRN "=========================================="
