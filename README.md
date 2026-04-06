# 🧰 Samba QuickDeploy — *Debian/Ubuntu*  
**Comparte carpetas con Windows en minutos, con roles (admin/usuario), permisos colaborativos y scripts de gestión.**  
> ¡Listo para VPS “vírgenes” vía SSH! 🖥️⚡

---

## 📚 Índice
- [✨ Qué resuelve](#-qué-resuelve)
- [🗂️ Qué incluye](#️-qué-incluye)
- [🧩 Requisitos](#-requisitos)
- [🚀 Instalación rápida](#-instalación-rápida)
- [🛠️ Uso de los scripts](#️-uso-de-los-scripts)
  - [Crear/actualizar usuario (admin o user)](#crearactualizar-usuario-admin-o-user)
  - [Listar cuentas Samba + roles](#listar-cuentas-samba--roles)
  - [Eliminar usuario (con reconfirmación)](#eliminar-usuario-con-reconfirmación)
  - [Ver sesiones activas](#ver-sesiones-activas)
- [🪟 Conexión desde Windows](#-conexión-desde-windows)
- [🔐 Seguridad & buenas prácticas](#-seguridad--buenas-prácticas)
- [🧱 Modelo de permisos (cómo funciona)](#-modelo-de-permisos-cómo-funciona)
- [🩺 Troubleshooting](#-troubleshooting)
- [🧭 Opcional: Webmin & Descubrimiento en Red](#-opcional-webmin--descubrimiento-en-red)
- [🧽 Mantenimiento](#-mantenimiento)
- [🗑️ Desinstalación completa](#️-desinstalación-completa)
- [❓FAQ](#faq)
- [📄 Licencia](#-licencia)

---

## ✨ Qué resuelve
- ✅ **Instala y configura Samba** de cero en Debian/Ubuntu.  
- ✅ Define **dos roles simples**:  
  - **Admins (RW)** → leer y **escribir** en todo el recurso.  
  - **Usuarios (RO)** → **solo lectura**.  
- ✅ Aplica **permisos colaborativos** (setgid + ACL por defecto) para que *todo lo que se cree dentro* sea editable por los admins.  
- ✅ Incluye **scripts de gestión** ultra sencillos para crear/listar/borrar usuarios y ver sesiones activas.  
- ✅ Opcionales para mejorar UX: **Webmin** (admin web), **wsdd** (aparece en “Red”), **UFW** (firewall).  
- ✅ Política segura por defecto: **SMB2+** y **NTLMv2 only**.

---

## 🗂️ Qué incluye
```
install-samba.sh                # Instalador interactivo (core)
└─ instala en /usr/local/sbin:
   ├── samba-user.sh            # Crear/actualizar usuarios (admin|user)
   ├── samba-del-user.sh        # Eliminar usuarios (con reconfirmación)
   ├── samba-list-users.sh      # Listar cuentas Samba + rol + estado
   └── samba-active-users.sh    # Ver sesiones activas (user/IP/share/tiempo)
uninstall-samba.sh              # Rollback completo (desinstala todo)
```

---

## 🧩 Requisitos
- 🐧 Debian/Ubuntu con `sudo` y acceso SSH.  
- 🌐 Puertos **445/TCP** y **139/TCP** accesibles desde los clientes (o túnel VPN).  
- 🔐 Recomendado: **no** exponer SMB a Internet; usar **VPN** (WireGuard/Tailscale) o **firewall por IP**.

---

## 🚀 Instalación rápida
1) Copiá el repo/archivos y corré el instalador:
```bash
sudo bash install-samba.sh
```
2) Elegí:
- **Nombre del share** (p. ej. `Compartida`)  
- **Ruta** (p. ej. `/srv/samba/Compartida`)  
- Extras (Webmin, wsdd, UFW) si querés.

3) Al finalizar, verás el acceso sugerido:
```
\\IP_DEL_SERVIDOR\NOMBRE_DEL_SHARE
```

---

## 🛠️ Uso de los scripts

### Crear/actualizar usuario (admin o user)
```bash
sudo samba-user.sh <usuario> <contraseña> <admin|user>

# Ejemplos:
sudo samba-user.sh adminagus 'MiPass#Fuerte' admin   # rol admin (RW)
sudo samba-user.sh juan      'OtraPass$'     user    # rol user (RO)
```
- Crea usuario **Linux** sin shell (seguro), lo agrega a grupos, lo **da de alta en Samba** y **habilita** la cuenta.
- Si existe, **actualiza la contraseña** y el **rol**.

### Listar cuentas Samba + roles
```bash
sudo samba-list-users.sh
```
Salida ejemplo:
```
USER                 ROLE     STATE      GROUPS
-------------------- -------- ---------- ----------------------------------------
adminagus            admin    enabled    adminagus,sambadmins,sambusers
z202                 user     enabled    z202,sambusers
user1                user     disabled   user1,sambusers
```
- **ROLE** depende de pertenencia al grupo `sambadmins`.  
- **STATE** se lee de *Account Flags* (si contiene `D` → deshabilitada).

### Eliminar usuario (con reconfirmación)
```bash
sudo samba-del-user.sh <usuario>
```
- Muestra sesiones activas si las hay (y pregunta si continuar).  
- Borra cuenta Samba y **opcionalmente** el usuario Linux (con o sin `home`).

### Ver sesiones activas
```bash
sudo samba-active-users.sh
```
Salida ejemplo:
```
USER    IP            SHARE       CONNECTED_AT                  AGE   PID    PROTO
admin1  192.168.1.20  Compartida  Fri Aug 22 02:59:48 2025     12m   12345  SMB3_11
```

---

## 🪟 Conexión desde Windows
**PowerShell (Administrador):**
```powershell
# Limpia conexiones previas
net use * /delete /y

# Mapea el share (usuario local del servidor Samba)
cmd /c "net use * \\IP_DEL_SERVIDOR\Compartida /user:.\adminagus * /persistent:no"
```
> Usa la **contraseña Samba** (la que seteaste con los scripts).

Si estás en Windows 11 (24H2) y ves “**NTLM deshabilitada**”:
- El servidor ya exige **NTLMv2** (seguro). Si el cliente bloquea NTLM saliente:
  - En **secpol.msc** → *Opciones de seguridad*:
    - “**Restrict NTLM: Outgoing NTLM traffic to remote servers**” → *Allow all*/*Audit* o agrega excepción para tu IP/host.
    - “**LAN Manager authentication level**” → *Send NTLMv2 response only. Refuse LM & NTLM* (recomendado).

---

## 🔐 Seguridad & buenas prácticas
- ✅ **SMB2+** y **NTLMv2 only** por defecto.  
- ✅ **Sin** guest/SMB1.  
- 🧱 **UFW** (opcional en el instalador): permitir 445/139 solo a IPs específicas.  
- 🛡️ **VPN** (WireGuard/Tailscale) para accesos remotos.  
- 🧾 Rotar contraseñas de admins; usar frases robustas.  
- 🧰 Logs: `sudo journalctl -u smbd -f` y `sudo smbstatus`.

---

## 🧱 Modelo de permisos (cómo funciona)
- Grupos:
  - `sambadmins` → **admins** (RW por Samba).
  - `sambusers` → **todos** (admins también pertenecen aquí).
- En el share:
  - `write list = @sambadmins` → solo admins escriben (Samba).
  - `force group = sambusers` → todo queda con grupo `sambusers`.
  - Máscaras y modo forzado:
    - `create mask = 0660`
    - `directory mask = 2770` (**setgid**)
    - `force create mode = 0660`
    - `force directory mode = 2770`
- **ACL por defecto** en la carpeta del share:
  - `setfacl -d -m g:sambusers:rwx /ruta/del/share`  
  - Resultado: lo que cree cualquier admin queda **editable** por los demás admins (colaboración real en subcarpetas).

---

## 🩺 Troubleshooting
**Cheat-sheet de diagnóstico:**
```bash
testparm -s                         # valida smb.conf
sudo systemctl status smbd          # estado del servicio
sudo journalctl -u smbd -f          # logs en vivo
sudo smbstatus                      # sesiones/archivos abiertos
sudo smbclient //localhost/SHARE -U usuario -m SMB3 -c 'ls'   # prueba local
```

**Problemas típicos:**

- **“NT_STATUS_ACCESS_DENIED” al subir/editar**  
  - Asegurá que el usuario sea **admin**: `id -nG usuario | grep sambadmins`  
  - Verificá permisos/ACL:
    ```bash
    sudo chgrp -R sambusers /ruta/del/share
    sudo chmod -R 2770 /ruta/del/share
    sudo setfacl -R  -m g:sambusers:rwx /ruta/del/share
    sudo setfacl -R  -d -m g:sambusers:rwx /ruta/del/share
    sudo systemctl restart smbd
    ```
- **Windows no conecta**  
  - Limpiar sesiones: `net use * /delete /y`  
  - Probar reachability: `Test-NetConnection IP -Port 445`  
  - Mapear así: `\\IP\Compartida` con `/user:.\usuario`  
  - Revisar firewall/ISP/VPN si el puerto 445 no llega.
- **“NTLM deshabilitada” (Win11/24H2)**  
  - El server ya usa **NTLMv2**; permití **NTLM saliente** o agregá **excepción** en el cliente.
- **Errores de config**  
  - `testparm -s` muestra la línea exacta. Restaurá backup `smb.conf.bak.*` si hace falta.

---

## 🧭 Opcional: Webmin & Descubrimiento en Red
- **Webmin** (admin por web) → opcional en el instalador:  
  `https://IP_DEL_SERVIDOR:10000` (certificado autofirmado).  
- **wsdd** (Windows “Red”) → opcional; hace que el server aparezca descubierto en entornos Windows modernos.

---

## 🧽 Mantenimiento
- **Crear/rotar** contraseñas y roles:  
  `sudo samba-user.sh <usuario> <nueva-pass> <admin|user>`
- **Listar** cuentas + roles:  
  `sudo samba-list-users.sh`
- **Eliminar** cuentas (con reconfirmación):  
  `sudo samba-del-user.sh <usuario>`
- **Sesiones activas** (para ver quién está conectado):  
  `sudo samba-active-users.sh`

---

## 🗑️ Desinstalación completa

Para hacer un rollback total de todo lo que instaló `install-samba.sh` (Samba, paquetes, scripts, grupos, datos):

```bash
sudo bash uninstall-samba.sh
```

El script pedirá que escribas `CONFIRMAR` antes de hacer cualquier cosa destructiva. Luego:
1. Detiene y deshabilita servicios (`smbd`, `nmbd`, `winbind`, `wsdd`, `wsdd2`)
2. Elimina todas las cuentas Samba (`pdbedit -x`)
3. Desinstala paquetes con `apt purge`
4. Elimina directorios de Samba (`/etc/samba`, `/var/lib/samba`, `/var/log/samba`, etc.)
5. Elimina los scripts de gestión de `/usr/local/sbin/`
6. Elimina los grupos `sambadmins` y `sambusers`
7. Pregunta si eliminar `/srv/samba` (la carpeta compartida)
8. Pregunta si eliminar usuarios Linux creados durante la instalación

Al finalizar, el sistema queda limpio y listo para volver a correr `install-samba.sh` de cero.

---

## ❓FAQ
**¿Puedo tener más de un share?**  
Sí. Repetí el patrón de la sección `[SHARE]` en `/etc/samba/smb.conf` y replicá los mismos permisos (grupo `sambusers`, `setfacl`, `2770`, etc.). Reiniciá `smbd`.

**¿Puedo dar escritura a un usuario “RO” puntual?**  
Añadilo a `sambadmins` (global RW) o creá otro share con `write list = usuario`.

**¿Por qué forzar NTLMv2 y SMB2+?**  
Por seguridad y compatibilidad con Windows actuales.

**¿Es seguro exponer SMB a Internet?**  
No recomendado. Preferí **VPN** o **restricción por IP** con UFW.

---

## 📄 Licencia
**MIT** — hacé lo que necesites, con cariño y responsabilidad. 💛

---

### 🏁 Resumen ejecutivo (copiar y pegar)
```bash
# 1) Instalar
sudo bash install-samba.sh

# 2) Crear usuarios
sudo samba-user.sh admin 'Pass#Fuerte' admin
sudo samba-user.sh juan  'abc123'      user

# 3) Windows (PowerShell Admin)
net use * /delete /y
cmd /c "net use * \\IP_DEL_SERVIDOR\Compartida /user:.\admin * /persistent:no"

# 4) Diagnóstico
testparm -s
sudo smbstatus
sudo journalctl -u smbd -f
```
