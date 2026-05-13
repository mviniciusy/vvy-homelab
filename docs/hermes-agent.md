# Container Hermes Agent – Integração de Mensageria com IA

> **Versão:** Maio/2026 | **Autor:** Vinícius Souza

---

## 1. Container 104 — hermes-agent

> Adicionado em Maio/2026 – baseado no LXC 104

### 1.1 Visão Geral

O **Hermes Agent** é um assistente de IA com capacidades de tool-calling (chamada de ferramentas) e integração com plataformas de mensageria (WhatsApp, Slack). Ele roda como um gateway de mensagens no container, permitindo interação com modelos de IA via canais de chat.

O serviço principal agora é o `hermes-dashboard.service`, que disponibiliza o painel de controle do Hermes na porta 9119. O acesso via Windows é feito através de túnel SSH na porta 9119:

```bash
ssh -L 9119:localhost:9119 root@<HERMES_IP> -N
```

### 1.2 Especificações do Container

|Item|Valor|
|---|---|
|**ID**|104|
|**Nome**|hermes-agent|
|**Função**|Gateway de mensageria IA (WhatsApp, Slack, etc.)|
|**IP**|`<HERMES_IP>`|
|**Cores**|4|
|**Memory**|4096 MB|
|**Swap**|1024 MB|
|**Storage**|nvme128:16G|
|**Sistema**|Debian 12 (Bookworm)|
|**Unprivileged**|1 (não-privilegiado)|
|**Onboot**|Sim|

### 1.3 Stack Tecnológica (dentro do LXC)

|Componente|Versão/Local|Observação|
|---|---|---|
|Hermes Agent|`/usr/local/lib/hermes-agent/`|Clonado do repositório oficial (git)|
|Python venv|`/usr/local/lib/hermes-agent/venv/`|Ambiente virtual isolado|
|Node.js|`/root/.hermes/node/`|Runtime para ferramentas JS do Hermes|
|Postfix|via systemd|MTA para envio de e-mails|
|SSH|OpenSSH|Acesso remoto ao container|

### 1.4 Serviço principal — hermes-dashboard

O serviço principal do container agora é o `hermes-dashboard.service`, que roda na porta 9119:

```ini
[Unit]
Description=Hermes Agent Dashboard - Web Interface
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/hermes dashboard
WorkingDirectory=/usr/local/lib/hermes-agent
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
```

**Características do Novo Serviço:**
- `Restart=always` — reinicia automaticamente em caso de falha
- `RestartSec=60` — espera 60s entre tentativas de reinício

### 1.5 Configuração do Hermes

|Arquivo|Localização|Função|
|---|---|---|
|Config principal|`/root/.hermes/config.yaml`|Configuração de modelos, providers, canais|
|Variáveis de ambiente|`/root/.hermes/.env`|API keys, tokens, credenciais|
|SOUL.md|`/root/.hermes/SOUL.md`|Personalidade/instruções base do agente|
|Auth|`/root/.hermes/auth.json`|Autenticação com plataformas externas|
|Cache|`/root/.hermes/cache/`|Cache de sessões e dados temporários|

### 1.6 Comandos Úteis (a partir do host Proxmox)

| Ação | Comando |
|------|---------|
| Entrar no container | `pct enter 104` |
| Status do dashboard | `pct exec 104 -- systemctl status hermes-dashboard` |
| Logs do dashboard | `pct exec 104 -- journalctl -u hermes-dashboard -f` |
| Reiniciar o dashboard | `pct exec 104 -- systemctl restart hermes-dashboard` |
| Ver config do Hermes | `pct exec 104 -- cat /root/.hermes/config.yaml` |
| Testar API local | `pct exec 104 -- curl http://127.0.0.1:9119` |
| Ver ports em uso | `pct exec 104 -- ss -tlnp` |
| Uso de disco | `pct exec 104 -- df -h /` |
| Uso de memória | `pct exec 104 -- free -m` |

### 1.7 Integração com o Ecossistema

- **Ollama local:** O Hermes pode se conectar ao Ollama (`<OLLAMA_IP>:11434`) como provider de modelos de IA
- **Acesso via rede local:** Disponível em `<HERMES_IP>` através da bridge `vmbr0`
- **Mensageria:** Suporta integração com WhatsApp e Slack via gateway

> ⚠️ O container **não usa Docker** internamente — o Hermes roda diretamente via Python venv e systemd.