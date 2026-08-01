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
- Scripts de sync em /root/backup-manager/app/ (ver seção Scripts de backup abaixo)

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

### sync_wd1tb.sh (CT 105)

Sync espelhado do HD-WD-1TB para Google Drive com lixeira:
- Origem: /mnt/wd1tb (NTFS)
- Destino: gdrive:"1. vvy/vvy-server-backup"/HD-WD-1TB/
- --backup-dir: move arquivos removidos para lixeira com timestamp
- Flags: --verbose --transfers=4 --drive-chunk-size=64M --checkers=8
- --dry-run disponível para preview
- Proteções: flock, mountpoint check, log em /var/log/sync_wd1tb.log
- Cron: SEG 03:00

### sync_wd500gb.sh (CT 105)

Sync espelhado do HD-WD500GB para Google Drive com lixeira:
- Origem: /mnt/wd500gb (ext4)
- Destino: gdrive:"1. vvy/vvy-server-backup"/HD-WD500GB/
- --backup-dir: move arquivos removidos para lixeira com timestamp
- Flags: --verbose --transfers=4 --drive-chunk-size=64M --checkers=8
- --dry-run disponível para preview
- Proteções: flock, mountpoint check, log em /var/log/sync_wd500gb.log
- Cron: TER 03:00

### clean_lixeira.sh (CT 105)

Limpeza semanal da lixeira no Google Drive:
- Destino: gdrive:"1. vvy/vvy-server-backup"/lixeira/
- rclone delete --min-age 14d --rmdirs (remove arquivos e pastas vazias com 14+ dias)
- --dry-run disponível para preview
- Proteções: flock, log em /var/log/clean_lixeira.log
- Cron: DOM 04:00

### sync_snapshots.sh (CT 105)

Upload de snapshots vzdump para Google Drive (Fase 5 — ainda não implementado):
- /mnt/wd500gb/vzdump/ → gdrive:"1. vvy/vvy-server-backup"/SSD-Snapshots/
- Flags: --transfers=2 --drive-chunk-size=64M

## Estrutura no Google Drive

```
1. vvy/vvy-server-backup/
├── HD-WD-1TB/           (mp1: dados do HD WD 1TB — sync segunda)
├── HD-WD500GB/          (mp0: dados do HD WD 500GB — sync terça)
├── SSD-Snapshots/       (vzdump de CTs/VMs — Fase 5)
├── Proxmox-Config/      (tar /etc/pve/ diário — Fase 6)
└── lixeira/             (arquivos removidos pelo sync — retenção 14 dias)
    ├── HD-WD-1TB/YYYY-MM-DD/
    └── HD-WD500GB/YYYY-MM-DD/
```

> HD-SEA1TB nao entra no backup nem e montado no CT 105.

## Plano de Backup

Documento detalhado em \\\\<HOST_IP>\\HD-WD-500GB\\Dados-WD500GB\\Plano_Backup\\:
- Plano_Backup.md — inventario completo de storage, plano de backup e cronograma

> Os planos anteriores (baseados em TeraBox Premium) foram abandonados. O destino de backup agora e Google Drive 2TB.

## Fases

- [x] Fase 1 — CT 105 + dependências
- [x] Fase 2 — OAuth Google Drive
- [x] Fase 3 — Web GUI (rclone rcd porta 5572)
- [x] Fase 4 — Scripts de sync dos HDs + lixeira (14 dias) + cronjobs
- [ ] Fase 4-bis — Backup dos arquivos em /root (8 pastas pendentes)
- [ ] Fase 5 — Scripts de snapshot (SSDs, vzdump)
- [ ] Fase 6 — Script de config Proxmox (tar /etc/pve/)
- [ ] Fase 7 — Validação e restore de teste

> A Fase 4-bis cobre a lacuna de backup de /root. Pastas que precisam de backup: 1 Documentação Privada, 1 Documentação GITHUB, 1 Obsidian, 2 Oracle, iac, logs, Markdown, scripts.
