# Sistema de Backup

> Atualizado em Ago/2026

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

### Storage backup-dump (vzdump)

| Item | Valor |
|---|---|
| Storage | backup-dump |
| Path (host) | /mnt/pve/HD-WD500GB/Dados-WD500GB/vzdump |
| Path (CT 105) | /mnt/wd500gb/vzdump |
| Content | backup (vzdump) |

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

Scripts executados no **CT 105** (rclone sync dos HDs):

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

Upload de snapshots vzdump para Google Drive:
- /mnt/wd500gb/vzdump/ → gdrive:"1. vvy/vvy-server-backup"/SSD-Snapshots/
- Flags: --transfers=2 --drive-chunk-size=64M
- Executado após os scripts de snapshot do host (Fase 5)

Scripts executados no **host vvy** (vzdump + tar + sync para CT 105):

### snapshot_hermes.sh (host vvy) — Fase 5

vzdump do CT 104 (Hermes Agent) diario:
- Destino: storage backup-dump (/mnt/pve/HD-WD500GB/Dados-WD500GB/vzdump)
- Conteudo: CT 104 (Hermes Agent completo)
- Cron: diario 02:30
- Retention local: 2 snapshots (removidos pelo vzdump --prune-backups)
- Retention Drive (rclone sync via sync_snapshots.sh): 7 dias
- Log: /var/log/snapshot_hermes.log

### snapshot_semanal.sh (host vvy) — Fase 5

vzdump semanal dos CTs principais:
- Destino: storage backup-dump (/mnt/pve/HD-WD500GB/Dados-WD500GB/vzdump)
- Conteudo: CTs 101, 199, 200, 160, 161
- Cron: DOM 01:00
- Retention local: 1 snapshot por CT
- Retention Drive: 14 dias

### snapshot_mensal.sh (host vvy) — Fase 5

vzdump mensal dos CTs de baixa frequencia:
- Destino: storage backup-dump (/mnt/pve/HD-WD500GB/Dados-WD500GB/vzdump)
- Conteudo: CTs 103, 112, 120
- Cron: 1º DOM do mes 01:00
- Retention local: 1 snapshot por CT
- Retention Drive: 30 dias

### backup_proxmox_config.sh (host vvy) — Fase 6

Backup diario da configuracao do Proxmox:
- Conteudo: tar de /etc/pve/ + configs do host (/etc/network/interfaces, /etc/hostname, /etc/hosts, /etc/resolv.conf, /etc/crontab, /root/.bashrc, /root/.zshrc)
- Destino local: /mnt/pve/HD-WD500GB/Dados-WD500GB/Proxmox-Config/proxmox-config-YYYY-MM-DD.tar.gz
- Cron: diario 02:00
- Retention local: 7 dias (remove arquivos com mais de 7d)
- Retention Drive (rclone sync): 30 dias → gdrive:"1. vvy/vvy-server-backup"/Proxmox-Config/
- Log: /var/log/backup_proxmox_config.log

### sync_root.sh (host vvy) — Fase 4-bis

Backup semanal de 7 pastas de /root:
- Conteudo: tar.gz de 7 pastas — "1 Documentação Privada", "1 Documentação GITHUB", "1 Obsidian", "2 Oracle", "iac", "logs", "scripts"
- Destino local: /mnt/pve/HD-WD500GB/Dados-WD500GB/root-backup/root-YYYY-MM-DD.tar.gz
- Cron: QUA 03:00 (semanal, quartas)
- Retention local: remove arquivos com mais de 30 dias
- Retention Drive (rclone sync): 30 dias → gdrive:"1. vvy/vvy-server-backup"/Root-Backup/
- Log: /var/log/sync_root.log

## Estrutura no Google Drive

```
1. vvy/vvy-server-backup/
├── HD-WD-1TB/           (mp1: dados do HD WD 1TB — sync segunda)
├── HD-WD500GB/          (mp0: dados do HD WD 500GB — sync terça)
├── SSD-Snapshots/       (vzdump de CTs — sync_snapshots.sh)
├── Proxmox-Config/      (tar /etc/pve/ diário — backup_proxmox_config.sh)
├── Root-Backup/          (tar.gz /root semanal — sync_root.sh)
└── lixeira/             (arquivos removidos pelo sync — retenção 14 dias)
    ├── HD-WD-1TB/YYYY-MM-DD/
    └── HD-WD500GB/YYYY-MM-DD/
```

> HD-SEA1TB nao entra no backup nem e montado no CT 105.

## Plano de Backup

Documento detalhado em \\<HOST_IP>\HD-WD-500GB\Dados-WD500GB\Plano_Backup\:
- Plano_Backup.md — inventario completo de storage, plano de backup e cronograma

> Os planos anteriores (baseados em TeraBox Premium) foram abandonados. O destino de backup agora e Google Drive 2TB.

## Fases

- [x] Fase 1 — CT 105 + dependências
- [x] Fase 2 — OAuth Google Drive
- [x] Fase 3 — Web GUI (rclone rcd porta 5572)
- [x] Fase 4 — Scripts de sync dos HDs + lixeira (14 dias) + cronjobs
- [x] Fase 4-bis — Backup dos arquivos em /root (sync_root.sh, 7 pastas, semanal QUA 03:00)
- [x] Fase 5 — Scripts de snapshot (snapshot_hermes.sh, snapshot_semanal.sh, snapshot_mensal.sh + sync_snapshots.sh)
- [x] Fase 6 — Script de config Proxmox (backup_proxmox_config.sh, tar /etc/pve/ diário 02:00)
- [ ] Fase 7 — Validação e restore de teste
