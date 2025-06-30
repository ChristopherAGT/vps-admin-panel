#!/bin/bash

# Colores
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# Obtener IP del servidor
IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

# ═════════════════════════════════════════════════════
mostrar_tabla_usuarios() {
  clear
  echo -e "${CYAN}=====================================================${RESET}"
  printf "                   ${YELLOW}CREAR USUARIOS${RESET}\n"
  echo -e "${CYAN}=====================================================${RESET}"
  echo -e "  N° Usuario       Contraseña   Fecha    Días Con Sta"
  echo -e "${CYAN}-----------------------------------------------------${RESET}"

  n=1
  while IFS=: read -r user _ uid _ _ _ shell; do
    if [[ $uid -ge 1000 && "$shell" != "/usr/sbin/nologin" && "$shell" != "/bin/false" ]]; then
      nombre=$(printf "%-14s" "$user")
      pass="********"
      fecha=$(date -d "+7 days" +"%b%d/%y")
      dias=7
      lim=2
      sta="ULK"
      printf "  %-2s) %-14s %-10s %-8s %-4s %-4s %-s\n" "$n" "$nombre" "$pass" "$fecha" "$dias" "$lim" "$sta"
      ((n++))
    fi
  done < /etc/passwd

  echo -e "${CYAN}=====================================================${RESET}"
  echo -e "  [0] > VOLVER"
  echo -e "${CYAN}=====================================================${RESET}"
}

# ═════════════════════════════════════════════════════
crear_usuario() {
  echo -ne "\n NUEVO USUARIO: "; read -r nuevo_usuario
  echo -ne " CONTRASEÑA: "; read -r nueva_pass
  echo -ne " DÍAS PARA EXPIRAR: "; read -r dias_exp
  echo -ne " CONEXIONES: "; read -r conexiones

  # Fecha en formato requerido
  fecha_exp=$(date -d "+$dias_exp days" +"%Y-%m-%d")
  fecha_mostrar=$(date -d "+$dias_exp days" +"%b/%d/%Y")

  # Crear usuario
  useradd -e "$fecha_exp" -M -s /bin/bash "$nuevo_usuario" &>/dev/null
  echo "$nuevo_usuario:$nueva_pass" | chpasswd

  # Mostrar resultado
  clear
  echo -e "${CYAN}=====================================================${RESET}"
  printf "              ${YELLOW}USUARIO CREADO CON ÉXITO!${RESET}\n"
  echo -e "${CYAN}=====================================================${RESET}"
  printf " IP:                      %s\n" "$IP"
  printf " NOMBRE DE USUARIO:       %s\n" "$nuevo_usuario"
  printf " CONTRASEÑA DE USUARIO:   %s\n" "$nueva_pass"
  printf " CONEXIONES:              %s\n" "$conexiones"
  printf " EXPIRA EN:               %s\n" "$fecha_mostrar"
  echo -e "${CYAN}=====================================================${RESET}"
  echo
  read -p "         >> Presione Enter para continuar <<" _
}

# ═════════════════════════════════════════════════════
mostrar_tabla_usuarios
crear_usuario
