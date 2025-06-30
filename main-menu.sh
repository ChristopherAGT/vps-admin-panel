#!/bin/bash

# Requisitos previos
command -v figlet >/dev/null 2>&1 || apt install figlet -y >/dev/null
command -v lolcat >/dev/null 2>&1 || apt install lolcat -y >/dev/null

# Colores
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# Ancho de terminal
WIDTH=$(tput cols)
LINE=$(printf "%${WIDTH}s" | tr ' ' '═')

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
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
CPU_USAGE_INT=${CPU_USAGE%.*}

if (( CPU_USAGE_INT > 70 )); then
  CPU_COLOR=$RED
elif (( CPU_USAGE_INT > 50 )); then
  CPU_COLOR=$YELLOW
else
  CPU_COLOR=$GREEN
fi

# ══════ PUERTOS AGRUPADOS ══════
obtener_puertos_agrupados() {
  declare -A grupos

  ss -tulnp 2>/dev/null | awk 'NR>1' | while read -r linea; do
    puerto=$(echo "$linea" | awk '{split($5,p,":"); print p[length(p)]}')
    servicio=$(echo "$linea" | grep -oP 'users:\(\(".*?"' | cut -d'"' -f2)
    [ -z "$servicio" ] && servicio="desconocido"

    case "$servicio" in
      dropbear)        grupo="Dropbear" ;;
      sshd)            grupo="SSH" ;;
      stunnel4)        grupo="SSL" ;;
      apache2)         grupo="HTTP" ;;
      badvpn-udpgw)    grupo="BadVPN" ;;
      udp-custom)      grupo="UDP-Custom" ;;
      udpmod)          grupo="UDP-Mod" ;;
      udp-request)     grupo="UDP-Request" ;;
      ntpd)            grupo="NTP" ;;
      systemd-resolve) grupo="DNS" ;;
      python3)         grupo="Python" ;;
      filebrowser)     grupo="FileBrowser" ;;
      v2ray)           grupo="V2Ray" ;;
      zivpn)           grupo="ZIVPN" ;;
      *)               grupo=$(echo "$servicio" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}') ;;
    esac

    grupos["$grupo"]+="$puerto "
  done

  # Mostrar en pares alineados
  keys=("${!grupos[@]}")
  total=${#keys[@]}

  for ((i = 0; i < total; i+=2)); do
    key1=${keys[i]}
    key2=${keys[i+1]}
    ports1=${grupos[$key1]}
    ports2=${grupos[$key2]}

    printf "  %-15s: %-20s" "$key1" "$ports1"
    if [ -n "$key2" ]; then
      printf "  %-15s: %s" "$key2" "$ports2"
    fi
    echo
  done
}

# ══════ MOSTRAR PANEL ══════
mostrar_panel() {
  clear
  figlet "VPS PANEL" | lolcat
  echo -e "${CYAN}${LINE}${RESET}"
  printf " %-60s\n" "${YELLOW}$USER_NAME${RESET}"
  echo -e "${CYAN}${LINE}${RESET}"
  printf "  %-40s Fecha:  %s\n" "S.O:     $SO" "$DATE"
  printf "  %-40s Hora:   %s\n" "IP:      $IP" "$TIME"
  echo -e "${CYAN}${LINE}${RESET}"
  printf "  DISCO -> Total: %-8s Usado: %-8s Libre: %-8s\n" "$DISK_TOTAL" "$DISK_USED" "$DISK_FREE"
  printf "  CPU   -> Núcleos: %-2s Uso: ${CPU_COLOR}%s%%%s\n" "$CPU_CORES" "$CPU_USAGE_INT" "$RESET"
  echo -e "${CYAN}${LINE}${RESET}"
  printf "  RAM   -> Total: %-8s Usada: %-8s Libre: %-8s\n" "$RAM_TOTAL" "$RAM_USED" "$RAM_FREE"
  printf "           Buffer: %-8s Cache: %-8s\n" "$RAM_BUFFER" "$RAM_CACHE"
  echo -e "${CYAN}${LINE}${RESET}"
  echo -e "  PUERTOS ACTIVOS AGRUPADOS:"
  obtener_puertos_agrupados
  echo -e "${CYAN}${LINE}${RESET}"
  echo -e "  [1] > GESTIÓN SSH / DROPBEAR"
  echo -e "  [2] > GESTIÓN V2RAY / XRAY"
  echo -e "  [3] > CONFIGURAR PROTOCOLOS"
  echo -e "  [4] > UTILIDADES Y HERRAMIENTAS"
  echo -e "  [5] > AJUSTES GENERALES / IDIOMA"
  echo -e "  [6] > [!] DESINSTALAR PANEL"
  echo -e "${CYAN}${LINE}${RESET}"
  echo -e "  0) SALIR VPS     7) SALIR SCRIPT     8) REINICIAR VPS"
  echo -e "${CYAN}${LINE}${RESET}"
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
