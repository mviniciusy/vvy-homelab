# Monitoramento de Infraestrutura (Grafana + Prometheus)

> **Versão:** Abril/2026 | **Autor:** Vinícius Souza

---

## 9. Monitoramento de Infraestrutura (Grafana + Prometheus)

### Diagrama do Stack de Monitoramento

```mermaid
graph LR
    subgraph Host Proxmox - vvy
        NE_Host[Node Exporter<br/>:9100]
    end

    subgraph LXC 161 - grafana
        NE_CT[Node Exporter<br/>:9100]
        Prom[Prometheus<br/>:9090]
        Grafana[Grafana 12.4<br/>:3000]
    end

    NE_Host -->|scrape| Prom
    NE_CT -->|scrape| Prom
    Prom -->|data source| Grafana
```

|Componente|Versão|Porta|Função|
|---|---|---|---|
|Grafana|12.4.2|3000|Dashboard visual – acesso via navegador|
|Prometheus|via apt Debian|9090|Banco de séries temporais – coleta e armazena métricas|
|Node Exporter|via apt Debian|9100|Agente de coleta – instalado no VVY e no container 161|

### URLs de Acesso

- **Grafana:** `http://<GRAFANA_IP>:3000` (usuário: `<GRAFANA_ADMIN_USER>`)

- **Prometheus UI:** `http://<GRAFANA_IP>:9090`


### Targets Prometheus

|Job|Endpoint|Alvo|Status|
|---|---|---|---|
|prometheus|localhost:9090|Próprio Prometheus|UP|
|node_exporter_grafana|localhost:9100|Container 161 (grafana)|UP|
|node_exporter_vvy|`<HOST_IP>`:9100|Host Proxmox VVY|UP|
