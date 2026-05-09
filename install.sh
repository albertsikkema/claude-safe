#!/usr/bin/env bash
# claude-safe installer — fetches the wrapper scripts to a local bin dir.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/albertsikkema/claude-safe/main/install.sh | bash
#
# Environment:
#   CLAUDE_SAFE_PREFIX   Install dir (default: $HOME/.local/bin; falls back to /usr/local/bin with sudo)
#   CLAUDE_SAFE_REPO     GitHub repo (default: albertsikkema/claude-safe)
#   CLAUDE_SAFE_REF      Git ref to download from (default: main)
#   CLAUDE_SAFE_NO_SERVER=1   Skip claude-server (only install claude-safe)
set -euo pipefail

REPO="${CLAUDE_SAFE_REPO:-albertsikkema/claude-safe}"
REF="${CLAUDE_SAFE_REF:-main}"
PREFIX="${CLAUDE_SAFE_PREFIX:-$HOME/.local/bin}"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${REF}"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: required command missing: $1" >&2
        exit 1
    }
}

need curl
if ! command -v docker >/dev/null 2>&1; then
    echo "WARNING: 'docker' not found on PATH. Install Docker before running claude-safe." >&2
fi

mkdir -p "$PREFIX" 2>/dev/null || true
USE_SUDO=""
if [[ ! -w "$PREFIX" ]]; then
    if [[ "$PREFIX" == "$HOME/.local/bin" ]]; then
        echo "ERROR: cannot write to $PREFIX" >&2
        exit 1
    fi
    need sudo
    USE_SUDO="sudo"
fi

install_one() {
    local name="$1"
    local url="${BASE_URL}/${name}"
    local target="${PREFIX}/${name}"
    local tmp
    tmp=$(mktemp)
    echo "==> Downloading ${name}"
    if ! curl -fsSL "$url" -o "$tmp"; then
        rm -f "$tmp"
        echo "ERROR: failed to download $url" >&2
        exit 1
    fi
    chmod 755 "$tmp"
    $USE_SUDO mv "$tmp" "$target"
    echo "==> Installed ${target}"
}

install_one claude-safe
if [[ -z "${CLAUDE_SAFE_NO_SERVER:-}" ]]; then
    install_one claude-server
fi

case ":$PATH:" in
    *":${PREFIX}:"*) ;;
    *) echo
       echo "NOTE: ${PREFIX} is not on PATH. Add to your shell profile:"
       echo "  export PATH=\"${PREFIX}:\$PATH\""
       ;;
esac

cat <<EOF

Done. Next steps:

  1. Authenticate to GHCR (only if the image is private):
       gh auth login            # easiest; the wrapper forwards GH_TOKEN
     or
       docker login ghcr.io     # use a GHCR PAT directly

  2. Run it:
       claude-safe              # auto-pulls image on first run, then daily

EOF

if [[ -z "${CLAUDE_SAFE_NO_SERVER:-}" ]]; then
    cat <<'EOF'
  3. (Optional) For claude-server, set your remote host in your shell profile:
       echo 'export CLAUDE_SERVER_HOST=your-host' >> ~/.zshrc   # zsh
       echo 'export CLAUDE_SERVER_HOST=your-host' >> ~/.bashrc  # bash
     Then:
       claude-server            # ssh's to $CLAUDE_SERVER_HOST

EOF
fi
