# Samba QuickDeploy (Debian/Ubuntu)

**Despliegue express de Samba** con un recurso compartido, dos roles de acceso (admins RW / usuarios RO), permisos colaborativos, script simple para creación de usuarios y extras opcionales (Webmin, wsdd, UFW).

---

## 🚀 Qué incluye
- `install-samba.sh`: instalador interactivo que:
  - Instala paquetes requeridos (Samba, ACL, smbclient).
  - Crea grupos `sambadmins` (RW) y `sambusers` (RO).
  - Pide **nombre** y **ruta** del recurso compartido.
  - Configura **permisos colaborativos** (setgid + ACL por defecto).
  - Genera `smb.conf` con `ntlm auth = ntlmv2-only` y SMB2+.
  - Crea el helper `samba-user.sh` para **crear usuarios** con:
    ```bash
    sudo samba-user.sh <usuario> <contraseña> <admin|user>
    ```
  - (Opcional) Crea usuarios iniciales.
  - (Opcional) Instala **wsdd** (descubrimiento en “Red” de Windows).
  - (Opcional) Instala **Webmin** para administrar por web.
  - (Opcional) Configura **UFW** (permitir 445/139, con opción de restringir por IP).
- `enable-ntlmv2-only.sh`: corrige configuraciones que bloqueen autenticación estableciendo **solo NTLMv2** y reinicia `smbd`.

---

## 🧩 Requisitos
- Debian/Ubuntu con `sudo`.
- Acceso SSH.
- **Recomendado**: restringir SMB por firewall o usar **VPN** (WireGuard/Tailscale) si accedés desde Internet.

---

## 🛠️ Instalación y uso
1. Ejecutá el instalador:
   ```bash
   sudo bash install-samba.sh
   ```
   Seguí los prompts (nombre del share, ruta, extras).
2. Creá usuarios cuando quieras:
   ```bash
   sudo samba-user.sh admin 'MiPassFuerte#' admin   # RW
   sudo samba-user.sh juan  'OtraPass$'   user     # RO
   ```
3. Conectar desde Windows (PowerShell como admin):
   ```powershell
   net use * /delete /y
   cmd /c "net use * \\IP_DEL_SERVIDOR\NOMBRE_DEL_SHARE /user:.\admin * /persistent:no"
   ```

---

## 🔐 Seguridad y permisos
- El share fuerza **grupo `sambusers`** y máscaras `0660/2770` con **setgid** y **ACL por defecto** → todos los admins pueden editar en cualquier subcarpeta.
- Samba permite **solo NTLMv2** (`ntlm auth = ntlmv2-only`) y **SMB2+**.
- Considerá:
  - Restringir 445/139 con **UFW** (por IP de origen).
  - Usar **VPN** si estás fuera de la LAN.
  - Deshabilitar SMB1 en clientes legados.

---

## 🩺 Troubleshooting rápido
- **Windows pide credenciales y no entra**:
  - Limpiá sesiones: `net use * /delete /y`.
  - Forzá usuario local: `\IP\SHARE` con `/user:.\usuario`.
  - Verificá reachability: `Test-NetConnection IP -Port 445`.
- **“NTLM deshabilitada”** (Win11/24H2): ejecutá en el server
  ```bash
  sudo bash enable-ntlmv2-only.sh
  ```
  y en Windows permití NTLM **saliente** o agregá excepción hacia tu IP/host.
- **Admins no pueden editar en subcarpetas**: asegurate de haber creado el share con este instalador o aplicar:
  ```bash
  sudo chgrp -R sambusers /ruta/del/share
  sudo chmod -R 2770 /ruta/del/share
  sudo setfacl -R  -m g:sambusers:rwx /ruta/del/share
  sudo setfacl -R  -d -m g:sambusers:rwx /ruta/del/share
  sudo systemctl restart smbd
  ```

---

## 📄 Licencia
MIT
