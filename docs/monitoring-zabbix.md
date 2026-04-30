# Monitoramento de Infraestrutura (Zabbix)

> **Versão:** Abril/2026 | **Autor:** Vinícius Souza

---

## 1. Monitoramento de Infraestrutura (Zabbix 7.2)

- **URL:** `http://<ZABBIX_IP>/zabbix`

- **Usuário padrão:** `<ZABBIX_ADMIN_USER>`

- **Versão:** Zabbix 7.2.15

- **Banco de dados:** MariaDB – usuário: `<DB_USER>` – banco: `<DB_NAME>`


### Hosts Monitorados

|Host|IP|Agent|Template|
|---|---|---|---|
|Zabbix server|127.0.0.1|zabbix-agent (interno)|Linux by Zabbix agent, Zabbix server health|
|nextcloud|`<NEXTCLOUD_IP>`|zabbix-agent|Linux by Zabbix agent|
|pihole|`<PIHOLE_IP>`|zabbix-agent|Linux by Zabbix agent|
|qbittorrent|`<QBITTORRENT_IP>`|zabbix-agent (UFW: 10050 liberada)|Linux by Zabbix agent|
|alist-backup|`<ALIST_IP>`|zabbix-agent|Linux by Zabbix agent|
|vvy|`<HOST_IP>`|zabbix-agent2 (Debian Trixie)|Linux by Zabbix agent|

> VVY roda Debian Trixie (13) – incompatível com `zabbix-agent` padrão. Instalado `zabbix-agent2`. Hostname corrigido para `vvy` em `/etc/zabbix/zabbix_agent2.conf`

### Thresholds Ajustados

|Macro|Valor Padrão|Valor Ajustado|Motivo|
|---|---|---|---|
|`{$MEMORY.UTIL.MAX}`|90|97|Linux usa RAM livre como cache – falso positivo no homelab|
|`{$LOAD_AVG_PER_CPU.MAX.WARN}`|1.5|3|Carga normal em servidor com múltiplos containers|
|`{$CPU.UTIL.CRIT}`|90|95|Margem mais realista para o ambiente|
