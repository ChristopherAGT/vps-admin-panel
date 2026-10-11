#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════╗
# ║          💎 DARNIX BACKUP MANAGER PREMIUM 💎            ║
# ║       Copias completas y restauración masiva SSH       ║
# ╚══════════════════════════════════════════════════════════╝

set -Eeuo pipefail
umask 077

VERSION="4.1.0"
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
    printf "  ${G}✔️  %s${N}\n" "$*"
}

warn() {
    printf "  ${GOLD}⚠️  %s${N}\n" "$*"
}

error() {
    printf "  ${R}❌  %s${N}\n" "$*" >&2
}

info() {
    printf "  ${C}➜ 🔹 %s${N}\n" "$*"
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
    echo "${M}║${N}       ${GOLD}✨ DARNIX BACKUP MANAGER ✨${N}               ${M}║${N}"
    echo "${M}║${N}             ${P}💎 PREMIUM EDITION 💎${N}               ${M}║${N}"
    echo "${M}╠══════════════════════════════════════════════════════╣${N}"
    printf "${M}║${N}  ${C}🛡️ Versión:${N} %-8s ${C}📦 Formato:${N} %-24s${M}║${N}\n" \
        "$VERSION" "TAR.GZ + JSON"
    echo "${M}╚══════════════════════════════════════════════════════╝${N}"
    echo
}

die() {
    error "$*"
    exit 1
}

require_root() {
    [[ "$EUID" -eq 0 ]] || die "Ejecuta el panel como root."
}

require_commands() {
    local cmd
    for cmd in python3 tar gzip getent useradd usermod chage \
               chpasswd sshd find sort awk grep date du stat \
               mktemp chmod mv; do
        command -v "$cmd" >/dev/null 2>&1 ||
            die "Falta el comando requerido: $cmd"
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

# ───────────────────── 📦 CREAR BACKUP NORMAL ─────────────────────

create_backup() {
    local stamp archive tmpdir jsonfile count

    stamp="$(date '+%Y%m%d-%H%M%S')"
    archive="$BACKUP_DIR/darnix-backup-${stamp}.tar.gz"

    # Evitar sobrescribir una copia con el mismo nombre.
    [[ ! -e "$archive" ]] || {
        error "Ya existe un backup con ese nombre."
        return 1
    }

    tmpdir="$(mktemp -d "$BACKUP_DIR/.work-XXXXXXXX")"
    chmod 700 "$tmpdir"
    jsonfile="$tmpdir/backup.json"

    info "🔍 Recopilando todas las cuentas Darnix..."

    if ! count="$(python3 - "$jsonfile" "$SSH_DIR" "$USERS_DB" \
        "$QUOTAS_DB" "$TRAFFIC_DB" "$CONFIG_DIR" "$BANNER_DIR" <<'PY'
import os
import sys
import json
import pwd
import base64
import datetime
import re
import tempfile

(output, ssh_dir, users_db, quotas_db, traffic_db,
 config_dir, banner_dir) = sys.argv[1:]

def read_json(path):
    with open(path, encoding="utf-8") as f:
        obj = json.load(f)
    if not isinstance(obj, dict):
        raise ValueError("Base JSON inválida: " + path)
    return obj

def read_file_b64(path):
    try:
        with open(path, "rb") as f:
            return base64.b64encode(f.read()).decode("ascii")
    except FileNotFoundError:
        return None

def valid_user(u):
    return isinstance(u, str) and bool(
        re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_.-]*[$]?", u)
    )

shadow = {}
with open("/etc/shadow", encoding="utf-8") as f:
    for line in f:
        fields = line.rstrip("\n").split(":")
        if len(fields) >= 2:
            shadow[fields[0]] = fields[1:]

with open(users_db, encoding="utf-8") as f:
    db_lines = f.readlines()

users = {}
for raw in db_lines:
    fields = raw.strip().split()
    if len(fields) >= 3 and fields[0] == "###":
        user = fields[1]
        if not valid_user(user):
            raise ValueError("Usuario inválido en .ssh.db: " + user)
        users.setdefault(user, []).append(raw.rstrip("\n"))

if not users:
    raise ValueError(
        "No se encontraron cuentas Darnix en .ssh.db. "
        "No se creó un backup normal."
    )

quotas = read_json(quotas_db)
traffic = read_json(traffic_db)
accounts = []

for user, records in sorted(users.items()):
    try:
        p = pwd.getpwnam(user)
    except KeyError:
        raise ValueError(
            f"La cuenta {user} aparece en Darnix pero no existe en Linux."
        )

    if user not in shadow:
        raise ValueError("No se encontró el registro shadow de " + user)

    expiry = records[-1].split()[2]
    datetime.date.fromisoformat(expiry)

    sh = shadow[user]
    sh += [""] * max(0, 8 - len(sh))

    account = {
        "username": user,
        "uid_original": p.pw_uid,
        "gid_original": p.pw_gid,
        "home_original": p.pw_dir,
        "shell_original": p.pw_shell,
        "darnix_expiry": expiry,
        "darnix_records": records,
        "shadow": {
            "password_hash": sh[0],
            "last_change": sh[1],
            "min_days": sh[2],
            "max_days": sh[3],
            "warn_days": sh[4],
            "inactive_days": sh[5],
            "account_expiry_day": sh[6],
            "reserved": sh[7]
        },
        "limit_file_b64": read_file_b64(os.path.join(ssh_dir, user)),
        "ssh_config_b64": read_file_b64(
            os.path.join(config_dir, user + ".conf")
        ),
        "banner_b64": read_file_b64(
            os.path.join(banner_dir, "banner_" + user + ".txt")
        ),
        "quota": {
            "exists": user in quotas,
            "value": quotas.get(user)
        },
        "traffic": {
            "exists": user in traffic,
            "value": traffic.get(user)
        }
    }
    accounts.append(account)

payload = {
    "format": "darnix-full-backup",
    "format_version": 4,
    "created_utc": datetime.datetime.now(
        datetime.timezone.utc
    ).isoformat(),
    "account_count": len(accounts),
    "accounts": accounts
}

fd, tmp = tempfile.mkstemp(
    prefix=".backup-json-", dir=os.path.dirname(output)
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

print(len(accounts))
PY
    )"; then
        rm -rf -- "$tmpdir"
        error "No se pudo generar el JSON completo."
        return 1
    fi

    info "🗜️ Comprimiendo la copia completa..."

    if ! tar -czf "$archive" -C "$tmpdir" backup.json; then
        rm -rf -- "$tmpdir"
        rm -f -- "$archive"
        error "No se pudo crear el archivo comprimido."
        return 1
    fi

    chmod 600 "$archive"
    rm -rf -- "$tmpdir"

    if ! tar -tzf "$archive" | grep -qx 'backup.json'; then
        rm -f -- "$archive"
        error "El archivo comprimido no pasó la verificación."
        return 1
    fi

    ok "Copia de seguridad completa creada."
    info "👥 Cuentas guardadas: $count"
    info "📦 Archivo: $archive"
    info "📏 Tamaño: $(du -h "$archive" | awk '{print $1}')"
    info "🔐 Permisos privados aplicados."
}

# ───────────────────── 🔎 VALIDAR Y EXTRAER ─────────────────────

extract_and_validate() {
    local archive="$1"
    local dest="$2"

    python3 - "$archive" "$dest" <<'PY'
import sys
import os
import json
import tarfile
import re
import base64
import datetime

archive, dest = sys.argv[1:]

def valid_user(u):
    return isinstance(u, str) and bool(
        re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_.-]*[$]?", u)
    )

def check_date(s):
    if not isinstance(s, str):
        raise ValueError("Fecha inválida.")
    datetime.date.fromisoformat(s)

with tarfile.open(archive, "r:gz") as tf:
    members = tf.getmembers()

    if len(members) != 1:
        raise ValueError("El archivo debe contener un único backup.json.")

    m = members[0]
    if m.name != "backup.json" or not m.isfile():
        raise ValueError("Contenido del archivo no reconocido.")
    if m.size > 200 * 1024 * 1024:
        raise ValueError("El JSON supera el límite de 200 MiB.")

    src = tf.extractfile(m)
    if src is None:
        raise ValueError("No se pudo leer el JSON.")

    raw = src.read()
    with open(dest, "wb") as f:
        f.write(raw)
    os.chmod(dest, 0o600)

with open(dest, encoding="utf-8") as f:
    data = json.load(f)

if data.get("format") != "darnix-full-backup":
    raise ValueError("Formato de backup no reconocido.")
if data.get("format_version") != 4:
    raise ValueError("Versión de backup incompatible.")

accounts = data.get("accounts")
if not isinstance(accounts, list) or not accounts:
    raise ValueError("El backup no contiene cuentas.")
if len(accounts) > 100000:
    raise ValueError("Número de cuentas fuera de rango.")

seen = set()

for a in accounts:
    if not isinstance(a, dict):
        raise ValueError("Registro de cuenta inválido.")

    u = a.get("username")
    if not valid_user(u):
        raise ValueError("Nombre de usuario inválido.")
    if u in seen:
        raise ValueError("Usuario duplicado: " + u)
    seen.add(u)

    check_date(a.get("darnix_expiry"))

    records = a.get("darnix_records")
    if not isinstance(records, list) or not records:
        raise ValueError("Faltan registros Darnix para " + u)

    matching_expiry = False
    for record in records:
        if not isinstance(record, str):
            raise ValueError("Registro Darnix inválido para " + u)
        parts = record.split()
        if len(parts) != 3 or parts[0] != "###" or parts[1] != u:
            raise ValueError("Registro Darnix incorrecto para " + u)
        check_date(parts[2])
        if parts[2] == a["darnix_expiry"]:
            matching_expiry = True

    if not matching_expiry:
        raise ValueError("Fecha Darnix incoherente para " + u)

    sh = a.get("shadow")
    if not isinstance(sh, dict):
        raise ValueError("Falta el hash de " + u)
    if not isinstance(sh.get("password_hash"), str) or not sh["password_hash"]:
        raise ValueError("Hash vacío o inválido para " + u)

    for key in ("quota", "traffic"):
        obj = a.get(key)
        if not isinstance(obj, dict) or not isinstance(obj.get("exists"), bool):
            raise ValueError("Campo incorrecto: " + key)
        if obj["exists"] and "value" not in obj:
            raise ValueError("Falta el valor de " + key)

    for key in ("limit_file_b64", "ssh_config_b64", "banner_b64"):
        value = a.get(key)
        if value is not None:
            if not isinstance(value, str):
                raise ValueError("Archivo codificado inválido: " + key)
            content = base64.b64decode(value, validate=True)

            if key == "ssh_config_b64":
                text = content.decode("utf-8")
                lines = [x.strip() for x in text.splitlines() if x.strip()]
                if not lines or lines[0] != "Match User " + u:
                    raise ValueError("Config SSH no corresponde a " + u)
                for line in lines[1:]:
                    if line.lower().startswith(("include ", "match ")):
                        raise ValueError("Directiva no permitida en config de " + u)

print(len(accounts))
PY
}

# ───────────────────── 🛡️ BACKUP PREVIO DE EMERGENCIA ─────────────────────

create_pre_restore_backup() {
    local stamp archive tmp_archive

    stamp="$(date '+%Y%m%d-%H%M%S')"
    archive="$BACKUP_DIR/darnix-pre-restore-${stamp}.tar.gz"

    [[ ! -e "$archive" ]] || {
        error "Ya existe una copia previa con ese nombre."
        return 1
    }

    info "🛡️ Creando copia de emergencia del estado actual..."

    tmp_archive="$(mktemp "$BACKUP_DIR/.pre-restore-XXXXXXXX")" || {
        error "No se pudo crear el archivo temporal."
        return 1
    }
    chmod 600 "$tmp_archive"

    # Esta copia no depende de que .ssh.db tenga cuentas reconocibles.
    # Incluye bases Darnix, configuración SSH y bases de cuentas Linux.
    if ! tar -czpf "$tmp_archive" -C / \
        etc/passwd \
        etc/shadow \
        etc/group \
        etc/gshadow \
        etc/ssh; then
        rm -f -- "$tmp_archive"
        error "No se pudo guardar el estado actual."
        return 1
    fi

    if [[ ! -s "$tmp_archive" ]] ||
       ! tar -tzf "$tmp_archive" >/dev/null 2>&1; then
        rm -f -- "$tmp_archive"
        error "La copia de emergencia no superó la verificación."
        return 1
    fi

    if ! mv -- "$tmp_archive" "$archive"; then
        rm -f -- "$tmp_archive"
        error "No se pudo guardar la copia de emergencia."
        return 1
    fi

    chmod 600 "$archive"

    ok "Copia de emergencia creada y verificada."
    info "📦 Archivo: $archive"
    info "📏 Tamaño: $(du -h "$archive" | awk '{print $1}')"
    info "🔐 Permisos privados aplicados."
}

# ───────────────────── ♻️ RESTAURAR TODO ─────────────────────

restore_archive() {
    local archive="$1"
    local tmpdir jsonfile count

    tmpdir="$(mktemp -d "$BACKUP_DIR/.restore-XXXXXXXX")"
    chmod 700 "$tmpdir"
    jsonfile="$tmpdir/backup.json"

    info "🔎 Validando el archivo seleccionado..."

    if ! count="$(extract_and_validate "$archive" "$jsonfile")"; then
        rm -rf -- "$tmpdir"
        error "El backup no pasó la validación. No se restauró nada."
        return 1
    fi

    ok "Backup válido: $count cuentas."

    create_pre_restore_backup || {
        rm -rf -- "$tmpdir"
        error "No se pudo crear el backup previo. Restauración cancelada."
        return 1
    }

    info "♻️ Restaurando todas las cuentas del archivo..."

    if ! python3 - "$jsonfile" "$SSH_DIR" "$USERS_DB" \
        "$QUOTAS_DB" "$TRAFFIC_DB" "$CONFIG_DIR" "$BANNER_DIR" <<'PY'
import os
import sys
import json
import base64
import tempfile
import subprocess
import datetime
import pwd
import re

(json_path, ssh_dir, users_db, quotas_db, traffic_db,
 config_dir, banner_dir) = sys.argv[1:]

with open(json_path, encoding="utf-8") as f:
    data = json.load(f)

accounts = data["accounts"]
users_to_restore = {a["username"] for a in accounts}

def valid_user(u):
    return isinstance(u, str) and bool(
        re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_.-]*[$]?", u)
    )

for u in users_to_restore:
    if not valid_user(u):
        raise ValueError("Nombre de usuario inválido: " + repr(u))

def atomic_write(path, content, mode=None):
    parent = os.path.dirname(path)
    os.makedirs(parent, exist_ok=True)

    old_stat = None
    try:
        old_stat = os.stat(path)
    except FileNotFoundError:
        pass

    fd, tmp = tempfile.mkstemp(prefix=".darnix-restore-", dir=parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(content)

        if mode is not None:
            os.chmod(tmp, mode)
        elif old_stat is not None:
            os.chmod(tmp, old_stat.st_mode & 0o777)
        else:
            os.chmod(tmp, 0o644)

        os.chown(tmp, 0, 0)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

def read_json(path):
    with open(path, encoding="utf-8") as f:
        obj = json.load(f)
    if not isinstance(obj, dict):
        raise ValueError("Base JSON inválida: " + path)
    return obj

def write_json(path, obj):
    atomic_write(
        path,
        (json.dumps(obj, ensure_ascii=False, indent=2) + "\n").encode(),
        None
    )

def decode(value):
    return None if value is None else base64.b64decode(value, validate=True)

def run(args):
    subprocess.run(args, check=True)

# Crear usuarios Linux que no existan.
for a in accounts:
    u = a["username"]
    try:
        pwd.getpwnam(u)
        exists = True
    except KeyError:
        exists = False

    if not exists:
        run(["useradd", "-M", "-s", "/bin/false", u])

# Aplicar hashes y propiedades de las cuentas.
for a in accounts:
    u = a["username"]
    sh = a["shadow"]

    original_shell = a.get("shell_original", "/bin/false")
    shell = original_shell if original_shell in (
        "/bin/false", "/usr/sbin/nologin"
    ) else "/bin/false"

    run(["usermod", "-s", shell, u])

    subprocess.run(
        ["chpasswd", "-e"],
        input=f'{u}:{sh["password_hash"]}\n',
        text=True,
        check=True
    )

    aging = (
        ("min_days", "-m"),
        ("max_days", "-M"),
        ("warn_days", "-W"),
        ("inactive_days", "-I"),
        ("last_change", "-d"),
    )

    for field, flag in aging:
        value = sh.get(field)
        if value is None or value == "":
            continue
        try:
            number = int(value)
        except (ValueError, TypeError):
            raise ValueError(f"Valor shadow inválido para {u}: {field}")
        run(["chage", flag, str(number), u])

    exp = sh.get("account_expiry_day")
    if exp is None or exp == "":
        run(["chage", "-E", "-1", u])
    else:
        try:
            exp_days = int(exp)
        except (ValueError, TypeError):
            raise ValueError("Expiración Linux inválida para " + u)

        if exp_days < 0:
            run(["chage", "-E", "-1", u])
        else:
            exp_date = (
                datetime.date(1970, 1, 1)
                + datetime.timedelta(days=exp_days)
            ).isoformat()
            run(["chage", "-E", exp_date, u])

# Fusionar .ssh.db y conservar las entradas de otros usuarios.
with open(users_db, encoding="utf-8") as f:
    old_lines = f.readlines()

new_lines = []
for line in old_lines:
    fields = line.strip().split()
    if len(fields) >= 2 and fields[0] == "###" and fields[1] in users_to_restore:
        continue
    new_lines.append(line)

for a in accounts:
    new_lines.extend(record + "\n" for record in a["darnix_records"])

atomic_write(users_db, "".join(new_lines).encode())

os.makedirs(config_dir, exist_ok=True)
os.makedirs(banner_dir, exist_ok=True)

for a in accounts:
    u = a["username"]

    files = (
        (a.get("limit_file_b64"), os.path.join(ssh_dir, u), 0o600),
        (a.get("ssh_config_b64"), os.path.join(config_dir, u + ".conf"), 0o644),
        (a.get("banner_b64"), os.path.join(banner_dir, "banner_" + u + ".txt"), 0o644),
    )

    for encoded, path, mode in files:
        content = decode(encoded)
        if content is None:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        else:
            atomic_write(path, content, mode)

# Fusionar cuotas y tráfico sin reemplazar registros ajenos.
quotas = read_json(quotas_db)
traffic = read_json(traffic_db)

for a in accounts:
    u = a["username"]
    for db, key in ((quotas, "quota"), (traffic, "traffic")):
        item = a[key]
        if item["exists"]:
            db[u] = item.get("value")
        else:
            db.pop(u, None)

write_json(quotas_db, quotas)
write_json(traffic_db, traffic)

print(f"Restauración de datos completada para {len(accounts)} cuentas.")
PY
    then
        rm -rf -- "$tmpdir"
        error "La restauración encontró un error."
        warn "La copia de emergencia se conserva en $BACKUP_DIR."
        warn "Revisa ese archivo antes de intentar otra restauración."
        return 1
    fi

    rm -rf -- "$tmpdir"

    info "🧪 Comprobando la configuración de SSH..."
    if sshd -t; then
        ok "Configuración SSH válida."
    else
        error "sshd -t detectó errores."
        warn "No se recargó ni reinició SSH."
        warn "Revisa los archivos restaurados y la copia de emergencia."
        return 1
    fi

    line
    ok "¡Restauración masiva completada!"
    info "👥 Cuentas procesadas: $count"
    info "🛡️ Se conservaron las entradas de otros usuarios."
    info "🔐 Se fusionaron las bases de cuotas y tráfico."
    info "⚙️ SSH no se recargó automáticamente."
}

# ───────────────────── 📚 LISTAR BACKUPS ─────────────────────

list_backups() {
    header
    echo "${GOLD}📚 COPIAS DE SEGURIDAD DISPONIBLES${N}"
    line

    local files=()
    mapfile -t files < <(
        find "$BACKUP_DIR" -maxdepth 1 -type f \
            -name 'darnix-backup-*.tar.gz' -printf '%f\n' | sort
    )

    if ((${#files[@]} == 0)); then
        warn "No hay copias de seguridad guardadas."
    else
        local f
        for f in "${files[@]}"; do
            printf "  ${G}📦${N} %-42s ${Y}%s${N}\n" \
                "$f" "$(du -h "$BACKUP_DIR/$f" | awk '{print $1}')"
        done
        echo
        info "Total de copias: ${#files[@]}"
    fi

    pause
}

# ───────────────────── 🗑️ ELIMINAR BACKUP ─────────────────────

delete_backup() {
    local files=() i=1 choice file answer

    mapfile -t files < <(
        find "$BACKUP_DIR" -maxdepth 1 -type f \
            -name 'darnix-backup-*.tar.gz' -printf '%f\n' | sort
    )

    header
    echo "${R}🗑️ ELIMINAR UNA COPIA DE SEGURIDAD${N}"
    line

    if ((${#files[@]} == 0)); then
        warn "No hay copias para eliminar."
        pause
        return
    fi

    for file in "${files[@]}"; do
        printf "  ${C}%2d)${N} 📦 %s\n" "$i" "$file"
        ((i+=1))
    done

    echo
    echo "  ${R}0)${N} ↩️ Volver"
    echo
    read -r -p "  ${GOLD}➤ Selecciona el backup:${N} " choice

    [[ "$choice" =~ ^[0-9]+$ ]] || {
        warn "Selección inválida."
        pause
        return
    }

    ((choice == 0)) && return

    ((choice >= 1 && choice <= ${#files[@]})) || {
        warn "Opción fuera de rango."
        pause
        return
    }

    file="${files[$((choice-1))]}"

    echo
    warn "Se eliminará: $file"
    read -r -p "  Escribe ELIMINAR para confirmar: " answer

    if [[ "$answer" == "ELIMINAR" ]]; then
        rm -f -- "$BACKUP_DIR/$file"
        ok "Backup eliminado."
    else
        info "Operación cancelada."
    fi

    pause
}

# ───────────────────── 🩺 DIAGNÓSTICO ─────────────────────

diagnostics() {
    header
    echo "${GOLD}🩺 DIAGNÓSTICO DEL SISTEMA${N}"
    line

    local f
    for f in "$USERS_DB" "$QUOTAS_DB" "$TRAFFIC_DB"; do
        if [[ -f "$f" ]]; then
            ok "Encontrado: $f"
        else
            error "Falta: $f"
        fi
    done

    echo
    python3 --version
    info "Directorio: $BACKUP_DIR"
    info "Permisos del directorio: $(stat -c '%a' "$BACKUP_DIR")"

    echo
    if sshd -t; then
        ok "Configuración SSH válida."
    else
        error "La configuración SSH contiene errores."
    fi

    pause
}

# ───────────────────── 🌟 MENÚ PRINCIPAL ─────────────────────

main() {
    local option archive files=() i choice

    while true; do
        header
        echo "  ${GOLD}🌟 MENÚ PRINCIPAL${N}"
        echo "  ${D}Administra todas las cuentas desde una sola copia.${N}"
        echo
        line
        echo "  ${G}[1]${N} 💾 Crear copia de seguridad completa"
        echo "  ${B}[2]${N} ♻️  Restaurar todas las cuentas desde backup"
        echo "  ${C}[3]${N} 📚 Ver copias de seguridad disponibles"
        echo "  ${R}[4]${N} 🗑️  Eliminar una copia de seguridad"
        echo "  ${Y}[5]${N} 🩺 Diagnóstico del sistema"
        echo "  ${R}[0]${N} 🚪 Salir"
        echo
        line
        echo
        read -r -p "  ${GOLD}➤ Selecciona una opción:${N} " option

        case "$option" in
            1)
                echo
                create_backup || true
                pause
                ;;
            2)
                mapfile -t files < <(
                    find "$BACKUP_DIR" -maxdepth 1 -type f \
                        -name 'darnix-backup-*.tar.gz' -printf '%f\n' |
                        sort
                )

                header
                echo "${GOLD}♻️ RESTAURAR TODAS LAS CUENTAS${N}"
                line

                if ((${#files[@]} == 0)); then
                    warn "No hay copias de seguridad disponibles."
                    pause
                    continue
                fi

                i=1
                for archive in "${files[@]}"; do
                    printf "  ${C}%2d)${N} 📦 %s\n" "$i" "$archive"
                    ((i+=1))
                done

                echo
                echo "  ${R}0)${N} ↩️ Volver"
                echo
                read -r -p "  ${GOLD}➤ Selecciona el backup:${N} " choice

                [[ "$choice" =~ ^[0-9]+$ ]] || {
                    warn "Selección inválida."
                    pause
                    continue
                }

                ((choice == 0)) && continue

                ((choice >= 1 && choice <= ${#files[@]})) || {
                    warn "Opción fuera de rango."
                    pause
                    continue
                }

                # Sin confirmación adicional: se ejecuta al elegir el archivo.
                restore_archive "$BACKUP_DIR/${files[$((choice-1))]}" || true
                pause
                ;;
            3) list_backups ;;
            4) delete_backup ;;
            5) diagnostics ;;
            0)
                echo
                echo "  ${P}👋 ¡Gracias por utilizar Darnix Premium!${N}"
                echo
                exit 0
                ;;
            *)
                warn "Opción inválida."
                sleep 1
                ;;
        esac
    done
}

init
main
