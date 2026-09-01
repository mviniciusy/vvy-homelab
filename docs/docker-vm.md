# VM Debian para Docker

> **Versão:** Abril/2026 | **Autor:** Vinícius Souza

---

## 1. VM Debian para Docker (docker-host)

|Parâmetro|Valor|
|---|---|
|ID da VM|200|
|Nome|debian|
|vCPUs|8|
|RAM|10 GB|
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
> - Python 3.11.2 presente. Node.js não instalado.
> - Acesso aos HDs do host: **não montado** — precisa configurar NFS ou bind mount.
> - Containers rodando: `finai_postgres` (porta 5432), `portainer` (9000/9443).
>
> **Correção 28/07/2026 (emergency mode):**
> - Disco de dados (`/dev/sdb`, 100GB) estava montado por device path no fstab sem `nofail`. Quando o disco não aparecia no boot, systemd caía em emergency mode com root locked.
> - Corrigido: fstab agora usa `UUID=<VM200_DADOS_DISK_UUID>` com opção `defaults,nofail`. A VM boota normalmente mesmo se o disco secundário não estiver disponível.
> - Journal recovery do disco secundário concluído (`e2fsck -fp /dev/sdb`).
> - Senha do root definida (estava locked).

> **Set/2026 (estado atual):**
> - RAM aumentada para 10 GB. Node.js 22.23.1 e Python 3.11.2 instalados.
> - Containers ativos: `gemini-fastapi` (porta 4981), `omniroute-prod` (20130/20131) + `omniroute-redis-prod`, `searxng` (8888), `portainer` (8000/9443).
> - Containers parados: `hojebelem-app-1` e `hojebelem-postgres-1` (Exited 255 desde ~22/Ago), `hojebelem-collector-1` em restart loop.
> - Disco de sistema `/dev/sda1` (31G): 87% em 01/Set; limpeza no mesmo dia (build cache 7.6 GB, 4 imagens antigas, journal, apt cache, vscode-server antigo) reduziu para **43%** (13G usados). Docker Engine usa containerd image store (`/var/lib/containerd`) — sem `daemon.json`; `/mnt/dados` (sdb) guarda apenas configs/bind mounts.


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

---

## 3. Hoje Belém — Site de Eventos (Ago/2026)

|Parâmetro|Valor|
|---|---|
|Repo|`github.com/ingridslv/hojebelem` (público, colaborador)|
|Stack|Next.js 16.3.1 + React 19 + Prisma 6 + Postgres 16 + NextAuth v5 (email/senha)|
|Local|`/opt/hojebelem` (git clone)|
|Acesso|http://<DOCKER_VM_IP>:3000 (LAN)|
|Admin seed|`admin@hojebelem.local` (senha temporária do README)|
|Compose|`docker compose up -d --build` — postgres + app|
|Volumes|`postgres_data` (banco), `uploads_data` (/app/public/uploads)|
|Restart|`unless-stopped` (override local)|

### Container
- `hojebelem-app-1` — Next.js na porta 3000 (imagem `hojebelem-app:latest`)
- `hojebelem-postgres-1` — Postgres 16 na porta 5432 (imagem `postgres:16-alpine`)

### Arquivos locais (fora do git, via .git/info/exclude)
- `Dockerfile.local` — igual ao Dockerfile do repo, mas aceita ARG `DATABASE_URL` no build
- `docker-compose.override.yml` — restart unless-stopped + volumes de uploads + `AUTH_TRUST_HOST=true`
- `package-lock.json` / `src/app/layout.tsx` — correções locais na branch `fix/local-build` (pendente PR)

### Por que o Dockerfile.local?
- O Dockerfile original do repo builda sem `DATABASE_URL`; as páginas admin consultam
  Prisma no prerender (`/admin/eventos`) e o `next build` quebra.
- `Dockerfile.local` recebe a URL via build ARG; o Postgres deve estar de pé antes do build:
  ```bash
  cd /opt/hojebelem
  docker compose up -d postgres
  export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/hojebelem?schema=public"
  npx prisma migrate deploy
  docker compose build app && docker compose up -d
  ```
- Correções do repo também aplicadas localmente:
  - `package-lock.json` regenerado (lock desatualizado: faltavam `@emnapi/*`).
  - `src/app/layout.tsx`: `LayoutProps<"/">` não existia — corrigido para `Readonly<{children: ReactNode}>`.

### Atualizar o site (pull + rebuild)
```bash
cd /opt/hojebelem && git pull
docker compose up -d postgres
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/hojebelem?schema=public"
npx prisma migrate deploy   # se houver migration nova
docker compose build app && docker compose up -d
```

### Observações
- Google OAuth só ativa se `GOOGLE_CLIENT_ID/SECRET` estiverem no compose — não configurado.
- **Set/2026:** containers desativados intencionalmente em 01/Set (`docker stop` em app-1, postgres-1 e collector-1 — encerra o restart loop do collector; imagens e volumes preservados). Site offline até novo `docker compose up -d`.
- VM 200 não roda tailscaled, mas é alcançável de fora da LAN via subnet routing do vvy (`192.168.1.0/24` anunciado no Tailscale) — o link `http://<DOCKER_VM_IP>:3000` funciona de qualquer lugar com o cliente conectado.
