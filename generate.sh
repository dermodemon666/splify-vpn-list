#!/bin/sh
set -eu

OUT="splify.lst"
TMP="$(mktemp)"
TMP2="$(mktemp)"

cleanup() {
    rm -f "$TMP" "$TMP2"
}
trap cleanup EXIT

echo "# splify custom IP list" > "$TMP"
echo "# Generated automatically. Do not edit manually." >> "$TMP"
echo "# Updated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "$TMP"

echo "# xyzmean YouTube" >> "$TMP"
curl -fsSL \
    "https://raw.githubusercontent.com/xyzmean/ru-bypass-ipsets/main/lists/youtube.lst" \
    >> "$TMP"

echo "# xyzmean Telegram" >> "$TMP"
curl -fsSL \
    "https://raw.githubusercontent.com/xyzmean/ru-bypass-ipsets/main/lists/telegram.lst" \
    >> "$TMP"

echo "# xyzmean Discord" >> "$TMP"
curl -fsSL \
    "https://raw.githubusercontent.com/xyzmean/ru-bypass-ipsets/main/lists/discord.lst" \
    >> "$TMP"

echo "# Resolve custom domains" >> "$TMP"

while IFS= read -r domain; do
    case "$domain" in
        ""|\#*) continue ;;
    esac

    echo "# $domain" >> "$TMP"

    # IPv4
    if command -v dig >/dev/null 2>&1; then
        dig +short A "$domain" |
            awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $0 "/32"}' \
            >> "$TMP" || true
    else
        getent ahostsv4 "$domain" 2>/dev/null |
            awk '{print $1 "/32"}' |
            sort -u \
            >> "$TMP" || true
    fi

done < domains.txt

# Keep only IPv4 CIDR/IP entries, remove comments and duplicates.
awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$/ {
        print
    }
' "$TMP" |
sort -u > "$TMP2"

{
    echo "# splify custom IP list"
    echo "# Generated automatically"
    echo "# Sources:"
    echo "# - xyzmean/ru-bypass-ipsets youtube.lst"
    echo "# - xyzmean/ru-bypass-ipsets telegram.lst"
    echo "# - xyzmean/ru-bypass-ipsets discord.lst"
    echo "# - domains.txt"
    echo
    cat "$TMP2"
} > "$OUT"

echo "Generated $OUT"
echo "Entries: $(wc -l < "$TMP2")"
