#!/bin/sh
set -eu

OUT="splify.lst"

TMP="$(mktemp -d)"
YT="$TMP/youtube.lst"
TG="$TMP/telegram.lst"
DC="$TMP/discord.lst"
DNS="$TMP/dns.lst"
ALL="$TMP/all.lst"

cleanup() {
    rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

echo "======================================"
echo " splify IP list generator"
echo "======================================"
echo

# ------------------------------------------------------------
# Download known IP lists
# ------------------------------------------------------------

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
    "https://raw.githubusercontent.com/fildunsky/clash_discord/main/discord-ip.yaml" |
    sed -n 's/^[[:space:]]*-[[:space:]]*IP-CIDR,\([^,]*\).*$/\1/p' \
    > "$DC"

# ------------------------------------------------------------
# Resolve domains ourselves
# ------------------------------------------------------------

echo
echo "Resolving service domains using public DNS..."

resolve_domain() {
    domain="$1"

    echo "  $domain"

    # Google DNS
    dig @8.8.8.8 +short A "$domain" 2>/dev/null || true

    # Cloudflare DNS
    dig @1.1.1.1 +short A "$domain" 2>/dev/null || true

    # Quad9
    dig @9.9.9.9 +short A "$domain" 2>/dev/null || true
}

while IFS= read -r domain; do

    case "$domain" in
        ""|\#*)
            continue
            ;;
    esac

    resolve_domain "$domain" >> "$DNS"

done < domains.txt

# ------------------------------------------------------------
# Validate source lists
# ------------------------------------------------------------

for file in "$YT" "$TG" "$DC"; do
    if ! grep -Eq \
        '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' \
        "$file"
    then
        echo "ERROR: source list contains no valid IPv4 CIDRs"
        exit 1
    fi
done

# ------------------------------------------------------------
# Normalize DNS results
# ------------------------------------------------------------

awk '
    /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {
        print $0 "/32"
    }
' "$DNS" > "$TMP/dns-clean.lst"

# ------------------------------------------------------------
# Combine everything
# ------------------------------------------------------------

cat \
    "$YT" \
    "$TG" \
    "$DC" \
    "$TMP/dns-clean.lst" |
awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }

    /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$/ {

        # Google DNS must ALWAYS remain direct.
        if ($0 == "8.8.4.0/24") next
        if ($0 == "8.8.8.0/24") next

        print
    }
' |
sort -u > "$ALL"

# ------------------------------------------------------------
# Statistics
# ------------------------------------------------------------

YT_COUNT=$(grep -Ec '^[0-9]+\.' "$YT" || true)
TG_COUNT=$(grep -Ec '^[0-9]+\.' "$TG" || true)
DC_COUNT=$(grep -Ec '^[0-9]+\.' "$DC" || true)
DNS_COUNT=$(grep -Ec '^[0-9]+\.' "$TMP/dns-clean.lst" || true)
TOTAL=$(wc -l < "$ALL" | tr -d ' ')

# ------------------------------------------------------------
# Verify exclusions
# ------------------------------------------------------------

echo
echo "========== EXCLUDE CHECK =========="

if grep -qx '8.8.4.0/24' "$ALL"; then
    echo "ERROR: 8.8.4.0/24 is still present!"
    exit 1
else
    echo "OK: 8.8.4.0/24 excluded"
fi

if grep -qx '8.8.8.0/24' "$ALL"; then
    echo "ERROR: 8.8.8.0/24 is still present!"
    exit 1
else
    echo "OK: 8.8.8.0/24 excluded"
fi

echo "===================================="

# ------------------------------------------------------------
# Generate final file
# ------------------------------------------------------------

{
    echo "# splify custom IP list"
    echo "# Generated automatically"
    echo "#"
    echo "# YouTube source: $YT_COUNT entries"
    echo "# Telegram source: $TG_COUNT entries"
    echo "# Discord source: $DC_COUNT entries"
    echo "# DNS resolved IPv4: $DNS_COUNT entries"
    echo "# Final unique IPv4 CIDRs: $TOTAL"
    echo "#"
    echo "# Sources:"
    echo "# xyzmean/ru-bypass-ipsets"
    echo "# domains.txt"
    echo "# DNS: Google / Cloudflare / Quad9"
    echo

    cat "$ALL"

} > "$OUT"

echo
echo "========== SUMMARY =========="
echo "YouTube:       $YT_COUNT"
echo "Telegram:      $TG_COUNT"
echo "Discord:       $DC_COUNT"
echo "DNS IPv4:      $DNS_COUNT"
echo "Final unique:  $TOTAL"
echo "============================="
