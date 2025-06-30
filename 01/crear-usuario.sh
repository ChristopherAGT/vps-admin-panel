#!/bin/bash

# Colores
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

# Obtener IP del servidor
IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

# Archivo base de datos de usuarios
DB="/etc/usuarios_creados.db"
touch "$DB"
chmod 600 "$DB"

# ═════════════════════════════════════════════════════
mostrar_tabla_usuarios() {
  clear
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo -e "                   ${YELLOW}CREAR USUARIOS${RESET}"
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo -e "  N° Usuario         Contraseña     Fecha     Días  Con  Sta"
  echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"

  if [[ ! -s "$DB" ]]; then
    echo -e "     ${RED}No hay usuarios creados aún.${RESET}"
  else
    n=1
    while IFS=':' read -r usuario clave fecha dias con estado; do
      printf "  %-2s) %-15s %-14s %-9s %-4s  %-3s  %-s\n" \
        "$n" "$usuario" "$clave" "$fecha" "$dias" "$con" "$estado"
      ((n++))
    done < "$DB"
  fi

  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo -e "  [0] > VOLVER"
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
}

# ═════════════════════════════════════════════════════
leer_input_validado() {
  local prompt="$1"
  local regex="$2"
  local maxlen="$3"
  local input

  while true; do
    echo -ne "$prompt"
    read -r input

    if (( ${#input} > maxlen )); then
      echo -e "${RED}[✘] Máximo permitido: $maxlen caracteres.${RESET}"
      continue
    fi

    if [[ "$input" =~ $regex ]]; then
      echo "$input"
      break
    else
      echo -e "${RED}[✘] Caracteres no permitidos.${RESET}"
    fi
  done
}

# ═════════════════════════════════════════════════════
leer_numero() {
  local prompt="$1"
  local min="$2"
  local max="$3"
  local input

  while true; do
    echo -ne "$prompt"
    read -r input
    input=$(echo "$input" | tr -cd '0-9')

    if [[ "$input" =~ ^[0-9]+$ && "$input" -ge "$min" && "$input" -le "$max" ]]; then
      echo "$input"
      break
    else
      echo -e "${RED}[✘] Solo números entre $min y $max permitidos.${RESET}"
    fi
  done
}

# ═════════════════════════════════════════════════════
crear_usuario() {
  nuevo_usuario=$(leer_input_validado " NUEVO USUARIO: " '^[a-zA-Z0-9._@-]+$' 16)
  nueva_pass=$(leer_input_validado  " CONTRASEÑA: "     '^[a-zA-Z0-9._@-]+$' 16)
  dias_exp=$(leer_numero " DÍAS PARA EXPIRAR (1-365): " 1 365)
  conexiones=$(leer_numero " CONEXIONES (1-999): " 1 999)

  # Calcular fechas
  fecha_exp=$(date -d "+$dias_exp days" +"%Y-%m-%d")
  fecha_mostrar=$(date -d "$fecha_exp" +"%b%d/%y")

  # Crear usuario en el sistema
  useradd -e "$fecha_exp" -M -s /bin/false "$nuevo_usuario" &>/dev/null
  echo "$nuevo_usuario:$nueva_pass" | chpasswd

  # Guardar en archivo
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
