
#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════╗
# ║          💎 DARNIX BACKUP MANAGER PREMIUM 💎             ║
# ║       Copias completas y restauración SSH / HWID        ║
# ╚══════════════════════════════════════════════════════════╝

set -Eeuo pipefail
umask 077

VERSION="4.3.0"

BACKUP_DIR="/root/darnix-json-backups"
SSH_DIR="/etc/ssh"
USERS_DB="$SSH_DIR/.ssh.db"
QUOTAS_DB="$SSH_DIR/quotas.db"
TRAFFIC_DB="$SSH_DIR/traffic.db"
CONFIG_DIR="$SSH_DIR/sshd_config.d"
BANNER_DIR="$SSH_DIR/banners"

HWID_DB="/usr/local/bin/usuarios.db"
HWID_DIR="/etc/adm-lite/userDIR"

# ───────────────────── 🎨 COLORES ─────────────────────

if [[ -t 1 ]]; then
    R=$'\033[1;31m'
    G=$'\033[1;32m'
    Y=$'\033[1;33m'
    B=$'\033[1;34m'
    M=$'\033[38;5;244m'
    C=$'\033[1;36m'
    W=$'\033[1;37m'
    D=$'\033[2;37m'
    O=$'\033[38;5;208m'
    P=$'\033[38;5;39m'
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
    printf "${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}\n"
}

pause() {
    echo
    read -r -p "  ${GOLD}💡 Presiona ENTER para continuar...${N} " _ || true
}

header() {
    clear 2>/dev/null || true
    echo
    echo "${B}╔══════════════════════════════════════════════════════╗${N}"
    echo "${B}║${N}       ${C}⚡ DARNIX BACKUP MANAGER ⚡${N}                ${B}║${N}"
    echo "${B}║${N}             ${GOLD}💎 PREMIUM EDITION 💎${N}               ${B}║${N}"
    echo "${B}╠══════════════════════════════════════════════════════╣${N}"
    printf "${B}║${N}  ${C}🛡️ Versión:${N} %-8s ${C}📦 Formato:${N} %-24s${B}║${N}\n" \
        "$VERSION" "TAR.GZ + JSON"
    echo "${B}╚══════════════════════════════════════════════════════╝${N}"
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
    for cmd in python3 tar gzip find sort awk grep date du stat \
        mktemp chmod mv cp rm mkdir sshd useradd usermod \
        chpasswd chage getent; do
        command -v "$cmd" >/dev/null 2>&1 ||
            die "Falta el comando requerido: $cmd"
    done
}

init() {
    require_root
    require_commands

    [[ -f "$USERS_DB" ]] ||
        die "No existe la base SSH: $USERS_DB"

    [[ -f "$QUOTAS_DB" ]] ||
        die "No existe la base de cuotas: $QUOTAS_DB"

    [[ -f "$TRAFFIC_DB" ]] ||
        die "No existe la base de tráfico: $TRAFFIC_DB"

    [[ -f "$HWID_DB" ]] ||
        warn "No existe $HWID_DB; se podrán respaldar cuentas SSH."

    [[ -d "$HWID_DIR" ]] ||
        warn "No existe $HWID_DIR; se podrán respaldar cuentas SSH."

    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
}

# ───────────────────── 📦 CREAR BACKUP ─────────────────────

create_backup() {
    local stamp archive tmpdir jsonfile count

    stamp="$(date '+%Y%m%d-%H%M%S')"
    archive="$BACKUP_DIR/darnix-backup-${stamp}.tar.gz"

    [[ ! -e "$archive" ]] || {
        error "Ya existe un backup con ese nombre."
        return 1
    }

    tmpdir="$(mktemp -d "$BACKUP_DIR/.work-XXXXXXXX")"
    chmod 700 "$tmpdir"
    jsonfile="$tmpdir/backup.json"

    info "🔍 Recopilando cuentas SSH y HWID..."

    if ! count="$(python3 - "$jsonfile" "$SSH_DIR" "$USERS_DB" \
        "$QUOTAS_DB" "$TRAFFIC_DB" "$CONFIG_DIR" "$BANNER_DIR" \
        "$HWID_DB" "$HWID_DIR" <<'PY'
import os
import sys
import json
import pwd
import base64
import datetime
import re
import tempfile

(output, ssh_dir, users_db, quotas_db, traffic_db,
 config_dir, banner_dir, hwid_db, hwid_dir) = sys.argv[1:]

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
    if not isinstance(u, str):
        return False
    return bool(
        re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_.-]*[$]?", u)
        or re.fullmatch(r"[A-Fa-f0-9]{32}", u)
    )

def detect_account_type(username):
    if re.fullmatch(r"[A-Fa-f0-9]{32}", username):
        return "HWID"
    return "SSH"

def extract_client_alias(banner_b64):
    if not banner_b64:
        return None
    try:
        content = base64.b64decode(
            banner_b64, validate=True
        ).decode("utf-8", errors="replace")
    except (ValueError, TypeError):
        return None

    for line in content.splitlines():
        match = re.match(
            r"^\s*Cliente\s*:\s*(.*?)\s*$",
            line,
            re.IGNORECASE
        )
        if match:
            return match.group(1).strip() or None
    return None

def check_date(value):
    return datetime.date.fromisoformat(value).isoformat()

# Leer las cuentas SSH administradas por Darnix.
with open(users_db, encoding="utf-8") as f:
    db_lines = f.readlines()

ssh_users = {}
for raw in db_lines:
    fields = raw.strip().split()
    if len(fields) >= 3 and fields[0] == "###":
        user = fields[1]
        if not valid_user(user):
            raise ValueError("Usuario inválido en .ssh.db: " + user)
        ssh_users.setdefault(user, []).append(raw.rstrip("\n"))

quotas = read_json(quotas_db)
traffic = read_json(traffic_db)

shadow = {}
with open("/etc/shadow", encoding="utf-8") as f:
    for raw in f:
        fields = raw.rstrip("\n").split(":")
        if len(fields) >= 2:
            shadow[fields[0]] = fields[1:]

accounts = []

for user, records in sorted(ssh_users.items()):
    try:
        p = pwd.getpwnam(user)
    except KeyError:
        raise ValueError(
            f"La cuenta SSH {user} figura en Darnix, "
            "pero no existe en Linux."
        )

    if user not in shadow:
        raise ValueError("No existe el registro shadow de " + user)

    fields = records[-1].split()
    if len(fields) < 3:
        raise ValueError("Registro Darnix incompleto: " + user)

    expiry = check_date(fields[2])
    sh = shadow[user] + [""] * max(0, 8 - len(shadow[user]))

    banner = read_file_b64(
        os.path.join(banner_dir, "banner_" + user + ".txt")
    )

    accounts.append({
        "username": user,
        "account_type": "SSH",
        "client_alias": extract_client_alias(banner),
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
        "limit_file_b64": read_file_b64(
            os.path.join(ssh_dir, user)
        ),
        "ssh_config_b64": read_file_b64(
            os.path.join(config_dir, user + ".conf")
        ),
        "banner_b64": banner,
        "quota": {
            "exists": user in quotas,
            "value": quotas.get(user)
        },
        "traffic": {
            "exists": user in traffic,
            "value": traffic.get(user)
        }
    })

# Leer las cuentas HWID: formato real "IDENTIFICADOR 1".
if os.path.isfile(hwid_db) and os.path.isdir(hwid_dir):
    with open(hwid_db, encoding="utf-8") as f:
        hwid_lines = f.readlines()

    seen_hwid = set()

    for raw in hwid_lines:
        fields = raw.strip().split()

        if not fields:
            continue

        # Solo identificadores HWID de 32 caracteres hexadecimales.
        if not re.fullmatch(r"[A-Fa-f0-9]{32}", fields[0]):
            continue

        user = fields[0]

        if user in seen_hwid:
            raise ValueError("HWID duplicado en usuarios.db: " + user)
        seen_hwid.add(user)

        metadata_path = os.path.join(hwid_dir, user)

        if not os.path.isfile(metadata_path):
            raise ValueError(
                f"Existe {user} en usuarios.db, pero falta "
                f"su metadata: {metadata_path}"
            )

        metadata = {}
        with open(metadata_path, encoding="utf-8") as f:
            for raw_meta in f:
                if ":" not in raw_meta:
                    continue
                key, value = raw_meta.split(":", 1)
                metadata[key.strip().lower()] = value.strip()

        required = ("senha", "limite", "data")
        missing = [k for k in required if k not in metadata]
        if missing:
            raise ValueError(
                f"Metadata incompleta para {user}: {', '.join(missing)}"
            )

        expiry = check_date(metadata["data"])

        accounts.append({
            "username": user,
            "account_type": "HWID",
            "client_alias": None,
            "hwid_db_record": raw.rstrip("\n"),
            "hwid_metadata": {
                "senha": metadata["senha"],
                "limite": metadata["limite"],
                "data": expiry
            },
            "darnix_expiry": expiry,
            "darnix_records": [],
            "quota": {
                "exists": user in quotas,
                "value": quotas.get(user)
            },
            "traffic": {
                "exists": user in traffic,
                "value": traffic.get(user)
            }
        })

if not accounts:
    raise ValueError(
        "No se encontraron cuentas SSH ni HWID compatibles."
    )

payload = {
    "format": "darnix-full-backup",
    "format_version": 5,
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
    if not isinstance(u, str):
        return False
    return bool(
        re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_.-]*[$]?", u)
        or re.fullmatch(r"[A-Fa-f0-9]{32}", u)
    )

def check_date(value):
    if not isinstance(value, str):
        raise ValueError("Fecha inválida.")
    datetime.date.fromisoformat(value)

with tarfile.open(archive, "r:gz") as tf:
    members = tf.getmembers()

    if len(members) != 1:
        raise ValueError("El archivo debe contener un único backup.json.")

    member = members[0]
    if member.name != "backup.json" or not member.isfile():
        raise ValueError("Contenido del archivo no reconocido.")

    if member.size > 200 * 1024 * 1024:
        raise ValueError("El JSON supera el límite de 200 MiB.")

    src = tf.extractfile(member)
    if src is None:
        raise ValueError("No se pudo leer el JSON.")

    raw = src.read()
    with open(dest, "wb") as f:
        f.write(raw)
    os.chmod(dest, 0o600)

with open(dest, encoding="utf-8") as f:
    data = json.load(f)

if not isinstance(data, dict):
    raise ValueError("El JSON no contiene un objeto válido.")

if data.get("format") != "darnix-full-backup":
    raise ValueError("Formato de backup no reconocido.")

version = data.get("format_version")
if version not in (4, 5):
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

    user = a.get("username")
    if not valid_user(user):
        raise ValueError("Nombre de usuario inválido.")
    if user in seen:
        raise ValueError("Usuario duplicado: " + user)
    seen.add(user)

    account_type = a.get("account_type")
    if account_type is None:
        account_type = (
            "HWID" if re.fullmatch(r"[A-Fa-f0-9]{32}", user)
            else "SSH"
        )

    if account_type not in ("SSH", "HWID"):
        raise ValueError("Tipo de cuenta inválido: " + user)

    if account_type == "HWID":
        if not re.fullmatch(r"[A-Fa-f0-9]{32}", user):
            raise ValueError("Identificador HWID inválido: " + user)

        metadata = a.get("hwid_metadata")
        if not isinstance(metadata, dict):
            raise ValueError("Faltan metadatos HWID: " + user)

        for key in ("senha", "limite", "data"):
            if not isinstance(metadata.get(key), str):
                raise ValueError(
                    f"Metadata HWID inválida ({key}): {user}"
                )

        check_date(metadata["data"])

        record = a.get("hwid_db_record")
        if not isinstance(record, str):
            raise ValueError("Falta el registro de usuarios.db: " + user)

        parts = record.split()
        if len(parts) < 2 or parts[0] != user:
            raise ValueError("Registro HWID incorrecto: " + user)

        continue

    check_date(a.get("darnix_expiry"))

    records = a.get("darnix_records")
    if not isinstance(records, list) or not records:
        raise ValueError("Faltan registros Darnix: " + user)

    matched = False
    for record in records:
        if not isinstance(record, str):
            raise ValueError("Registro Darnix inválido: " + user)

        parts = record.split()
        if len(parts) != 3 or parts[0] != "###" or parts[1] != user:
            raise ValueError("Registro Darnix incorrecto: " + user)

        check_date(parts[2])
        matched |= parts[2] == a["darnix_expiry"]

    if not matched:
        raise ValueError("Fecha Darnix incoherente: " + user)

    shadow = a.get("shadow")
    if not isinstance(shadow, dict):
        raise ValueError("Faltan datos shadow: " + user)

    if not isinstance(shadow.get("password_hash"), str) or not shadow["password_hash"]:
        raise ValueError("Hash vacío o inválido: " + user)

    for key in ("quota", "traffic"):
        item = a.get(key)
        if not isinstance(item, dict) or not isinstance(item.get("exists"), bool):
            raise ValueError("Campo incorrecto: " + key)
        if item["exists"] and "value" not in item:
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

                if not lines or lines[0] != "Match User " + user:
                    raise ValueError("Config SSH no corresponde a " + user)

                for line in lines[1:]:
                    if line.lower().startswith(("include ", "match ")):
                        raise ValueError(
                            "Directiva no permitida en config de " + user
                        )

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

    local paths=()
    local path

    for path in \
        etc/passwd etc/shadow etc/group etc/gshadow \
        etc/ssh usr/local/bin/usuarios.db etc/adm-lite/userDIR; do
        [[ -e "/$path" ]] && paths+=("$path")
    done

    if ((${#paths[@]} == 0)) ||
       ! tar -czpf "$tmp_archive" -C / "${paths[@]}"; then
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
        "$QUOTAS_DB" "$TRAFFIC_DB" "$CONFIG_DIR" "$BANNER_DIR" \
        "$HWID_DB" "$HWID_DIR" <<'PY'
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
 config_dir, banner_dir, hwid_db, hwid_dir) = sys.argv[1:]

with open(json_path, encoding="utf-8") as f:
    data = json.load(f)

accounts = data["accounts"]

ssh_accounts = []
hwid_accounts = []

for a in accounts:
    kind = a.get("account_type")
    if kind is None:
        kind = (
            "HWID" if re.fullmatch(
                r"[A-Fa-f0-9]{32}", a["username"]
            ) else "SSH"
        )

    if kind == "HWID":
        hwid_accounts.append(a)
    else:
        ssh_accounts.append(a)

users_to_restore = {a["username"] for a in ssh_accounts}
hwids_to_restore = {a["username"] for a in hwid_accounts}

def atomic_write(path, content, mode=None):
    parent = os.path.dirname(path)
    os.makedirs(parent, exist_ok=True)

    old_stat = None
    try:
        old_stat = os.stat(path)
    except FileNotFoundError:
        pass

    fd, tmp = tempfile.mkstemp(
        prefix=".darnix-restore-", dir=parent
    )
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
    return None if value is None else base64.b64decode(
        value, validate=True
    )

def run(args):
    subprocess.run(args, check=True)

# ── Restaurar cuentas Linux SSH ──

for a in ssh_accounts:
    user = a["username"]

    try:
        pwd.getpwnam(user)
        exists = True
    except KeyError:
        exists = False

    if not exists:
        run(["useradd", "-M", "-s", "/bin/false", user])

for a in ssh_accounts:
    user = a["username"]
    sh = a["shadow"]

    original_shell = a.get("shell_original", "/bin/false")
    shell = original_shell if original_shell in (
        "/bin/false", "/usr/sbin/nologin"
    ) else "/bin/false"

    run(["usermod", "-s", shell, user])

    subprocess.run(
        ["chpasswd", "-e"],
        input=f'{user}:{sh["password_hash"]}\n',
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
        number = int(value)
        if number < -1:
            raise ValueError(f"Valor shadow fuera de rango: {user}")
        run(["chage", flag, str(number), user])

    exp = sh.get("account_expiry_day")
    if exp is None or exp == "":
        run(["chage", "-E", "-1", user])
    else:
        exp_days = int(exp)

        if exp_days < 0:
            run(["chage", "-E", "-1", user])
        else:
            exp_date = (
                datetime.date(1970, 1, 1)
                + datetime.timedelta(days=exp_days)
            ).isoformat()
            run(["chage", "-E", exp_date, user])

# ── Fusionar .ssh.db sin borrar cuentas ajenas ──

if ssh_accounts:
    with open(users_db, encoding="utf-8") as f:
        old_lines = f.readlines()

    new_lines = []
    for line in old_lines:
        fields = line.strip().split()
        if (
            len(fields) >= 2
            and fields[0] == "###"
            and fields[1] in users_to_restore
        ):
            continue
        new_lines.append(line)

    for a in ssh_accounts:
        new_lines.extend(
            record + "\n" for record in a["darnix_records"]
        )

    atomic_write(users_db, "".join(new_lines).encode())

    os.makedirs(config_dir, exist_ok=True)
    os.makedirs(banner_dir, exist_ok=True)

    for a in ssh_accounts:
        user = a["username"]

        files = (
            (
                a.get("limit_file_b64"),
                os.path.join(ssh_dir, user),
                0o600
            ),
            (
                a.get("ssh_config_b64"),
                os.path.join(config_dir, user + ".conf"),
                0o644
            ),
            (
                a.get("banner_b64"),
                os.path.join(banner_dir, "banner_" + user + ".txt"),
                0o644
            ),
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

# ── Restaurar registros HWID ──
#
# El formato detectado es:
# usuarios.db: IDENTIFICADOR 1
# userDIR/IDENTIFICADOR:
# senha: ...
# limite: ...
# data: YYYY-MM-DD

if hwid_accounts:
    if not os.path.isfile(hwid_db):
        raise FileNotFoundError(
            "No existe la base HWID: " + hwid_db
        )

    os.makedirs(hwid_dir, exist_ok=True)

    with open(hwid_db, encoding="utf-8") as f:
        old_lines = f.readlines()

    new_lines = []
    for line in old_lines:
        fields = line.strip().split()

        if fields and fields[0] in hwids_to_restore:
            continue

        new_lines.append(line)

    for a in hwid_accounts:
        user = a["username"]
        record = a["hwid_db_record"]

        new_lines.append(record + "\n")

        metadata = a["hwid_metadata"]
        content = (
            f'senha: {metadata["senha"]}\n'
            f'limite: {metadata["limite"]}\n'
            f'data: {metadata["data"]}\n'
        ).encode("utf-8")

        atomic_write(
            os.path.join(hwid_dir, user),
            content,
            0o644
        )

    atomic_write(hwid_db, "".join(new_lines).encode())

# ── Fusionar cuotas y tráfico ──

quotas = read_json(quotas_db)
traffic = read_json(traffic_db)

for a in accounts:
    user = a["username"]

    for db, key in ((quotas, "quota"), (traffic, "traffic")):
        item = a.get(key, {"exists": False})

        if item["exists"]:
            db[user] = item.get("value")
        else:
            db.pop(user, None)

write_json(quotas_db, quotas)
write_json(traffic_db, traffic)

print(
    f"Restauración de datos completada: "
    f"{len(ssh_accounts)} SSH y {len(hwid_accounts)} HWID."
)
PY
    then
        rm -rf -- "$tmpdir"
        error "La restauración encontró un error."
        warn "La copia de emergencia se conserva en $BACKUP_DIR."
        warn "La restauración puede haber quedado parcial; no se revierte automáticamente."
        return 1
    fi

    rm -rf -- "$tmpdir"

    info "🧪 Comprobando la configuración de SSH..."

    if sshd -t; then
        ok "Configuración SSH válida."
    else
        error "sshd -t detectó errores."
        warn "No se recargó ni reinició SSH."
        warn "Revisa los archivos y la copia de emergencia."
        return 1
    fi

    line
    ok "¡Restauración masiva completada!"
    info "👥 Cuentas procesadas: $count"
    info "🛡️ Se conservaron las entradas ajenas en las bases fusionadas."
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
            -name 'darnix-backup-*.tar.gz' -printf '%f\n' |
            sort
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
            -name 'darnix-backup-*.tar.gz' -printf '%f\n' |
            sort
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
    for f in "$USERS_DB" "$QUOTAS_DB" "$TRAFFIC_DB" "$HWID_DB"; do
        if [[ -f "$f" ]]; then
            ok "Encontrado: $f"
        else
            warn "No encontrado: $f"
        fi
    done

    if [[ -d "$HWID_DIR" ]]; then
        ok "Directorio HWID encontrado: $HWID_DIR"
    else
        warn "No existe el directorio HWID: $HWID_DIR"
    fi

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
        echo "  ${D}Administra cuentas SSH y HWID.${N}"
        echo
        line

        echo "  ${G}[1]${N} 💾 Crear copia de seguridad completa"
        echo "  ${B}[2]${N} ♻️ Restaurar todas las cuentas desde backup"
        echo "  ${C}[3]${N} 📚 Ver copias de seguridad disponibles"
        echo "  ${R}[4]${N} 🗑️ Eliminar una copia de seguridad"
        echo "  ${Y}[5]${N} 🩺 Diagnóstico del sistema"
        echo "  ${R}[0]${N} 🚪 Salir"

        echo
        line
        echo

        read -r -p "  ${GOLD}➤ Selecciona una opción:${N} " option ||
            exit 0

        case "$option" in
            1)
                echo
                create_backup || true
                pause
                ;;

            2)
                mapfile -t files < <(
                    find "$BACKUP_DIR" -maxdepth 1 -type f \
                        -name 'darnix-backup-*.tar.gz' \
                        -printf '%f\n' | sort
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

                restore_archive \
                    "$BACKUP_DIR/${files[$((choice-1))]}" || true
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
