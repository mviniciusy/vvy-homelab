#!/bin/bash
LOG_FILE="/root/logs/telemetry.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# Coleta de dados
TEMP=$(sensors | grep "Package id 0" | awk '{print $4}')
RAM=$(free -m | awk '/Mem:/ { print $3 "/" $2 "MB" }')
LOAD=$(uptime | awk -F'load average:' '{ print $2 }')

# Escreve no arquivo
echo "[$TIMESTAMP] Temp: $TEMP | RAM: $RAM | Load: $LOAD" >> $LOG_FILE

# Mantém apenas as últimas 10.000 linhas
tail -n 10000 $LOG_FILE > ${LOG_FILE}.tmp && mv ${LOG_FILE}.tmp $LOG_FILE
