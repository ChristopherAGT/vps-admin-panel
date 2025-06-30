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

# ══════ PUERTOS AGRUPADOS ══════
obtener_puertos_agrupados() {
  declare -A grupos_unicos
  declare -A grupos_finales

  mapfile -t lineas < <(ss -tulnp 2>/dev/null | awk 'NR>1')

  for linea in "${lineas[@]}"; do
    puerto=$(echo "$linea" | awk '{split($5,p,":"); print p[length(p)]}')
    servicio=$(echo "$linea" | grep -oP 'users:\(\(".*?"' | cut -d'"' -f2)
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

    clave="$grupo:$puerto"
    if [[ -z "${grupos_unicos[$clave]}" ]]; then
      grupos_unicos["$clave"]=1
      grupos_finales["$grupo"]+="$puerto "
    fi
  done

  if (( ${#grupos_finales[@]} == 0 )); then
    echo -e "  ${YELLOW}[!] No hay puertos activos detectados.${RESET}"
    return
  fi

  # Ordenar y mostrar
  IFS=$'\n' keys=($(printf "%s\n" "${!grupos_finales[@]}" | sort))
  total=${#keys[@]}
  for ((i=0; i<total; i+=2)); do
    k1=${keys[i]}; p1=$(echo "${grupos_finales[$k1]}" | tr ' ' '\n' | sort -n | xargs)
    k2=${keys[i+1]}; p2=$(echo "${grupos_finales[$k2]}" | tr ' ' '\n' | sort -n | xargs)
    printf "  %-18s : %-22s" "$k1" "$p1"
    if [ -n "$k2" ]; then
      printf "  %-18s : %s" "$k2" "$p2"
    fi
    echo
  done
}

# ══════ MOSTRAR PANEL ══════
mostrar_panel() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════${RESET}"
  printf "                           ${YELLOW}%-60s${RESET}\n" "$USER_NAME"
  echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════╗${RESET}"
  printf "  %-42s Fecha:  %s\n" "S.O:     $SO" "$DATE"
  printf "  %-42s Hora:   %s\n" "IP:      $IP" "$TIME"
  echo -e "${CYAN}╠════════════════════════ DISCO ═══════════════════╦═════ CPU ═════╣${RESET}"
  printf "  %-37s Núcleos: %-2s\n" "Total: $DISK_TOTAL  Usado: $DISK_USED  Libre: $DISK_FREE" "$CPU_CORES"
  printf "  %-37s Uso:     %s\n" "" "$CPU_USAGE"
  echo -e "${CYAN}╠═════════════════════════ MEMORIA RAM ══════════════════════════════════════╣${RESET}"
  printf "  %-20s %-20s %-20s\n" "Total:   $RAM_TOTAL" "Usada: $RAM_USED" "Libre: $RAM_FREE"
  printf "  %-20s %-20s\n" "Buffer:  $RAM_BUFFER" "Cache: $RAM_CACHE"
  echo -e "${CYAN}╠════════════════════════ PUERTOS ACTIVOS ═══════════════════════════════════╣${RESET}"
  obtener_puertos_agrupados
  echo -e "${CYAN}╠════════════════════════ ESTADO DE CUENTAS ═════════════════════════════════╣${RESET}"
  echo -e "       ACTIVAS: 1     EXPIRADAS: 0     BLOQUEADAS: 0     TOTAL: 6"
  echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════╝${RESET}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════${RESET}"
  echo -e "  [1] > GESTIÓN SSH / DROPBEAR"
  echo -e "  [2] > GESTIÓN V2RAY / XRAY"
  echo -e "──────────────────────────────────────────────────────────────────────────────"
  echo -e "  [3] > CONFIGURAR PROTOCOLOS"
  echo -e "  [4] > UTILIDADES Y HERRAMIENTAS"
  echo -e "──────────────────────────────────────────────────────────────────────────────"
  echo -e "  [5] > AJUSTES GENERALES / IDIOMA"
  echo -e "  [6] > [!] DESINSTALAR PANEL"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════${RESET}"
  echo -e "  0) SALIR VPS     7) SALIR SCRIPT     8) REINICIAR VPS"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════${RESET}"
  echo -ne "  Seleccione una opción: "
  read -r opcion
  ejecutar_opcion "$opcion"
}

# ══════ LÓGICA DEL MENÚ ══════
ejecutar_opcion() {
  case "$1" in
    1) ;;
    2) ;;
    3) ;;
    4) ;;
    5) ;;
    6) ;;
    7) exit 0 ;;
    8)
      WIDTH=78  # Coincide con tus bordes decorativos

      # Mensaje centrado
      mensaje="⚠️  El VPS se reiniciará en 5 segundos..."
      espacio=$(( (WIDTH - ${#mensaje}) / 2 ))
      printf "\n%*s" $espacio ""
      echo -e "${CYAN}${mensaje}${RESET}"
      echo

      # Contador centrado con estilo 》5《
      for i in {5..1}; do
        contador="》$i《"
        espacio=$(( (WIDTH - ${#contador}) / 2 ))
        printf "%*s" $espacio ""
        echo -e "${CYAN}${contador}${RESET}"
        sleep 1
      done

      echo ""
      reboot
      ;;
    0)
      pkill -KILL -t "$(tty | sed 's:/dev/::')" || exit
      ;;
    *)
      echo -e "${RED}Opción no válida.${RESET}"
      sleep 1
      ;;
  esac

  if [[ "$1" != "7" && "$1" != "8" ]]; then
    read -p "Presiona Enter para volver al menú..." enter
    mostrar_panel
  fi
}

# ══════ INICIO ══════
mostrar_panel
