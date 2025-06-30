#!/bin/bash

# Colores
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# Ruta del archivo de usuarios
DB="/etc/ssh_panel_usuarios.db"

# Función principal
mostrar_tabla_usuarios() {
  clear
  WIDTH=$(tput cols)
  LINE=$(printf '%*s' "$WIDTH" '' | tr ' ' '═')

  echo -e "${CYAN}${LINE}${RESET}"
  printf "            ${YELLOW}%-${WIDTH}s${RESET}\n" "ADMINISTRACIÓN DE USUARIOS SSH"
  echo -e "${CYAN}${LINE}${RESET}"
  echo -e "  Nº │ USUARIO         │ CONTRASEÑA      │ EXPIRA       │ DÍAS │ LÍM │ ESTADO"
  echo -e "${CYAN}────┼────────────────┼────────────────┼──────────────┼─────┼────┼──────────${RESET}"

  n=1
  while IFS=: read -r usuario pass fecha dias lim estado; do
    case "$estado" in
      ULK) estado_fmt="ACTIVO" ;;
      BLK) estado_fmt="BLOQUEADO" ;;
      EXP) estado_fmt="VENCIDO" ;;
      *)   estado_fmt="-" ;;
    esac

    printf "  %-2s │ %-15s │ %-15s │ %-12s │ %-4s │ %-3s │ %-9s\n" \
      "$n" "$usuario" "$pass" "$fecha" "$dias" "$lim" "$estado_fmt"
    ((n++))
  done < "$DB"

  echo -e "${CYAN}${LINE}${RESET}"
  echo -e "  [0] > VOLVER"
  echo -e "${CYAN}${LINE}${RESET}"
}

# Ejecutar
mostrar_tabla_usuarios
