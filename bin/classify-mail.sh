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

MAILDIR="$DATA_DIR/mail/$ACCOUNT_NAME/$INBOX_FOLDER"
STATEFILE="$DATA_DIR/state/mailfilter/processed"
BOGOFILTER_DIR="$DATA_DIR/state/bogofilter"
SPAMQUEUE="$DATA_DIR/state/mailfilter/spam-queue"
IMAPFILTER_CONFIG="$REPO_DIR/config/imapfilter/move-spam.lua"

mkdir -p "$(dirname "$STATEFILE")"
touch "$STATEFILE"
touch "$SPAMQUEUE"

find "$MAILDIR/new" "$MAILDIR/cur" -type f | while read -r msg; do
    msgid=$(grep -m1 '^Message-ID:' "$msg" | grep -oP '<[^>]+>' | tr -d '[:space:]')
    [ -z "$msgid" ] && msgid="fname:$(basename "$msg" | cut -d',' -f1)"

    grep -qF -- "$msgid" "$STATEFILE" && continue

    if bogofilter -d "$BOGOFILTER_DIR" < "$msg"; then
        # exit 0 = SPAM
        echo "-s:${msgid}" >> "$STATEFILE"
        rawid=$(grep -m1 '^Message-ID:' "$msg" | sed 's/^Message-ID://i' | tr -d '[:space:]')
        echo "$rawid" >> "$SPAMQUEUE"
    else
        # exit 1 = HAM (also catches exit 2 = unsure, leaving it in INBOX)
        echo "-n:${msgid}" >> "$STATEFILE"
    fi

done

# If there's anything in the spam queue, run imapfilter to move it
if [ -s "$SPAMQUEUE" ]; then
    imapfilter -c "$IMAPFILTER_CONFIG" 2>&1 | systemd-cat -t imapfilter
fi
