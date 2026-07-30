# Sistema de Backup

> Atualizado em Jul/2026

---

## Status

**Sistema ativo.** O stack anterior (Alist + Rclone no LXC 130) foi removido e o CT 130 destruido.

**Sistema atual:** rclone no CT 105 (LXC, Debian 12) com sync espelhado para Google Drive 2TB. Web GUI do rclone (rcd) na porta 5572.

## Container CT 105 — backup-manager

| Parametro | Valor |
|---|---|
| CTID | 105 |
| Hostname | backup-manager |
| IP | <BACKUP_MANAGER_IP> |
| CPU | 2 cores |
| RAM | 512 MB + 256 swap |
| Storage | nvme128, rootfs 4GB |
| OS | Debian 12 (Bookworm) |
| Unprivileged | sim (nesting=1) |
| onboot | sim |

### Mount points (SEM HD Seagate)

| Mount | HD | Caminho no CT |
|---|---|---|
| mp0 | HD-WD500GB (ext4) | /mnt/wd500gb |
| mp1 | HD-WD-1TB (NTFS) | /mnt/wd1tb |

### Software instalado

- rclone 1.60.1 (apt) — motor de sync espelhado
- Python 3.11 + venv com google-api-python-client, fastapi, apscheduler (backup)
- Scripts sync_dados.sh e sync_snapshots.sh em /root/backup-manager/app/

### Google Drive — rclone remote gdrive

| Item | Valor |
|---|---|
| Projeto Google Cloud | vvy-backup |
| OAuth Client ID | rclone-vvy (Desktop app) |
| Escopo | .../auth/drive (read/write/delete) |
| App em modo teste | sim (nao publicado, uso pessoal) |
| Pasta base no Drive | 1. vvy/vvy-server-backup/ |
| Token | /root/.config/rclone/rclone.conf (CT 105) |
| credentials.json | /root/backup-manager/config/credentials.json |

### Web GUI (rclone rcd)

| Item | Valor |
|---|---|
| URL | http://<BACKUP_MANAGER_IP>:5572 |
| Usuario | admin |
| Senha | <RCLONE_RCD_PASSWORD> |
| Servico systemd | rclone-rcd.service (enable + active) |

## Scripts de backup

### sync_dados.sh

Sync espelhado dos HDs para Google Drive:
- HD-WD500GB → gdrive:"1. vvy/vvy-server-backup"/HD-WD500GB/
- HD-WD-1TB → gdrive:"1. vvy/vvy-server-backup"/HD-WD-1TB/
- Flags: --transfers=4 --drive-chunk-size=64M --checkers=8
- --dry-run disponivel para preview

### sync_snapshots.sh

Upload de snapshots vzdump para Google Drive:
- /mnt/wd500gb/vzdump/ → gdrive:"1. vvy/vvy-server-backup"/SSD-Snapshots/
- Flags: --transfers=2 --drive-chunk-size=64M

## Estrutura no Google Drive

```
1. vvy/vvy-server-backup/
├── HD-WD500GB/          (mp0: dados do HD WD 500GB)
├── HD-WD-1TB/           (mp1: dados do HD WD 1TB)
└── SSD-Snapshots/       (vzdump de CTs/VMs)
```

> HD-SEA1TB nao entra no backup nem e montado no CT 105.

## Plano de Backup

Documento detalhado em \\\\<HOST_IP>\\HD-WD-500GB\\Dados-WD500GB\\Plano_Backup\\:
- Plano_Backup.md — inventario completo de storage, plano de backup e cronograma

> Os planos anteriores (baseados em TeraBox Premium) foram abandonados. O destino de backup agora e Google Drive 2TB.

## Pendente (proximas fases)

- [ ] Configurar cronjobs (sync semanal 03:00, snapshots periodicas)
- [ ] Configurar vzdump storage no HD-WD500GB
- [ ] Primeiro sync completo (dry-run → real)
- [ ] Restore de teste
