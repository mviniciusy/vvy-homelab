# Infraestrutura de IA Local (Ollama)

> **Versão:** Abril/2026 | **Autor:** Vinícius Souza

---

## 12. Infraestrutura de IA Local (Ollama)

> Seção adicionada em Abril/2026

### Diagrama do GPU Passthrough

```mermaid
graph TB
    subgraph Host Proxmox - vvy
        Driver[NVIDIA Driver 555.58.02<br/>Host Proxmox]
        GPU[RTX 3060 12GB<br/>CUDA 12.5]
    end

    subgraph LXC 102 - ollama Privilegiado
        DevNVIDIA[/dev/nvidia*<br/>nvidia0, nvidiactl<br/>nvidia-modeset, nvidia-uvm]
        OllamaSvc[Ollama Service<br/>:11434]
        Models[Modelos<br/>qwen2.5-coder<br/>qwen3.5:9b<br/>qwen-admin<br/>qwen2-admin]
    end

    Driver --> GPU
    GPU -->|Passthrough| DevNVIDIA
    DevNVIDIA --> OllamaSvc
    OllamaSvc --> Models

    subgraph Clientes
        Cline[Cline<br/>VS Code Extension]
        Continue[Continue<br/>VS Code Extension]
        N8N[n8n<br/>LXC 103]
    end

    OllamaSvc -->|HTTP API :11434| Cline
    OllamaSvc -->|HTTP API :11434| Continue
    OllamaSvc -->|HTTP API :11434| N8N

    style GPU fill:#f9a825,stroke:#f57f17,color:#000
    style OllamaSvc fill:#4caf50,stroke:#2e7d32,color:#fff
```

### 12.1 Container 102 – Backend de Processamento (Ollama)

|Item|Detalhe|
|---|---|
|Função|Núcleo de processamento LLM com aceleração de hardware|
|Hostname|ollama|
|IP|`<OLLAMA_IP>`|

### Configurações Realizadas

- **Migração de Repositório:** Sistema atualizado para Debian Trixie (Testing) para compatibilidade com bibliotecas modernas (`libssl3t64`).

- **Drivers NVIDIA:** Instalação manual da versão 555.58.02 via pacotes `.deb` injetados por `pct push`, garantindo o casamento exato com o driver do Host Proxmox.

- **GPU Passthrough:** Configuração bem-sucedida da RTX 3060 12GB. Validação via `nvidia-smi` operando com CUDA 12.5.

- **Ollama Service:** Instalação do binário em `/usr/local/bin/ollama`. Configuração de variável de ambiente `OLLAMA_HOST=0.0.0.0` no `systemctl edit ollama.service` para permitir conexões externas (Cline e Continue).

- **Modelos:** Qwen2.5-Coder (autocomplete/desenvolvimento) e Qwen3.5:9b (chat/agente).

- **Shell:** Instalação de Oh My Zsh com o tema padronizado VVY.

- **Symlink:** Criado symlink `/usr/bin/ollama` → `/usr/local/bin/ollama` para permitir execução direta do comando `ollama` sem caminho completo.

- **Script de atalho:** Criado script `/usr/bin/qwen` que executa `ollama run qwen2.5-coder:latest` com um único comando.


### 12.2 Otimizações de Performance (Abril/2026)

#### Variáveis de Ambiente do Ollama (`/etc/systemd/system/ollama.service`)

|Variável|Valor|Descrição|
|---|---|---|
|`OLLAMA_FLASH_ATTENTION`|`1`|Flash Attention ativado — reduz consumo de VRAM e aumenta velocidade de inferência|
|`OLLAMA_KEEP_ALIVE`|`86400`|Modelo permanece carregado na VRAM por 24h — elimina recarregamento a cada uso|
|`OLLAMA_MAX_LOADED_MODELS`|`1`|Apenas 1 modelo carregado por vez — mais VRAM disponível por requisição|

#### Swappiness do Host Proxmox

|Parâmetro|Valor Anterior|Valor Atual|Detalhe|
|---|---|---|---|
|`vm.swappiness`|60|1|O sistema só faz swap em extrema necessidade, priorizando RAM para offload da GPU|

> ℹ️ Configuração persistente em `/etc/sysctl.conf` — sobrevive a reinicializações.

### 12.3 Criação de Modelfiles para Qwen 2.5 e 3.5

Os **Modelfiles** permitem customizar o comportamento padrão dos modelos, definindo parâmetros como contexto, temperatura e um prompt de sistema específico para tarefas administrativas. Abaixo estão as configurações utilizadas no ambiente.

#### Modelos base

- `qwen2.5-coder:latest`

- `qwen3.5:9b`


#### Criar o arquivo do Modelfile para Qwen 3.5

```
nano Modelfile.qwen
```

**Conteúdo:**

```dockerfile
FROM qwen3.5:9b
PARAMETER num_ctx 32768 # 32k é o ponto ideal para 12GB de VRAM
PARAMETER temperature 0
PARAMETER stop "thought"
SYSTEM "Você é um administrador de sistemas Linux. Se um comando falhar, não o repita. Analise o erro, explique o motivo e tente uma abordagem diferente."
```

#### Criar o arquivo do Modelfile para Qwen 2.5 Coder

```
nano Modelfile.qwen2
```

**Conteúdo (exemplo adaptado para autocomplete/assistente de código):**

```dockerfile
FROM qwen2.5-coder:latest
PARAMETER num_ctx 16384 # contexto suficiente para código
PARAMETER temperature 0.2
SYSTEM "Você é um assistente especialista em programação Linux. Responda com código limpo e explicações concisas."
```

#### Aplicar os Modelfiles

**Qwen 3.5 (chat/agente):**
```bash
ollama create qwen-admin -f Modelfile.qwen
```

**Qwen 2.5 (autocomplete/code):**
```bash
ollama create qwen2-admin -f Modelfile.qwen2
```

Após a criação, os novos modelos customizados estarão disponíveis como `qwen-admin` e `qwen2-admin` para uso nas integrações (Cline, Continue etc.).
