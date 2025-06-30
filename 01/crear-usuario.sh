#!/bin/bash

# Colores
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

# IP del servidor
IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

# Base de datos
DB="/etc/usuarios_creados.db"
touch "$DB"
chmod 600 "$DB"

# ═════════════════════════════════════════════════════
mostrar_tabla_usuarios() {
  clear
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo -e "                   ${YELLOW}CREAR USUARIOS${RESET}"
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo -e "  N°  Usuario           Contraseña        Fecha     Días  Con   Sta"
  echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"

  if [[ ! -s "$DB" ]]; then
    echo -e "     ${RED}No hay usuarios creados aún.${RESET}"
  else
    n=1
    while IFS=':' read -r usuario clave fecha dias con estado; do
      # Validar campos: todos deben estar presentes y válidos
      [[ -z "$usuario" || -z "$clave" || -z "$fecha" || -z "$dias" || -z "$con" || -z "$estado" ]] && continue

      # Truncar si excede el límite visual permitido
      usuario_fmt=$(printf "%.16s" "$usuario")
      clave_fmt=$(printf "%.16s" "$clave")

      printf "  %-3s %-16s %-16s %-9s %-4s  %-5s %-5s\n" \
        "$n" "$usuario_fmt" "$clave_fmt" "$fecha" "$dias" "$con" "$estado"
      ((n++))
    done < "$DB"
  fi

  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo -e "  [0] > VOLVER"
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
}

# ═════════════════════════════════════════════════════
validar_input() {
  local input="$1"
  local regex="$2"
  local maxlen="$3"

  if (( ${#input} > maxlen )); then
    echo -e "${RED}[✘] Máximo permitido: $maxlen caracteres.${RESET}"
    return 1
  fi

  if [[ "$input" =~ $regex ]]; then
    return 0
  else
    echo -e "${RED}[✘] Caracteres no permitidos.${RESET}"
    return 1
  fi
}

# ═════════════════════════════════════════════════════
leer_input() {
  local varname="$1"
  local prompt="$2"
  local regex="$3"
  local maxlen="$4"
  local value

  while true; do
    echo -ne "$prompt"
    read -r value
    validar_input "$value" "$regex" "$maxlen" && break
  done
  eval "$varname='$value'"
}

# ═════════════════════════════════════════════════════
leer_numero() {
  local varname="$1"
  local prompt="$2"
  local min="$3"
  local max="$4"
  local value

  while true; do
    echo -ne "$prompt"
    read -r value
    value=$(echo "$value" | tr -cd '0-9')
    if [[ "$value" =~ ^[0-9]+$ && "$value" -ge "$min" && "$value" -le "$max" ]]; then
      break
    else
      echo -e "${RED}[✘] Solo números entre $min y $max permitidos.${RESET}"
    fi
  done
  eval "$varname='$value'"
}

# ═════════════════════════════════════════════════════
crear_usuario() {
  local nuevo_usuario nueva_pass dias_exp conexiones

  leer_input nuevo_usuario " NUEVO USUARIO: " '^[a-zA-Z0-9._@-]+$' 16
  leer_input nueva_pass   " CONTRASEÑA: "     '^[a-zA-Z0-9._@-]+$' 16
  leer_numero dias_exp    " DÍAS PARA EXPIRAR (1-365): " 1 365
  leer_numero conexiones  " CONEXIONES (1-999): " 1 999

  # Calcular fechas
  fecha_exp=$(date -d "+$dias_exp days" +"%Y-%m-%d")
  fecha_mostrar=$(date -d "$fecha_exp" +"%b%d/%y")

  # Crear usuario en el sistema
  useradd -e "$fecha_exp" -M -s /bin/false "$nuevo_usuario" &>/dev/null
  echo "$nuevo_usuario:$nueva_pass" | chpasswd

  # Guardar en base de datos
  echo "$nuevo_usuario:$nueva_pass:$fecha_mostrar:$dias_exp:$conexiones:ULK" >> "$DB"
  
  # Mostrar resumen
  clear
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo -e "              ${YELLOW}USUARIO GENERADO CON ÉXITO!${RESET}"
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo " IP DEL SERVIDOR:      $IP"
  echo " NOMBRE DE USUARIO:    $nuevo_usuario"
  echo " CONTRASEÑA DE USUARIO:$nueva_pass"
  echo " CONEXIONES:           $conexiones"
  echo " EXPIRA EN:            $fecha_mostrar"
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  read -p "         >> Presione Enter para continuar <<" _
}

# ═════════════════════════════════════════════════════
mostrar_tabla_usuarios
crear_usuario
