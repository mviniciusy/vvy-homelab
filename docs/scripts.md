# Scripts

> **Versão:** Maio/2026 | **Autor:** Vinícius Souza

---

## 1. Scripts

### 1.1 monitor.sh — REMOVIDO (31/Jul/2026)

> Script `/root/monitor.sh` nao existe mais. Entrada órfã no crontab removida em 31/Jul/2026.
> A telemetria do servidor agora é feita pelo `server-watchdog.sh` (seção 1.2).

### 1.2 server-watchdog.sh – Monitoramento Preventivo

|Item|Detalhe|
|---|---|
|Localização|`/usr/local/bin/server-watchdog.sh` – no node Proxmox (vvy)|
|Log|`/var/log/watchdog/server-state.log`|
|Execução|A cada 1 minuto via CronJob|
|Retenção|Últimos 50.000 registros (rotação automática — aumentado de 10.000 em 13/Mai/2026)|
|Métricas|Memória/Swap, Load Average, Top CPU/MEM, Disk I/O, Disk Space, Inodes, Network conns, Zombies|

### 1.3 heartbeat-watchdog.sh – Reboot Automático via iTCO_wdt

|Item|Detalhe|
|---|---|
|Localização|`/usr/local/bin/heartbeat-watchdog.sh` – no node Proxmox (vvy)|
|Log|`/var/log/watchdog/heartbeat.log`|
|Execução|Serviço systemd contínuo (`heartbeat-watchdog.service`)|
|Mecanismo|Ping em `/dev/watchdog` (iTCO_wdt — hardware watchdog Intel) a cada 10s. Se parar, hardware reboot em 60s|
|Config módulo|`/etc/modules-load.d/iTCO_wdt.conf` (carrega no boot) + `/etc/modprobe.d/iTCO_wdt.conf` (`options iTCO_wdt nowayout=1 heartbeat=60`)|
|Migração 21/Jun/2026|Migrado de softdog (software) para iTCO_wdt (hardware). O softdog travava junto com o kernel em hard freeze. NMI watchdog desativado via GRUB cmdline (`nmi_watchdog=0`) desde 21/Jun/2026 — o PMU counter consumia recursos e nao ajudava em hard freeze silicon-level. kdump-tools instalado (`crashkernel=256M`). softdog carregado como backup do iTCO_wdt|
|Correção 18/Jun/2026|`printf 'V'` (magic close) substituído por `printf '1'` (keepalive) — o watchdog era desarmado ao invés de reiniciar o servidor|
|Correção 13/Mai/2026|`WatchdogSec=60` removido do service — era redundante e causava loop de crashes (842+ restarts)|

> **IMPORTANTE:** O watchdog atual é o iTCO_wdt (hardware Intel TCO Timer), NÃO o softdog. O iTCO_wdt tem timer de hardware independente — mesmo em hard freeze onde o kernel congela, o hardware reinicia a máquina. O softdog era um watchdog software que travava junto com o kernel. O script deve usar `printf '1'` (ou qualquer caractere exceto `V`) para keepalive. O service file NÃO deve conter `WatchdogSec`.

### 1.4 vvy-heartbeat.sh — Heartbeat Externo (Oracle VM → vvy via Tailscale)

|Item|Detalhe|
|---|---|
|Localização|`/opt/vvy-monitor/vvy-heartbeat.sh` — na Oracle VM (nuvem, sempre online)|
|Estado|`/var/lib/vvy-monitor/state`|
|Log|`/var/log/vvy-monitor.log` (rotação 5000 linhas)|
|Execução|Cron a cada 1 min via `/etc/cron.d/vvy-heartbeat`|
|Método|Ping Tailscale para vvy (<TAILSCALE_VVV_IP>), 3 falhas consecutivas = offline|
|Alerta|Telegram bot `@hermesvvy_bot` (chat <TELEGRAM_CHAT_ID>)|
|Eventos|Offline (após 3 falhas), lembrete a cada 30 min, recuperação|
|Proteções|`flock` contra execução simultânea, rotação automática de log|

> **Por que externo:** O Zabbix (CT 160) e o server-watchdog.sh rodam DENTRO do vvy. Em hard freeze, ambos morrem junto. A Oracle VM é o único nó sempre online que pode detectar a queda e alertar via Telegram.

### 1.5 vvy-healthcheck-unified.sh — Healthcheck + MCE/EDAC (unificado 31/Jul/2026)

|Item|Detalhe|
|---|---|
|Localização|`~/.hermes/scripts/vvy-healthcheck-unified.sh` no CT 104 (hermes-agent) + repo `scripts/monitoring/`|
|Execução|Cronjob do Hermes Agent a cada 2 horas (no_agent=True, script-only)|
|Comportamento|Silencioso se tudo OK, alerta se detectar problemas|
|Verificações|heartbeat restart counter, WatchdogSec regression, load average, SMART discos, kernel errors (OOM/MCE/hardware), uptime recente, CE/UE RAM (EDAC/MCE)|

> **Unificação (31/Jul/2026):** Substitui dois scripts separados: `healthcheck-vvy.sh` (healthcheck) e `mce-monitor.sh` (MCE/EDAC). Antes eram dois cron jobs separados entregando duas mensagens Telegram a cada 2h. Agora é um único job entregando uma mensagem consolidada.

> **Contexto MCE/EDAC:** Monitora erros de memória ECC nos pentes de 16GB Micron (channel 1, slot 0) e 8GB (channel 3, slot 0). Ver `scripts/server-freeze/docs/Incidentes-Modificações/` para histórico completo de incidentes.
