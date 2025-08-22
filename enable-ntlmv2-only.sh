#!/usr/bin/env bash
set -Eeuo pipefail

CONF="/etc/samba/smb.conf"
BACK="/etc/samba/smb.conf.bak.$(date +%F_%H%M%S)"

err(){ echo -e "\e[31mERROR:\e[0m $*" >&2; exit 1; }
ok(){  echo -e "\e[32m$*\e[0m"; }
info(){ echo -e "\e[33m$*\e[0m"; }

[[ $EUID -eq 0 ]] || err "Ejecutá como root (sudo)."

# 1) Backup o base mínima
if [[ -f "$CONF" ]]; then
  cp -a "$CONF" "$BACK"
  info "Backup creado: $BACK"
else
  printf "[global]\n" > "$CONF"
  info "Creado $CONF con sección [global] mínima."
fi

# 2) Normalizar saltos de línea (evita CRLF)
sed -i 's/\r$//' "$CONF"

# 3) Asegurar que existe [global]
grep -q '^\[global\]' "$CONF" || printf "\n[global]\n" >> "$CONF"

# 4) Quitar líneas previas de ntlm auth (si las hubiera)
sed -i '/^[[:space:]]*ntlm[[:space:]]\+auth[[:space:]]*=.*/Id' "$CONF"

# 5) Insertar "ntlm auth = ntlmv2-only" inmediatamente después de la primera [global]
awk '
  BEGIN{inserted=0}
  /^\[global\]/{print; if(!inserted){print "    ntlm auth = ntlmv2-only"; inserted=1; next}}
  {print}
  END{if(!inserted){print "[global]"; print "    ntlm auth = ntlmv2-only"}}
' "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"

# 6) Validar y aplicar
if ! testparm -s >/dev/null; then
  cp -a "$BACK" "$CONF"
  err "testparm detectó errores; restaurado $BACK"
fi

testparm -sv | grep -i 'ntlm auth' || true
systemctl restart smbd
ok "Aplicado: 'ntlm auth = ntlmv2-only' y smbd reiniciado."
