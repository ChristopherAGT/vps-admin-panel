#!/bin/bash

# Colores
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

clear
echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════${RESET}"
printf "               ${YELLOW}ADMINISTRACIÓN DE USUARIOS SSH - PANEL V16${RESET}\n"
echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════${RESET}"
echo -e "  [1]> NUEVO USUARIO SSH"
echo -e "  [2]> CREAR USUARIO TEMPORAL"
echo -e "  [3]> REMOVER USUARIO"
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
