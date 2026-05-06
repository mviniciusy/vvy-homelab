#!/bin/bash
# ============================================================================
# nvidia-fan-control.sh - Controle de fans da GPU RTX 3060
#
# Fixa as fans em 70% para evitar superaquecimento e travamento do servidor.
# Executado pelo nvidia-fancontrol.service após o Xorg headless iniciar.
#
# Atualizado em: Maio/2026 - Fans fixadas em 70% (antes 100%)
# ============================================================================

set -e
export DISPLAY=:1

# Aguardar Xorg iniciar
sleep 5

# Ativar controle manual de fan
/usr/bin/nvidia-settings -a '[gpu:0]/GPUFanControlState=1'

# Fixar fans em 70%
/usr/bin/nvidia-settings -a '[fan:0]/GPUTargetFanSpeed=70'
/usr/bin/nvidia-settings -a '[fan:1]/GPUTargetFanSpeed=70'

# Verificar se aplicou corretamente
/usr/bin/nvidia-settings -q '[gpu:0]/GPUFanControlState' -q '[fan:0]/GPUTargetFanSpeed' -q '[fan:1]/GPUTargetFanSpeed'
