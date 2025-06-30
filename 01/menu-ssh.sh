#!/bin/bash

# Colores
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

# ══════════════ MENÚ SSH ══════════════
mostrar_menu_ssh() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════${RESET}"
  printf "               ${YELLOW}ADMINISTRACIÓN DE USUARIOS SSH - PANEL V16${RESET}\n"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════${RESET}"
  echo -e "  [1]> CREAR NUEVO USUARIO"
  echo -e "  [2]> CREAR USUARIO TEMPORAL"
  echo -e "  [3]> ELIMINAR USUARIO"
  echo -e "  [4]> RENOVAR USUARIO"
  echo -e "  [5]> EDITAR USUARIO"
  echo -e "  [6]> BLOQUEAR / DESBLOQUEAR USUARIO"
  echo -e "${CYAN}──────────────────────────────────────────────────────────────────────────────${RESET}"
  echo -e "  [7]> CONFIGURAR CONTRASEÑA GENERAL"
  echo -e "${CYAN}──────────────────────────────────────────────────────────────────────────────${RESET}"
  echo -e "  [8]> DETALLES DE TODOS LOS USUARIOS"
  echo -e "  [9]> MONITOR DE USUARIOS CONECTADOS"
  echo -e " [10]> LIMITADOR DE CUENTAS"
  echo -e "${CYAN}──────────────────────────────────────────────────────────────────────────────${RESET}"
  echo -e " [11]> ELIMINAR USUARIOS VENCIDOS"
  echo -e " [12]> ELIMINAR TODOS LOS USUARIOS"
  echo -e "${CYAN}──────────────────────────────────────────────────────────────────────────────${RESET}"
  echo -e " [13]> ADMINISTRAR COPIAS DE USUARIOS"
  echo -e "${CYAN}──────────────────────────────────────────────────────────────────────────────${RESET}"
  echo -e " [14]> CONFIGURACIÓN DEL ADMINISTRADOR SSH"
  echo -e " [15]> CAMBIAR A MODO HWID / TOKEN"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════${RESET}"
  echo -e "  [0]> VOLVER"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════${RESET}"

  # Centrado del prompt final
  WIDTH=$(tput cols)
  prompt="SELECCIONE UNA OPCIÓN:"
  padding=$(( (WIDTH - ${#prompt}) / 2 ))
  printf "\n%*s%s " "$padding" "" "$prompt"
  read -r opcion
  ejecutar_opcion_ssh "$opcion"
}

# ══════════════ LÓGICA DE OPCIONES SSH ══════════════
ejecutar_opcion_ssh() {
  case "$1" in
    1)
      # NUEVO USUARIO SSH
      bash <(curl -s https://raw.githubusercontent.com/tuusuario/repositorio/main/crear-usuario.sh)
      ;;
    2)
      # USUARIO TEMPORAL
      bash <(curl -s https://raw.githubusercontent.com/tuusuario/repositorio/main/usuario-temporal.sh)
      ;;
    3)
      bash <(curl -s https://raw.githubusercontent.com/tuusuario/repositorio/main/remover-usuario.sh)
      ;;
    4)
      bash <(curl -s https://raw.githubusercontent.com/tuusuario/repositorio/main/renovar-usuario.sh)
      ;;
    5)
      bash <(curl -s https://raw.githubusercontent.com/tuusuario/repositorio/main/editar-usuario.sh)
      ;;
    6)
      bash <(curl -s https://raw.githubusercontent.com/tuusuario/repositorio/main/bloquear-usuario.sh)
      ;;
    7)
      bash <(curl -s https://raw.githubusercontent.com/tuusuario/repositorio/main/contrasena-general.sh)
      ;;
    8)
      bash <(curl -s https://raw.githubusercontent.com/tuusuario/repositorio/main/detalles-usuarios.sh)
      ;;
    9)
      bash <(curl -s https://raw.githubusercontent.com/tuusuario/repositorio/main/monitor-conexiones.sh)
      ;;
    10)
      bash <(curl -s https://raw.githubusercontent.com/tuusuario/repositorio/main/limitador-cuentas.sh)
      ;;
    11)
      bash <(curl -s https://raw.githubusercontent.com/tuusuario/repositorio/main/eliminar-vencidos.sh)
      ;;
    12)
      bash <(curl -s https://raw.githubusercontent.com/tuusuario/repositorio/main/eliminar-todos.sh)
      ;;
    13)
      bash <(curl -s https://raw.githubusercontent.com/tuusuario/repositorio/main/copias-usuarios.sh)
      ;;
    14)
      bash <(curl -s https://raw.githubusercontent.com/tuusuario/repositorio/main/admin-ssh.sh)
      ;;
    15)
      bash <(curl -s https://raw.githubusercontent.com/tuusuario/repositorio/main/cambiar-modo.sh)
      ;;
    0)
      echo -e "\n${CYAN}Volviendo al menú principal...${RESET}"
      sleep 1
      return
      ;;
    *)
      echo -e "${RED}Opción no válida.${RESET}"
      ;;
  esac

  # Espera para volver al menú
  read -p $'\nPresiona Enter para volver al menú SSH...' _
  mostrar_menu_ssh
}

# ══════════════ INICIO ══════════════
mostrar_menu_ssh
