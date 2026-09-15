# Zomboid Server na VM Oracle (resumo público)

> Tutorial completo com credenciais está fora do git, em `2 Oracle/Zomboid Server/`
> (host vvy). Este arquivo documenta a arquitetura e o acesso sem segredos.

## O que roda

Servidor dedicado **Project Zomboid Build 42.20.4** dentro do container
`etheth888/project-zomboid-arm64:main` (imagem ARM64 com **FEX-Emu** embutido,
repo https://github.com/EthanHand/project-zomboid-docker-arm64). Limites do
container: `--cpus 4 --memory 16g`, heap JVM `-Xmx12g`. O jogo é x86_64-only;
em Arm roda emulado. Os binários do servidor e o mundo são montados de
`/srv/zomboid/server` e `/srv/zomboid/data` na VM Oracle (obtados via Steam no
PC — o app dedicado 380870 não baixa mais anonimamente).

## Fix crítico obrigatório (B42 em emulação)

`ProjectZomboid64.json`: trocar `-XX:+UseZGC` por `-XX:+UseG1GC` + flags de
reflection (`-Dsun.reflect.noInflation=true`,
`-Djdk.reflect.useDirectMethodHandle=false`,
`-XX:CompileCommand=exclude,java/lang/Class,reflectionData`). ZGC não emula e
causa SIGILL/SIGSEGV no boot (receita do README do Danixu).

## Portas exigidas (wiki oficial / README Danixu)

| Uso | Protocolo | Porta |
|---|---|---|
| Steam matchmaking | UDP | 8766, 8767 |
| Porta do jogo (config. `PORT`) | UDP | 16261 |
| Handshake adicional | UDP | 16262 |
| Slots de cliente (1 TCP por jogador) | TCP | 16262-16272 |

Mudando a porta base, a faixa TCP acompanha (PORT=12234 → TCP 12234-12244).

As portas passam por 3 camadas, todas liberadas:
1. **Security List da VCN** (`vvy-vcn`): UDP 16261-16262, UDP 8766-8767, TCP 16262-16272 — gerenciável via OCI CLI (receita na skill `oracle-cloud` / doc da API key)
2. **iptables interno da VM**: regras `-I INPUT 6 ...` antes do REJECT, persistidas (`netfilter-persistent`)
3. **Docker publish**: `-p` no `docker run` do container `zomboid`

## Conexão dos jogadores

`<IP_PÚBLICO_DA_VM>:16261` (recomendado hostname DuckDNS próprio; IP efêmero atual
é reservável). Adicionar pelo *Add New Server* do jogo. **GSLT (Game Server Login
Token)** é obrigatório para multiplayer Steam no B42: sem token, o cliente trava em
"obtendo informações". Gerar em `https://steamcommunity.com/dev/managegameservers`
na conta que possui o jogo (App ID `108600`), aplicar com `steam=1` +
`-authglslt <TOKEN>` no start.

## Comandos úteis (VM Oracle)

```bash
docker ps | grep zomboid
docker exec zomboid bash -c 'tail -20 /home/steam/ZomboidData/pz.log'
docker restart zomboid          # aplicar pzvvy.ini
ss -lun | grep -cE "1626[12]"   # portas abertas
```

## Manutenção

- Configs de jogo: `/srv/zomboid/data/Server/pzvvy.ini` e
  `pzvvy_SandboxVars.lua`
- Backups do mundo: o próprio servidor gera em `/srv/zomboid/data/backups/`
- Update de build: baixar de novo no PC (Steam → Tools → Dedicated Server) →
  copiar para o share do vvy → `rsync` vvy → VM (path:
  `/mnt/pve/HD-WD500GB/Dados-WD500GB/zomboid/pz-server-linux/`)
