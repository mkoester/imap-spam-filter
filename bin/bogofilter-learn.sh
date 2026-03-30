#!/usr/bin/env bash
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_ENV="$REPO_DIR/config.env"

if [ ! -f "$CONFIG_ENV" ]; then
    echo "Error: $CONFIG_ENV not found. Run setup.sh first." >&2
    exit 1
fi

set -a
# shellcheck source=/dev/null
source "$CONFIG_ENV"
set +a

MAIL_DIR="$DATA_DIR/mail/$ACCOUNT_NAME"
INBOX="$MAIL_DIR/$INBOX_FOLDER"
JUNK="$MAIL_DIR/$JUNK_FOLDER"
LEARNDB="$DATA_DIR/state/mailfilter/learned"
BOGOFILTER_DIR="$DATA_DIR/state/bogofilter"
MBSYNC_CONFIG="$REPO_DIR/config/mbsync/mbsyncrc"

mkdir -p "$(dirname "$LEARNDB")"
touch "$LEARNDB"

mbsync -c "$MBSYNC_CONFIG" "$ACCOUNT_NAME"

learn() {
    local dir="$1"
    local mode="$2"
    local label="$3"
    local opposite
    opposite=$([ "$mode" = "-s" ] && echo "-n" || echo "-s")
    local relearn_flag
    relearn_flag=$([ "$mode" = "-s" ] && echo "-Ns" || echo "-Sn")

    find "$dir/cur" "$dir/new" -type f 2>/dev/null | while read -r msg; do
        msgid=$(grep -m1 '^Message-ID:' "$msg" | grep -oP '<[^>]+>' | tr -d '[:space:]')
        [ -z "$msgid" ] && msgid="fname:$(basename "$msg" | cut -d',' -f1)"

        target_entry="${mode}:${msgid}"
        opposite_entry="${opposite}:${msgid}"

        grep -qF -- "$target_entry" "$LEARNDB" && continue

        if grep -qF -- "$opposite_entry" "$LEARNDB"; then
            bogofilter -d "$BOGOFILTER_DIR" "$relearn_flag" < "$msg" || true
            sed -i "s|${opposite_entry}|${target_entry}|" "$LEARNDB"
            echo "Relearned as $label: $(basename "$msg")"
        else
            bogofilter -d "$BOGOFILTER_DIR" "$mode" < "$msg" || true
            echo "${target_entry}" >> "$LEARNDB"
            echo "Learned $label: $(basename "$msg")"
        fi

    done
}

echo "=== bogofilter learning run: $(date) ==="
learn "$JUNK"  -s "spam"
learn "$INBOX" -n "ham"
echo "=== done ==="
