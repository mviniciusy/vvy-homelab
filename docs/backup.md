# Sistema de Backup (TeraBox)

> Atualizado em Jul/2026

---

## Status

O sistema anterior (Alist + Rclone no LXC 130) foi **removido**. O CT 130 foi destruído.

**Novo sistema planejado:** TeraBox Backup Manager — aplicação Python/FastAPI + Node.js (terabox-api) deployada na VM 200 (Docker).

## Capacidade TeraBox

- **Plano:** Premium
- **Total:** 2048 GB
- **Usado:** ~161 GB
- **Disponível:** ~1887 GB

## Plano de Backup

Documentos detalhados em `\\<HOST_IP>\HD-WD-500GB\Dados-WD500GB\Plano_Backup\`:
- `Plano_Backup.md` — inventário completo de storage e plano de backup
- `Plano_App_TeraBox_Backup_Manager.md` — arquitetura do app
- `Prompt_Inicio.md` — prompt para iniciar implementação em chat limpo

## Estrutura de Destino no TeraBox (planejada)

|Caminho|Status|Volume|
|---|---|---|
|Terabox/1. vvy (server - backup)/HD-WD-1TB/|Planejado|85 GB|
|Terabox/1. vvy (server - backup)/HD-WD-500GB/|Planejado|11 GB|
|Terabox/1. vvy (server - backup)/SSD-SATA-128GB/|Planejado|Snapshots CTs|
|Terabox/1. vvy (server - backup)/SSD-NVMe-128GB/|Planejado|Snapshots CTs + VM 200|

## Repositorio

- Repo publico: `mviniciusy/terabox-backup-manager` (a criar)
