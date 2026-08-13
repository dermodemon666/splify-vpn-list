#!/bin/sh
set -eu

OUT="splify.lst"
TMP="$(mktemp)"
YT="$(mktemp)"
TG="$(mktemp)"
DC="$(mktemp)"
DNS="$(mktemp)"
ALL="$(mktemp)"

cleanup() {
    rm -f "$TMP" "$YT" "$TG" "$DC" "$DNS" "$ALL"
}
trap cleanup EXIT

echo "Downloading YouTube list..."
curl -fsSL \
    "https://raw.githubusercontent.com/xyzmean/ru-bypass-ipsets/main/lists/youtube.lst" \
    > "$YT"

echo "Downloading Telegram list..."
curl -fsSL \
    "https://raw.githubusercontent.com/xyzmean/ru-bypass-ipsets/main/lists/telegram.lst" \
    > "$TG"

echo "Downloading Discord list..."
curl -fsSL \
    "https://raw.githubusercontent.com/xyzmean/ru-bypass-ipsets/main/lists/discord.lst" \
    > "$DC"

echo "Resolving custom domains..."

while IFS= read -r domain; do
    case "$domain" in
        ""|\#*) continue ;;
    esac

    echo "  $domain"

    dig +short A "$domain" 2>/dev/null |
        awk '
            /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {
                print $0 "/32"
            }
        ' >> "$DNS" || true

done < domains.txt

# Validate downloaded lists.
for file in "$YT" "$TG" "$DC"; do
    if ! grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' "$file"; then
        echo "ERROR: downloaded list contains no valid IPv4 CIDRs"
        exit 1
    fi
done

# Keep valid CIDRs only.
cat "$YT" "$TG" "$DC" "$DNS" |
    awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }

        /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$/ {
            if ($0 == "8.8.4.0/24") next
            if ($0 == "8.8.8.0/24") next
            print
        }
    ' |
sort -u > "$ALL"

YT_COUNT=$(grep -Ec '^[0-9]+\.' "$YT" || true)
TG_COUNT=$(grep -Ec '^[0-9]+\.' "$TG" || true)
DC_COUNT=$(grep -Ec '^[0-9]+\.' "$DC" || true)
DNS_COUNT=$(grep -Ec '^[0-9]+\.' "$DNS" || true)
TOTAL=$(wc -l < "$ALL" | tr -d ' ')

{
    echo "# splify custom IP list"
    echo "# Generated automatically"
    echo "#"
    echo "# YouTube source: $YT_COUNT entries"
    echo "# Telegram source: $TG_COUNT entries"
    echo "# Discord source: $DC_COUNT entries"
    echo "# DNS domains: $DNS_COUNT entries"
    echo "# Final unique IPv4 CIDRs: $TOTAL"
    echo "#"
    echo "# Sources:"
    echo "# https://github.com/xyzmean/ru-bypass-ipsets"
    echo "# domains.txt"
    echo
    cat "$ALL"
} > "$OUT"

echo
echo "========== SUMMARY =========="
echo "YouTube:       $YT_COUNT"
echo "Telegram:      $TG_COUNT"
echo "Discord:       $DC_COUNT"
echo "DNS:           $DNS_COUNT"
echo "Final unique:  $TOTAL"
echo "============================="
