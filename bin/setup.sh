#!/bin/bash
# Generates config files from templates and creates required directories.
# Run once after filling in config.env, and again after any config.env change.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_ENV="$REPO_DIR/config.env"

if [ ! -f "$CONFIG_ENV" ]; then
    echo "Error: $CONFIG_ENV not found." >&2
    echo "Copy config.env.example to config.env and fill in your settings." >&2
    exit 1
fi

# Load config and export all vars (required for envsubst)
set -a
# shellcheck source=/dev/null
source "$CONFIG_ENV"
set +a

export REPO_DIR

GOIMAPNOTIFY_BIN="$(command -v goimapnotify 2>/dev/null || true)"
if [ -z "$GOIMAPNOTIFY_BIN" ]; then
    echo "Error: goimapnotify not found in PATH. Install it first (see README.md)." >&2
    exit 1
fi
export GOIMAPNOTIFY_BIN

echo "Creating data directories..."
mkdir -p \
    "$DATA_DIR/mail/$ACCOUNT_NAME" \
    "$DATA_DIR/state/mailfilter" \
    "$DATA_DIR/state/bogofilter"

echo "Generating config/mbsync/mbsyncrc..."
envsubst < "$REPO_DIR/config/mbsync/mbsyncrc.template" \
         > "$REPO_DIR/config/mbsync/mbsyncrc"

echo "Generating config/goimapnotify/config.json..."
envsubst < "$REPO_DIR/config/goimapnotify/config.json.template" \
         > "$REPO_DIR/config/goimapnotify/config.json"

SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"

echo "Generating and installing systemd user units..."
for tmpl in "$REPO_DIR/systemd/"*.template; do
    unit_name="$(basename "${tmpl%.template}")"
    envsubst < "$tmpl" > "$SYSTEMD_USER_DIR/$unit_name"
    echo "  -> $SYSTEMD_USER_DIR/$unit_name"
done

echo "Reloading systemd user daemon..."
systemctl --user daemon-reload

echo ""
echo "Setup complete. Next steps:"
echo "  1. Verify the generated configs look correct."
echo "  2. Bootstrap bogofilter with initial training data (see README.md)."
echo "  3. Enable and start the services:"
echo "       systemctl --user enable --now goimapnotify.service"
echo "       systemctl --user enable --now bogofilter-learn.timer"
