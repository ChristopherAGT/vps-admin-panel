
#!/usr/bin/env bash
# ============================================================
# DARNIX SSH BACKUP MANAGER PREMIUM
# Backup y restauracion selectiva de cuentas SSH
# ============================================================

set -Eeuo pipefail
umask 077

VERSION="1.0.0"
BACKUP_DIR="/root/darnix-backups"
SSH_DIR="/etc/ssh"
DB_USERS="$SSH_DIR/.ssh.db"
DB_QUOTAS="$SSH_DIR/quotas.db"
DB_TRAFFIC="$SSH_DIR/traffic.db"
CONFIG_DIR="$SSH_DIR/sshd_config.d"
BANNER_DIR="$SSH_DIR/banners"
TEMP_DIR=""
CURRENT_USER=""

# -------------------- COLORES --------------------

if [[ -t 1 ]]; then
    RED=$'\033[1;31m'
    GREEN=$'\033[1;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[1;34m'
    MAGENTA=$'\033[1;35m'
    CYAN=$'\033[1;36m'
    WHITE=$'\033[1;37m'
    DIM=$'\033[2m'
    RESET=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE=''
    MAGENTA='' CYAN='' WHITE='' DIM='' RESET=''
fi

# -------------------- UTILIDADES --------------------

pause() {
    echo
    read -r -p "Presiona ENTER para continuar..." _
}

ok()   { echo "${GREEN}✔${RESET} $*"; }
warn() { echo "${YELLOW}⚠${RESET} $*"; }
err()  { echo "${RED}✖${RESET} $*" >&2; }
info() { echo "${CYAN}➜${RESET} $*"; }

die() {
    err "$*"
    exit 1
}

cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
}
trap cleanup EXIT

header() {
    clear 2>/dev/null || true
    echo "${CYAN}╔══════════════════════════════════════════════════════╗${RESET}"
    echo "${CYAN}║${WHITE}          DARNIX SSH BACKUP MANAGER PREMIUM          ${CYAN}║${RESET}"
    echo "${CYAN}╠══════════════════════════════════════════════════════╣${RESET}"
    printf "${CYAN}║${RESET}  ${MAGENTA}Version:${RESET} %-12s ${MAGENTA}Modo:${RESET} %-24s${CYAN}║${RESET}\n" \
        "$VERSION" "Backup selectivo"
    echo "${CYAN}╚══════════════════════════════════════════════════════╝${RESET}"
    echo
}

require_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Ejecuta este panel como root."
}

require_commands() {
    local missing=()
    local cmd
    for cmd in python3 tar gzip getent stat awk grep date mktemp; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    ((${#missing[@]} == 0)) || die "Faltan comandos: ${missing[*]}"
}

init() {
    require_root
    require_commands

    [[ -d "$SSH_DIR" ]] || die "No existe $SSH_DIR"
    [[ -f "$DB_USERS" ]] || die "No existe $DB_USERS"
    [[ -f "$DB_QUOTAS" ]] || die "No existe $DB_QUOTAS"
    [[ -f "$DB_TRAFFIC" ]] || die "No existe $DB_TRAFFIC"

    mkdir -p -- "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
}

valid_user() {
    [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*[$]?$ ]]
}

account_exists() {
    getent passwd "$1" >/dev/null 2>&1
}

darnix_expiry() {
    awk -v u="$1" '
        $1=="###" && $2==u { d=$3 }
        END { if (d!="") print d }
    ' "$DB_USERS"
}

list_users() {
    awk '
        $1=="###" && $2!="" { print $2 }
    ' "$DB_USERS" | sort -u
}

is_darnix_user() {
    [[ -n "$(darnix_expiry "$1")" ]]
}

safe_banner_path() {
    printf '%s/banner_%s.txt' "$BANNER_DIR" "$1"
}

safe_config_path() {
    printf '%s/%s.conf' "$CONFIG_DIR" "$1"
}

# -------------------- RESPALDO --------------------

backup_one() {
    local user="$1"
    local expiry uid gid shell hash
    local work archive config banner

    valid_user "$user" || {
        err "Nombre de usuario no válido: $user"
        return 1
    }

    is_darnix_user "$user" || {
        err "El usuario $user no aparece en la base Darnix."
        return 1
    }

    account_exists "$user" || {
        err "No existe la cuenta Linux $user."
        return 1
    }

    expiry="$(darnix_expiry "$user")"
    IFS=: read -r _ _ uid gid _ _ shell < <(getent passwd "$user")

    hash="$(awk -F: -v u="$user" '$1==u {print $2}' /etc/shadow)"
    [[ -n "$hash" ]] || {
        err "No se encontró la entrada de shadow para $user."
        return 1
    }

    work="$(mktemp -d "$BACKUP_DIR/.work.XXXXXXXX")"
    chmod 700 "$work"
    mkdir -p "$work/account"
    chmod 700 "$work/account"

    # Metadatos individuales. No se guarda la contraseña en claro.
    printf '%s\n' "$user" > "$work/account/username"
    printf '%s\n' "$expiry" > "$work/account/darnix-expiry"
    printf '%s\n' "$uid" > "$work/account/uid"
    printf '%s\n' "$gid" > "$work/account/gid"
    printf '%s\n' "$shell" > "$work/account/shell"

    # Guardar solamente la entrada de shadow del usuario seleccionado.
    awk -F: -v u="$user" '$1==u {print; found=1} END {exit !found}' \
        /etc/shadow > "$work/account/shadow-entry" || {
        rm -rf "$work"
        err "No se pudo guardar la entrada de shadow."
        return 1
    }

    # Expiración de la cuenta Linux.
    chage -l "$user" > "$work/account/chage.txt" 2>/dev/null || true
    chage -E "$user" -l >/dev/null 2>&1 || true

    # Registro individual de Darnix.
    awk -v u="$user" '$1=="###" && $2==u {print}' \
        "$DB_USERS" > "$work/account/darnix-entry"

    # Límite individual.
    if [[ -f "$SSH_DIR/$user" ]]; then
        cp -a -- "$SSH_DIR/$user" "$work/account/limit"
    else
        : > "$work/account/limit-missing"
    fi

    # Archivos de configuración SSH y banner.
    config="$(safe_config_path "$user")"
    banner="$(safe_banner_path "$user")"

    if [[ -f "$config" ]]; then
        cp -a -- "$config" "$work/account/sshd-user.conf"
    else
        : > "$work/account/config-missing"
    fi

    if [[ -f "$banner" ]]; then
        cp -a -- "$banner" "$work/account/banner.txt"
    else
        : > "$work/account/banner-missing"
    fi

    # Extraer únicamente la cuota y el tráfico de este usuario.
    python3 - "$DB_QUOTAS" "$DB_TRAFFIC" "$user" \
        "$work/account/quota.json" "$work/account/traffic.json" <<'PY'
import json, os, sys

qpath, tpath, user, qout, tout = sys.argv[1:]

def read_db(path):
    with open(path, encoding="utf-8") as f:
        obj = json.load(f)
    if not isinstance(obj, dict):
        raise ValueError(f"La base {path} no es un objeto JSON")
    return obj

q = read_db(qpath)
t = read_db(tpath)

for obj, out in ((q, qout), (t, tout)):
    data = {"exists": user in obj}
    if user in obj:
        data["value"] = obj[user]
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
        f.write("\n")
    os.chmod(out, 0o600)
PY

    # Información de la versión del backup.
    printf '%s\n' "$VERSION" > "$work/account/backup-version"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "$work/account/created-utc"

    archive="$BACKUP_DIR/${user}-$(date '+%Y%m%d-%H%M%S').tar.gz"

    if ! tar -czf "$archive" -C "$work" account; then
        rm -rf "$work"
        rm -f "$archive"
        err "Falló la creación del archivo."
        return 1
    fi

    chmod 600 "$archive"
    rm -rf "$work"

    ok "Backup creado para: $user"
    info "Archivo: $archive"
    info "Tamaño: $(du -h "$archive" | awk '{print $1}')"
}

backup_all() {
    local users=()
    local user failures=0

    mapfile -t users < <(list_users)

    ((${#users[@]} > 0)) || {
        warn "No hay usuarios en la base Darnix."
        return
    }

    echo
    info "Se respaldarán ${#users[@]} cuentas."
    read -r -p "¿Continuar? [s/N]: " confirm
    [[ "$confirm" =~ ^[sS]$ ]] || return

    for user in "${users[@]}"; do
        echo
        if ! backup_one "$user"; then
            ((failures+=1))
        fi
    done

    echo
    if ((failures == 0)); then
        ok "Todos los backups terminaron correctamente."
    else
        warn "Backups fallidos: $failures"
    fi
}

backup_menu() {
    local users=()
    local user
    mapfile -t users < <(list_users)

    header
    echo "${WHITE}CREAR RESPALDO${RESET}"
    echo
    echo "  1) Respaldar una cuenta"
    echo "  2) Respaldar todas las cuentas"
    echo "  0) Volver"
    echo
    read -r -p "Selecciona una opción: " option

    case "$option" in
        1)
            echo
            if ((${#users[@]} == 0)); then
                warn "No se encontraron cuentas."
                pause
                return
            fi
            printf '  %s\n' "${users[@]}"
            echo
            read -r -p "Usuario a respaldar: " user
            backup_one "$user" || true
            pause
            ;;
        2)
            backup_all
            pause
            ;;
        0) return ;;
        *)
            warn "Opción no válida."
            pause
            ;;
    esac
}

# -------------------- VALIDAR ARCHIVO --------------------

validate_archive() {
    local archive="$1"
    local listing

    [[ -f "$archive" ]] || {
        err "El archivo no existe."
        return 1
    }

    gzip -t "$archive" 2>/dev/null || {
        err "El archivo comprimido está dañado."
        return 1
    }

    listing="$(tar -tzf "$archive")" || return 1

    # Rechazar rutas absolutas y traversal.
    if printf '%s\n' "$listing" |
        grep -Eq '(^/|(^|/)\.\.(/|$))'; then
        err "El archivo contiene rutas inseguras."
        return 1
    fi

    if ! printf '%s\n' "$listing" |
        grep -qx 'account/username'; then
        err "No parece un backup compatible."
        return 1
    fi
}

# -------------------- FUSIÓN JSON --------------------

merge_json_key() {
    local file="$1"
    local user="$2"
    local saved="$3"

    python3 - "$file" "$user" "$saved" <<'PY'
import json, os, sys, tempfile

path, user, saved = sys.argv[1:]
with open(path, encoding="utf-8") as f:
    db = json.load(f)
with open(saved, encoding="utf-8") as f:
    entry = json.load(f)

if not isinstance(db, dict):
    raise ValueError(f"{path} no contiene un objeto JSON")

if entry.get("exists"):
    db[user] = entry.get("value")
else:
    db.pop(user, None)

directory = os.path.dirname(path)
fd, temp = tempfile.mkstemp(prefix=".darnix-db-", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(db, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.chmod(temp, os.stat(path).st_mode & 0o777)
    os.replace(temp, path)
except Exception:
    try:
        os.unlink(temp)
    except OSError:
        pass
    raise
PY
}

# -------------------- RESTAURACIÓN --------------------

restore_one() {
    local archive="$1"
    local user expiry hash shadow_line shell uid gid
    local config banner current_hash prebackup
    local existed=0
    local created=0
    local dest_config dest_banner
    local backup_files

    validate_archive "$archive" || return 1

    TEMP_DIR="$(mktemp -d)"
    chmod 700 "$TEMP_DIR"

    tar -xzf "$archive" -C "$TEMP_DIR" || {
        err "No se pudo extraer el backup."
        rm -rf "$TEMP_DIR"
        TEMP_DIR=""
        return 1
    }

    local a="$TEMP_DIR/account"

    [[ -f "$a/username" && -f "$a/shadow-entry" &&
       -f "$a/darnix-entry" && -f "$a/quota.json" &&
       -f "$a/traffic.json" ]] || {
        err "Faltan archivos obligatorios en el backup."
        rm -rf "$TEMP_DIR"
        TEMP_DIR=""
        return 1
    }

    user="$(cat "$a/username")"
    valid_user "$user" || {
        err "Nombre de usuario inválido en el backup."
        rm -rf "$TEMP_DIR"
        TEMP_DIR=""
        return 1
    }

    expiry="$(cat "$a/darnix-expiry")"
    shell="$(cat "$a/shell")"
    uid="$(cat "$a/uid")"
    gid="$(cat "$a/gid")"

    [[ "$expiry" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
        err "Fecha de vencimiento inválida."
        rm -rf "$TEMP_DIR"
        TEMP_DIR=""
        return 1
    }

    shadow_line="$(cat "$a/shadow-entry")"
    [[ "$(printf '%s\n' "$shadow_line" | awk -F: '{print $1}')" == "$user" ]] || {
        err "La entrada de shadow no corresponde a la cuenta."
        rm -rf "$TEMP_DIR"
        TEMP_DIR=""
        return 1
    }

    hash="$(printf '%s\n' "$shadow_line" | awk -F: '{print $2}')"
    [[ -n "$hash" ]] || {
        err "Hash de contraseña vacío. Restauración cancelada."
        rm -rf "$TEMP_DIR"
        TEMP_DIR=""
        return 1
    }

    echo
    echo "${YELLOW}Cuenta seleccionada:${RESET} $user"
    echo "${YELLOW}Vencimiento Darnix:${RESET} $expiry"
    echo "${YELLOW}UID original:${RESET} $uid"
    echo
    warn "No se restaurará la contraseña en texto claro."
    warn "Las bases de datos se modificarán únicamente para este usuario."

    if account_exists "$user"; then
        existed=1
        warn "La cuenta ya existe en este VPS."
        echo "La restauración actualizará la credencial y los datos Darnix."
    else
        info "La cuenta no existe; se creará en este VPS."
    fi

    read -r -p "Escribe RESTAURAR para continuar: " confirm
    [[ "$confirm" == "RESTAURAR" ]] || {
        info "Operación cancelada."
        rm -rf "$TEMP_DIR"
        TEMP_DIR=""
        return 0
    }

    # Respaldo previo de archivos y bases de datos que se modificarán.
    prebackup="$BACKUP_DIR/pre-restore-${user}-$(date '+%Y%m%d-%H%M%S').tar.gz"
    backup_files=(
        etc-passwd
        etc-shadow
        darnix-users
        darnix-quotas
        darnix-traffic
    )

    local safety="$TEMP_DIR/safety"
    mkdir -p "$safety"

    cp -a /etc/passwd "$safety/etc-passwd"
    cp -a /etc/shadow "$safety/etc-shadow"
    cp -a "$DB_USERS" "$safety/darnix-users"
    cp -a "$DB_QUOTAS" "$safety/darnix-quotas"
    cp -a "$DB_TRAFFIC" "$safety/darnix-traffic"

    if [[ -f "$SSH_DIR/$user" ]]; then
        cp -a "$SSH_DIR/$user" "$safety/limit"
    fi
    if [[ -f "$(safe_config_path "$user")" ]]; then
        cp -a "$(safe_config_path "$user")" "$safety/user.conf"
    fi
    if [[ -f "$(safe_banner_path "$user")" ]]; then
        cp -a "$(safe_banner_path "$user")" "$safety/banner.txt"
    fi

    tar -czf "$prebackup" -C "$safety" . || {
        err "No se pudo crear el respaldo previo. No se continuará."
        rm -rf "$TEMP_DIR"
        TEMP_DIR=""
        return 1
    }
    chmod 600 "$prebackup"
    ok "Respaldo de seguridad previo: $prebackup"

    # Crear cuenta si falta. No forzar UID/GID del servidor de origen:
    # podrían estar ocupados por otras cuentas en el destino.
    if ((existed == 0)); then
        if ! useradd -M -s /bin/false "$user"; then
            err "No se pudo crear la cuenta Linux."
            rm -rf "$TEMP_DIR"
            TEMP_DIR=""
            return 1
        fi
        created=1
    fi

    # Restaurar el hash cifrado, nunca una contraseña en texto claro.
    if ! printf '%s:%s\n' "$user" "$hash" | chpasswd -e; then
        err "No se pudo restaurar la credencial."
        rm -rf "$TEMP_DIR"
        TEMP_DIR=""
        return 1
    fi

    # Mantener shell restringida, salvo que el respaldo tenga otra shell válida.
    if [[ "$shell" == "/bin/false" || "$shell" == "/usr/sbin/nologin" ]]; then
        usermod -s "$shell" "$user"
    else
        warn "Shell original no restringida; se usará /bin/false por seguridad."
        usermod -s /bin/false "$user"
    fi

    # Restaurar vencimiento de Linux y registro Darnix.
    chage -E "$expiry" "$user"

    python3 - "$DB_USERS" "$user" "$expiry" <<'PY'
import os, sys, tempfile
path, user, expiry = sys.argv[1:]
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
lines = [x for x in lines if not (x.split()[:2] == ["###", user])]
lines.append(f"### {user} {expiry}\n")
fd, temp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".sshdb-")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.writelines(lines)
    os.chmod(temp, os.stat(path).st_mode & 0o777)
    os.replace(temp, path)
except Exception:
    try: os.unlink(temp)
    except OSError: pass
    raise
PY

    # Restaurar límite individual o eliminarlo si no existía en el origen.
    if [[ -f "$a/limit" ]]; then
        install -o root -g root -m 600 "$a/limit" "$SSH_DIR/$user"
    else
        rm -f -- "$SSH_DIR/$user"
    fi

    mkdir -p "$CONFIG_DIR" "$BANNER_DIR"
    dest_config="$(safe_config_path "$user")"
    dest_banner="$(safe_banner_path "$user")"

    if [[ -f "$a/sshd-user.conf" ]]; then
        install -o root -g root -m 644 "$a/sshd-user.conf" "$dest_config"
    else
        rm -f -- "$dest_config"
    fi

    if [[ -f "$a/banner.txt" ]]; then
        install -o root -g root -m 644 "$a/banner.txt" "$dest_banner"
    else
        rm -f -- "$dest_banner"
    fi

    # Fusionar exclusivamente la entrada del usuario en cada JSON.
    merge_json_key "$DB_QUOTAS" "$user" "$a/quota.json"
    merge_json_key "$DB_TRAFFIC" "$user" "$a/traffic.json"

    # Validar sintaxis antes de finalizar.
    if ! sshd -t; then
        err "La configuración SSH no es válida tras la restauración."
        warn "No se recargó SSH. Revisa el respaldo previo:"
        echo "$prebackup"
        warn "Puede ser necesario restaurar manualmente los archivos afectados."
        rm -rf "$TEMP_DIR"
        TEMP_DIR=""
        return 1
    fi

    ok "Cuenta restaurada: $user"
    ok "Credencial cifrada aplicada."
    ok "Vencimiento Darnix y límite individual procesados."
    ok "Cuota y tráfico fusionados por usuario."
    ok "Configuración SSH validada con sshd -t."
    info "No se ha reiniciado ni recargado SSH."

    if ((created == 1)); then
        info "Cuenta Linux nueva; su UID/GID se asignó localmente."
    fi

    rm -rf "$TEMP_DIR"
    TEMP_DIR=""
}

# -------------------- LISTADOS --------------------

show_users() {
    local users=()
    local user expiry uid
    mapfile -t users < <(list_users)

    header
    echo "${WHITE}CUENTAS DARNIX${RESET}"
    echo

    if ((${#users[@]} == 0)); then
        warn "No se encontraron cuentas."
    else
        printf "%-4s %-20s %-15s %-12s\n" "#" "USUARIO" "ESTADO LINUX" "VENCE DARNIX"
        printf '%s\n' "----------------------------------------------------------"

        local n=0
        for user in "${users[@]}"; do
            ((n+=1))
            expiry="$(darnix_expiry "$user")"
            if account_exists "$user"; then
                printf "%-4s %-20s %-15s %-12s\n" "$n" "$user" "Existe" "$expiry"
            else
                printf "%-4s %-20s %-15s %-12s\n" "$n" "$user" "Sin cuenta Linux" "$expiry"
            fi
        done
    fi
    pause
}

show_backups() {
    header
    echo "${WHITE}RESPALDOS DISPONIBLES${RESET}"
    echo

    local files=()
    mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' -printf '%f\n' | sort)

    if ((${#files[@]} == 0)); then
        warn "Todavía no hay backups."
    else
        local f
        for f in "${files[@]}"; do
            printf "  ${GREEN}•${RESET} %-55s %s\n" "$f" \
                "$(du -h "$BACKUP_DIR/$f" | awk '{print $1}')"
        done
    fi
    echo
    info "Directorio: $BACKUP_DIR"
    pause
}

restore_menu() {
    local files=()
    local i=1
    local f choice archive

    mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' -printf '%f\n' | sort)

    header
    echo "${WHITE}RESTAURAR CUENTA${RESET}"
    echo

    if ((${#files[@]} == 0)); then
        warn "No hay archivos de backup."
        pause
        return
    fi

    for f in "${files[@]}"; do
        printf "  ${CYAN}%2d)${RESET} %s\n" "$i" "$f"
        ((i+=1))
    done

    echo
    echo "  0) Volver"
    echo
    read -r -p "Selecciona el backup: " choice

    [[ "$choice" =~ ^[0-9]+$ ]] || {
        warn "Selección no válida."
        pause
        return
    }

    ((choice == 0)) && return
    ((choice >= 1 && choice <= ${#files[@]})) || {
        warn "Selección fuera de rango."
        pause
        return
    }

    archive="$BACKUP_DIR/${files[$((choice-1))]}"
    restore_one "$archive" || true
    pause
}

delete_backup_menu() {
    local files=()
    local i=1 choice f

    mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' -printf '%f\n' | sort)

    header
    echo "${WHITE}ELIMINAR BACKUP${RESET}"
    echo

    if ((${#files[@]} == 0)); then
        warn "No hay backups para eliminar."
        pause
        return
    fi

    for f in "${files[@]}"; do
        printf "  ${CYAN}%2d)${RESET} %s\n" "$i" "$f"
        ((i+=1))
    done

    echo
    echo "  0) Volver"
    read -r -p "Selecciona el archivo: " choice

    [[ "$choice" =~ ^[0-9]+$ ]] || {
        warn "Selección no válida."
        pause
        return
    }

    ((choice == 0)) && return
    ((choice >= 1 && choice <= ${#files[@]})) || {
        warn "Selección fuera de rango."
        pause
        return
    }

    f="${files[$((choice-1))]}"
    echo
    warn "Se eliminará permanentemente: $f"
    read -r -p "Escribe ELIMINAR para confirmar: " confirm

    if [[ "$confirm" == "ELIMINAR" ]]; then
        rm -f -- "$BACKUP_DIR/$f"
        ok "Backup eliminado."
    else
        info "Operación cancelada."
    fi
    pause
}

# -------------------- MENÚ PRINCIPAL --------------------

main_menu() {
    while true; do
        header
        echo "${WHITE}PANEL PRINCIPAL${RESET}"
        echo
        echo "  ${GREEN}1)${RESET} Crear backup de una cuenta"
        echo "  ${GREEN}2)${RESET} Crear backup de todas las cuentas"
        echo "  ${BLUE}3)${RESET} Restaurar una cuenta"
        echo "  ${CYAN}4)${RESET} Ver cuentas Darnix"
        echo "  ${CYAN}5)${RESET} Ver backups disponibles"
        echo "  ${RED}6)${RESET} Eliminar un backup"
        echo "  ${YELLOW}7)${RESET} Verificar requisitos del sistema"
        echo "  ${RED}0)${RESET} Salir"
        echo
        echo "${DIM}Directorio de backups: $BACKUP_DIR${RESET}"
        echo
        read -r -p "Selecciona una opción: " option

        case "$option" in
            1) backup_menu ;;
            2) backup_all; pause ;;
            3) restore_menu ;;
            4) show_users ;;
            5) show_backups ;;
            6) delete_backup_menu ;;
            7)
                header
                echo "${WHITE}DIAGNÓSTICO${RESET}"
                echo
                for f in "$DB_USERS" "$DB_QUOTAS" "$DB_TRAFFIC"; do
                    if [[ -f "$f" ]]; then
                        ok "Encontrado: $f"
                    else
                        err "Falta: $f"
                    fi
                done
                command -v python3 >/dev/null && ok "Python 3 disponible" || err "Falta Python 3"
                command -v sshd >/dev/null && ok "OpenSSH disponible" || err "Falta sshd"
                sshd -t && ok "Configuración SSH válida" || err "Configuración SSH inválida"
                pause
                ;;
            0)
                echo
                ok "Gracias por utilizar Darnix Backup Manager."
                exit 0
                ;;
            *)
                warn "Opción no válida."
                sleep 1
                ;;
        esac
    done
}

init
main_menu
