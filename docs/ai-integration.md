# Integração com Ambiente de Desenvolvimento

> **Versão:** Abril/2026 | **Autor:** Vinícius Souza

---

## 13. Integração com Ambiente de Desenvolvimento

> Seção adicionada em Abril/2026

### 13.1 Cline (VS Code Extension) – Agente

|Parâmetro|Valor|
|---|---|
|Provider|Ollama|
|Base URL|`http://<OLLAMA_IP>:11434`|
|Modelo|`qwen3.5:9b`|
|Capacidades|O agente possui permissão para ler/escrever arquivos no servidor e executar comandos no terminal usando a VRAM da RTX 3060|

### 13.2 Continue (VS Code Extension) – Autocomplete e Chat

|Parâmetro|Valor|
|---|---|
|Autocomplete|Qwen2.5-Coder via `http://<OLLAMA_IP>:11434`|
|Chat principal|Qwen3.5:9b via `http://<OLLAMA_IP>:11434`|
|Chat alternativo|Gemini Flash (API key configurada)|

### 13.3 Comandos de Monitoramento Críticos

|Descrição|Comando|Local de Execução|
|---|---|---|
|Monitoramento Global|`watch -n 1 nvidia-smi`|CT 102 (ollama) – valida uso de VRAM|
|Auditoria Rápida|`pct exec 102 -- nvidia-smi`|Host Proxmox (vvv) – auditoria sem entrar no CT|
