# OpenBot (servidor na VM Oracle)

> **Versão:** Nov/2026 | **Autor:** Vinícius Souza | **Última verificação no servidor:** 2026-11-03

---

## 1. Visão geral

O OpenBot é uma plataforma para rodar uma equipe de agentes de IA persistentes (cada agente tem nome, instruções e espaço de trabalho; os agentes trocam mensagens e arquivos). O projeto está em "development preview" e usa a licença PolyForm Noncommercial 1.0.0 (uso pessoal).

No homelab ele roda em **modo servidor, na VM `vvy-vnic` da Oracle Cloud** (Ubuntu 24.04, arm64, 4 cores, 24 GB). Ele substituiu o agente de IA que rodava no CT 104 (destruído em 03/Nov/2026). O servidor se conecta para fora (conta e sinalização do OpenBot) e é acessado pelos apps: desktop (Windows), celular e navegador. A partir da Oracle ele alcança a casa (host Proxmox e VM Docker) por SSH, pelo Tailscale.

Dependências: conta do OpenBot, ao menos um provedor de IA conectado no servidor, Tailscale (para alcançar a LAN de casa) e as chaves SSH descritas na seção 5.

## 2. Especificações

| Item | Valor |
|---|---|
| Máquina | VM `vvy-vnic` (Oracle Cloud, `VM.Standard.A1.Flex`), 4 OCPU / 24 GB, disco de 200 GB |
| Endereços | público `<ORACLE_PUBLIC_IP>` (efêmero) · privado `<ORACLE_PRIVATE_IP>` · Tailscale `<TAILSCALE_ORACLE_VM_IP>` |
| Sistema | Ubuntu 24.04.4 LTS (aarch64), systemd |
| Versão do OpenBot | 0.59.0 (instalado em 03/Nov/2026 com `install-server.sh`) |
| Serviço | `openbot.service` (+ `openbot-update.timer`, `openbot-update.service`, `openbot-update-apply.service`, `openbot-update-request.path`) |
| Usuário de serviço | `openbot` (home `/var/lib/openbot`) |
| Binários | `/opt/OpenBot/app/` (aplicativo) e `/opt/OpenBot/hosted/openbot-hosted-server` (processo do servidor) |
| Dados | `/var/lib/openbot` e chave de criptografia em `/srv/openbot-hosted` (sempre juntos) |
| Socket de controle | `/run/openbot/control.sock` (só o usuário de serviço e o root) |
| Portas | nenhuma publicada (o servidor só conecta para fora) |
| Conta / servidor | conta `<OCI_TENANCY_EMAIL>`; servidor "OpenBot VPS" |
| Limites (systemd) | `MemoryHigh=10G`, `MemoryMax=12G`, `CPUQuota=300%` |
| Concorrência | até 16 turnos simultâneos (com mais de 10 GiB de memória disponível) |
| Pacotes trazidos pelo instalador | Xvfb (duas telas virtuais), gnome-keyring, bubblewrap, bibliotecas de áudio e vídeo, perfil do AppArmor, driver de "computer use" |

## 3. Instalação (resumo do que foi feito)

1. Acesso à VM: `ssh ubuntu@<ORACLE_PUBLIC_IP>` (chave ed25519 do notebook).
2. Instalador oficial: `curl -fsSL https://raw.githubusercontent.com/nightly-labs/openbot/main/scripts/install-server.sh | sudo bash`. Na primeira tentativa o `dpkg` estava ocupado por outro processo; esperar e repetir (nunca remover o arquivo de trava).
3. Login: `sudo openbot login --name "OpenBot VPS"` (e-mail e código enviado por e-mail). O servidor aparece na lista de servidores da conta, usada no desktop e no celular.
4. Limites: arquivo `/etc/systemd/system/openbot.service.d/limits.conf` com `MemoryHigh=10G`, `MemoryMax=12G` e `CPUQuota=300%`; depois `systemctl daemon-reload` e `sudo openbot restart`.
5. Antes da instalação, o `Vaultwarden` (na mesma VM) teve as permissões fechadas (`/opt/vaultwarden` 750, `data` 700), para o usuário `openbot` não ler o cofre.

## 4. Operação

| Ação | Comando |
|---|---|
| Estado do servidor e da conta | `sudo openbot status` |
| Logs ao vivo | `sudo openbot logs -f` |
| Reiniciar / parar / iniciar | `sudo openbot restart` · `stop` · `start` |
| Atualizar | `sudo openbot update` (reinicia o serviço; **fazer backup antes**) |
| Versão | `openbot version` |
| Parear o celular | `sudo openbot mobile-connect` (QR de uso único, expira em 2 min) |
| Renomear o servidor | `sudo openbot name "<nome>"` |
| Uso de CPU e memória por serviço | `systemd-cgtop` |
| Limites aplicados | `systemctl show openbot.service -p MemoryHigh -p MemoryMax -p CPUQuotaPerSecUSec` |
| Remover (mantém os dados) | `sudo openbot uninstall` |

Atualização automática: um timer prepara as versões novas; elas são aplicadas no próximo boot ou quando um administrador instala pela tela de atualizações do servidor.

## 5. Integração com o ecossistema

### 5.1 Acesso do OpenBot à casa (acesso total, decidido em 03/Nov/2026)

O usuário `openbot` tem um par de chaves ed25519 próprio (comentário `openbot@vvy-vnic`, sem senha, em `/var/lib/openbot/.ssh/`, permissão 600). A chave pública está autorizada como **root** em:

| Destino | Endereço | Alias no `~/.ssh/config` do `openbot` |
|---|---|---|
| Host Proxmox `vvy` | `<HOST_IP>` (LAN, por rota de sub-rede do Tailscale) ou `<TAILSCALE_VVV_IP>` (Tailscale) | `vvy` |
| VM Docker (VM 200) | `<DOCKER_VM_IP>` | `docker-vm` |

Testado em 03/Nov/2026: `ssh vvy` e `ssh docker-vm` funcionam a partir da Oracle, sem senha. Cada acesso passa pelo Tailscale (latência de cerca de 36 ms).

- No host Proxmox o `/root/.ssh/authorized_keys` é um **link para `/etc/pve/priv/authorized_keys`**: editar sempre com `>>` ou em arquivo temporário (nunca redirecionar para o próprio arquivo).
- Chaves autorizadas hoje no host: notebook (RSA e ed25519), `root@vvy`, `root@n8n` (container destruído, pode sair), `ubuntu@vvy-vnic` (Oracle, usada pelo WoL) e `openbot@vvy-vnic`.
- A Oracle também alcança a VM 200 por serviços HTTP: OmniRoute (`:20130`), Gemini-FastAPI (`:4981`) e SearXNG (`:8888`), sem consumidor configurado no OpenBot por enquanto.
- Revogar o acesso: remover a linha `openbot@vvy-vnic` do `authorized_keys` do host e da VM 200.

Riscos aceitos: um agente com root no host e na VM pode alterar ou apagar qualquer coisa nos dois. Se for necessário reduzir, trocar por usuário com `sudo` restrito ou por token de API do Proxmox com papel limitado.

### 5.2 Provedores de IA

- **NVIDIA NIM**: três provedores personalizados no app (NV1, NV2, NV3), base `https://integrate.api.nvidia.com/v1`, com cinco modelos cada (GLM 5.3 Flash, Deepseek v4.1 Flash, Nemotron 3.5 Super VL, Minimax M3.1 Flash, Nemotron 3 Ultra). Os segredos ficam no próprio OpenBot. Funcionam.
- **OpenCode**: o OpenBot traz um runtime próprio do OpenCode (2.2.5), separado do CLI instalado para o usuário `ubuntu`. O runtime guarda credenciais em um banco SQLite próprio (`/var/lib/openbot/.local/share/opencode/opencode.db`, tabela `credential`). Ver seção 7.

### 5.3 Monitoramento e backup

- **Monitoramento externo pela Oracle:** planejado, ainda não implementado.
- **Backup:** a Oracle **não entra no backup por decisão do usuário** (03/Nov/2026). Os dados do OpenBot (`/var/lib/openbot` + `/srv/openbot-hosted`) e do Vaultwarden não têm backup automático.

## 6. Credenciais

| Credencial | Onde fica |
|---|---|
| Sessão da conta do OpenBot | gerenciada pelo próprio servidor (`/var/lib/openbot`); criptografada com a chave em `/srv/openbot-hosted` |
| Chaves dos provedores personalizados (NV1 a NV3) | dentro do OpenBot (arquivo `openbot-custom-providers-v1.json` guarda só o cadastro) |
| Credencial do OpenCode do OpenBot | banco do runtime, criada com `auth login --method device` |
| Credencial do OpenCode CLI | `/home/ubuntu/.local/share/opencode/auth.json` (600) |
| Chave SSH do `openbot` | `/var/lib/openbot/.ssh/id_ed25519` (600) |

Nenhum valor secreto é registrado neste documento.

## 7. Troubleshooting e pitfalls

| Sintoma | Causa | Correção |
|---|---|---|
| Instalador: `dpkg frontend lock` | outro processo de pacotes em andamento | esperar terminar e repetir; nunca remover a trava |
| `FreeUsageLimitError` nos modelos `opencode/*-free` | a cota gratuita do OpenCode é compartilhada e oscila; sem credencial o runtime cai no modo anônimo | autenticar o runtime: `sudo -u openbot -H bash -c 'cd ~ && /var/lib/openbot/.config/OpenBot/provider-runtimes/opencode/linux-arm64/2.2.5/bin/opencode auth login opencode --method device'` (abrir a URL e autorizar); alternativa: usar um modelo do NVIDIA NIM |
| Colei a chave na tela do OpenBot e não adiantou | a interface não preenche o banco de credenciais do OpenCode embutido | usar o comando acima |
| `PermissionDenied` ou `UnexpectedStatus: 500` ao usar o runtime pelo terminal | diretório atual inacessível ao usuário `openbot` (por exemplo `/home/ubuntu`) | sempre `cd ~` como o usuário `openbot` |
| Biblioteca `libasound.so.2` faltando no `/opt/OpenBot/app/openbot` | o `apt autoremove` (depois de remover o Java 21) apagou a `libasound2t64` | `sudo apt-get install -y libasound2t64` e `sudo apt-mark manual libasound2t64`; conferir com `ldd /opt/OpenBot/app/openbot \| grep "not found"` |
| Serviço morto ao estourar memória | `MemoryMax=12G` e a VM não tem swap | criar swap de 4 GB (`fallocate`, `mkswap`, `swapon`) ou diminuir a concorrência |
| `rpcbind` escutando na porta 111 | dependência instalada junto | bloqueado pelo firewall e pela Security List; sem ação |
| Mensagens `handshake failed ... net_error -107` repetidas no log | ruído de conexão TLS de um serviço externo (origem não identificada) | monitorar; não impediu o funcionamento |

Cuidados ao mexer nos pacotes da VM: não rodar `autoremove` sem conferir o que será removido; o OpenBot depende de bibliotecas que ele mesmo instalou como "automáticas".

## 8. Histórico de mudanças

- 2026-11-03 — Instalação do OpenBot 0.59.0 na Oracle, limites de 12 GB e 3 cores, login da conta, runtime do OpenCode autenticado, geração da chave SSH do `openbot` e autorização no host e na VM 200 (acesso total), remoção do Java 21, restauração da `libasound2t64`.
- 2026-11-03 — O CT 104 (agente de IA anterior) foi destruído; o OpenBot passou a ser o agente do homelab.

## 9. Pendências

- Monitoramento externo pela Oracle (planejamento salvo na pasta de backup do usuário).
- Backup dos dados do OpenBot e do Vaultwarden (a Oracle ainda não entra no backup).
- Avaliar acesso mais restrito ao host (token com papel limitado) em vez de root.
- Desativar autenticação por senha no `sshd` da Oracle.
- Consumo opcional do OmniRoute, Gemini-FastAPI e SearXNG (VM 200) como provedores do OpenBot.