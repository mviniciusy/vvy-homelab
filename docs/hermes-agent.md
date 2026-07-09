# Container Hermes Agent – Integração de Mensageria com IA

> **Versão:** Maio/2026 | **Autor:** Vinícius Souza

---

## 1. Container 104 — hermes-agent

> Adicionado em Maio/2026 – baseado no LXC 104

### 1.1 Visão Geral

O **Hermes Agent** é um assistente de IA com capacidades de tool-calling (chamada de ferramentas) e integração com plataformas de mensageria (WhatsApp, Slack). Ele roda como um gateway de mensagens no container, permitindo interação com modelos de IA via canais de chat.

O serviço principal agora é o `hermes-serve.service`, que disponibiliza a interface web do Hermes com bind em `0.0.0.0:9119` e autenticação Basic Auth. O acesso remoto (Desktop App no Windows) é feito diretamente via Tailscale, sem túnel SSH:

```bash
# Acesso via Tailscale (do Windows ou qualquer nó da tailnet)
http://<TAILSCALE_HERMES_IP>:9119
```

> O Tailscale está instalado **dentro do LXC 104** (IP `<TAILSCALE_HERMES_IP>`), eliminando o hop pelo subnet router do host e o túnel SSH que eram necessários antes.

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
|Tailscale|`<TAILSCALE_HERMES_IP>`|Nó Tailscale dentro do LXC — acesso remoto direto ao hermes-serve|

### 1.4 Serviço principal — hermes-serve (bind 0.0.0.0 + Basic Auth)

O serviço principal do container agora é o `hermes-serve.service`, que roda na porta 9119 com bind em `0.0.0.0` e autenticação Basic Auth. Ele substituiu o antigo `hermes-dashboard.service` (que bindava em `127.0.0.1` e exigia túnel SSH para acesso remoto).

```ini
[Unit]
Description=Hermes Agent Serve (Remote Backend)
After=network-online.target tailscale.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
EnvironmentFile=/root/.hermes/.env
ExecStart=/usr/local/lib/hermes-agent/venv/bin/hermes serve --host 0.0.0.0 --port 9119 --skip-build
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**Características do Novo Serviço:**
- `Restart=always` — reinicia automaticamente em caso de falha
- `RestartSec=5` — espera 5s entre tentativas de reinício
- `--host 0.0.0.0` — bind em todas as interfaces (acessível via Tailscale, não só loopback)
- `--skip-build` — pula build do frontend (já buildado)
- `EnvironmentFile=/root/.hermes/.env` — carrega credenciais e secret do Basic Auth
- `After=tailscale.service` — garante que o Tailscale suba antes do hermes-serve

**Autenticação Basic Auth (`/root/.hermes/.env` no LXC 104):**

|Variável|Valor|Função|
|---|---|---|
|`HERMES_DASHBOARD_BASIC_AUTH_USERNAME`|`admin`|Usuário do Basic Auth|
|`HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`|`<HERMES_BASIC_AUTH_PASSWORD>`|Senha do Basic Auth|
|`HERMES_DASHBOARD_BASIC_AUTH_SECRET`|Gerado com `openssl rand -base64 32`|Garante que a sessão OAuth sobrevive a restarts|

> O `hermes serve` com bind público exige auth provider configurado. O Basic Auth protege o WebSocket e a API REST. O `SECRET` garante que a sessão OAuth persiste entre restarts do serviço.

### Topologia de acesso remoto (Desktop App Windows)

```
Windows (Acer Nitro)                         Proxmox Host (vvy)
Tailscale: <TAILSCALE_NOTEBOOK_IP>          <--> Tailscale direto no LXC 104 -> <TAILSCALE_HERMES_IP>
                                                                |
                                                    hermes-serve: 0.0.0.0:9119 (Basic Auth)
```

O Desktop App no Windows conecta via Tailscale direto ao LXC 104, sem hop pelo subnet router do host e sem túnel SSH. O fluxo de autenticação é OAuth via Basic Auth (username/password), gerando cookies de sessão.

**Arquivo de conexão do Desktop App (`%APPDATA%\Hermes\connection.json`):**

```json
{
  "mode": "remote",
  "remote": {
    "authMode": "oauth",
    "url": "http://<TAILSCALE_HERMES_IP>:9119"
  }
}
```

**Fluxo de conexão:**
1. Abre Desktop App
2. Settings -> Gateway -> "Sign in to remote gateway"
3. Username: `admin` | Password: `<HERMES_BASIC_AUTH_PASSWORD>`
4. App obtém cookies OAuth -> ticket -> WebSocket autenticado
5. Sessões aparecem (vêm de `/root/.hermes/state.db` no LXC)

> O antigo `hermes-dashboard.service` (`hermes dashboard`, porta `127.0.0.1:9119`) e o acesso via SSH tunnel (`ssh -L 9119:localhost:9119`) ficaram **obsoletos**. O script `hermes-tunnels.ps1` no Windows também não é mais necessário.

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
| Status do hermes-serve | `pct exec 104 -- systemctl status hermes-serve` |
| Logs do hermes-serve | `pct exec 104 -- journalctl -u hermes-serve -f` |
| Reiniciar o hermes-serve | `pct exec 104 -- systemctl restart hermes-serve` |
| Verificar Tailscale no LXC | `pct exec 104 -- tailscale status` |
| Ver config do Hermes | `pct exec 104 -- cat /root/.hermes/config.yaml` |
| Testar API local | `pct exec 104 -- curl http://127.0.0.1:9119` |
| Ver ports em uso | `pct exec 104 -- ss -tlnp` |
| Uso de disco | `pct exec 104 -- df -h /` |
| Uso de memória | `pct exec 104 -- free -m` |

### 1.7 Integração com o Ecossistema

- **Acesso via rede local:** Disponível em `<HERMES_IP>` através da bridge `vmbr0`
- **Acesso via Tailscale:** `http://<TAILSCALE_HERMES_IP>:9119` (Basic Auth) — Tailscale direto no LXC, sem hop pelo subnet router do host
- **Desktop App (Windows):** Conecta via Tailscale direto ao LXC 104, autenticação OAuth via Basic Auth (admin/<HERMES_BASIC_AUTH_PASSWORD>)
- **Mensageria:** Suporta integração com WhatsApp e Slack via gateway

> ⚠️ O container **não usa Docker** internamente — o Hermes roda diretamente via Python venv e systemd.


### 1.8 Cronjobs do Hermes

O Hermes Agent possui um sistema de cronjobs nativo para monitoramento automatizado.

|Cronjob|Schedule|Modo|Script|Descricao|
|---|---|---|---|---|
|vvy-healthcheck|A cada 2h|no_agent=True (script-only)|`~/.hermes/scripts/healthcheck-vvy.sh`|Verifica saude do Proxmox: heartbeat, load, SMART, kernel, uptime. Silencioso se OK, alerta se detectar problemas.|

**Modo no_agent=True:** O script roda diretamente sem chamada ao LLM. O stdout do script e entregue como mensagem no canal configurado. Isso evita rate limits (HTTP 429), saida vazia e alucinacoes do modelo.

**Scripts do cronjob:**
- Copia de trabalho: `~/.hermes/scripts/healthcheck-vvy.sh` (usado pelo cronjob)
- Script original: `/root/scripts/healthcheck-vvy.sh`
- Copia no repo: `scripts/monitoring/healthcheck-vvy.sh`

**Comandos uteis:**

| Acao | Comando |
|------|---------|
| Listar cronjobs | `hermes cron list` |
| Rodar healthcheck manualmente | `hermes cron run vvy-healthcheck` |
| Ver log do healthcheck | `hermes cron log vvy-healthcheck` |

### 1.9 Acesso ao Host via Token de API Proxmox

> Adicionado em Julho/2026 — Token de API dedicado para o Hermes Agent (CT 104)

O CT 104 é unprivileged e precisa de acesso ao host vvy para listar CTs/VMs,
consultar status, executar start/stop e outros comandos administrativos. Para
evitar elevar o container a privileged, foram configurados **dois caminhos
complementares**:

**1. Token de API Proxmox (`root@pam!hermes`) — preferencial para consultas**

- Wrapper `pveapi` instalado em `/usr/local/bin/pveapi` (dentro do CT 104)
- Secret guardado em `/root/.proxmox-api` (0600)
- Latência: ~22ms por chamada (vs ~1.420ms via SSH ControlMaster)

```bash
# Sintaxe: pveapi <method> <endpoint>
pveapi get /version                              # versão do PVE
pveapi get /nodes                                # nodes
pveapi get "/cluster/resources?type=vm"          # lista CTs + VMs
pveapi get /nodes/vvy/status                     # status do node vvy
pveapi post /nodes/vvy/lxc/103/status/start      # iniciar CT 103
```

**2. SSH ControlMaster (`ssh vvy`) — shells interativos e comandos sem endpoint**

- `/root/.ssh/config` configurado com ControlMaster auto (socket 10min)
- Alias: `ssh vvy` = `ssh root@<HOST_IP>`

**Quando usar cada um:**

| Cenário | Método |
|---|---|
| Listar, consultar status, métricas, start/stop | API (`pveapi`) |
| Scripts de automação, watchers, monitoração | API |
| `pct exec`, `pct enter`, editar `/etc/pve/` direto | SSH (`ssh vvy`) |
| Operações de arquivo (rsync, cp inter-host) | SSH |

> O Token de API NÃO substitui o SSH — complementa. Para detalhes completos
> (benchmark, arquivos no container, troca de contexto), veja a Seção 16 do
> PROXMOX_VVY.md.

