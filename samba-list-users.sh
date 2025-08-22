\
    #!/usr/bin/env bash
    set -Eeuo pipefail
    # Lista usuarios de Samba y rol (admin/user) + estado + grupos POSIX.

    ADM_GROUP="sambadmins"
    USR_GROUP="sambusers"

    err(){ echo "ERROR: $*" >&2; exit 1; }

    command -v pdbedit >/dev/null 2>&1 || err "pdbedit no encontrado. Instalá: sudo apt install -y samba-common-bin"
    command -v id >/dev/null 2>&1 || err "'id' no encontrado."

    mapfile -t USERS < <(pdbedit -L 2>/dev/null | cut -d: -f1 | sort)

    if [[ ${#USERS[@]} -eq 0 ]]; then
      echo "No hay cuentas Samba en la base (pdbedit -L vacío)."
      exit 0
    fi

    printf "%-20s %-8s %-10s %s\n" "USER" "ROLE" "STATE" "GROUPS"
    printf "%-20s %-8s %-10s %s\n" "--------------------" "--------" "----------" "----------------------------------------"

    for U in "${USERS[@]}"; do
      FLAGS="$(pdbedit -u "$U" -v 2>/dev/null | awk -F'[][]' '/Account Flags/ {print $2; exit}')"
      STATE="enabled"
      [[ "$FLAGS" == *D* ]] && STATE="disabled"

      if id -nG "$U" >/dev/null 2>&1; then
        GRPS="$(id -nG "$U" | tr ' ' ',')"
      else
        GRPS="(sin usuario POSIX)"
      fi

      ROLE="user"
      if id -nG "$U" 2>/dev/null | tr ' ' '\n' | grep -qx "$ADM_GROUP"; then
        ROLE="admin"
      fi

      printf "%-20s %-8s %-10s %s\n" "$U" "$ROLE" "$STATE" "$GRPS"
    done
