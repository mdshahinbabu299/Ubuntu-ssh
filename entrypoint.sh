#!/usr/bin/env bash
# Container entrypoint: creates the SSH user, installs keys/password,
# persists host keys, then starts sshd in the foreground.
#
# Environment variables:
#   SSH_USERNAME      user to create (default: dev)
#   SSH_PASSWORD      password (min 12 chars). Used only if AUTHORIZED_KEYS is empty.
#   AUTHORIZED_KEYS   one or more public keys (newline separated, or literal \n).
#                     If set, password login is disabled completely.
#   SUDO_NOPASSWD     "true" (default) or "false"
#   SSH_HOSTKEY_DIR   where host keys are stored (default: /home/.sshd-hostkeys)
#                     Mount a volume at /home so keys and files survive redeploys.
set -euo pipefail

SSHD_BIN="${SSHD_BIN:-/usr/sbin/sshd}"
SSH_USERNAME="${SSH_USERNAME:-dev}"
SSH_PASSWORD="${SSH_PASSWORD:-}"
AUTHORIZED_KEYS="${AUTHORIZED_KEYS:-}"
SUDO_NOPASSWD="${SUDO_NOPASSWD:-true}"
HOSTKEY_DIR="${SSH_HOSTKEY_DIR:-/home/.sshd-hostkeys}"
HOME_DIR="/home/${SSH_USERNAME}"

die() { echo "[entrypoint] ERROR: $*" >&2; exit 1; }
log() { echo "[entrypoint] $*"; }

# ---- validate input -------------------------------------------------------
[[ "$SSH_USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] \
  || die "SSH_USERNAME must be lowercase letters/digits/_/- (max 32 chars)"
case "$SSH_USERNAME" in
  root|ubuntu|admin|test|user) die "SSH_USERNAME '$SSH_USERNAME' is too common/forbidden";;
esac

# Normalise keys: accept real newlines or literal "\n"
KEYS="$(printf '%s' "$AUTHORIZED_KEYS" | sed 's/\\n/\n/g' | sed '/^[[:space:]]*$/d')"

if [[ -n "$KEYS" ]]; then
  AUTH_MODE="key"
else
  [[ -n "$SSH_PASSWORD" ]] || die "Set AUTHORIZED_KEYS (recommended) or SSH_PASSWORD"
  [[ ${#SSH_PASSWORD} -ge 12 ]] || die "SSH_PASSWORD must be at least 12 characters"
  case "$SSH_PASSWORD" in
    mypassword*|password*|changeme*|123456*) die "SSH_PASSWORD is a known weak/default value";;
  esac
  AUTH_MODE="password"
fi

# ---- create / refresh user ------------------------------------------------
if ! id -u "$SSH_USERNAME" >/dev/null 2>&1; then
  useradd -u 1000 -s /bin/bash -d "$HOME_DIR" "$SSH_USERNAME" 2>/dev/null \
    || useradd -s /bin/bash -d "$HOME_DIR" "$SSH_USERNAME"
  log "created user $SSH_USERNAME"
fi

mkdir -p "$HOME_DIR"
# Populate dotfiles on first run (works with an empty mounted volume too)
cp -rn /etc/skel/. "$HOME_DIR"/ 2>/dev/null || true
chown "$SSH_USERNAME:$SSH_USERNAME" "$HOME_DIR"
chmod 755 "$HOME_DIR"

# ---- credentials ----------------------------------------------------------
SSH_DIR="$HOME_DIR/.ssh"
mkdir -p "$SSH_DIR"
if [[ "$AUTH_MODE" == "key" ]]; then
  printf '%s\n' "$KEYS" > "$SSH_DIR/authorized_keys"
  # '*' = no password, but account is not "locked" so key login works
  usermod -p '*' "$SSH_USERNAME"
else
  printf '%s:%s\n' "$SSH_USERNAME" "$SSH_PASSWORD" | chpasswd
  rm -f "$SSH_DIR/authorized_keys"
fi
chown -R "$SSH_USERNAME:$SSH_USERNAME" "$SSH_DIR"
chmod 700 "$SSH_DIR"
[[ -f "$SSH_DIR/authorized_keys" ]] && chmod 600 "$SSH_DIR/authorized_keys"

# ---- sudo -----------------------------------------------------------------
mkdir -p /etc/sudoers.d
if [[ "$SUDO_NOPASSWD" == "true" ]]; then
  echo "$SSH_USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-ssh-user
else
  echo "$SSH_USERNAME ALL=(ALL) ALL" > /etc/sudoers.d/90-ssh-user
fi
chmod 440 /etc/sudoers.d/90-ssh-user

# ---- persistent host keys (so "Verify & Pin Host Key" survives redeploys) --
mkdir -p "$HOSTKEY_DIR"
chmod 700 "$HOSTKEY_DIR"
HOSTKEY="$HOSTKEY_DIR/ssh_host_ed25519_key"
if [[ ! -f "$HOSTKEY" ]]; then
  ssh-keygen -q -t ed25519 -N "" -f "$HOSTKEY"
  log "generated new host key"
fi

mkdir -p /run/sshd
chmod 755 /run/sshd

# ---- summary (no secrets) -------------------------------------------------
log "user=$SSH_USERNAME auth=$AUTH_MODE sudo_nopasswd=$SUDO_NOPASSWD"
log "host key fingerprint (compare with the app before pinning):"
ssh-keygen -lf "$HOSTKEY.pub" || true

if [[ "$AUTH_MODE" == "key" ]]; then
  PW_OPT="PasswordAuthentication=no"
else
  PW_OPT="PasswordAuthentication=yes"
fi

exec "$SSHD_BIN" -D -e \
  -o "HostKey=$HOSTKEY" \
  -o "$PW_OPT" \
  -o "AllowUsers=$SSH_USERNAME"
