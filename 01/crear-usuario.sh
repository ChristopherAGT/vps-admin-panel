#!/bin/bash

# Colores
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

USUARIOS_FILE="/etc/usuarios_panel.txt"
touch "$USUARIOS_FILE"
chmod 600 "$USUARIOS_FILE"

# Obtener IP del servidor
IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

# ═════════════════════════════════════════════════════
mostrar_tabla_usuarios() {
  clear
  LINEA="════════════════════════════════════════════════════════════════════════════"
  echo -e "${CYAN}${LINEA}${RESET}"
  printf "                 ${YELLOW}CREAR USUARIOS${RESET}\n"
  echo -e "${CYAN}${LINEA}${RESET}"
  echo -e "  N° USUARIO         CONTRASEÑA       EXPIRA     DÍAS  LÍM  ESTADO"
  echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────${RESET}"

  n=1
  while IFS=' ' read -r user pass exp; do
    [[ -z "$user" ]] && continue

    if id -u "$user" &>/dev/null; then
      exp_date=$(date -d "$exp" +"%b%d/%y" 2>/dev/null || echo "N/A")
      dias_left=$(( ( $(date -d "$exp" +%s) - $(date +%s) ) / 86400 ))
      (( dias_left < 0 )) && dias_left=0
      lim="--"
      estado="ULK"
      printf "  %-2s) %-17s %-15s %-10s %-4s  %-3s  %-s\n" "$n" "$user" "$pass" "$exp_date" "$dias_left" "$lim" "$estado"
      ((n++))
    fi
  done < "$USUARIOS_FILE"

  echo -e "${CYAN}${LINEA}${RESET}"
  echo -e "  [0] > VOLVER"
  echo -e "${CYAN}${LINEA}${RESET}"
}

# ═════════════════════════════════════════════════════
leer_numero_valido() {
  local prompt="$1"
  local valor
  while true; do
    echo -ne "$prompt "
    read -r valor
    if [[ "$valor" =~ ^[0-9]+$ && "$valor" -gt 0 ]]; then
      echo "$valor"
      break
    else
      echo -e "${RED}[✘] Entrada inválida. Ingresa solo números enteros positivos.${RESET}"
    fi
  done
}

# ═════════════════════════════════════════════════════
crear_usuario() {
  while true; do
    echo -ne "\n NUEVO USUARIO (max 16 chars, solo a-zA-Z0-9_-): "
    read -r nuevo_usuario
    if [[ ${#nuevo_usuario} -gt 16 ]]; then
      echo -e "${RED} [✘] Usuario demasiado largo (máximo 16 caracteres).${RESET}"
      continue
    elif ! [[ "$nuevo_usuario" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo -e "${RED} [✘] Usuario inválido. Solo letras, números, guion bajo y medio permitido.${RESET}"
      continue
    elif id -u "$nuevo_usuario" >/dev/null 2>&1; then
      echo -e "${RED} [✘] El usuario '$nuevo_usuario' ya existe. Intenta otro.${RESET}"
      continue
    fi
    break
  done

  while true; do
    echo -ne " CONTRASEÑA (max 16 chars, solo a-zA-Z0-9@._-): "
    read -r nueva_pass
    if [[ ${#nueva_pass} -gt 16 ]]; then
      echo -e "${RED} [✘] Contraseña demasiado larga (máximo 16 caracteres).${RESET}"
      continue
    elif ! [[ "$nueva_pass" =~ ^[a-zA-Z0-9@._-]+$ ]]; then
      echo -e "${RED} [✘] Contraseña inválida. Solo letras, números y: @ . _ - permitidos.${RESET}"
      continue
    fi
    break
  done

  # Pedir primero días de expiración, luego conexiones
  dias_exp=$(leer_numero_valido " ➤ ¿Cuántos días hasta la expiración?:")
  conexiones=$(leer_numero_valido " ➤ ¿Límite de conexiones simultáneas?:")

  # Calcular fechas
  fecha_exp=$(date -d "+$dias_exp days" +"%Y-%m-%d" 2>/dev/null || echo "N/A")
  fecha_mostrar=$(date -d "$fecha_exp" +"%b/%d/%Y" 2>/dev/null || echo "N/A")

  # Crear usuario
  useradd -e "$fecha_exp" -M -s /usr/sbin/nologin "$nuevo_usuario" &>/dev/null
  echo "$nuevo_usuario:$nueva_pass" | chpasswd

  # Guardar registro
  echo "$nuevo_usuario $nueva_pass $fecha_exp" >> "$USUARIOS_FILE"

  # Mostrar resumen
  clear
  echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${RESET}"
  printf "            ${YELLOW}USUARIO CREADO CON ÉXITO!${RESET}\n"
  echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${RESET}"
  printf " IP:                      %s\n" "$IP"
  printf " NOMBRE DE USUARIO:       %s\n" "$nuevo_usuario"
  printf " CONTRASEÑA DE USUARIO:   %s\n" "$nueva_pass"
  printf " CONEXIONES:              %s\n" "$conexiones"
  printf " EXPIRA EN:               %s\n" "$fecha_mostrar"
  echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${RESET}"
  echo
  read -p "         >> Presione Enter para continuar <<" _
}

# ═════════════════════════════════════════════════════
mostrar_tabla_usuarios
crear_usuario
