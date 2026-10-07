#!/bin/bash
set -uo pipefail

# ============================================================
#        🚀 ADM-LITE SSH BACKUP MANAGER PREMIUM v2.0
# ============================================================
#
# Backup y restauración ADM-Lite HWID
#
# Incluye:
#   👤 Usuarios Linux
#   🔑 Cuentas HWID
#   📅 Vencimientos
#   📊 Tráfico
#   📦 Cuotas
#   🖼️ Banners SSH
#   🔒 Límites SSH
#   ⚙️ PAM
#
# Restauración:
#   💾 Local
#   ☁️ URL / Nube
#
# Mejoras:
#   ✅ Validación root
#   ✅ Backup preventivo
#   ✅ Validación TAR
#   ✅ Validación SSH
#   ✅ Restauración segura
#
# ============================================================


# ============================================================
# CONFIGURACIÓN
# ============================================================


BACKUP_DIR="/root"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")

BACKUP_NAME="adm-lite-backup-$DATE.tar.gz"


# ============================================================
# COLORES
# ============================================================


GREEN="\033[1;32m"
BLUE="\033[1;34m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
MAGENTA="\033[1;35m"
WHITE="\033[1;37m"
RESET="\033[0m"



# ============================================================
# FUNCIONES VISUALES
# ============================================================


line(){

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

}



banner(){

clear

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════╗"
echo "║                                              ║"
echo "║       🚀 ADM-LITE SSH BACKUP MANAGER         ║"
echo "║             PREMIUM EDITION v2.0             ║"
echo "║                                              ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${RESET}"

}



pause(){

echo ""

read -p "⏎ Presiona Enter para continuar..."

}



success(){

echo -e "${GREEN}✅ $1${RESET}"

}



error(){

echo -e "${RED}❌ $1${RESET}"

}



info(){

echo -e "${YELLOW}➜ $1${RESET}"

}



warning(){

echo -e "${RED}⚠️ $1${RESET}"

}



# ============================================================
# VERIFICACIÓN ROOT
# ============================================================


check_root(){

if [ "$(id -u)" != "0" ]; then

error "Este programa debe ejecutarse como root"

exit 1

fi

}



# ============================================================
# CREAR BACKUP
# ============================================================


create_backup(){


banner


BACKUP_FILE="$BACKUP_DIR/$BACKUP_NAME"


line

echo -e "${MAGENTA}📦 CREANDO COPIA DE SEGURIDAD${RESET}"

line


echo ""

info "Preparando información del backup..."



TEMP_INFO="/tmp/adm-lite-backup-info.txt"


cat > "$TEMP_INFO" <<EOF
========================================
ADM-LITE SSH BACKUP MANAGER
========================================

Fecha:
$(date)

Servidor:
$(hostname)

Sistema:
$(uname -a)

Backup:
$BACKUP_NAME

========================================
EOF



echo ""

info "Comprimiendo archivos..."



tar --ignore-failed-read \
    -czpvf "$BACKUP_FILE" \
    "$TEMP_INFO" \
    /etc/adm-lite \
    /etc/ssh/.ssh.db \
    /etc/ssh/traffic.db \
    /etc/ssh/quotas.db \
    /etc/ssh/banners \
    /etc/ssh/sshd_config \
    /etc/ssh/sshd_config.d \
    /etc/passwd \
    /etc/shadow \
    /etc/group \
    /etc/gshadow \
    /etc/pam.d \
    /etc/security \
    /usr/local/bin/pam_limit.sh \
    2>/dev/null || true



rm -f "$TEMP_INFO"



echo ""

line

success "BACKUP COMPLETADO"

line



echo ""

echo -e "${WHITE}📁 Archivo generado:${RESET}"

echo "$BACKUP_FILE"


echo ""

ls -lh "$BACKUP_FILE"



echo ""

info "Verificando integridad..."



if tar -tzf "$BACKUP_FILE" >/dev/null 2>&1; then

success "Backup verificado correctamente"

else

error "El backup parece estar corrupto"

fi



pause


}



# ============================================================
# PREPARAR RESTAURACIÓN
# ============================================================


prepare_restore(){


echo ""

info "Creando copia preventiva del sistema..."



PRE="/root/pre_restore_backup_$DATE"



mkdir -p "$PRE"



cp -a /etc/passwd "$PRE/" 2>/dev/null || true

cp -a /etc/shadow "$PRE/" 2>/dev/null || true

cp -a /etc/group "$PRE/" 2>/dev/null || true

cp -a /etc/gshadow "$PRE/" 2>/dev/null || true

cp -a /etc/ssh/sshd_config "$PRE/" 2>/dev/null || true

cp -a /etc/ssh/sshd_config.d "$PRE/" 2>/dev/null || true



echo ""

line

warning "ATENCIÓN"

line


echo ""

echo "La restauración reemplazará archivos actuales."

echo ""

echo "Backup preventivo:"
echo "$PRE"

echo ""



read -p "¿Continuar restauración? (s/n): " CONFIRM



if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then

error "Restauración cancelada"

return 1

fi


return 0


}

# ============================================================
# EJECUTAR RESTAURACIÓN
# ============================================================


execute_restore(){


BACKUP="$1"



if ! prepare_restore; then

pause

return

fi



echo ""

line

info "Deteniendo servicio SSH temporalmente..."

line



systemctl stop ssh 2>/dev/null || \
systemctl stop sshd 2>/dev/null || true



echo ""

line

info "Restaurando archivos..."

line



if tar -xzpvf "$BACKUP" -C /; then

success "Archivos restaurados correctamente"

else

error "Error durante la restauración"

pause

return

fi



echo ""

info "Aplicando permisos..."



if [ -d /etc/adm-lite ]; then

chmod 755 /etc/adm-lite 2>/dev/null || true

fi



if [ -d /etc/adm-lite/userDIR ]; then

chmod 700 /etc/adm-lite/userDIR 2>/dev/null || true

chmod 644 /etc/adm-lite/userDIR/* 2>/dev/null || true

fi



chmod 600 /etc/ssh/*.db 2>/dev/null || true



echo ""

info "Validando configuración SSH..."



if command -v sshd >/dev/null 2>&1; then


if sshd -t 2>/dev/null; then

success "Configuración SSH válida"

else

warning "SSH tiene errores de configuración"

fi


fi



echo ""

info "Iniciando servicio SSH..."



if systemctl start ssh 2>/dev/null; then

success "SSH iniciado"

elif systemctl start sshd 2>/dev/null; then

success "SSHD iniciado"

else

warning "No se pudo iniciar SSH automáticamente"

fi



echo ""

line

success "RESTAURACIÓN COMPLETADA"

line



echo ""

echo -e "${WHITE}🛡️ Backup preventivo guardado en:${RESET}"

echo "$PRE"



pause


}




# ============================================================
# RESTAURACIÓN LOCAL
# ============================================================


restore_local(){


banner


line

echo -e "${MAGENTA}💾 RESTAURACIÓN DESDE ARCHIVO LOCAL${RESET}"

line



echo ""

echo -e "${YELLOW}📂 Backups encontrados:${RESET}"

echo ""



BACKUPS=$(find /root -maxdepth 1 -name "adm-lite-backup-*.tar.gz" 2>/dev/null)



if [ -z "$BACKUPS" ]; then

error "No existen backups locales"

pause

return

fi



echo "$BACKUPS"



echo ""

read -p "📦 Nombre completo del backup: " BACKUP



if [ -f "/root/$BACKUP" ]; then

BACKUP="/root/$BACKUP"

fi



if [ ! -f "$BACKUP" ]; then

error "Archivo no encontrado"

pause

return

fi



info "Validando backup..."



if ! tar -tzf "$BACKUP" >/dev/null 2>&1; then

error "Backup inválido o corrupto"

pause

return

fi



success "Backup válido"



execute_restore "$BACKUP"



}




# ============================================================
# RESTAURACIÓN DESDE URL / NUBE
# ============================================================


restore_cloud(){


banner


line

echo -e "${MAGENTA}☁️ RESTAURACIÓN DESDE URL / NUBE${RESET}"

line



echo ""

read -p "🔗 URL del backup: " URL



TEMP="/root/adm-lite-cloud-restore.tar.gz"



echo ""

info "Descargando backup..."



if command -v curl >/dev/null 2>&1; then


curl -L --progress-bar "$URL" -o "$TEMP"



elif command -v wget >/dev/null 2>&1; then


wget --show-progress "$URL" -O "$TEMP"



else

error "No existe curl ni wget instalado"

pause

return

fi



if [ ! -s "$TEMP" ]; then

error "La descarga falló"

pause

return

fi



info "Validando archivo descargado..."



if ! tar -tzf "$TEMP" >/dev/null 2>&1; then

error "El archivo descargado no es un backup válido"

rm -f "$TEMP"

pause

return

fi



success "Backup descargado correctamente"



ls -lh "$TEMP"



execute_restore "$TEMP"



rm -f "$TEMP"



}




# ============================================================
# MENÚ RESTAURACIÓN
# ============================================================


restore_menu(){


while true

do


banner


line

echo -e "${MAGENTA}💾 MENÚ RESTAURACIÓN${RESET}"

line



echo ""

echo " 1) 💾 Restaurar archivo local"

echo " 2) ☁️ Restaurar desde URL / Nube"

echo " 0) 🔙 Volver"



echo ""

read -p "Seleccione una opción: " OPTION



case "$OPTION" in


1)

restore_local

;;


2)

restore_cloud

;;


0)

break

;;


*)

error "Opción inválida"

sleep 2

;;


esac


done


}




# ============================================================
# MENÚ PRINCIPAL
# ============================================================


main_menu(){


while true

do


banner



line

echo -e "${MAGENTA}📌 MENÚ PRINCIPAL${RESET}"

line



echo ""

echo " 1) 📦 Crear Copia de Seguridad"

echo " 2) 💾 Restaurar Copia de Seguridad"

echo " 0) 🚪 Salir"



echo ""

read -p "Seleccione una opción: " OPTION



case "$OPTION" in


1)

create_backup

;;


2)

restore_menu

;;


0)

clear

echo ""

echo -e "${CYAN}👋 Cerrando ADM-LITE BACKUP MANAGER...${RESET}"

echo ""

exit 0

;;


*)

error "Opción inválida"

sleep 2

;;


esac


done


}




# ============================================================
# INICIO DEL PROGRAMA
# ============================================================


check_root

main_menu
