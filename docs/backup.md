# Sistema de Backup

> Atualizado em Jul/2026

---

## Status

Sistema de backup em transição. O stack anterior (Alist + Rclone no LXC 130) foi removido e o CT 130 foi destruído.

**Novo sistema planejado:** Google Drive 2TB — aplicação self-hosted (Python/FastAPI) deployada no CT 105 (LXC, Debian 12). Modo sync espelhado para dados; vzdump sem sync.

## Plano de Backup

Documentos detalhados em `\\<HOST_IP>\HD-WD-500GB\Dados-WD500GB\Plano_Backup\`:
- `Plano_Backup.md` — inventário completo de storage e plano de backup
- `Plano_App.md` — arquitetura do app backup manager (Google Drive)

> Os planos anteriores (baseados em TeraBox Premium) foram abandonados. O destino de backup agora e Google Drive 2TB.
