#!/bin/bash

# Colores estilo dark para terminal
RESET="\e[0m"
BOLD="\e[1m"

FG_WHITE="\e[97m"
FG_CYAN="\e[96m"
FG_GREEN="\e[92m"
FG_YELLOW="\e[93m"
FG_RED="\e[91m"
FG_BLUE="\e[94m"

BG_BLACK="\e[40m"

# Función para imprimir línea para bordes (longitud 54)
linea() {
  printf "═%.0s" $(seq 1 54)
}

# Padding espacios para alinear texto dentro del ancho
espacios() {
  local len=${#1}
  local total=54
  local spaces=$((total - len))
  printf "%-${spaces}s" " "
}

# Obtener usuario actual
usuario="@$(whoami)"

# Obtener fecha y hora actuales
fecha=$(date +"%d-%m-%Y")
hora=$(date +"%H:%M:%S")

# Obtener IP pública (usa dig, si no tienes internet puede quedar vacía)
ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)
# fallback IP local si no hay pública
if [[ -z "$ip" ]]; then
  ip=$(hostname -I | awk '{print $1}')
fi

# Obtener nombre y versión de SO
so=$(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2- | tr -d '"')

# Info disco - asumimos "/" para disco principal
disco_total=$(df -h / | awk 'NR==2 {print $2}')
disco_usado=$(df -h / | awk 'NR==2 {print $3}')
disco_libre=$(df -h / | awk 'NR==2 {print $4}')

# Info CPU
cpu_cores=$(nproc)
# Uso cpu total en %: sumamos idle y restamos de 100, método simplificado
cpu_usage() {
  # leer dos valores de /proc/stat en un intervalo para calcular uso real
  local cpu_line1 cpu_line2 cpu_idle1 cpu_idle2 cpu_total1 cpu_total2 cpu_usage
  cpu_line1=($(head -n1 /proc/stat))
  cpu_idle1=${cpu_line1[4]}
  cpu_total1=0
  for val in "${cpu_line1[@]:1}"; do
    cpu_total1=$((cpu_total1 + val))
  done

  sleep 0.4

  cpu_line2=($(head -n1 /proc/stat))
  cpu_idle2=${cpu_line2[4]}
  cpu_total2=0
  for val in "${cpu_line2[@]:1}"; do
    cpu_total2=$((cpu_total2 + val))
  done

  local total_diff=$((cpu_total2 - cpu_total1))
  local idle_diff=$((cpu_idle2 - cpu_idle1))
  local busy_diff=$((total_diff - idle_diff))

  cpu_usage=$(awk "BEGIN {printf \"%.1f\", (${busy_diff} * 100) / ${total_diff}}")
  echo "$cpu_usage"
}
cpu_porcentaje=$(cpu_usage)

# Info RAM en MiB
mem_info() {
  # tomamos valores de /proc/meminfo
  local total used free buffers cached
  total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  free=$(awk '/MemFree/ {print $2}' /proc/meminfo)
  buffers=$(awk '/Buffers/ {print $2}' /proc/meminfo)
  cached=$(awk '/^Cached/ {print $2}' /proc/meminfo)
  used=$((total - free - buffers - cached))

  # convertimos a MiB
  echo $((total / 1024)) $((used / 1024)) $((free / 1024)) $((buffers / 1024)) $((cached / 1024))
}
read -r mem_total mem_usado mem_libre mem_buffers mem_cached < <(mem_info)

print_header_usuario() {
  echo -e "${BG_BLACK}${FG_CYAN}╔$(linea)╗${RESET}"
  echo -e "${BG_BLACK}${FG_CYAN}║${RESET}  ${BOLD}${FG_WHITE}${usuario}$(espacios "$usuario")${RESET}${BG_BLACK}${FG_CYAN}║${RESET}"
  echo -e "${BG_BLACK}${FG_CYAN}╚$(linea)╝${RESET}"
}

print_menu() {
  clear
  print_header_usuario

  echo -e "${BG_BLACK}${FG_CYAN}╔════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BG_BLACK}${FG_WHITE}║  S.O: ${so}$(espacios "S.O: ${so}")Fecha: ${fecha}        ║${RESET}"
  echo -e "${BG_BLACK}${FG_WHITE}║  IP:  ${ip}$(espacios "IP:  ${ip}")Hora: ${hora}           ║${RESET}"
  echo -e "${BG_BLACK}${FG_CYAN}╠══════════════╦══════════════╦══════════════╣${RESET}"
  echo -e "${BG_BLACK}${FG_WHITE}║     Disco    ║      CPU     ║      RAM     ║${RESET}"
  echo -e "${BG_BLACK}${FG_CYAN}╠══════════════╬══════════════╬══════════════╣${RESET}"
  echo -e "${BG_BLACK}${FG_WHITE}║ Total: ${disco_total}  ║ Cores: ${cpu_cores}   ║ Total: ${mem_total}Mi ║${RESET}"
  echo -e "${BG_BLACK}${FG_WHITE}║ Usado: ${disco_usado}  ║ Uso:  ${cpu_porcentaje}% ║ Usado: ${mem_usado}Mi ║${RESET}"
  echo -e "${BG_BLACK}${FG_WHITE}║ Libre: ${disco_libre}  ║              ║ Libre: ${mem_libre}Mi ║${RESET}"
  echo -e "${BG_BLACK}${FG_WHITE}║              ║ Buffer: ${mem_buffers}Mi ║             ║${RESET}"
  echo -e "${BG_BLACK}${FG_WHITE}║              ║ Cache:  ${mem_cached}Mi ║             ║${RESET}"
  echo -e "${BG_BLACK}${FG_CYAN}╚════════════════════════════════════════════════════════╝${RESET}"

  echo
  # Estado cuentas (fijo)
  echo -e "${FG_GREEN}  ACTIVA:  ${FG_YELLOW}45  ${FG_GREEN}EXPIRADA:  ${FG_RED}0  ${FG_GREEN}BLOQUEADA:  ${FG_RED}0  ${FG_GREEN}TOTAL: ${FG_YELLOW}10${RESET}"
  echo -e "${FG_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

  # Opciones menú
  echo -e "${FG_CYAN}[1]${RESET}  🔐  ADMINISTRAR CUENTAS (SSH/DROPBEAR)"
  echo -e "${FG_CYAN}[2]${RESET}  🚀  ADMINISTRAR CUENTAS (V2RAY/XRAY)"
  echo -e "${FG_CYAN}[3]${RESET}  ⚙️  CONFIGURACIÓN DE PROTOCOLOS"
  echo -e "${FG_CYAN}[4]${RESET}  🛠️  HERRAMIENTAS EXTRAS"
  echo -e "${FG_CYAN}[5]${RESET}  📝  CONFIGURACIÓN DEL SCRIPT"
  echo -e "${FG_CYAN}[6]${RESET}  🌐  IDIOMA / LANGUAGE"
  echo -e "${FG_CYAN}[7]${FG_RED}[!] DESINSTALAR PANEL${RESET}"
  echo -e "${FG_CYAN}[0]${RESET}  🚪  SALIR DEL VPS"
  echo -e "${FG_CYAN}[8]${RESET}  ✋  SALIR DEL SCRIPT"
  echo -e "${FG_CYAN}[9]${RESET}  🔄  REINICIAR VPS"
  echo -e "${FG_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

  echo -ne "${FG_YELLOW}Ingrese una opción: ${RESET}"
}

print_menu
read -r opcion
echo -e "\nHas elegido la opción: $opcion"
