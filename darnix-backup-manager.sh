
#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════╗
# ║          💎 DARNIX BACKUP MANAGER PREMIUM 💎             ║
# ║        Copias completas y restauración SSH / HWID       ║
# ╚══════════════════════════════════════════════════════════╝

set -Eeuo pipefail
umask 077

VERSION="4.6.0"
BACKUP_DIR="/root/darnix-json-backups"
SSH_DIR="/etc/ssh"
USERS_DB="$SSH_DIR/.ssh.db"
QUOTAS_DB="$SSH_DIR/quotas.db"
TRAFFIC_DB="$SSH_DIR/traffic.db"
CONFIG_DIR="$SSH_DIR/sshd_config.d"
BANNER_DIR="$SSH_DIR/banners"
USERDIR_DIR="/etc/adm-lite/userDIR"
USUARIOS_DB="/usr/local/bin/usuarios.db"

# ───────────────────── 🎨 COLORES ─────────────────────
if [[ -t 1 ]]; then
    R=$'\033[1;31m'; G=$'\033[1;32m'; Y=$'\033[1;33m'; B=$'\033[1;34m'
    M=$'\033[38;5;244m'; C=$'\033[1;36m'; W=$'\033[1;37m'; D=$'\033[2;37m'
    O=$'\033[38;5;208m'; P=$'\033[38;5;39m'; GOLD=$'\033[38;5;220m'; N=$'\033[0m'
else
    R='' G='' Y='' B='' M='' C='' W='' D='' O='' P='' GOLD='' N=''
fi

# ───────────────────── 🧰 UTILIDADES ─────────────────────
ok()    { printf "  ${G}✔️  %s${N}\n" "$*"; }
warn()  { printf "  ${GOLD}⚠️  %s${N}\n" "$*"; }
error() { printf "  ${R}❌  %s${N}\n" "$*" >&2; }
info()  { printf "  ${C}➜ 🔹 %s${N}\n" "$*"; }
line()  { printf "${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}\n"; }
pause() { echo; read -r -p "  ${GOLD}💡 Presiona ENTER para continuar...${N} " _; }

header() {
    clear 2>/dev/null || true
    echo
    echo "${B}╔══════════════════════════════════════════════════════╗${N}"
    echo "${B}║${N}       ${C}⚡ DARNIX BACKUP MANAGER ⚡${N}                ${B}║${N}"
    echo "${B}║${N}             ${GOLD}💎 PREMIUM EDITION 💎${N}               ${B}║${N}"
    echo "${B}╠══════════════════════════════════════════════════════╣${N}"
    printf "${B}║${N}  ${C}🛡️ Versión:${N} %-8s ${C}📦 Formato:${N} %-24s${B}║${N}\n" "$VERSION" "TAR.GZ + JSON"
    echo "${B}╚══════════════════════════════════════════════════════╝${N}"
    echo
}

die() { error "$*"; exit 1; }
require_root() { [[ "$EUID" -eq 0 ]] || die "Ejecuta el panel como root."; }

require_commands() {
    local cmd
    for cmd in python3 tar gzip getent useradd usermod chage chpasswd sshd find sort awk grep date du stat mktemp chmod mv cp; do
        command -v "$cmd" >/dev/null 2>&1 || die "Falta el comando requerido: $cmd"
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

# ───────────────────── 📦 CREAR BACKUP ─────────────────────
create_backup() {
    local stamp archive tmpdir jsonfile count
    stamp="$(date '+%Y%m%d-%H%M%S')"
    archive="$BACKUP_DIR/darnix-backup-${stamp}.tar.gz"
    [[ ! -e "$archive" ]] || { error "Ya existe un backup con ese nombre."; return 1; }
    tmpdir="$(mktemp -d "$BACKUP_DIR/.work-XXXXXXXX")"
    chmod 700 "$tmpdir"
    jsonfile="$tmpdir/backup.json"
    info "🔍 Recopilando cuentas SSH, HWID y metadatos ADM-Lite..."

    if ! count="$(python3 - "$jsonfile" "$SSH_DIR" "$USERS_DB" "$QUOTAS_DB" "$TRAFFIC_DB" "$CONFIG_DIR" "$BANNER_DIR" "$USERDIR_DIR" "$USUARIOS_DB" <<'PY'
import os, sys, json, pwd, base64, datetime, re, tempfile
(output, ssh_dir, users_db, quotas_db, traffic_db, config_dir, banner_dir, userdir_dir, usuarios_db) = sys.argv[1:]
HWID_RE = re.compile(r'[A-Fa-f0-9]{32}\Z')

def valid_user(u):
    return isinstance(u, str) and bool(re.fullmatch(r'[a-zA-Z_][a-zA-Z0-9_.-]*[$]?', u) or HWID_RE.fullmatch(u))

def read_json(path):
    with open(path, encoding='utf-8') as f:
        obj = json.load(f)
    if not isinstance(obj, dict):
        raise ValueError('Base JSON inválida: ' + path)
    return obj

def read_b64(path):
    try:
        with open(path, 'rb') as f:
            return base64.b64encode(f.read()).decode('ascii')
    except FileNotFoundError:
        return None

def read_text(path):
    try:
        with open(path, encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        return None

def parse_userdir(content):
    result = {}
    if content is not None:
        for line in content.splitlines():
            if ':' in line:
                k, v = line.split(':', 1)
                result[k.strip().lower()] = v.strip()
    return result

def read_user_records(path, username):
    try:
        with open(path, encoding='utf-8') as f:
            lines = f.readlines()
    except FileNotFoundError:
        return []
    return [x.rstrip('\n') for x in lines if x.split() and x.split()[0] == username]

def extract_banner_alias(b64):
    if not b64:
        return None
    try:
        text = base64.b64decode(b64, validate=True).decode('utf-8', errors='replace')
    except (ValueError, TypeError):
        return None
    for line in text.splitlines():
        m = re.match(r'^\s*Cliente\s*:\s*(.*?)\s*$', line, re.I)
        if m and m.group(1).strip():
            return m.group(1).strip()
    return None

shadow = {}
with open('/etc/shadow', encoding='utf-8') as f:
    for line in f:
        fields = line.rstrip('\n').split(':')
        if len(fields) >= 2:
            shadow[fields[0]] = fields[1:]

with open(users_db, encoding='utf-8') as f:
    db_lines = f.readlines()

records_by_user = {}
for raw in db_lines:
    fields = raw.strip().split()
    if len(fields) >= 3 and fields[0] == '###':
        user = fields[1]
        if not valid_user(user):
            raise ValueError('Usuario inválido en .ssh.db: ' + user)
        datetime.date.fromisoformat(fields[2])
        records_by_user.setdefault(user, []).append(raw.rstrip('\n'))

# Descubrir HWID desde los metadatos de ADM-Lite y usuarios.db.
hwid_candidates = set()

if os.path.isdir(userdir_dir):
    for name in os.listdir(userdir_dir):
        if HWID_RE.fullmatch(name):
            hwid_candidates.add(name)

try:
    with open(usuarios_db, encoding='utf-8') as f:
        for raw in f:
            fields = raw.split()
            if fields and HWID_RE.fullmatch(fields[0]):
                hwid_candidates.add(fields[0])
except FileNotFoundError:
    pass

# Si falta una línea en .ssh.db, recuperar la fecha desde userDIR.
for user in sorted(hwid_candidates):
    if user in records_by_user:
        continue
    meta = parse_userdir(read_text(os.path.join(userdir_dir, user)))
    expiry = meta.get('data')
    if expiry:
        datetime.date.fromisoformat(expiry)
        records_by_user[user] = [f'### {user} {expiry}']

if not records_by_user:
    raise ValueError('No se encontraron cuentas Darnix en .ssh.db ni metadatos HWID recuperables.')

quotas, traffic = read_json(quotas_db), read_json(traffic_db)
accounts = []

for user, records in sorted(records_by_user.items()):
    if not valid_user(user):
        raise ValueError('Nombre de usuario inválido: ' + user)

    try:
        p = pwd.getpwnam(user)
    except KeyError:
        raise ValueError(f'La cuenta {user} aparece en Darnix pero no existe en Linux.')

    if user not in shadow:
        raise ValueError('No se encontró el registro shadow de ' + user)

    expiry = records[-1].split()[2]
    datetime.date.fromisoformat(expiry)

    sh = list(shadow[user])
    sh += [''] * max(0, 8-len(sh))

    banner_b64 = read_b64(os.path.join(banner_dir, 'banner_' + user + '.txt'))
    userdir_content = read_text(os.path.join(userdir_dir, user)) if HWID_RE.fullmatch(user) else None
    meta = parse_userdir(userdir_content)
    alias = meta.get('senha') or extract_banner_alias(banner_b64)
    is_hwid = bool(HWID_RE.fullmatch(user))

    account = {
        'username': user,
        'account_type': 'HWID' if is_hwid else 'SSH',
        'client_alias': alias,
        'uid_original': p.pw_uid,
        'gid_original': p.pw_gid,
        'home_original': p.pw_dir,
        'shell_original': p.pw_shell,
        'darnix_expiry': expiry,
        'darnix_records': records,
        'shadow': {
            'password_hash': sh[0],
            'last_change': sh[1],
            'min_days': sh[2],
            'max_days': sh[3],
            'warn_days': sh[4],
            'inactive_days': sh[5],
            'account_expiry_day': sh[6],
            'reserved': sh[7]
        },
        'limit_file_b64': read_b64(os.path.join(ssh_dir, user)),
        'ssh_config_b64': read_b64(os.path.join(config_dir, user + '.conf')),
        'banner_b64': banner_b64,
        'quota': {'exists': user in quotas, 'value': quotas.get(user)},
        'traffic': {'exists': user in traffic, 'value': traffic.get(user)},
        'adm_lite_userdir_b64': base64.b64encode(userdir_content.encode('utf-8')).decode('ascii') if userdir_content is not None else None,
        'usuarios_db_records': read_user_records(usuarios_db, user) if is_hwid else []
    }
    accounts.append(account)

payload = {
    'format': 'darnix-full-backup',
    'format_version': 5,
    'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'account_count': len(accounts),
    'accounts': accounts
}

fd, tmp = tempfile.mkstemp(prefix='.backup-json-', dir=os.path.dirname(output))
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write('\n')
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
    local archive="$1" dest="$2"

    python3 - "$archive" "$dest" <<'PY'
import sys, os, json, tarfile, re, base64, datetime

archive, dest = sys.argv[1:]
HWID_RE = re.compile(r'[A-Fa-f0-9]{32}\Z')

def valid_user(u):
    return isinstance(u, str) and bool(re.fullmatch(r'[a-zA-Z_][a-zA-Z0-9_.-]*[$]?', u) or HWID_RE.fullmatch(u))

def check_date(s):
    if not isinstance(s, str):
        raise ValueError('Fecha inválida.')
    datetime.date.fromisoformat(s)

with tarfile.open(archive, 'r:gz') as tf:
    members = tf.getmembers()
    if len(members) != 1:
        raise ValueError('El archivo debe contener un único backup.json.')
    m = members[0]
    if m.name != 'backup.json' or not m.isfile():
        raise ValueError('Contenido del archivo no reconocido.')
    if m.size > 200*1024*1024:
        raise ValueError('El JSON supera el límite de 200 MiB.')
    src = tf.extractfile(m)
    if src is None:
        raise ValueError('No se pudo leer el JSON.')
    raw = src.read()
    with open(dest, 'wb') as f:
        f.write(raw)
    os.chmod(dest, 0o600)

with open(dest, encoding='utf-8') as f:
    data = json.load(f)

if data.get('format') != 'darnix-full-backup':
    raise ValueError('Formato de backup no reconocido.')
if data.get('format_version') not in (4, 5):
    raise ValueError('Versión de backup incompatible.')

accounts = data.get('accounts')
if not isinstance(accounts, list) or not accounts:
    raise ValueError('El backup no contiene cuentas.')
if len(accounts) > 100000:
    raise ValueError('Número de cuentas fuera de rango.')

seen = set()
for a in accounts:
    if not isinstance(a, dict):
        raise ValueError('Registro de cuenta inválido.')

    u = a.get('username')
    if not valid_user(u):
        raise ValueError('Nombre de usuario inválido.')
    if u in seen:
        raise ValueError('Usuario duplicado: ' + u)
    seen.add(u)

    typ = a.get('account_type')
    if typ is not None and typ not in ('SSH', 'HWID'):
        raise ValueError('Tipo de cuenta inválido para ' + u)

    alias = a.get('client_alias')
    if alias is not None and not isinstance(alias, str):
        raise ValueError('Alias inválido para ' + u)

    check_date(a.get('darnix_expiry'))

    records = a.get('darnix_records')
    if not isinstance(records, list) or not records:
        raise ValueError('Faltan registros Darnix para ' + u)

    matched = False
    for record in records:
        if not isinstance(record, str):
            raise ValueError('Registro Darnix inválido para ' + u)
        parts = record.split()
        if len(parts) != 3 or parts[0] != '###' or parts[1] != u:
            raise ValueError('Registro Darnix incorrecto para ' + u)
        check_date(parts[2])
        matched = matched or parts[2] == a['darnix_expiry']

    if not matched:
        raise ValueError('Fecha Darnix incoherente para ' + u)

    sh = a.get('shadow')
    if not isinstance(sh, dict) or not isinstance(sh.get('password_hash'), str) or not sh['password_hash']:
        raise ValueError('Hash vacío o inválido para ' + u)

    for key in ('quota', 'traffic'):
        obj = a.get(key)
        if not isinstance(obj, dict) or not isinstance(obj.get('exists'), bool):
            raise ValueError('Campo incorrecto: ' + key)
        if obj['exists'] and 'value' not in obj:
            raise ValueError('Falta el valor de ' + key)

    for key in ('limit_file_b64', 'ssh_config_b64', 'banner_b64', 'adm_lite_userdir_b64'):
        value = a.get(key)
        if value is not None:
            if not isinstance(value, str):
                raise ValueError('Archivo codificado inválido: ' + key)
            content = base64.b64decode(value, validate=True)

            if key == 'ssh_config_b64':
                text = content.decode('utf-8')
                lines = [x.strip() for x in text.splitlines() if x.strip()]
                if not lines or lines[0] != 'Match User ' + u:
                    raise ValueError('Config SSH no corresponde a ' + u)
                for line in lines[1:]:
                    if line.lower().startswith(('include ', 'match ')):
                        raise ValueError('Directiva no permitida en config de ' + u)

    recs = a.get('usuarios_db_records')
    if recs is not None:
        if not isinstance(recs, list):
            raise ValueError('Registros usuarios.db inválidos para ' + u)
        for rec in recs:
            if not isinstance(rec, str) or not rec.split() or rec.split()[0] != u:
                raise ValueError('Registro usuarios.db incorrecto para ' + u)

print(len(accounts))
PY
}

# ───────────────────── 🛡️ BACKUP PREVIO DE EMERGENCIA ─────────────────────
create_pre_restore_backup() {
    local stamp archive tmp_archive
    stamp="$(date '+%Y%m%d-%H%M%S')"
    archive="$BACKUP_DIR/darnix-pre-restore-${stamp}.tar.gz"
    [[ ! -e "$archive" ]] || { error "Ya existe una copia previa con ese nombre."; return 1; }

    info "🛡️ Creando copia de emergencia del estado actual..."
    tmp_archive="$(mktemp "$BACKUP_DIR/.pre-restore-XXXXXXXX")" || {
        error "No se pudo crear el archivo temporal."
        return 1
    }
    chmod 600 "$tmp_archive"

    local backup_paths=(etc/passwd etc/shadow etc/group etc/gshadow etc/ssh)
    [[ -d /etc/adm-lite/userDIR ]] && backup_paths+=(etc/adm-lite/userDIR)
    [[ -f /usr/local/bin/usuarios.db ]] && backup_paths+=(usr/local/bin/usuarios.db)

    if ! tar -czpf "$tmp_archive" -C / "${backup_paths[@]}"; then
        rm -f -- "$tmp_archive"
        error "No se pudo guardar el estado actual."
        return 1
    fi

    if [[ ! -s "$tmp_archive" ]] || ! tar -tzf "$tmp_archive" >/dev/null 2>&1; then
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

# ───────────────────── ♻️ RESTAURAR ─────────────────────
restore_archive() {
    local archive="$1" tmpdir jsonfile count
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

    info "♻️ Restaurando cuentas y metadatos..."

    if ! python3 - "$jsonfile" "$SSH_DIR" "$USERS_DB" "$QUOTAS_DB" "$TRAFFIC_DB" "$CONFIG_DIR" "$BANNER_DIR" "$USERDIR_DIR" "$USUARIOS_DB" <<'PY'
import os, sys, json, base64, tempfile, subprocess, datetime, pwd, re

(json_path, ssh_dir, users_db, quotas_db, traffic_db, config_dir, banner_dir, userdir_dir, usuarios_db) = sys.argv[1:]

with open(json_path, encoding='utf-8') as f:
    data = json.load(f)

accounts = data['accounts']
users_to_restore = {a['username'] for a in accounts}
HWID_RE = re.compile(r'[A-Fa-f0-9]{32}\Z')

def valid_user(u):
    return isinstance(u, str) and bool(re.fullmatch(r'[a-zA-Z_][a-zA-Z0-9_.-]*[$]?', u) or HWID_RE.fullmatch(u))

for u in users_to_restore:
    if not valid_user(u):
        raise ValueError('Nombre de usuario inválido: ' + repr(u))

def atomic_write(path, content, mode=None):
    parent = os.path.dirname(path)
    os.makedirs(parent, exist_ok=True)
    try:
        old_stat = os.stat(path)
    except FileNotFoundError:
        old_stat = None

    fd, tmp = tempfile.mkstemp(prefix='.darnix-restore-', dir=parent)
    try:
        with os.fdopen(fd, 'wb') as f:
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
    with open(path, encoding='utf-8') as f:
        obj = json.load(f)
    if not isinstance(obj, dict):
        raise ValueError('Base JSON inválida: ' + path)
    return obj

def write_json(path, obj):
    atomic_write(path, (json.dumps(obj, ensure_ascii=False, indent=2) + '\n').encode(), None)

def decode(value):
    return None if value is None else base64.b64decode(value, validate=True)

def run(args):
    subprocess.run(args, check=True)

# Comprobar bases actuales antes de hacer cambios adicionales.
quotas = read_json(quotas_db)
traffic = read_json(traffic_db)

# Crear usuarios Linux ausentes, sin recrear ni cambiar UID existentes.
for a in accounts:
    u = a['username']
    try:
        pwd.getpwnam(u)
        exists = True
    except KeyError:
        exists = False

    if not exists:
        run(['useradd', '-M', '-s', '/bin/false', u])

# Restaurar propiedades de autenticación y caducidad.
for a in accounts:
    u = a['username']
    sh = a['shadow']

    original_shell = a.get('shell_original', '/bin/false')
    shell = original_shell if original_shell in ('/bin/false', '/usr/sbin/nologin') else '/bin/false'
    run(['usermod', '-s', shell, u])
    subprocess.run(['chpasswd', '-e'], input=f'{u}:{sh["password_hash"]}\n', text=True, check=True)

    for field, flag in (
        ('min_days', '-m'),
        ('max_days', '-M'),
        ('warn_days', '-W'),
        ('inactive_days', '-I'),
        ('last_change', '-d')
    ):
        value = sh.get(field)
        if value is None or value == '':
            continue
        number = int(value)
        run(['chage', flag, str(number), u])

    exp = sh.get('account_expiry_day')
    if exp is None or exp == '':
        run(['chage', '-E', '-1', u])
    else:
        exp_days = int(exp)
        if exp_days < 0:
            run(['chage', '-E', '-1', u])
        else:
            run(['chage', '-E', (datetime.date(1970, 1, 1) + datetime.timedelta(days=exp_days)).isoformat(), u])

# Fusionar .ssh.db: conservar todos los registros de cuentas fuera del backup.
with open(users_db, encoding='utf-8') as f:
    old_lines = f.readlines()

new_lines = []
for line in old_lines:
    fields = line.strip().split()
    if len(fields) >= 2 and fields[0] == '###' and fields[1] in users_to_restore:
        continue
    new_lines.append(line)

for a in accounts:
    new_lines.extend(record + '\n' for record in a['darnix_records'])

atomic_write(users_db, ''.join(new_lines).encode(), 0o644)

os.makedirs(config_dir, exist_ok=True)
os.makedirs(banner_dir, exist_ok=True)

for a in accounts:
    u = a['username']
    for encoded, path, mode in (
        (a.get('limit_file_b64'), os.path.join(ssh_dir, u), 0o600),
        (a.get('ssh_config_b64'), os.path.join(config_dir, u + '.conf'), 0o644),
        (a.get('banner_b64'), os.path.join(banner_dir, 'banner_' + u + '.txt'), 0o644)
    ):
        content = decode(encoded)
        if content is None:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        else:
            atomic_write(path, content, mode)

# Restaurar userDIR solo si el backup incluye ese campo.
# En backups v4 se conserva lo que ya exista.
os.makedirs(userdir_dir, exist_ok=True)

metadata_accounts = [a for a in accounts if a.get('usuarios_db_records')]
metadata_users = {a['username'] for a in metadata_accounts}

for a in accounts:
    if 'adm_lite_userdir_b64' not in a:
        continue

    u = a['username']
    encoded = a.get('adm_lite_userdir_b64')
    path = os.path.join(userdir_dir, u)

    if encoded is None:
        # La ausencia en el backup no significa que deban borrarse metadatos.
        continue

    content = base64.b64decode(encoded, validate=True)
    text = content.decode('utf-8')

    fields = {}
    for line in text.splitlines():
        if ':' in line:
            k, v = line.split(':', 1)
            fields[k.strip().lower()] = v.strip()

    if not HWID_RE.fullmatch(u):
        raise ValueError('Metadatos ADM-Lite asociados a cuenta no HWID: ' + u)

    if fields.get('data') and fields['data'] != a['darnix_expiry']:
        raise ValueError('Fecha userDIR incoherente para ' + u)

    atomic_write(path, content, 0o600)

# usuarios.db: reemplazar registros de HWID incluidos y conservar los demás.
if metadata_accounts:
    try:
        with open(usuarios_db, encoding='utf-8') as f:
            old_meta = f.readlines()
    except FileNotFoundError:
        old_meta = []

    out = []
    for line in old_meta:
        fields = line.split()
        if fields and fields[0] in metadata_users:
            continue
        out.append(line)

    for a in metadata_accounts:
        for record in a.get('usuarios_db_records') or []:
            out.append(record + '\n')

    atomic_write(usuarios_db, ''.join(out).encode('utf-8'), 0o644)

# Fusionar cuotas y tráfico sin reemplazar registros ajenos.
for a in accounts:
    u = a['username']
    for db, key in ((quotas, 'quota'), (traffic, 'traffic')):
        item = a[key]
        if item['exists']:
            db[u] = item.get('value')
        else:
            db.pop(u, None)

write_json(quotas_db, quotas)
write_json(traffic_db, traffic)

print(f'Restauración de datos completada para {len(accounts)} cuentas.')
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
    info "🔐 Se fusionaron cuotas, tráfico y metadatos disponibles."
    info "⚙️ SSH no se recargó automáticamente."
}

# ───────────────────── 📚 LISTAR BACKUPS ─────────────────────
list_backups() {
    header
    echo "${GOLD}📚 COPIAS DE SEGURIDAD DISPONIBLES${N}"
    line

    local files=()
    mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'darnix-backup-*.tar.gz' -printf '%f\n' | sort)

    if ((${#files[@]} == 0)); then
        warn "No hay copias de seguridad guardadas."
    else
        local f
        for f in "${files[@]}"; do
            printf "  ${G}📦${N} %-42s ${Y}%s${N}\n" "$f" "$(du -h "$BACKUP_DIR/$f" | awk '{print $1}')"
        done
        echo
        info "Total de copias: ${#files[@]}"
    fi

    pause
}

# ───────────────────── 🗑️ ELIMINAR BACKUP ─────────────────────
delete_backup() {
    local files=() i=1 choice file answer
    mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'darnix-backup-*.tar.gz' -printf '%f\n' | sort)

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
    read -r -p "  ¿Deseas eliminar esta copia? [s/n]: " answer

    case "$answer" in
        s|S)
            if rm -f -- "$BACKUP_DIR/$file"; then
                ok "Backup eliminado."
            else
                error "No se pudo eliminar el backup."
            fi
            ;;
        n|N)
            info "Operación cancelada."
            ;;
        *)
            warn "Respuesta inválida. Usa únicamente s o n."
            ;;
    esac

    pause
}

# ───────────────────── 🩺 DIAGNÓSTICO ─────────────────────
diagnostics() {
    header
    echo "${GOLD}🩺 DIAGNÓSTICO DEL SISTEMA${N}"
    line

    local f
    for f in "$USERS_DB" "$QUOTAS_DB" "$TRAFFIC_DB" "$USUARIOS_DB"; do
        if [[ -f "$f" ]]; then
            ok "Encontrado: $f"
        else
            warn "No existe $f"
        fi
    done

    [[ -d "$USERDIR_DIR" ]] && ok "Directorio ADM-Lite: $USERDIR_DIR" || warn "No existe $USERDIR_DIR"

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
        echo "  ${D}Crea un respaldo de tus cuentas SSH y HWID.${N}"
        echo
        line

        echo "  ${G}[1]${N} 💾 Crear copia de seguridad"
        echo "  ${B}[2]${N} ♻️ Restaurar copia de seguridad"
        echo "  ${C}[3]${N} 📚 Ver copias de seguridad disponibles"
        echo "  ${R}[4]${N} 🗑️ Eliminar una copia de seguridad"
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
                mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'darnix-backup-*.tar.gz' -printf '%f\n' | sort)

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

                echo
                restore_archive "$BACKUP_DIR/${files[$((choice-1))]}" || true
                pause
                ;;
            3)
                list_backups
                ;;
            4)
                delete_backup
                ;;
            5)
                diagnostics
                ;;
            0)
                echo
                echo "  ${P}👋 ¡Hasta Luego! Espero haya sido de utilidad${N}"
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
