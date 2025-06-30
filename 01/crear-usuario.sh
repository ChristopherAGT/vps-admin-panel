#!/bin/bash

# Colores
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# IP del servidor
IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

# Archivo que registra los usuarios creados por este script
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
crear_usuario() {
  echo -ne "\n NUEVO USUARIO: "
  read -r nuevo_usuario

  echo -ne " CONTRASEÑA: "
  read -r nueva_pass

  echo -ne " DÍAS PARA EXPIRAR: "
  read -r dias_exp

  echo -ne " CONEXIONES: "
  read -r conexiones

  # Calcular fechas
  fecha_exp=$(date -d "+$dias_exp days" +"%Y-%m-%d")
  fecha_mostrar=$(date -d "$fecha_exp" +"%b%d/%y")

  # Crear usuario real en el sistema
  useradd -e "$fecha_exp" -M -s /bin/false "$nuevo_usuario" &>/dev/null
  echo "$nuevo_usuario:$nueva_pass" | chpasswd

  # Guardar en base de datos interna
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
