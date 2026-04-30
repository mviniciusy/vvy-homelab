# Virtualização Proxmox

> **Versão:** Abril/2026 | **Autor:** Vinícius Souza

---

## 1. Virtualização (Proxmox 9.1.6)

- **IP Host Local:** `<HOST_IP>`

- **Kernel:** `6.17.13-2-pve`

### Diagrama da Arquitetura Proxmox

```mermaid
graph LR
    PVE[Proxmox VE 9.1.6<br/>vvy - HOST_IP] --> LXC100[nextcloud<br/>CT 100]
    PVE --> LXC101[pihole<br/>CT 101]
    PVE --> LXC102[ollama<br/>CT 102 - GPU]
    PVE --> LXC103[n8n<br/>CT 103]
    PVE --> LXC112[handbrake<br/>CT 112]
    PVE --> LXC120[qbittorrent<br/>CT 120]
    PVE --> LXC130[alist-backup<br/>CT 130]
    PVE --> LXC160[zabbix<br/>CT 160]
    PVE --> LXC161[grafana<br/>CT 161]
    PVE --> VM200[debian-docker<br/>VM 200]

    style LXC102 fill:#f9a825,stroke:#f57f17,color:#000
    style LXC103 fill:#4caf50,stroke:#2e7d32,color:#fff
    style VM200 fill:#42a5f5,stroke:#1565c0,color:#fff
```

### Containers LXC

|ID|Nome|IP|Cores|Storage|Serviço|
|---|---|---|---|---|---|
|100|nextcloud|`<NEXTCLOUD_IP>`|2|HD-WD500GB|Nextcloud – nuvem privada|
|101|pihole|`<PIHOLE_IP>`|2|local-lvm|Pi-hole – DNS/bloqueio anúncios|
|102|ollama|`<OLLAMA_IP>`|8|nvme128:32G|Ollama – LLM local com GPU passthrough|
|**103**|**n8n**|**`<N8N_IP>`**|**4**|**nvme128:20G**|**n8n – orquestração de workflows IA**|
|112|handbrake|`<HANDBRAKE_IP>`:5800|2|local-lvm|Handbrake – transcodificação|
|120|qbittorrent|`<QBITTORRENT_IP>`:8080|6|local-lvm|qBittorrent – cliente torrent|
|130|alist-backup|`<ALIST_IP>`|2|local-lvm|Alist + Rclone – backup TeraBox|
|160|zabbix|`<ZABBIX_IP>`|2|local-lvm (20GB)|Zabbix 7.2 – monitoramento|
|161|grafana|`<GRAFANA_IP>`|2|local-lvm (10GB)|Grafana 12.4 + Prometheus + Node Exporter|

> **Container de IA** – Adicionado em Abril/2026

### LXC 102 — ollama (Privilegiado | GPU Passthrough)

|Parâmetro|Valor|
|---|---|
|rootfs|nvme128:32G|
|Cores|8|
|Memory|8192 MB|
|Swap|2048 MB|
|IP|`<OLLAMA_IP>`/24|
|unprivileged|0 (privilegiado – necessário para GPU passthrough)|
|GPU Passthrough|nvidia0, nvidiactl, nvidia-modest, nvidia-uvm, nvidia-uvm-tools|

> O LXC 102 é privilegiado (`unprivileged: 0`) pois o GPU passthrough de dispositivos NVIDIA (`/dev/nvidia*`) requer acesso direto ao hardware, incompatível com containers não-privilegiados.

### Máquinas Virtuais

|ID|Nome|Storage|Uso|
|---|---|---|---|
|200|debian 12.12 (Bookworm)|nvme128|docker|
