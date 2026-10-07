#!/bin/bash
set -e

# ============================================================
#        🚀 ADM-LITE SSH BACKUP MANAGER PREMIUM
# ============================================================
#
# Backup y restauración ADM-Lite HWID
#
# Incluye:
#   👤 Usuarios Linux
#   🔑 Cuentas HWID ADM-Lite
#   📅 Fechas de vencimiento
#   📊 Tráfico
#   📦 Cuotas
#   🖼️ Banners SSH
#   🔒 Límites SSH
#   ⚙️ PAM
#   🛠️ Scripts del sistema
#
# Restauración:
#   💾 Archivo local
#   ☁️ URL / Nube
#
# ============================================================


# ============================================================
#                VALIDACIÓN ROOT
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo "❌ Este script debe ejecutarse como root"
    exit 1
fi


# ============================================================
#                VARIABLES
# ============================================================

BACKUP_DIR="/root"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")


# ============================================================
#                COLORES
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
#                FUNCIONES VISUALES
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
echo "║             PREMIUM EDITION                  ║"
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




# ============================================================
#                CREAR BACKUP
# ============================================================


create_backup(){


banner


BACKUP_FILE="$BACKUP_DIR/adm-lite-backup-$DATE.tar.gz"



line

echo -e "${MAGENTA}📦 CREANDO COPIA DE SEGURIDAD${RESET}"

line


echo ""

info "Recolectando archivos ADM-Lite..."



tar --ignore-failed-read \
-czpvf "$BACKUP_FILE" \

    /etc/adm-lite \
    /etc/ssh/.ssh.db \
    /etc/ssh/traffic.db \
    /etc/ssh/quotas.db \
    /etc/ssh/banners \
    /etc/ssh/sshd_config.d \
    /etc/ssh/*.db \
    /etc/ssh/* \
    /etc/passwd \
    /etc/shadow \
    /etc/group \
    /etc/gshadow \
    /etc/pam.d \
    /usr/local/bin \
    /usr/local/sbin \
    2>/dev/null



echo ""

line

success "BACKUP COMPLETADO"

line



echo ""

echo -e "${WHITE}📁 Archivo generado:${RESET}"

echo "$BACKUP_FILE"



echo ""

ls -lh "$BACKUP_FILE"



pause


}




# ============================================================
#                PREPARAR RESTAURACIÓN
# ============================================================


prepare_restore(){


PRE="/root/pre_restore_backup_$DATE"



info "Creando backup preventivo..."



mkdir -p "$PRE"



cp -a /etc/passwd "$PRE/" 2>/dev/null || true
cp -a /etc/shadow "$PRE/" 2>/dev/null || true
cp -a /etc/group "$PRE/" 2>/dev/null || true
cp -a /etc/gshadow "$PRE/" 2>/dev/null || true
cp -a /etc/ssh "$PRE/" 2>/dev/null || true
cp -a /etc/adm-lite "$PRE/" 2>/dev/null || true



echo ""

line

echo -e "${RED}⚠️ ADVERTENCIA${RESET}"

echo ""

echo "La restauración reemplazará configuraciones actuales."

echo "Se recomienda usarlo en un VPS limpio."

echo ""



read -p "¿Continuar restauración? (s/n): " CONFIRM



if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then

error "Restauración cancelada"

return 1

fi


return 0


}

# ============================================================
#                EJECUTAR RESTAURACIÓN
# ============================================================


execute_restore(){


BACKUP="$1"



if ! prepare_restore; then

pause

return

fi



echo ""

line

info "Restaurando archivos..."

line



tar -xzpvf "$BACKUP" -C /



echo ""

info "Aplicando permisos..."



chmod 700 /etc/adm-lite/userDIR 2>/dev/null || true

chmod 644 /etc/adm-lite/userDIR/* 2>/dev/null || true



echo ""

info "Reiniciando servicios SSH..."



systemctl restart ssh 2>/dev/null || \
systemctl restart sshd 2>/dev/null || \
systemctl restart ssh.service 2>/dev/null || true



echo ""

line

success "RESTAURACIÓN COMPLETADA"

line



echo ""

echo -e "${WHITE}🛡️ Backup preventivo guardado:${RESET}"

echo "/root/pre_restore_backup_$DATE"



pause


}




# ============================================================
#                RESTAURACIÓN LOCAL
# ============================================================


restore_local(){


banner



line

echo -e "${MAGENTA}💾 RESTAURACIÓN LOCAL${RESET}"

line



echo ""

echo -e "${YELLOW}📂 Backups encontrados:${RESET}"

echo ""



BACKUPS=$(ls /root/adm-lite-backup-*.tar.gz 2>/dev/null || true)



if [ -z "$BACKUPS" ]; then

error "No existen backups locales"

pause

return

fi



echo "$BACKUPS"



echo ""

read -p "📦 Nombre del backup: " BACKUP



if [ -f "/root/$BACKUP" ]; then

BACKUP="/root/$BACKUP"

fi



if [ ! -f "$BACKUP" ]; then

error "Archivo no encontrado"

pause

return

fi



if ! tar -tzf "$BACKUP" >/dev/null 2>&1; then

error "Backup corrupto o inválido"

pause

return

fi



execute_restore "$BACKUP"



}





# ============================================================
#                RESTAURACIÓN DESDE NUBE
# ============================================================


restore_cloud(){


banner



line

echo -e "${MAGENTA}☁️ RESTAURACIÓN DESDE URL${RESET}"

line



echo ""

read -p "🔗 URL del backup: " URL



TEMP="/root/adm-lite-cloud-restore-$DATE.tar.gz"



echo ""

info "Descargando backup..."



if command -v curl >/dev/null 2>&1; then


curl -L "$URL" -o "$TEMP"



elif command -v wget >/dev/null 2>&1; then


wget "$URL" -O "$TEMP"



else


error "No existe curl ni wget"

pause

return


fi




if [ ! -s "$TEMP" ]; then


error "Descarga fallida"

pause

return


fi



if ! tar -tzf "$TEMP" >/dev/null 2>&1; then


error "El archivo descargado no es válido"

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
#                MENU RESTAURACIÓN
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



case $OPTION in


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
#                MENU PRINCIPAL
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



case $OPTION in


1)

create_backup

;;


2)

restore_menu

;;


0)

clear

echo ""

echo -e "${CYAN}👋 Cerrando ADM-LITE SSH BACKUP MANAGER${RESET}"

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
#                INICIO
# ============================================================


main_menu
