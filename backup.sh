
#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════╗
# ║       💎 DARNIX JSON BACKUP MANAGER PREMIUM 💎          ║
# ║       Backup y restauración selectiva de cuentas SSH    ║
# ╚══════════════════════════════════════════════════════════╝

set -Eeuo pipefail
umask 077

VERSION="3.0.0"
BACKUP_DIR="/root/darnix-json-backups"
SSH_DIR="/etc/ssh"
USERS_DB="$SSH_DIR/.ssh.db"
QUOTAS_DB="$SSH_DIR/quotas.db"
TRAFFIC_DB="$SSH_DIR/traffic.db"
CONFIG_DIR="$SSH_DIR/sshd_config.d"
BANNER_DIR="$SSH_DIR/banners"

# ───────────────────── 🎨 COLORES ─────────────────────

if [[ -t 1 ]]; then
    R=$'\033[1;31m'
    G=$'\033[1;32m'
    Y=$'\033[1;33m'
    B=$'\033[1;34m'
    M=$'\033[1;35m'
    C=$'\033[1;36m'
    W=$'\033[1;37m'
    D=$'\033[2m'
    O=$'\033[38;5;208m'
    P=$'\033[38;5;213m'
    GOLD=$'\033[38;5;220m'
    N=$'\033[0m'
else
    R='' G='' Y='' B='' M='' C='' W='' D=''
    O='' P='' GOLD='' N=''
fi

# ───────────────────── 🧰 UTILIDADES ─────────────────────

ok() {
    printf "  ${G}╭─ ✔️  ÉXITO ──────────────────────────────────────╮${N}\n"
    printf "  ${G}│${N}  %s\n" "$*"
    printf "  ${G}╰───────────────────────────────────────────────────╯${N}\n"
}

warn() {
    printf "  ${GOLD}⚠️  ATENCIÓN:${N} %s\n" "$*"
}

error() {
    printf "  ${R}❌ ERROR:${N} %s\n" "$*" >&2
}

info() {
    printf "  ${C}➜ 🔹${N} %s\n" "$*"
}

line() {
    printf "${M}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}\n"
}

pause() {
    echo
    read -r -p "  ${GOLD}💡 Presiona ENTER para continuar...${N} " _
}

header() {
    clear 2>/dev/null || true
    echo
    echo "${M}╔══════════════════════════════════════════════════════╗${N}"
    echo "${M}║${N}       ${GOLD}✨ DARNIX JSON BACKUP MANAGER ✨${N}           ${M}║${N}"
    echo "${M}║${N}          ${P}💎 PREMIUM EDITION 💎${N}                   ${M}║${N}"
    echo "${M}╠══════════════════════════════════════════════════════╣${N}"
    printf "${M}║${N}  ${C}🛡️ Versión:${N} %-8s ${C}📦 Formato:${N} %-24s${M}║${N}\n" \
        "$VERSION" "JSON individual"
    echo "${M}╚══════════════════════════════════════════════════════╝${N}"
    echo
}

die() {
    error "$*"
    exit 1
}

require_root() {
    [[ $EUID -eq 0 ]] || die "Ejecuta el panel como root."
}

require_commands() {
    local cmd
    for cmd in python3 sshd getent useradd usermod chage \
               install stat find sort awk grep date; do
        command -v "$cmd" >/dev/null 2>&1 ||
            die "Falta el comando necesario: $cmd"
    done
}

init() {
    require_root
    require_commands

    [[ -f "$USERS_DB" ]] || die "No existe $USERS_DB"
    [[ -f "$QUOTAS_DB" ]] || die "No existe $QUOTAS_DB"
    [[ -f "$TRAFFIC_DB" ]] || die "No existe $TRAFFIC_DB"

    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
}

valid_user() {
    [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*[$]?$ ]]
}

darnix_expiry() {
    awk -v u="$1" \
        '$1=="###" && $2==u {d=$3} END {print d}' "$USERS_DB"
}

list_users() {
    awk '$1=="###" && $2!="" {print $2}' "$USERS_DB" | sort -u
}

config_path() {
    printf '%s/%s.conf' "$CONFIG_DIR" "$1"
}

banner_path() {
    printf '%s/banner_%s.txt' "$BANNER_DIR" "$1"
}

# ───────────────────── 💾 CREAR JSON ─────────────────────

backup_one() {
    local u="$1"
    local expiry stamp output

    valid_user "$u" || {
        error "Nombre de usuario inválido."
        return 1
    }

    expiry="$(darnix_expiry "$u")"
    [[ -n "$expiry" ]] || {
        error "$u no figura en la base de usuarios Darnix."
        return 1
    }

    getent passwd "$u" >/dev/null || {
        error "No existe la cuenta Linux $u."
        return 1
    }

    stamp="$(date '+%Y%m%d-%H%M%S')"
    output="$BACKUP_DIR/${u}-${stamp}.json"

    if ! python3 - "$u" "$expiry" "$output" \
        "$SSH_DIR/$u" "$(config_path "$u")" "$(banner_path "$u")" \
        "$USERS_DB" "$QUOTAS_DB" "$TRAFFIC_DB" <<'PY'
import os
import sys
import json
import base64
import pwd
import spwd
import datetime
import tempfile

(user, expiry, output, limit_path, config_path, banner_path,
 users_db, quotas_db, traffic_db) = sys.argv[1:]

def read_json(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError(f"Base JSON inválida: {path}")
    return data

def encode_file(path):
    try:
        with open(path, "rb") as f:
            return base64.b64encode(f.read()).decode("ascii")
    except FileNotFoundError:
        return None

p = pwd.getpwnam(user)
s = spwd.getspnam(user)

with open(users_db, encoding="utf-8") as f:
    records = [
        line.rstrip("\n") for line in f
        if line.split()[:2] == ["###", user]
    ]

if not records:
    raise ValueError("No se encontró el registro Darnix.")

quotas = read_json(quotas_db)
traffic = read_json(traffic_db)

payload = {
    "format": "darnix-account-backup",
    "format_version": 3,
    "created_utc": datetime.datetime.now(
        datetime.timezone.utc
    ).isoformat(),
    "account": {
        "username": user,
        "uid_original": p.pw_uid,
        "gid_original": p.pw_gid,
        "home_original": p.pw_dir,
        "shell_original": p.pw_shell,
        "darnix_expiry": expiry,
        "shadow": {
            "password_hash": s.sp_pwdp,
            "last_change": s.sp_lstchg,
            "min_days": s.sp_min,
            "max_days": s.sp_max,
            "warn_days": s.sp_warn,
            "inactive_days": s.sp_inact,
            "account_expiry_day": s.sp_expire
        },
        "darnix_records": records,
        "limit_file_b64": encode_file(limit_path),
        "ssh_config_b64": encode_file(config_path),
        "banner_b64": encode_file(banner_path),
        "quota": {
            "exists": user in quotas,
            "value": quotas.get(user)
        },
        "traffic": {
            "exists": user in traffic,
            "value": traffic.get(user)
        }
    }
}

fd, tmp = tempfile.mkstemp(
    prefix=".darnix-json-", suffix=".tmp",
    dir=os.path.dirname(output)
)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, output)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise

print(output)
PY
    then
        error "No se pudo crear el JSON de $u."
        return 1
    fi

    chmod 600 "$output"
    ok "Backup JSON creado: $u"
    info "📄 Archivo: $output"
    info "📏 Tamaño: $(du -h "$output" | awk '{print $1}')"
}

backup_menu() {
    local u option
    header
    echo "${GOLD}💾 CREAR COPIA DE SEGURIDAD${N}"
    line
    echo "  ${G}[1]${N} 👤 Respaldar una cuenta"
    echo "  ${G}[2]${N} 🗂️  Respaldar todas las cuentas"
    echo "  ${R}[0]${N} ↩️  Volver"
    echo
    read -r -p "  ${GOLD}➤ Selecciona:${N} " option

    case "$option" in
        1)
            echo
            list_users
            echo
            read -r -p "  👤 Usuario: " u
            backup_one "$u" || true
            pause
            ;;
        2)
            read -r -p "  ¿Respaldar todas las cuentas? [s/N]: " answer
            if [[ "$answer" =~ ^[sS]$ ]]; then
                while IFS= read -r u; do
                    [[ -n "$u" ]] || continue
                    echo
                    info "Respaldando $u..."
                    backup_one "$u" || true
                done < <(list_users)
                ok "Proceso finalizado."
            else
                info "Operación cancelada."
            fi
            pause
            ;;
        0) return ;;
        *) warn "Opción inválida."; pause ;;
    esac
}

# ───────────────────── 🔎 VALIDAR JSON ─────────────────────

validate_json() {
    python3 - "$1" <<'PY'
import json, sys, re, base64

with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)

if d.get("format") != "darnix-account-backup":
    raise SystemExit("Formato no reconocido.")
if d.get("format_version") != 3:
    raise SystemExit("Versión no compatible.")

a = d.get("account")
if not isinstance(a, dict):
    raise SystemExit("Falta la sección account.")

u = a.get("username", "")
if not isinstance(u, str) or not re.fullmatch(
    r"[a-zA-Z_][a-zA-Z0-9_.-]*[$]?", u
):
    raise SystemExit("Nombre de usuario inválido.")

if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", a.get("darnix_expiry", "")):
    raise SystemExit("Fecha de expiración inválida.")

s = a.get("shadow")
if not isinstance(s, dict) or not s.get("password_hash"):
    raise SystemExit("Falta el hash de contraseña.")

for k in ("quota", "traffic"):
    if not isinstance(a.get(k), dict) or "exists" not in a[k]:
        raise SystemExit(f"Falta la sección {k}.")

for k in ("limit_file_b64", "ssh_config_b64", "banner_b64"):
    value = a.get(k)
    if value is not None:
        if not isinstance(value, str):
            raise SystemExit(f"Campo inválido: {k}")
        base64.b64decode(value, validate=True)

print(u)
PY
}

# ───────────────────── 🔐 RESPALDO PREVIO ─────────────────────

create_prebackup() {
    local u="$1"
    if [[ -n "$(darnix_expiry "$u")" ]] &&
       getent passwd "$u" >/dev/null 2>&1; then
        backup_one "$u"
    fi
}

# ───────────────────── ♻️ RESTAURAR CUENTA ─────────────────────

restore_one() {
    local file="$1"
    local u expiry hash shell existing answer
    local min_days max_days warn_days inactive_days acct_exp_day
    local config_data

    [[ -f "$file" ]] || {
        error "No existe el archivo JSON."
        return 1
    }

    if ! u="$(validate_json "$file")"; then
        error "El JSON no pasó la validación."
        return 1
    fi

    echo
    line
    echo "${GOLD}♻️  RESTAURACIÓN DE CUENTA${N}"
    line
    echo "  👤 Usuario: ${C}$u${N}"
    echo "  📄 Archivo: $file"
    echo

    existing=0
    if getent passwd "$u" >/dev/null 2>&1; then
        existing=1
        if [[ -z "$(darnix_expiry "$u")" ]]; then
            error "El usuario existe en Linux, pero no figura en Darnix."
            warn "Se cancela para proteger la cuenta existente."
            return 1
        fi

        warn "La cuenta ya existe y sus datos serán actualizados."
        read -r -p "  ¿Crear backup previo? [S/n]: " answer
        if [[ ! "$answer" =~ ^[nN]$ ]]; then
            create_prebackup "$u" || {
                error "No se pudo crear el backup previo."
                return 1
            }
        else
            warn "Has elegido continuar sin backup previo."
            read -r -p "  Escribe CONTINUAR: " answer
            [[ "$answer" == "CONTINUAR" ]] || return 1
        fi
    fi

    read -r -p "  Escribe RESTAURAR para confirmar: " answer
    [[ "$answer" == "RESTAURAR" ]] || {
        info "Restauración cancelada."
        return 0
    }

    # Leer valores escalares del JSON.
    local fields
    fields="$(python3 - "$file" <<'PY'
import json, sys
a=json.load(open(sys.argv[1], encoding="utf-8"))["account"]
s=a["shadow"]
def val(x):
    return "-" if x is None else str(x)
for x in (
    a["darnix_expiry"], s["password_hash"],
    s.get("min_days"), s.get("max_days"), s.get("warn_days"),
    s.get("inactive_days"), s.get("account_expiry_day"),
    a.get("shell_original", "/bin/false")
):
    print(val(x))
PY
)" || return 1

    local arr=()
    mapfile -t arr <<< "$fields"
    expiry="${arr[0]}"
    hash="${arr[1]}"
    min_days="${arr[2]}"
    max_days="${arr[3]}"
    warn_days="${arr[4]}"
    inactive_days="${arr[5]}"
    acct_exp_day="${arr[6]}"
    shell="${arr[7]}"

    # No permitir una shell interactiva en cuentas SSH Darnix.
    case "$shell" in
        /bin/false|/usr/sbin/nologin) ;;
        *) shell="/bin/false" ;;
    esac

    if ((existing == 0)); then
        useradd -M -s "$shell" "$u" || {
            error "No se pudo crear la cuenta Linux."
            return 1
        }
    fi

    # Aplicar únicamente el hash cifrado.
    printf '%s:%s\n' "$u" "$hash" | chpasswd -e || {
        error "No se pudo aplicar el hash de contraseña."
        return 1
    }

    usermod -s "$shell" "$u"

    [[ "$min_days" == "-" ]] || chage -m "$min_days" "$u"
    [[ "$max_days" == "-" ]] || chage -M "$max_days" "$u"
    [[ "$warn_days" == "-" ]] || chage -W "$warn_days" "$u"
    [[ "$inactive_days" == "-" ]] || chage -I "$inactive_days" "$u"

    # La fecha de expiración Linux se conserva independientemente
    # de la fecha de vencimiento registrada en Darnix.
    if [[ "$acct_exp_day" == "-" ]]; then
        chage -E -1 "$u"
    elif [[ "$acct_exp_day" == "0" ]]; then
        chage -E 0 "$u"
    else
        local linux_expiry
        linux_expiry="$(python3 - "$acct_exp_day" <<'PY'
import datetime, sys
n=int(sys.argv[1])
print((datetime.date(1970,1,1)+datetime.timedelta(days=n)).isoformat())
PY
)" || return 1
        chage -E "$linux_expiry" "$u"
    fi

    # Actualizar exclusivamente el registro Darnix seleccionado.
    python3 - "$USERS_DB" "$u" "$expiry" <<'PY'
import os, sys, tempfile
path, user, expiry = sys.argv[1:]
with open(path, encoding="utf-8") as f:
    lines=f.readlines()
lines=[x for x in lines if x.split()[:2] != ["###", user]]
lines.append(f"### {user} {expiry}\n")
fd,tmp=tempfile.mkstemp(prefix=".darnix-users-",dir=os.path.dirname(path))
try:
    with os.fdopen(fd,"w",encoding="utf-8") as f:
        f.writelines(lines)
    os.chmod(tmp,os.stat(path).st_mode & 0o777)
    os.chown(tmp,0,0)
    os.replace(tmp,path)
except Exception:
    try: os.unlink(tmp)
    except OSError: pass
    raise
PY

    # Restaurar archivos individuales con rutas fijas y seguras.
    python3 - "$file" "$SSH_DIR" "$CONFIG_DIR" "$BANNER_DIR" "$u" <<'PY'
import json, sys, os, base64, tempfile

backup, ssh, cfgdir, bdir, user = sys.argv[1:]
a=json.load(open(backup,encoding="utf-8"))["account"]
os.makedirs(cfgdir,exist_ok=True)
os.makedirs(bdir,exist_ok=True)

items=[
    (a.get("limit_file_b64"),os.path.join(ssh,user),0o600),
    (a.get("ssh_config_b64"),os.path.join(cfgdir,user+".conf"),0o644),
    (a.get("banner_b64"),os.path.join(bdir,"banner_"+user+".txt"),0o644),
]

for encoded,dest,mode in items:
    if encoded is None:
        try: os.unlink(dest)
        except FileNotFoundError: pass
        continue

    content=base64.b64decode(encoded,validate=True)

    # La configuración debe ser estrictamente individual.
    if dest.endswith(".conf"):
        text=content.decode("utf-8")
        lines=[x.strip() for x in text.splitlines() if x.strip()]
        if not lines or lines[0] != "Match User " + user:
            raise ValueError("La configuración SSH no corresponde al usuario.")
        if any(x.lower().startswith(("include ", "match " ))
               for x in lines[1:]):
            raise ValueError("La configuración individual contiene directivas no permitidas.")

    fd,tmp=tempfile.mkstemp(prefix=".darnix-file-",dir=os.path.dirname(dest))
    try:
        with os.fdopen(fd,"wb") as f:
            f.write(content)
        os.chmod(tmp,mode)
        os.chown(tmp,0,0)
        os.replace(tmp,dest)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        raise
PY

    # Fusionar cuota y tráfico, sin sustituir otros usuarios.
    python3 - "$file" "$QUOTAS_DB" "$TRAFFIC_DB" "$u" <<'PY'
import json, sys, os, tempfile

backup,qpath,tpath,user=sys.argv[1:]
a=json.load(open(backup,encoding="utf-8"))["account"]

for path,key in ((qpath,"quota"),(tpath,"traffic")):
    with open(path,encoding="utf-8") as f:
        db=json.load(f)
    if not isinstance(db,dict):
        raise ValueError("Base JSON inválida: "+path)

    item=a[key]
    if item["exists"]:
        db[user]=item.get("value")
    else:
        db.pop(user,None)

    fd,tmp=tempfile.mkstemp(prefix=".darnix-db-",dir=os.path.dirname(path))
    try:
        with os.fdopen(fd,"w",encoding="utf-8") as f:
            json.dump(db,f,ensure_ascii=False,indent=2)
            f.write("\n")
        os.chmod(tmp,os.stat(path).st_mode & 0o777)
        os.chown(tmp,0,0)
        os.replace(tmp,path)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        raise
PY

    if ! sshd -t; then
        error "sshd -t falló después de la restauración."
        warn "No se recargó SSH. Revisa el backup previo antes de continuar."
        return 1
    fi

    ok "Cuenta $u restaurada."
    ok "Hash, vencimiento, límite, cuota y tráfico procesados."
    ok "Configuración SSH validada."
    info "No se reinició ni recargó SSH."
    warn "Prueba una conexión antes de dar la restauración por finalizada."
}

restore_menu() {
    local files=() i=1 choice
    mapfile -t files < <(
        find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.json' -printf '%f\n' |
        sort
    )

    header
    echo "${GOLD}♻️  RESTAURAR DESDE JSON${N}"
    line

    if ((${#files[@]} == 0)); then
        warn "No hay backups JSON disponibles."
        pause
        return
    fi

    local f
    for f in "${files[@]}"; do
        printf "  ${C}%2d)${N} 📄 %s\n" "$i" "$f"
        ((i+=1))
    done

    echo
    echo "  ${R} 0)${N} ↩️ Volver"
    read -r -p "  ➤ Selecciona un archivo: " choice

    [[ "$choice" =~ ^[0-9]+$ ]] || {
        warn "Selección inválida."
        pause
        return
    }

    ((choice == 0)) && return
    ((choice >= 1 && choice <= ${#files[@]})) || {
        warn "Selección fuera de rango."
        pause
        return
    }

    restore_one "$BACKUP_DIR/${files[$((choice-1))]}" || true
    pause
}

# ───────────────────── 📚 LISTAR BACKUPS ─────────────────────

list_backups() {
    header
    echo "${GOLD}📚 BACKUPS JSON GUARDADOS${N}"
    line

    local files=()
    mapfile -t files < <(
        find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.json' -printf '%f\n' |
        sort
    )

    if ((${#files[@]} == 0)); then
        warn "Todavía no hay backups."
    else
        local f
        for f in "${files[@]}"; do
            printf "  ${G}📄${N} %-48s ${Y}%s${N}\n" \
                "$f" "$(du -h "$BACKUP_DIR/$f" | awk '{print $1}')"
        done
    fi

    echo
    info "Ubicación: $BACKUP_DIR"
    pause
}

# ───────────────────── 🗑️ ELIMINAR BACKUP ─────────────────────

delete_backup() {
    local files=() i=1 choice file confirm

    mapfile -t files < <(
        find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.json' -printf '%f\n' |
        sort
    )

    header
    echo "${R}🗑️  ELIMINAR BACKUP${N}"
    line

    if ((${#files[@]} == 0)); then
        warn "No hay backups para eliminar."
        pause
        return
    fi

    for file in "${files[@]}"; do
        printf "  ${C}%2d)${N} 📄 %s\n" "$i" "$file"
        ((i+=1))
    done

    echo
    echo "  0) ↩️ Volver"
    read -r -p "  ➤ Selecciona: " choice

    [[ "$choice" =~ ^[0-9]+$ ]] || {
        warn "Opción inválida."
        pause
        return
    }

    ((choice == 0)) && return
    ((choice >= 1 && choice <= ${#files[@]})) || {
        warn "Selección fuera de rango."
        pause
        return
    }

    file="${files[$((choice-1))]}"
    echo
    warn "Se eliminará permanentemente $file"
    read -r -p "  Escribe ELIMINAR para confirmar: " confirm

    if [[ "$confirm" == "ELIMINAR" ]]; then
        rm -f -- "$BACKUP_DIR/$file"
        ok "Backup eliminado."
    else
        info "Operación cancelada."
    fi
    pause
}

# ───────────────────── 👥 LISTAR CUENTAS ─────────────────────

show_users() {
    header
    echo "${GOLD}👥 CUENTAS DARNIX${N}"
    line
    printf "  ${W}%-22s %-16s %-12s${N}\n" "USUARIO" "ESTADO LINUX" "VENCE"
    echo "  ----------------------------------------------------"

    local u state
    while IFS= read -r u; do
        [[ -n "$u" ]] || continue

        if getent passwd "$u" >/dev/null 2>&1; then
            state="${G}✔ Existe${N}"
        else
            state="${R}✘ Falta${N}"
        fi

        printf "  %-22s " "$u"
        printf "%b " "$state"
        printf "%-12s\n" "$(darnix_expiry "$u")"
    done < <(list_users)

    pause
}

# ───────────────────── 🩺 DIAGNÓSTICO ─────────────────────

diagnostics() {
    header
    echo "${GOLD}🩺 DIAGNÓSTICO DEL SISTEMA${N}"
    line

    local f
    for f in "$USERS_DB" "$QUOTAS_DB" "$TRAFFIC_DB"; do
        [[ -f "$f" ]] && ok "Encontrado: $f" || error "Falta: $f"
    done

    python3 --version
    echo

    if sshd -t; then
        ok "Configuración SSH válida."
    else
        error "La configuración SSH no es válida."
    fi

    echo
    info "Los JSON se guardan con permisos 600."
    info "El directorio se protege con permisos 700."
    pause
}

# ───────────────────── 🌟 MENÚ PRINCIPAL ─────────────────────

main() {
    while true; do
        header
        echo "  ${GOLD}🌟 PANEL PRINCIPAL${N}"
        echo "  ${D}Administra tus cuentas SSH de forma selectiva.${N}"
        echo
        line
        echo "  ${W}💾 COPIAS DE SEGURIDAD${N}"
        echo "  ${G}[1]${N} 💎 Crear backup de una cuenta"
        echo "  ${G}[2]${N} 🗂️  Respaldar TODAS las cuentas"
        echo
        line
        echo "  ${W}♻️  RESTAURACIÓN${N}"
        echo "  ${B}[3]${N} 🔄 Restaurar cuenta desde JSON"
        echo
        line
        echo "  ${W}👥 ADMINISTRACIÓN${N}"
        echo "  ${C}[4]${N} 👤 Ver cuentas Darnix"
        echo "  ${C}[5]${N} 📚 Ver backups guardados"
        echo "  ${R}[6]${N} 🗑️  Eliminar un backup"
        echo "  ${Y}[7]${N} 🩺 Diagnóstico del sistema"
        echo
        line
        echo "  ${R}[0]${N} 🚪 Salir del panel"
        echo
        read -r -p "  ${GOLD}➤ Selecciona una opción:${N} " option

        case "$option" in
            1) backup_menu ;;
            2)
                read -r -p "  ¿Respaldar todas las cuentas? [s/N]: " yes
                if [[ "$yes" =~ ^[sS]$ ]]; then
                    while IFS= read -r u; do
                        [[ -n "$u" ]] || continue
                        echo
                        info "Respaldando $u..."
                        backup_one "$u" || true
                    done < <(list_users)
                    ok "Proceso de backup finalizado."
                else
                    info "Operación cancelada."
                fi
                pause
                ;;
            3) restore_menu ;;
            4) show_users ;;
            5) list_backups ;;
            6) delete_backup ;;
            7) diagnostics ;;
            0)
                echo
                line
                echo "  ${P}👋 ¡Gracias por utilizar Darnix Premium!${N}"
                echo "  ${D}🔐 Tus cuentas, tus respaldos, tu control.${N}"
                line
                echo
                exit 0
                ;;
            *)
                warn "Opción inválida. Selecciona un número del menú."
                sleep 1
                ;;
        esac
    done
}

init
main
