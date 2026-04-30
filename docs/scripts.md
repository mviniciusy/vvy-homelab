# Scripts

> **Versão:** Abril/2026 | **Autor:** Vinícius Souza

---

## 10. Scripts

### 10.1 monitor.sh – Telemetria do Servidor

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
