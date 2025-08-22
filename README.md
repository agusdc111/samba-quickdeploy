# Samba QuickDeploy (Debian/Ubuntu)

Despliegue express de Samba con un recurso compartido, **roles** (admins RW / usuarios RO), **permisos colaborativos** y **scripts de gestión** listos para usar.

## Uso rápido
```bash
sudo bash install-samba.sh
```
Scripts: `samba-del-user.sh`, `samba-list-users.sh`, `samba-active-users.sh`.

## Seguridad
NTLMv2-only, SMB2+, máscaras colaborativas 0660/2770 con setgid y ACL.
