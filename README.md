# vvy-homelab

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Home Lab baseado no **Proxmox VE**, projetado para centralizar serviços de infraestrutura de rede, armazenamento em nuvem privada. Atua como núcleo de processamento para tarefas que exigem disponibilidade 24/7, permitindo que o notebook principal seja utilizado apenas para interface de trabalho e criação.

---

## Arquitetura do Homelab

```mermaid
graph TB
    subgraph Internet
        TeraBox[TeraBox<br/>Cloud Backup 2TB]
    end

    subgraph Rede Local
        Router[Roteador<br/>Fibra 450 Mbps]
    end

    subgraph Tailscale Mesh
        TS[VPN Tailscale<br/>Subnet Router]
        NB[Notebook]
        Phone[Celular]
    end

    subgraph Proxmox VE - vvy
        subgraph Containers LXC
            NC[nextcloud<br/>CT 100]
            PH[pihole<br/>CT 101 - DNS]
                       N8N[n8n<br/>CT 103 - Workflows IA]
            HER[hermes-agent<br/>CT 104 - Mensageria IA]
            HB[handbrake<br/>CT 112]
            QB[qbittorrent<br/>CT 120]
            AL[alist-backup<br/>CT 130]
            ZB[zabbix<br/>CT 160]
            GF[grafana<br/>CT 161]
        end

        subgraph Máquinas Virtuais
            DK[debian-docker<br/>VM 200]
        end

        subgraph Armazenamento
            SSD1[SSD 128GB SATA<br/>Proxmox OS]
            SSD2[SSD 128GB NVMe<br/>CT/VM Pool]
            HD1[HD 1TB WD<br/>Ext4]
            HD2[HD 1TB SEA<br/>Ext4]
            HD3[HD 1TB WD<br/>NTFS]
        end
    end

    Router --> Proxmox
    TS --> |Subnet Router| Router
    NB -.-> TS
    Phone -.-> TS
    AL -->|Rclone + WebDAV| TeraBox
   
       style N8N fill:#4caf50,stroke:#2e7d32,color:#fff
    style HER fill:#9c27b0,stroke:#6a1b9a,color:#fff
    style DK fill:#42a5f5,stroke:#1565c0,color:#fff
    style PH fill:#ff9800,stroke:#e65100,color:#fff
```

---

## Documentacao

| Documento | Descricao |
|---|---|
| [Hardware](docs/hardware.md) | Especificacoes do servidor (Xeon E5-2470 v2, RAM, SSDs) e do cliente |
| [Proxmox Setup](docs/proxmox-setup.md) | Virtualizacao Proxmox 9.1.6, containers LXC e VMs |
| [Storage](docs/storage.md) | HDs de dados, pontos de montagem e UUIDs |
| [Networking](docs/networking.md) | VPN Tailscale, nos, subnet router e acesso remoto |
| [Backup](docs/backup.md) | Sistema automatizado Alist + Rclone + TeraBox |
| [Monitoring - Zabbix](docs/monitoring-zabbix.md) | Zabbix 7.2, hosts monitorados e thresholds |
| [Monitoring - Grafana](docs/monitoring-grafana.md) | Grafana 12.4 + Prometheus + Node Exporter |
| [Scripts](docs/scripts.md) | Scripts de telemetria e automacao |
| [Admin Remoto](docs/admin-remote.md) | VS Code Remote SSH e boas praticas |
| [Docker VM](docs/docker-vm.md) | VM Debian 12 com Docker e Portainer |
| [n8n Workflows](docs/n8n-workflows.md) | Oquestracao de workflows IA com n8n |
| [Hermes Agent](docs/hermes-agent.md) | Gateway de mensageria IA (WhatsApp, Slack) + backend remoto via Tailscale (Desktop App) - CT 104 |
| [Terraform](docs/terraform-proxmox.md) | Infraestrutura como Codigo - provisionamento Proxmox |
| [Ansible](docs/ansible-proxmox.md) | Configuracao como Codigo - automacao de tarefas |

---

## Scripts

| Script | Descricao |
|---|---|
| [`scripts/monitoring/monitor.sh`](scripts/monitoring/monitor.sh) | Telemetria do servidor - temperatura CPU, RAM e load average |
| [`scripts/server-freeze/`](scripts/server-freeze/) | Kit de diagnostico de travamento - watchdog, diagnostico pos-reboot e instalador |
| [`scripts/sync/`](scripts/sync/) | Sincronizacao privado->publico (sync_public.py) |
| [`scripts/monitoring/healthcheck-vvy.sh`](scripts/monitoring/healthcheck-vvy.sh) | Verificacao de saude automatizada do vvy - cronjob Hermes a cada 2h (no_agent=True, script-only) |

---

## Licenca

Este projeto esta licenciado sob a [MIT License](LICENSE).
