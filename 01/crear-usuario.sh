#!/bin/bash

# Colores
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
RESET='\033[0m'

# Archivo donde se guardan usuarios con formato:
# usuario:contraseña:fecha_expiracion:dias_restantes:limite_conexiones:estado
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
  printf "                 ${YELLOW}LISTA DE USUARIOS${RESET}\n"
  echo -e "${CYAN}${LINEA}${RESET}"
  echo -e "  N° │ USUARIO         │ CONTRASEÑA      │ EXPIRA       │ DÍAS │ LÍM │ ESTADO"
  echo -e "${CYAN}────┼────────────────┼────────────────┼──────────────┼─────┼────┼────────${RESET}"

  if [[ ! -s "$USUARIOS_FILE" ]]; then
    echo -e "${RED}  No hay usuarios registrados.${RESET}"
  else
    n=1
    while IFS=: read -r user pass fecha dias lim estado; do
      [[ -z "$user" ]] && continue

      # Formatear estado
      case "$estado" in
        ULK) estado_fmt="ACTIVO" ;;
        BLK) estado_fmt="BLOQUEADO" ;;
        EXP) estado_fmt="VENCIDO" ;;
        *)   estado_fmt="DESCONOCIDO" ;;
      esac

      printf "  %-2s │ %-15s │ %-15s │ %-12s │ %4s │ %3s │ %-8s\n" \
        "$n" "$user" "$pass" "$fecha" "$dias" "$lim" "$estado_fmt"
      ((n++))
    done < "$USUARIOS_FILE"
  fi

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
  # Pedir nombre de usuario válido
  while true; do
    echo -ne "\n NUEVO USUARIO (max 16 chars, solo a-zA-Z0-9_-): "
    read -r nuevo_usuario
    if [[ ${#nuevo_usuario} -gt 16 ]]; then
      echo -e "${RED}[✘] Usuario demasiado largo (máximo 16 caracteres).${RESET}"
      continue
    elif ! [[ "$nuevo_usuario" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo -e "${RED}[✘] Usuario inválido. Solo letras, números, guion bajo y medio permitido.${RESET}"
      continue
    elif id -u "$nuevo_usuario" >/dev/null 2>&1; then
      echo -e "${RED}[✘] El usuario '$nuevo_usuario' ya existe. Intenta otro.${RESET}"
      continue
    fi
    break
  done

  # Pedir contraseña válida
  while true; do
    echo -ne " CONTRASEÑA (max 16 chars, solo a-zA-Z0-9@._-): "
    read -r nueva_pass
    if [[ ${#nueva_pass} -gt 16 ]]; then
      echo -e "${RED}[✘] Contraseña demasiado larga (máximo 16 caracteres).${RESET}"
      continue
    elif ! [[ "$nueva_pass" =~ ^[a-zA-Z0-9@._-]+$ ]]; then
      echo -e "${RED}[✘] Contraseña inválida. Solo letras, números y: @ . _ - permitidos.${RESET}"
      continue
    fi
    break
  done

  # Pedir días de expiración y límite de conexiones
  dias_exp=$(leer_numero_valido " ➤ ¿Cuántos días hasta la expiración?:")
  conexiones=$(leer_numero_valido " ➤ ¿Límite de conexiones simultáneas?:")

  # Calcular fecha de expiración en formato YYYY-MM-DD
  fecha_exp=$(date -d "+$dias_exp days" +"%Y-%m-%d" 2>/dev/null || echo "N/A")
  fecha_mostrar=$(date -d "$fecha_exp" +"%b%d/%y" 2>/dev/null || echo "N/A")

  # Crear usuario en sistema sin home y sin login shell
  useradd -e "$fecha_exp" -M -s /usr/sbin/nologin "$nuevo_usuario" &>/dev/null
  echo "$nuevo_usuario:$nueva_pass" | chpasswd

  # Guardar registro en archivo con formato separado por :
  # usuario:contraseña:fecha_expiracion:dias_restantes:limite_conexiones:estado
  echo "${nuevo_usuario}:${nueva_pass}:${fecha_mostrar}:${dias_exp}:${conexiones}:ULK" >> "$USUARIOS_FILE"

  # Mostrar resumen bonito
  clear
  echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${RESET}"
  printf "            ${YELLOW}USUARIO CREADO CON ÉXITO!${RESET}\n"
  echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${RESET}"
  printf " IP DEL SERVIDOR:          %s\n" "$IP"
  printf " NOMBRE DE USUARIO:        %s\n" "$nuevo_usuario"
  printf " CONTRASEÑA DE USUARIO:    %s\n" "$nueva_pass"
  printf " LÍMITE DE CONEXIONES:     %s\n" "$conexiones"
  printf " EXPIRA EN (Fecha):        %s\n" "$fecha_exp"
  printf " EXPIRA EN (Días Rest):    %s\n" "$dias_exp"
  echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${RESET}"
  echo
  read -p "         >> Presione Enter para continuar <<" _
}

# ═════════════════════════════════════════════════════
# Menú principal simple
while true; do
  mostrar_tabla_usuarios
  echo -ne "Seleccione una opción: "
  read -r opcion
  case "$opcion" in
    0) 
      echo "Saliendo..."
      exit 0
      ;;
    *)
      crear_usuario
      ;;
  esac
done
