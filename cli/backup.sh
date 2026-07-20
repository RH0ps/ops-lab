#!/bin/bash

ops_backup_list() {

    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    BACKUP_DIR="$ROOT/backup"
    COUNT=0

    echo "=============================="
    echo "     Available Backups"
    echo "=============================="
    echo

    for FILE in "$BACKUP_DIR"/index_*; do

        [[ -f "$FILE" ]] || continue

        COUNT=$((COUNT + 1))

        NAME=$(basename "$FILE")
        SIZE=$(du -h "$FILE" | awk '{print $1}')
        TIME=$(date -r "$FILE" "+%Y-%m-%d %H:%M")

        printf "%2d. %-30s %6s  %s\n" \
        "$COUNT" "$NAME" "$SIZE" "$TIME"

    done

    TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | awk '{print $1}')

    echo
    printf "Total Files : %d\n" "$COUNT"
    printf "Total Size  : %s\n" "$TOTAL_SIZE"
    echo "=============================="  
}

