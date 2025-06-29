#!/bin/bash

# ══════════════ COLORES ══════════════
RED='\e[31m'       # 🔴
GREEN='\e[32m'     # 🟢
YELLOW='\e[33m'    # 🟡
BLUE='\e[34m'      # 🔵
MAGENTA='\e[35m'   # 🟣
CYAN='\e[36m'      # 🟦
WHITE='\e[97m'     # ⚪
RESET='\e[0m'

# ══════════════ INFO DEL SISTEMA ══════════════
SO=$(lsb_release -d | cut -f2)
IP=$(curl -s ipv4.icanhazip.com)
FECHA=$(date +"%d-%m-%Y")
HORA=$(date +"%T")

# Disco
TOTAL_DISK=$(df -h / | awk 'NR==2 {print $2}')
USO_DISK=$(df -h / | awk 'NR==2 {print $3}')
LIBRE_DISK=$(df -h / | awk 'NR==2 {print $4}')

# RAM
TOTAL_RAM=$(free -h | awk '/Mem:/ {print $2}')
USO_RAM=$(free -h | awk '/Mem:/ {print $3}')
LIBRE_RAM=$(free -h | awk '/Mem:/ {print $4}')
BUFFER=$(free -h | awk '/Mem:/ {print $6}')
CACHE=$(free -h | awk '/Mem:/ {print $7}')

# CPU
CORES=$(nproc)
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8"%"}')

# Cuentas de ejemplo
ACTIVAS=45
EXPIRADAS=0
BLOQUEADAS=0
TOTAL=10

# ══════════════ PANEL VISUAL ══════════════
clear
echo -e "${MAGENTA}               @TuUsuario"
echo -e "${RED}╔══════════════════════════════════════════════╗"
echo -e "║${WHITE} S.O: ${CYAN}$SO${RED}         Fecha: ${CYAN}$FECHA${RED}      ║"
echo -e "║${WHITE} IP:  ${CYAN}$IP${RED}         Hora:  ${CYAN}$HORA${RED}       ║"
echo -e "╠══════════════╦══════════════╦══════════════╣"
echo -e "║${YELLOW}     Disco     ${RED}║${YELLOW}      CPU      ${RED}║${YELLOW}     RAM       ${RED}║"
echo -e "╠══════════════╬══════════════╬══════════════╣"
echo -e "║ Total: ${CYAN}$TOTAL_DISK${RED} ║ Cores: ${CYAN}$CORES${RED}     ║ Total: ${CYAN}$TOTAL_RAM${RED} ║"
echo -e "║ Usado: ${CYAN}$USO_DISK${RED} ║ Uso:   ${CYAN}$CPU_USAGE${RED} ║ Usado: ${CYAN}$USO_RAM${RED} ║"
echo -e "║ Libre: ${CYAN}$LIBRE_DISK${RED} ║                ║ Libre: ${CYAN}$LIBRE_RAM${RED} ║"
echo -e "║                         ║ Buffer: ${CYAN}$BUFFER${RED} ║"
echo -e "║                         ║ Cache:  ${CYAN}$CACHE${RED} ║"
echo -e "╚══════════════════════════════════════════════╝"

# ══════════════ CONTADORES DE CUENTAS ══════════════
echo -e "${GREEN}  ACTIVA: ${ACTIVAS}  ${RED}EXPIRADA: ${EXPIRADAS}  ${BLUE}BLOQUEADA: ${BLOQUEADAS}  ${YELLOW}TOTAL: ${TOTAL}${RESET}"

# ══════════════ MENÚ ══════════════
echo -e "${CYAN}"
echo    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${WHITE}[1]${RESET} ADMINISTRAR CUENTAS (SSH/DROPBEAR)"
echo -e "${WHITE}[2]${RESET} ADMINISTRAR CUENTAS (V2RAY/XRAY)"
echo -e "${WHITE}[3]${RESET} CONFIGURACIÓN DE PROTOCOLOS"
echo -e "${WHITE}[4]${RESET} HERRAMIENTAS EXTRAS"
echo -e "${WHITE}[5]${RESET} CONFIGURACIÓN DEL SCRIPT"
echo -e "${WHITE}[6]${RESET} IDIOMA / LANGUAGE"
echo -e "${WHITE}[7]${YELLOW}[!] DESINSTALAR PANEL${RESET}"
echo -e "${WHITE}[0]${RED} SALIR DEL VPS ${WHITE}[8]${RESET} SALIR DEL SCRIPT ${WHITE}[9]${BLUE} REINICIAR VPS${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ══════════════ ENTRADA DE OPCIÓN ══════════════
echo -ne "${GREEN}Ingrese una opción: ${RESET}"
read opcion
