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

> O código-fonte do script está disponível em [`scripts/monitor.sh`](../scripts/monitor.sh).

### 1.2 server-watchdog.sh – Monitoramento Preventivo

|Item|Detalhe|
|---|---|
|Localização|`/usr/local/bin/server-watchdog.sh` – no node Proxmox (vvy)|
|Log|`/var/log/watchdog/server-state.log`|
|Execução|A cada 1 minuto via CronJob|
|Retenção|Últimos 50.000 registros (rotação automática — aumentado de 10.000 em 13/Mai/2026)|
|Métricas|Memória/Swap, Load Average, Top CPU/MEM, Disk I/O, Disk Space, Inodes, Network conns, Zombies, GPU NVIDIA|

### 1.3 heartbeat-watchdog.sh – Reboot Automático via Softdog

|Item|Detalhe|
|---|---|
|Localização|`/usr/local/bin/heartbeat-watchdog.sh` – no node Proxmox (vvy)|
|Log|`/var/log/watchdog/heartbeat.log`|
|Execução|Serviço systemd contínuo (`heartbeat-watchdog.service`)|
|Mecanismo|Ping em `/dev/watchdog` (softdog) a cada 10s. Se parar, kernel reboot em 60s|
|Config GRUB|`softdog.nowayout=1 softdog.soft_noboot=0 softdog.soft_active_on_boot=1 softdog.soft_margin=60`|
|Correção 13/Mai/2026|`WatchdogSec=60` removido do service — era redundante com softdog e causava loop de crashes (842+ restarts)|

> **IMPORTANTE:** O service file NÃO deve conter `WatchdogSec`. O script bash não envia `sd_notify`. O softdog do kernel já é o mecanismo de reboot automático. `WatchdogSec` do systemd é redundante e destrutivo neste contexto.

### 1.4 healthcheck-vvy.sh – Verificacao de Saude Automatizada

|Item|Detalhe|
|---|---|
|Localização|`/root/scripts/healthcheck-vvy.sh` no CT 104 (hermes-agent) + copia em repo `scripts/healthcheck-vvy.sh`|
|Execução|Cronjob do Hermes Agent a cada 2 horas|
|Comportamento|Silencioso se tudo OK, alerta se detectar problemas|
|Verificações|heartbeat restart counter, WatchdogSec regression, nvidia-fancontrol ativo, load average, GPU temperatura, SMART discos, kernel errors (OOM/MCE/hardware), uptime recente|

**Verificações e thresholds:**

|Verificação|Threshold|Nível|
|---|---|---|
|heartbeat-watchdog restart counter|> 5|CRÍTICO|
|WatchdogSec no service file|qualquer ocorrência|CRÍTICO|
|nvidia-fancontrol.service inativo|qualquer status != active|ALERTA|
|Load average|> 15|ALERTA|
|GPU temperatura|> 85°C|ALERTA|
|SMART disk failure|qualquer FAILED|CRÍTICO|
|Kernel OOM/MCE/hardware errors|> 0 ocorrências|ALERTA|
|Uptime < 10 minutos|< 600s|ALERTA (possível travamento)|

> Este script roda dentro do CT 104 (hermes-agent) e faz SSH para o host vvy. O cronjob carrega a skill `proxmox-crash-loop-diagnosis` para sugerir correções caso problemas sejam detectados.
