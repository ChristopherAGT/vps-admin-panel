#!/bin/bash

# Colores
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# ══════ INFO DEL SISTEMA ══════
USER_NAME="@$(whoami)"
SO=$(lsb_release -d | cut -f2-)
DATE=$(date +"%d-%m-%Y")
TIME=$(date +"%T")
IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

# Disco
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')

# RAM
read total used free shared buff cache <<< $(free -m | awk '/Mem:/ {print $2, $3, $4, $5, $6, $7}')
RAM_TOTAL="${total}MB"
RAM_USED="${used}MB"
RAM_FREE="${free}MB"
RAM_BUFFER="${buff}MB"
RAM_CACHE="${cache}MB"

# CPU
CPU_CORES=$(nproc)
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')%

# ══════ FUNCIÓN: PUERTOS ACTIVOS CON SERVICIOS ══════
obtener_puertos_activos() {
  ss -tulnp 2>/dev/null | awk 'NR>1' | while read -r linea; do
    puerto=$(echo "$linea" | awk '{split($5,p,":"); print p[length(p)]}')
    servicio=$(echo "$linea" | grep -oP 'users:\(\(".*?"' | cut -d'"' -f2)
    [ -z "$servicio" ] && servicio="desconocido"
    printf "%-25s : %s\n" "$servicio" "$puerto"
  done | sort -u
}

# ══════ MOSTRAR PANEL ══════
mostrar_panel() {
  clear
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${RESET}"
  printf "                            ${YELLOW}%-60s${RESET}\n" "$USER_NAME"
  echo -e "${CYAN}╔═════════════════════════════════════════════════════════════════════════════╗${RESET}"
  printf "  %-40s Fecha:  %s\n" "S.O:     $SO" "$DATE"
  printf "  %-40s Hora:   %s\n" "IP:      $IP" "$TIME"
  echo -e "${CYAN}╠════════════════════════ DISCO ═════════════════════╦══════ CPU ══════╣${RESET}"
  printf "  %-35s %-10s Núcleos: %-2s\n" "Total:   $DISK_TOTAL  Usado: $DISK_USED" "" "$CPU_CORES"
  printf "  %-35s %-10s Uso:     %s\n" "Libre:   $DISK_FREE" "" "$CPU_USAGE"
  echo -e "${CYAN}╠════════════════════════════ MEMORIA RAM ═════════════════════════════════════╣${RESET}"
  printf "  %-20s %-20s %-20s\n" "Total:   $RAM_TOTAL" "Usada: $RAM_USED" "Libre: $RAM_FREE"
  printf "  %-20s %-20s\n" "Buffer:  $RAM_BUFFER" "Cache: $RAM_CACHE"
  echo -e "${CYAN}╠═════════════════════════ PUERTOS ACTIVOS ════════════════════════════════════╣${RESET}"

  mapfile -t PUERTOS < <(obtener_puertos_activos)
  for ((i = 0; i < ${#PUERTOS[@]}; i+=2)); do
    LEFT="${PUERTOS[i]}"
    RIGHT="${PUERTOS[i+1]}"
    printf "  %-39s %-39s\n" "$LEFT" "${RIGHT:-}"
  done

  echo -e "${CYAN}╠═════════════════════════ ESTADO DE CUENTAS ══════════════════════════════════╣${RESET}"
  echo -e "       ACTIVAS: 1     EXPIRADAS: 0     BLOQUEADAS: 0     TOTAL: 6"
  echo -e "${CYAN}╚═════════════════════════════════════════════════════════════════════════════╝${RESET}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${RESET}"
  echo -e "  [1] > GESTIÓN SSH / DROPBEAR"
  echo -e "  [2] > GESTIÓN V2RAY / XRAY"
  echo -e "───────────────────────────────────────────────────────────────────────────────"
  echo -e "  [3] > CONFIGURAR PROTOCOLOS"
  echo -e "  [4] > UTILIDADES Y HERRAMIENTAS"
  echo -e "───────────────────────────────────────────────────────────────────────────────"
  echo -e "  [5] > AJUSTES GENERALES / IDIOMA"
  echo -e "  [6] > [!] DESINSTALAR PANEL"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${RESET}"
  echo -e "  0) SALIR VPS     7) SALIR SCRIPT     8) REINICIAR VPS"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${RESET}"
  echo -ne "  Seleccione una opción: "
  read -r opcion
  ejecutar_opcion "$opcion"
}

# ══════ LÓGICA DEL MENÚ ══════
ejecutar_opcion() {
  case "$1" in
    1) echo -e "${GREEN}Abrir gestión SSH...${RESET}"; sleep 1 ;;
    2) echo -e "${GREEN}Abrir gestión V2Ray...${RESET}"; sleep 1 ;;
    3) echo -e "${GREEN}Configurando protocolos...${RESET}"; sleep 1 ;;
    4) echo -e "${GREEN}Herramientas adicionales...${RESET}"; sleep 1 ;;
    5) echo -e "${GREEN}Configuración general...${RESET}"; sleep 1 ;;
    6) echo -e "${RED}Desinstalando...${RESET}"; sleep 1 ;;
    7) echo -e "${YELLOW}Saliendo del script...${RESET}"; exit 0 ;;
    8) echo -e "${CYAN}Reiniciando VPS...${RESET}"; reboot ;;
    0) echo -e "${CYAN}Cerrando sesión VPS...${RESET}"; exit ;;
    *) echo -e "${RED}Opción no válida.${RESET}"; sleep 1 ;;
  esac
  read -p "Presiona Enter para volver al menú..." enter
  mostrar_panel
}

# ══════ EJECUTAR PANEL ══════
mostrar_panel
