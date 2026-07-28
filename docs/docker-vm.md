# VM Debian para Docker

> **Versão:** Abril/2026 | **Autor:** Vinícius Souza

---

## 1. VM Debian para Docker (docker-host)

|Parâmetro|Valor|
|---|---|
|ID da VM|200|
|Nome|debian|
|vCPUs|8|
|RAM|4 GB|
|Disco de sistema|32 GB (storage `nvme128`)|
|Disco de dados|100 GB (storage `HD-WD500GB`, montado em `/mnt/dados`)|
|Sistema operacional|Debian 12.12 (Bookworm), sem interface gráfica|
|IP|`<DOCKER_VM_IP>` (DHCP, reservado via roteador)|
|MAC address|`<DOCKER_VM_MAC>`|
|Acesso SSH|`debian@<DOCKER_VM_IP>`|
|Docker|versão estável (via repositório oficial)|
|Portainer|`https://<DOCKER_VM_IP>:9443` (interface web de gerenciamento Docker)|
|Data de criação|Abril/2026|

> **Jul/2026:**
> - SSH root com senha definida (chave `id_ed25519` do notebook + Hermes instaladas).
> - Python 3.11.2 presente. Node.js **não instalado** (necessário para terabox-backup-manager).
> - Acesso aos HDs do host: **não montado** — precisa configurar NFS ou bind mount.
> - App planejado: TeraBox Backup Manager (deploy nesta VM via Docker). Ver `Plano_Backup/Plano_App_TeraBox_Backup_Manager.md`.
> - Containers rodando: `finai_postgres` (porta 5432), `portainer` (9000/9443).
>
> **Correção 28/07/2026 (emergency mode):**
> - Disco de dados (`/dev/sdb`, 100GB) estava montado por device path no fstab sem `nofail`. Quando o disco não aparecia no boot, systemd caía em emergency mode com root locked.
> - Corrigido: fstab agora usa `UUID=<VM200_DADOS_DISK_UUID>` com opção `defaults,nofail`. A VM boota normalmente mesmo se o disco secundário não estiver disponível.
> - Journal recovery do disco secundário concluído (`e2fsck -fp /dev/sdb`).
> - Senha do root definida (estava locked).


---

## 2. SearXNG — Metasearch Self-Hosted (Jul/2026)

|Parâmetro|Valor|
|---|---|
|Container|`searxng` (imagem `searxng/searxng:latest`)|
|Porta|`8888:8080` (host:container)|
|IP|`<DOCKER_VM_IP>:8888`|
|Config|`/root/searxng/docker-compose.yml` + `settings.yml`|
|Compose|`cd /root/searxng && docker compose up -d`|
|Persistência|Stateless (sem volume de dados, config via bind mount)|
|Restart policy|`unless-stopped`|

### Funcionamento

- Metasearch que agrega 70+ motores (Google, Bing, DuckDuckGo, etc.)
- Retorna resultados em JSON (`format=json` na query string)
- Sem API key, sem limite de uso, sem custo
- Usado pelo Hermes Agent (CT 104) como backend de `web_search` via
  `SEARXNG_URL=http://<DOCKER_VM_IP>:8888` no `.env` e
  `web.backend: searxng` no `config.yaml`

### Comandos

```bash
# Gerenciar via qm guest exec (do CT 104)
ssh root@<HOST_IP> 'qm guest exec 200 -- docker compose -f /root/searxng/docker-compose.yml up -d'
ssh root@<HOST_IP> 'qm guest exec 200 -- docker compose -f /root/searxng/docker-compose.yml down'

# Testar busca
curl -s 'http://<DOCKER_VM_IP>:8888/search?q=test&format=json' | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results',[])), 'results')"

# Logs
ssh root@<HOST_IP> 'qm guest exec 200 -- docker logs searxng --tail 20'
```

### Web Extract (alternativa)

O SearXNG é search-only (não faz extract de URL). Para extrair conteúdo
de páginas em markdown, o Hermes usa o **Jina Reader SaaS** (`r.jina.ai`)
via `curl` — grátis, sem API key, sem self-hosting:

```bash
# Extrair página em markdown limpo
curl -sL 'https://r.jina.ai/https://exemplo.com'
```

> Considerou-se self-hostar o Jina Reader (`ghcr.io/jina-ai/reader:oss`)
> nesta VM, mas foi descartado pela RAM limitada (3.8 GB alocados, Chrome
> headless consome ~500MB-1GB). O SaaS via curl custa zero RAM e zero
> manutenção.
