# Container n8n para Orquestração de Workflows IA

> **Versão:** Abril/2026 | **Autor:** Vinícius Souza

---

## 1. Container n8n para Orquestração de Workflows IA

> Adicionado em Abril/2026 – baseado no LXC 103

### Diagrama do Workflow Multi-agente

```mermaid
sequenceDiagram
    participant Trigger as Trigger<br/>(webhook/schedule)
    participant Ollama1 as Ollama<br/>(qwen3.5:9b)
    participant Exec as Execute Command<br/>(SSH no Host/LXC)
    participant Ollama2 as Ollama<br/>(qwen2.5-coder)
    participant File as Write to File<br/>(markdown)

    Trigger->>Ollama1: Gera comando shell<br/>com base no objetivo
    Ollama1->>Exec: Comando gerado
    Exec->>Exec: Executa e captura saída
    Exec->>Ollama2: Comando + saída<br/>para documentação
    Ollama2->>File: Documentação técnica<br/>em markdown
```

### 1.1 Visão Geral

O **n8n** é uma ferramenta de automação de workflows (low-code) que permite conectar diferentes serviços e APIs. Neste homelab, ele é usado para orquestrar interações entre os LLMs locais (Ollama) e outras fontes de dados, além de coordenar ações no terminal e documentar resultados em tempo real.

### 1.2 Especificações do Container

|Item|Valor|
|---|---|
|**ID**|103|
|**Nome**|n8n|
|**Função**|Orquestrador de workflows IA|
|**IP**|`<N8N_IP>`|
|**Porta UI**|5678|
|**Cores**|4|
|**Storage**|nvme128:20G|
|**Acesso Web**|`http://<N8N_IP>:5678`|

### 1.3 Stack Tecnológica (dentro do LXC)

|Componente|Versão|Observação|
|---|---|---|
|Docker|29.4.1|Engine + CLI|
|Docker Compose|5.1.3|Plugin integrado|
|n8n|2.17.7|Imagem oficial `n8nio/n8n`|
|Armazenamento persistente|Volume Docker `n8n_data`|Localizado no storage nvme128|

### 1.4 Integração com o Ecossistema

- **Ollama local:** O n8n chama a API do container `ollama` (`<OLLAMA_IP>:11434`) usando nós HTTP Request. Pode usar qualquer modelo disponível (Qwen2.5-Coder, Qwen3.5:9b, ou os customizados `qwen-admin`/`qwen2-admin`).

- **Acesso via Tailscale:** Disponível em `http://<N8N_IP>:5678` através do Subnet Router do Proxmox.

- **Segurança:** Como o n8n é acessível apenas na rede local (e via Tailscale), a variável `N8N_SECURE_COOKIE=false` foi configurada para permitir acesso HTTP sem certificado TLS.


### 1.5 Exemplo de Uso (Workflow Multi‑agente)

Um workflow típico que implementa o conceito de "IA age no terminal enquanto outra documenta" pode ser estruturado assim:

1. **Trigger** (webhook ou schedule) inicia o workflow.

2. **Nó HTTP Request** chama o Ollama (ex.: `qwen3.5:9b`) para gerar um comando shell com base em um objetivo.

3. **Nó Execute Command** (SSH no host Proxmox ou diretamente no LXC) executa o comando e captura a saída.

4. **Nó HTTP Request** chama um segundo modelo (ex.: `qwen2.5-coder:latest`) com o prompt: _"Documente o comando [comando] e sua saída [saída] em um parágrafo técnico."_

5. **Nó Write to File** (ou Append to File) salva a documentação em um arquivo markdown dentro do container ou em um dos HDs montados.


> ℹ️ O n8n não acelera nem desacelera a inferência dos modelos – a performance é sempre limitada pela GPU RTX 3060 do LXC 102. O ganho está na automação e orquestração.

### 1.6 Comandos Úteis (a partir do host Proxmox)

|Ação|Comando|
|---|---|
|Entrar no container|`pct enter 103`|
|Ver logs do n8n (Docker)|`docker logs n8n -f`|
|Reiniciar o n8n|`docker restart n8n`|
|Atualizar imagem do n8n|`docker pull n8nio/n8n && docker-compose down && docker-compose up -d` (se usar compose)|
