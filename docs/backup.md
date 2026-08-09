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
| RAM | 8192 MiB + 512 MiB swap (OOM em 512 MiB com rclone --transfers=4) |
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
| App publicado | sim (publicado 08/08/2026 — refresh token nao expira mais) |
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

Sync espelhado da pasta "1. Geral" do HD-WD-1TB para Google Drive com lixeira:
- Origem: /mnt/wd1tb/1. Geral (NTFS)
- Destino: gdrive:"1. vvy/vvy-server-backup"/HD-WD-1TB/1. Geral/
- --backup-dir: move arquivos removidos para lixeira com timestamp
- Flags: --verbose --transfers=8 --drive-chunk-size=64M --checkers=16
- --dry-run disponível para preview
- Proteções: flock, mountpoint check (verifica /mnt/wd1tb + se "1. Geral" existe), log em /var/log/sync_wd1tb.log
- Cron: SEG 03:00
- Nota: Antes sincronizava o HD inteiro; alterado para só "1. Geral" em Ago/2026 (ISOs/WavesCentral fora do escopo)

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
- Cron: diario 02:45
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
- Cron: 2º domingo (dias 8-14) 01:00
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
- Retention Drive (rclone sync): 30 dias → gdrive:"1. vvy/vvy-server-backup"/Host-Root/
- Log: /var/log/sync_root.log

## Estrutura no Google Drive

```
1. vvy/vvy-server-backup/
├── HD-WD-1TB/                (mp1: pasta "1. Geral" do HD WD 1TB — sync segunda)
│   └── 1. Geral/
├── HD-WD500GB/               (mp0: dados do HD WD 500GB — sync terça)
├── SSD-NVMe-128GB/           (vzdump de CTs/VMs no NVMe — snapshot_hermes.sh, snapshot_semanal.sh)
│   ├── CT-104-hermes-agent/
│   ├── CT-199-minecraft/
│   └── VM-200-debian/
├── SSD-SATA-128GB/           (vzdump de CTs no SATA — snapshot_semanal.sh, snapshot_mensal.sh)
│   ├── CT-101-pihole/
│   ├── CT-160-zabbix/
│   ├── CT-161-grafana/
│   ├── CT-103-n8n/
│   ├── CT-112-handbrake/
│   └── CT-120-qbit-vpn/
├── Proxmox-Config/           (tar /etc/pve/ diário — backup_proxmox_config.sh)
├── Host-Root/                (tar.gz /root semanal — sync_root.sh)
└── lixeira/                  (arquivos removidos pelo sync — retenção 14 dias)
    ├── HD-WD-1TB/YYYY-MM-DD/
    └── HD-WD500GB/YYYY-MM-DD/
```

> HD-SEA1TB nao entra no backup nem e montado no CT 105.
> VM 200 disco de dados (scsi1, 100 GB HD-WD500GB) tem backup=0 — vazio, sera usado depois.



## Pitfalls

### pct exec não preserva aspas em paths com espaços

O `pct exec 105 -- rclone copy "$src" "gdrive:1. vvy/path/"` **NÃO** funciona — o `pct exec` (via `lxc-attach`) re-parseia os argumentos via shell do container e quebra o path no espaço, criando pastas `'1. vvy` na raiz do Drive.

**Solução:** usar `bash -c` com argumentos posicionais ($1, $2, ...):

```bash
pct exec 105 -- bash -c 'rclone copy "$1/" "$2"' _ "$src" "gdrive:1. vvy/path/"
```

O `_` ocupa `$0` (nome do shell), e os valores reais ficam em `$1` e `$2` — preservando os espaços sem aspas literais no path.

Validado em Ago/2026. Todos os scripts de snapshot, config e sync_root foram corrigidos para este padrão.

### DUMP_DIR_BASE com path incompleto

Os scripts de snapshot usavam `/mnt/pve/HD-WD500GB/vzdump/dump` mas o path real é `/mnt/pve/HD-WD500GB/Dados-WD500GB/vzdump/dump` (o storage `HD-WD500GB` monta em `/mnt/pve/HD-WD500GB` e os dados estão na subpasta `Dados-WD500GB/`). Sem o `Dados-WD500GB/` no path, a retention local não encontra os arquivos e não remove snapshots antigos. Corrigido em Ago/2026.

### VM 200 backup=0 no disco de dados

O VM 200 (debian) tem 2 discos: scsi0 (32 GB NVMe, rootfs) e scsi1 (100 GB HD-WD500GB, montado em /mnt/dados). O disco de 100 GB estava vazio (só lost+found) e era desnecessário no vzdump — o snapshot passou de 132 GB para 6.4 GB. Configurado `backup=0` no scsi1 via `qm set 200 -scsi1 HD-WD500GB:200/vm-200-disk-0.raw,backup=0,size=100G`. Para reverter: remover `,backup=0`.

### OAuth do Google Drive expira em 7 dias (modo teste) — RESOLVIDO

O app `vvy-backup` no Google Cloud Console estava em "modo teste" (nao publicado). O Google revoga refresh tokens de apps de teste apos 7 dias sem uso. Sintoma: `invalid_grant` / "Token has been expired or revoked". O token OAuth foi revogado em 05/08/2026 (apos 7 dias sem uso), causando falha em todos os uploads de 05-07/08. Reautorizado em 08/08/2026 e app publicado no mesmo dia — refresh token nao expira mais.

### Crontab do root perdido (07/08/2026) — RESOLVIDO

O `/var/spool/cron/crontabs/root` foi reinstalado vazio em 07/08 12:45:05 — apenas o header, sem nenhum job. Os 5 cronjobs de backup foram perdidos. Restaturado em 08/08 com os 5 jobs + `PATH=/usr/sbin:/usr/bin:/sbin:/bin` no header. O `backup_proxmox_config.sh` coleta o crontab para /tmp/ mas nao inclui no tar.gz — o arquivo em /tmp e limpo pelo sistema. Pendencia: adicionar crontab ao tar.gz do backup_proxmox_config.sh.

### PATH do cron (corrigido 07/08/2026)

O `PATH` do cron e `/usr/bin:/bin`, mas `pvesm` e `pct` estao em `/usr/sbin`. Os 5 scripts de backup do host falhavam silenciosamente (exit 127 mascarado por `2>/dev/null`). Correcao: `export PATH=/usr/sbin:/usr/bin:/sbin:/bin` apos `set -euo pipefail` em todos os 5 scripts.

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
