#!/usr/bin/env bash
# bootstrap.sh — Parte A de la Fase 1 del SPEC.
# Deja un Ubuntu Server (24.04 o 26.04) recién instalado listo para que Claude Code
# ejecute el resto del spec. Idempotente: se puede volver a correr.
#
# Uso (desde el PC, como tu usuario normal con sudo):
#   curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/bootstrap.sh | bash
# o, si ya clonaste el repo:
#   bash bootstrap.sh

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/haefrain/servidor-ia.git}"
DEST="${DEST:-$HOME/dev/servidor-ia}"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m   ✔ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m   ! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m   ✖ %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- checks
[[ $EUID -eq 0 ]] && die "No lo corras como root; usa tu usuario normal (con sudo)."
command -v sudo >/dev/null || die "sudo no está disponible."
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || warn "Esto está pensado para Ubuntu Server 24.04/26.04; detectado: ${PRETTY_NAME:-desconocido}"

log "Disco de arranque"
ROOT_DEV=$(findmnt -n -o SOURCE /)
ok "raíz montada en $ROOT_DEV"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS | sed 's/^/   /'
warn "Confirma que la raíz está en el SSD de 512 GB y que el de 1 TB NO aparece montado."

# ---------------------------------------------------------------- sistema
log "Actualizando el sistema"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  curl git gnupg ca-certificates ethtool openssh-server
ok "paquetes base instalados"

# ---------------------------------------------------------------- tailscale
log "Tailscale"
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
if ! tailscale status >/dev/null 2>&1; then
  warn "Tailscale instalado pero no conectado. Ejecuta: sudo tailscale up"
else
  ok "Tailscale conectado: $(tailscale ip -4 | head -n1)"
fi

# ---------------------------------------------------------------- claude code
log "Claude Code (instalador nativo oficial)"
if ! command -v claude >/dev/null 2>&1 && [[ ! -x "$HOME/.local/bin/claude" ]]; then
  curl -fsSL https://claude.ai/install.sh | bash
fi
export PATH="$HOME/.local/bin:$PATH"
grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
if command -v claude >/dev/null; then
  ok "claude $(claude --version 2>/dev/null | head -n1)"
else
  die "claude no quedó en el PATH; abre otra terminal y revisa ~/.local/bin"
fi

# ---------------------------------------------------------------- repo
log "Clonando el spec en $DEST"
if [[ -d "$DEST/.git" ]]; then
  git -C "$DEST" pull --ff-only
elif [[ "$REPO_URL" == *"__OWNER__"* ]]; then
  warn "REPO_URL no está configurada; copia SPEC.md y CLAUDE.md a $DEST a mano."
  mkdir -p "$DEST"
else
  mkdir -p "$(dirname "$DEST")"
  git clone "$REPO_URL" "$DEST"
fi
ok "listo en $DEST"

# ---------------------------------------------------------------- resumen
TS_IP=$(tailscale ip -4 2>/dev/null | head -n1 || echo "<pendiente: sudo tailscale up>")
cat <<EOF

================================================================
 Bootstrap terminado. Lo que sigue (a mano, una sola vez):

 1. Si Tailscale no está conectado:    sudo tailscale up
 2. Desde el Mac:                       ssh $USER@$TS_IP
 3. En el PC:                           cd $DEST && claude
    - Claude Code imprime una URL de login; ábrela en el Mac,
      inicia sesión con tu cuenta Max y pega el código de vuelta.
 4. Cuando Claude Code esté dentro, dile:

    Lee CLAUDE.md y SPEC.md. Ejecuta la Parte B de la Fase 1.
    Detente al final de cada fase y reporta.

================================================================
EOF
