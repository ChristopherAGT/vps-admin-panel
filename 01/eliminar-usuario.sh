#!/bin/bash

# Colores
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
RESET='\033[0m'

DB="/etc/usuarios_creados.db"
touch "$DB"
chmod 600 "$DB"

# ═════════════════════════════════════════════════════
mostrar_tabla_usuarios() {
  clear
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo -e "                ${YELLOW}ELIMINAR USUARIO SSH${RESET}"
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo -e "  N°  Usuario           Contraseña        Fecha     Días  Con   Sta"
  echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"

  mapfile -t lineas < "$DB"

  if [[ ${#lineas[@]} -eq 0 ]]; then
    echo -e "     ${RED}No hay usuarios registrados.${RESET}"
    return 1
  fi

  for i in "${!lineas[@]}"; do
    IFS=':' read -r usuario clave fecha dias con estado <<< "${lineas[$i]}"
    usuario_fmt=$(printf "%.16s" "$usuario")
    clave_fmt=$(printf "%.16s" "$clave")
    printf "  %-3s %-16s %-16s %-9s %-4s  %-5s %-5s\n" "$((i+1))" "$usuario_fmt" "$clave_fmt" "$fecha" "$dias" "$con" "$estado"
  done

  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo -e "  [0] > CANCELAR"
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
}

# ═════════════════════════════════════════════════════
eliminar_usuario() {
  local seleccion="$1"

  mapfile -t lineas < "$DB"
  total=${#lineas[@]}

  if (( seleccion < 1 || seleccion > total )); then
    echo -e "${RED}Número inválido.${RESET}"
    return 1
  fi

  IFS=':' read -r usuario clave fecha dias con estado <<< "${lineas[$((seleccion-1))]}"

  # Confirmación
  echo -e "${YELLOW}¿Seguro que deseas eliminar al usuario '$usuario'? (s/n)${RESET}"
  read -r confirm
  [[ "$confirm" != "s" && "$confirm" != "S" ]] && echo -e "${RED}Cancelado.${RESET}" && return 1

  # Eliminar usuario real
  pkill -u "$usuario" &>/dev/null
  userdel -r "$usuario" &>/dev/null

  # Eliminar del archivo
  unset 'lineas[seleccion-1]'
  printf "%s\n" "${lineas[@]}" > "$DB"

  echo -e "\n${GREEN}✔ Usuario '$usuario' eliminado correctamente.${RESET}"
  read -p ">> Presione Enter para continuar <<" _
}

# ═════════════════════════════════════════════════════
while true; do
  mostrar_tabla_usuarios || { read -p "Presione Enter para salir..."; exit 1; }
  echo -ne "\n Seleccione el número del usuario a eliminar: "
  read -r opcion

  if [[ "$opcion" == "0" ]]; then
    echo -e "${YELLOW}Operación cancelada.${RESET}"
    break
  elif [[ "$opcion" =~ ^[0-9]+$ ]]; then
    eliminar_usuario "$opcion"
  else
    echo -e "${RED}Entrada inválida.${RESET}"
    sleep 1
  fi
done
