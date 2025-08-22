\
    #!/usr/bin/env bash
    set -Eeuo pipefail

    command -v smbstatus >/dev/null 2>&1 || { echo "ERROR: smbstatus no encontrado. Instala samba-common-bin."; exit 1; }

    TMP1="$(mktemp)"; TMP2="$(mktemp)"
    trap 'rm -f "$TMP1" "$TMP2"' EXIT

    smbstatus      >"$TMP1" 2>/dev/null || true
    smbstatus -S   >"$TMP2" 2>/dev/null || true

    awk -v NOW="$(date +%s)" -v T1="$TMP1" -v T2="$TMP2" '
      function trim(s){ sub(/^[ \t\r\n]+/,"",s); sub(/[ \t\r\n]+$/,"",s); return s }
      function get_ip(s,   m){ if (match(s, /([0-9]{1,3}\.){3}[0-9]{1,3}/, m)) return m[0]; return "?" }
      function human_age(sec,   d,h,m){ if (sec<0) sec=0; d=int(sec/86400); sec%=86400; h=int(sec/3600); sec%=3600; m=int(sec/60);
                                        if (d>0) return d "d " h "h"; if (h>0) return h "h " m "m"; return m "m" }

      FNR==1 { mode = (FILENAME==T1 ? 1 : 2) }

      mode==1 {
        if ($0 ~ /^PID[ \t]+Username[ \t]+Group[ \t]+Machine/) { in1=1; next }
        if (in1 && $0 ~ /^-+/) { next }
        if (in1 && $0 ~ /^[[:space:]]*$/) { in1=0; next }
        if (in1) {
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

      mode==2 {
        if (!header_printed) { print "USER","IP","SHARE","CONNECTED_AT","AGE","PID","PROTO"; header_printed=1 }
        if ($0 ~ /^Service[ \t]+pid[ \t]+Machine[ \t]+Connected at/) { in2=1; next }
        if (in2 && $0 ~ /^-+/) { next }
        if (in2 && $0 ~ /^[[:space:]]*$/) { next }
        if (in2) {
          service=$1; pid=$2
          if (pid !~ /^[0-9]+$/) next
          connected=""
          for (i=4; i<=NF-2; i++) connected = connected (i==4?"":" ") $i
          connected=trim(connected)
          ip=get_ip($0)
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
