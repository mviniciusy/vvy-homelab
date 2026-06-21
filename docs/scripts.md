# Scripts

> **Versão:** Maio/2026 | **Autor:** Vinícius Souza

---

## 1. Scripts

### 1.1 monitor.sh – Telemetria do Servidor

|Item|Detalhe|
|---|---|
|Localização|`/root/monitor.sh` – no node Proxmox (vvv)|
|Log|`/root/logs/telemetry.log`|
|Execução|A cada 1 minuto via CronJob: `* * * * * /root/monitor.sh`|
|Retenção|Últimas 10.000 linhas (rotação automática)|
|Métricas|Temperatura CPU (sensors), RAM usada/total (free -m), Load Average (uptime)|

**Comandos úteis:**

```bash
tail -20 /root/logs/telemetry.log    # Ver últimas 20 entradas
tail -f /root/logs/telemetry.log     # Monitorar em tempo real
grep '2026-04-18' /root/logs/telemetry.log  # Ver entradas de uma data
```

> O código-fonte do script está disponível em [`scripts/monitoring/monitor.sh`](../scripts/monitoring/monitor.sh).

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
|Migração 21/Jun/2026|Migrado de softdog (software) para iTCO_wdt (hardware). O softdog travava junto com o kernel em hard freeze. NMI watchdog desativado via GRUB cmdline (`nmi_watchdog=0`) — sysctl sozinho não funciona (PMU consumido no boot)|
|Correção 18/Jun/2026|`printf 'V'` (magic close) substituído por `printf '1'` (keepalive) — o watchdog era desarmado ao invés de reiniciar o servidor|
|Correção 13/Mai/2026|`WatchdogSec=60` removido do service — era redundante e causava loop de crashes (842+ restarts)|

> **IMPORTANTE:** O watchdog atual é o iTCO_wdt (hardware Intel TCO Timer), NÃO o softdog. O iTCO_wdt tem timer de hardware independente — mesmo em hard freeze onde o kernel congela, o hardware reinicia a máquina. O softdog era um watchdog software que travava junto com o kernel. O script deve usar `printf '1'` (ou qualquer caractere exceto `V`) para keepalive. O service file NÃO deve conter `WatchdogSec`.

### 1.4 healthcheck-vvy.sh – Verificacao de Saude Automatizada

|Item|Detalhe|
|---|---|
|Localização|`/root/scripts/healthcheck-vvy.sh` no CT 104 (hermes-agent) + `~/.hermes/scripts/healthcheck-vvy.sh` (copia cronjob) + repo `scripts/monitoring/healthcheck-vvy.sh`|
|Execução|Cronjob do Hermes Agent a cada 2 horas (no_agent=True, script-only)|
|Comportamento|Silencioso se tudo OK, alerta se detectar problemas|
|Verificações|heartbeat restart counter, WatchdogSec regression, iTCO_wdt (identity/nowayout/state), NMI watchdog, load average, SMART discos, kernel errors (OOM/MCE/hardware), uptime recente|

**Verificações e thresholds:**

|Verificação|Threshold|Nível|
|---|---|---|
|heartbeat-watchdog restart counter|> 5|CRÍTICO|
|WatchdogSec no service file|qualquer ocorrência|CRÍTICO|
|iTCO_wdt identity diferente ou ausente|não é "iTCO_wdt"|CRÍTICO|
|iTCO_wdt nowayout=0|nowayout != 1|CRÍTICO|
|iTCO_wdt state não ativo|state != "active"|ALERTA|
|NMI watchdog ativo|kernel.nmi_watchdog != 0|ALERTA|
|Load average|> 15|ALERTA|
|SMART disk failure|qualquer FAILED|CRÍTICO|
|Kernel OOM/MCE/hardware errors|> 0 ocorrências|ALERTA|
|Uptime < 10 minutos|< 600s|ALERTA (possível travamento)|

> Este script roda dentro do CT 104 (hermes-agent) e faz SSH para o host vvy. O cronjob usa modo `no_agent=True` (script-only): o stdout do script e entregue diretamente como mensagem, sem chamada ao LLM. Se problemas forem detectados, o usuario pode pedir ao agente para carregar a skill `proxmox-crash-loop-diagnosis` e sugerir correcoes.
