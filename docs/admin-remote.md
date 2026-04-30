# Administração e Acesso Remoto

> **Versão:** Abril/2026 | **Autor:** Vinícius Souza

---

## 11. Administração e Acesso Remoto

### VS Code Remote SSH

|Item|Detalhe|
|---|---|
|Extensão|Remote - SSH (Microsoft)|
|Host (local)|`root@<HOST_IP>`|
|Host (via Tailscale)|`root@<TAILSCALE_VVV_IP>`|
|Acesso|`Ctrl+Shift+P` → `Remote-SSH: Connect to Host`|

> ⚠️ **ATENÇÃO:** nunca abrir a pasta raiz `/` no VS Code – causa indexação de todos os HDs (processo `rg`/`ripgrep`). Abrir sempre pastas específicas: `/etc`, `/root` ou `/etc/pve/lxc`.
> ℹ️ Acessar containers via terminal do VS Code: `pct enter <ID>`
