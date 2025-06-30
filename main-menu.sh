#!/bin/bash

# Colores
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# Ancho de terminal y líneas dinámicas
WIDTH=$(tput cols)
LINE_TOP="╔$(printf '═%.0s' $(seq 1 $((WIDTH-2))))╗"
LINE_MID="╠$(printf '═%.0s' $(seq 1 $((WIDTH-2))))╣"
LINE_BOT="╚$(printf '═%.0s' $(seq 1 $((WIDTH-2))))╝"
LINE_SEP="$(printf '─%.0s' $(seq 1 $((WIDTH-2))))"

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
CPU_USAGE_RAW=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
CPU_USAGE_INT=${CPU_USAGE_RAW%.*}
if (( CPU_USAGE_INT > 70 )); then
  CPU_COLOR=$RED
elif (( CPU_USAGE_INT > 50 )); then
  CPU_COLOR=$YELLOW
else
  CPU_COLOR=$GREEN
fi

# ══════ FUNCIÓN: PUERTOS AGRUPADOS ══════
obtener_puertos_agrupados() {
  declare -A grupos
  ss -tulnp 2>/dev/null | awk 'NR>1' | while read -r linea; do
    puerto=$(echo "$linea" | awk '{split($5,p,":"); print p[length(p)]}')
    servicio=$(echo "$linea" | grep -oP 'users:\(\(\".*?\"' | cut -d'\"' -f2)
    [ -z "$servicio" ] && servicio="desconocido"
    case "$servicio" in
      dropbear)        grupo="DROPBEAR" ;;
      sshd)            grupo="SSHD" ;;
      stunnel4)        grupo="SSL" ;;
      apache2)         grupo="APACHE" ;;
      badvpn-udpgw)    grupo="BADVPN" ;;
      udp-custom)      grupo="UDP-CUSTOM" ;;
      udpmod)          grupo="UDP-MOD" ;;
      udp-request)     grupo="UDP-REQUEST" ;;
      ntpd)            grupo="NTP" ;;
      systemd-resolve) grupo="DNS" ;;
      python3)         grupo="PYTHON" ;;
      filebrowser)     grupo="FILEBROWSER" ;;
      v2ray)           grupo="V2RAY" ;;
      zivpn)           grupo="ZIVPN" ;;
      *)               grupo=$(echo "$servicio" | tr 'a-z' 'A-Z') ;;
    esac
    grupos["$grupo"]+="$puerto "
  done

  keys=("${!grupos[@]}")
  total=${#keys[@]}
  for ((i=0; i<total; i+=2)); do
    k1=${keys[i]}; p1=${grupos[$k1]}
    k2=${keys[i+1]}; p2=${grupos[$k2]}
    printf "  %-12s: %-15s" "$k1" "$p1"
    if [ -n "$k2" ]; then
      printf "  %-12s: %s" "$k2" "$p2"
    fi
    echo
  done
}

# ══════ MOSTRAR PANEL ══════
mostrar_panel() {
  clear
  echo -e "${CYAN}${LINE_TOP}${RESET}"
  printf "│%*s%*s│\n" $(( (WIDTH + ${#USER_NAME})/2 )) "${YELLOW}${USER_NAME}${RESET}" $(( (WIDTH - ${#USER_NAME})/2 )) ""
  echo -e "${CYAN}${LINE_MID}${RESET}"
  printf "  %-30s Fecha: %-10s   IP: %-15s Hora: %s\n" "S.O: $SO" "$DATE" "$IP" "$TIME"
  echo -e "${CYAN}${LINE_MID}${RESET}"
  printf "  DISCO -> Total: %-7s Usado: %-7s Libre: %-7s" "$DISK_TOTAL" "$DISK_USED" "$DISK_FREE"
  printf "   CPU -> Núcleos: %-2s Uso: ${CPU_COLOR}%3s%%%s\n" "$CPU_CORES" "$CPU_USAGE_INT" "$RESET"
  echo -e "${CYAN}${LINE_MID}${RESET}"
  printf "  RAM   -> Total: %-7s Usada: %-7s Libre: %-7s\n" "$RAM_TOTAL" "$RAM_USED" "$RAM_FREE"
  printf "           Buffer: %-7s Cache: %-7s\n" "$RAM_BUFFER" "$RAM_CACHE"
  echo -e "${CYAN}${LINE_MID}${RESET}"
  echo "  PUERTOS ACTIVOS AGRUPADOS:"
  obtener_puertos_agrupados
  echo -e "${CYAN}${LINE_MID}${RESET}"
  echo "  [1] > GESTIÓN SSH / DROPBEAR     [2] > GESTIÓN V2RAY / XRAY"
  echo -e "${CYAN}${LINE_SEP}${RESET}"
  echo "  [3] > CONFIGURAR PROTOCOLOS      [4] > UTILIDADES Y HERRAMIENTAS"
  echo -e "${CYAN}${LINE_SEP}${RESET}"
  echo "  [5] > AJUSTES GENERALES / IDIOMA [6] > [!] DESINSTALAR PANEL"
  echo -e "${CYAN}${LINE_MID}${RESET}"
  echo "  0) SALIR VPS   7) SALIR SCRIPT   8) REINICIAR VPS"
  echo -e "${CYAN}${LINE_BOT}${RESET}"
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
