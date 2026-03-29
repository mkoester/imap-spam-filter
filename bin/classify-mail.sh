#!/bin/bash
set -uo pipefail

MAILDIR=/mnt/data/spamfilter/mail/domain/INBOX
STATEFILE=/mnt/data/spamfilter/state/mailfilter/processed
BOGOFILTER_DIR=/mnt/data/spamfilter/state/bogofilter
SPAMQUEUE=/mnt/data/spamfilter/state/mailfilter/spam-queue

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
    imapfilter -c /mnt/data/spamfilter/config/imapfilter/move-spam.lua
fi
