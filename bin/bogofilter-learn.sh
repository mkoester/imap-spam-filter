#!/bin/bash
set -uo pipefail

INBOX=/mnt/data/spamfilter/mail/domain/INBOX
JUNK=/mnt/data/spamfilter/mail/domain/Junk
LEARNDB=/mnt/data/spamfilter/state/mailfilter/learned
BOGOFILTER_DIR=/mnt/data/spamfilter/state/bogofilter

mkdir -p "$(dirname "$LEARNDB")"
touch "$LEARNDB"

mbsync -c /mnt/data/spamfilter/config/mbsync/mbsyncrc domain

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
