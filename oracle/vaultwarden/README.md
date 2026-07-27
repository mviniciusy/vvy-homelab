# Vaultwarden — Oracle Cloud VM

## Visão geral

| Item | Valor |
|---|---|
| Servidor | Oracle Cloud VM (Arm A1 Flex, 2 OCPU, 12GB RAM, 200GB) |
| IP público | <ORACLE_PUBLIC_IP> (efêmero) |
| Domínio | `<DUCKDNS_SUBDOMAIN>.duckdns.org` |
| DNS dinâmico | DuckDNS (cron job a cada 5 min) |
| HTTPS | Caddy + Let's Encrypt automático |
| Aplicação | Vaultwarden (compatível com apps Bitwarden oficiais) |
| Provisionado em | 2026-07-27 |

## Decisões

| Decisão | Escolha | Motivo |
|---|---|---|
| Vaultwarden vs Bitwarden oficial | **Vaultwarden** | 1 container (~30MB RAM) vs 8+ containers (~2GB). Mesma API, mesma compatibilidade com apps |
| DNS dinâmico | **DuckDNS** | NO-IP já usado para vvy (casa). DuckDNS gratuito, 5 subdomínios, cliente simples (curl) |
| Reverse proxy | **Caddy** | Let's Encrypt automático nativo, configuração mínima, HTTP/3 |
| Banco de dados | **SQLite** (default Vaultwarden) | Adequado para uso pessoal, sem overhead de PostgreSQL |

## Arquitetura

```
Internet → <DUCKDNS_SUBDOMAIN>.duckdns.org (<ORACLE_PUBLIC_IP>)
    → Security List VCN (80/443)
        → iptables interno (80/443 antes do REJECT catch-all)
            → Caddy (:80, :443)
                → Vaultwarden (:80 interno)
```

## Portas de rede

| Camada | Porta | Protocolo | Regra |
|---|---|---|---|
| Security List VCN (OCI) | 80 | TCP | Ingress 0.0.0.0/0 |
| Security List VCN (OCI) | 443 | TCP | Ingress 0.0.0.0/0 |
| iptables interno VM | 80 | TCP | ACCEPT antes do REJECT (linha 7) |
| iptables interno VM | 443 | TCP | ACCEPT antes do REJECT (linha 7) |
| iptables interno VM | 22 | TCP | SSH (pré-existente) |

> **Pitfall iptables Oracle**: A imagem Ubuntu da Oracle tem regra catch-all REJECT no iptables. Regras do UFW ficam DEPOIS do REJECT e não funcionam. Solução: `iptables -I INPUT 7 -p tcp --dport 80 -j ACCEPT` (insert, não append). Persistir com `netfilter-persistent save`.

## DuckDNS

| Item | Valor |
|---|---|
| Subdomínio | `<DUCKDNS_SUBDOMAIN>` |
| Domínio completo | `<DUCKDNS_SUBDOMAIN>.duckdns.org` |
| Token | `[CENSURADO — ver sanitization-map.conf]` |
| Script | `/opt/duckdns/duckdns.sh` |
| Cron | `*/5 * * * *` em `/etc/cron.d/duckdns` |

Script:
```bash
#!/bin/bash
curl -s "https://www.duckdns.org/update?domains=<DUCKDNS_SUBDOMAIN>&token=<TOKEN>&ip=" > /dev/null 2>&1
```

## Stack Docker

Caminho: `/opt/vaultwarden/`

### docker-compose.yml

```yaml
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    environment:
      - DOMAIN=https://<DUCKDNS_SUBDOMAIN>.duckdns.org
      - SIGNUPS_ALLOWED=true
      - INVITATIONS_ALLOWED=true
      - SHOW_PASSWORD_HINT=false
      - WEBSOCKET_ENABLED=true
    volumes:
      - ./data:/data
    networks:
      - vaultnet

  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - vaultnet
    depends_on:
      - vaultwarden

networks:
  vaultnet:

volumes:
  caddy_data:
  caddy_config:
```

### Caddyfile

```caddy
<DUCKDNS_SUBDOMAIN>.duckdns.org {
    reverse_proxy vaultwarden:80

    encode gzip zstd

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy no-referrer
    }
}
```

## Comandos de gestão

```bash
# Subir stack
cd /opt/vaultwarden && docker compose up -d

# Parar stack
cd /opt/vaultwarden && docker compose down

# Logs
docker logs -f caddy
docker logs -f vaultwarden

# Atualizar Vaultwarden
cd /opt/vaultwarden && docker compose pull && docker compose up -d

# Backup dos dados
tar -czf vaultwarden-backup-$(date +%Y%m%d).tar.gz /opt/vaultwarden/data/

# Forçar atualização do DuckDNS
/opt/duckdns/duckdns.sh
```

## Tailscale

| Item | Valor |
|---|---|
| Versão | 1.98.9 |
| Status | Instalado, pendente `tailscale up` |

## Próximos passos

- [ ] `tailscale up` na VM e adicionar à tailnet
- [ ] Após criar primeira conta admin no Vaultwarden, desabilitar `SIGNUPS_ALLOWED=false`
- [ ] Configurar backup automático dos dados do Vaultwarden
- [ ] Configurar alerta de downtime (opcional)
- [ ] WoL do vvy via Tailscale (futuro)
