#!/bin/sh
set -eu

OUT="splify.lst"
IPSUM_URL="https://raw.githubusercontent.com/1andrevich/Re-filter-lists/master/ipsum.lst"

TMP="$(mktemp -d)"
IPSUM="$TMP/ipsum.lst"
YT="$TMP/youtube.lst"
TG="$TMP/telegram.lst"
DC="$TMP/discord.lst"
DCVOICE="$TMP/discord-voice.lst"
CF="$TMP/cloudflare.lst"
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
# Original ipsum list
# ------------------------------------------------------------
echo "Downloading original ipsum list..."
curl -fsSL "$IPSUM_URL" > "$IPSUM"

# ------------------------------------------------------------
# YouTube
# ------------------------------------------------------------
echo "Downloading YouTube list..."
curl -fsSL \
    "https://raw.githubusercontent.com/xyzmean/ru-bypass-ipsets/main/lists/youtube.lst" \
    > "$YT"

# ------------------------------------------------------------
# Telegram
# ------------------------------------------------------------
echo "Downloading Telegram list..."
curl -fsSL \
    "https://raw.githubusercontent.com/xyzmean/ru-bypass-ipsets/main/lists/telegram.lst" \
    > "$TG"

# ------------------------------------------------------------
# Discord IP sources
# ------------------------------------------------------------
echo "Downloading Discord IP list..."
curl -fsSL \
    "https://raw.githubusercontent.com/fildunsky/clash_discord/main/discord-ip.yaml" |
    sed -n 's/^[[:space:]]*-[[:space:]]*IP-CIDR,\([^,]*\).*$/\1/p' |
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' |
    sort -u > "$DC"

echo "Downloading Discord Voice list..."
curl -fsSL \
    "https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/discord-voice/discord-voice_plain_ipv4.txt" |
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' |
    sort -u > "$DCVOICE"

# ------------------------------------------------------------
# Discord Voice/Video now predominantly runs on Cloudflare Edge.
# Keep the current Cloudflare IPv4 feed in the generated list so
# Discord Go Live / video traffic is not lost when Discord changes
# edge addresses. This is deliberately a live feed, not a hardcoded
# snapshot.
# ------------------------------------------------------------
echo "Downloading Cloudflare IPv4 ranges..."
curl -fsSL \
    "https://www.cloudflare.com/ips-v4" |
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' |
    sort -u > "$CF"

# ------------------------------------------------------------
# Resolve service domains to IPv4.
#
# AnyDesk does not publish a stable, dedicated IPv4 CIDR feed. Its
# official firewall documentation instead requires *.net.anydesk.com.
# We therefore resolve the service domains at generation time rather
# than inventing static AnyDesk CIDRs that can go stale.
# ------------------------------------------------------------
echo
echo "Resolving Discord and AnyDesk service domains..."

resolve_domain() {
    domain="$1"
    echo "  $domain" >&2
    dig @1.1.1.1 +short A "$domain" 2>/dev/null || true
    dig @8.8.8.8 +short A "$domain" 2>/dev/null || true
    dig @9.9.9.9 +short A "$domain" 2>/dev/null || true
}

DISCORD_DOMAINS="
discord.com
www.discord.com
discord.gg
gateway.discord.gg
cdn.discordapp.com
media.discordapp.net
images-ext-1.discordapp.net
images-ext-2.discordapp.net
discordapp.com
discord.media
latency.discord.media
discord.co
dis.gd
discord.new
discord.gift
discord.gifts
discord.dev
discord.store
discordstatus.com
"

# Official AnyDesk firewall requirement: *.net.anydesk.com.
# Include the apex/service names most commonly used by clients.
ANYDESK_DOMAINS="
net.anydesk.com
anydesk.com
www.anydesk.com
relay.net.anydesk.com
api.net.anydesk.com
client.net.anydesk.com
my.anydesk.com
"

for domain in $DISCORD_DOMAINS $ANYDESK_DOMAINS; do
    resolve_domain "$domain" >> "$DNS"
done

# ------------------------------------------------------------
# Validate source lists
# ------------------------------------------------------------
for file in "$IPSUM" "$YT" "$TG" "$DC" "$DCVOICE" "$CF"; do
    if ! grep -Eq \
        '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' \
        "$file"
    then
        echo "ERROR: source list contains no valid IPv4 CIDRs:"
        echo "$file"
        exit 1
    fi
done

# ------------------------------------------------------------
# Normalize DNS results
# ------------------------------------------------------------
awk '
    /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print $0 "/32" }
' "$DNS" | sort -u > "$TMP/dns-clean.lst"

# ------------------------------------------------------------
# Combine everything
# ------------------------------------------------------------
# Original ipsum remains the base list. Everything else is additive.
cat \
    "$IPSUM" \
    "$YT" \
    "$TG" \
    "$DC" \
    "$DCVOICE" \
    "$CF" \
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
' | sort -u > "$ALL"

# ------------------------------------------------------------
# Statistics
# ------------------------------------------------------------
IPSUM_COUNT=$(grep -Ec '^[0-9]+\.' "$IPSUM" || true)
YT_COUNT=$(grep -Ec '^[0-9]+\.' "$YT" || true)
TG_COUNT=$(grep -Ec '^[0-9]+\.' "$TG" || true)
DC_COUNT=$(grep -Ec '^[0-9]+\.' "$DC" || true)
DCVOICE_COUNT=$(grep -Ec '^[0-9]+\.' "$DCVOICE" || true)
CF_COUNT=$(grep -Ec '^[0-9]+\.' "$CF" || true)
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
fi
if grep -qx '8.8.8.0/24' "$ALL"; then
    echo "ERROR: 8.8.8.0/24 is still present!"
    exit 1
fi
echo "OK: Google DNS ranges excluded"
echo "===================================="

# ------------------------------------------------------------
# Generate final list
# ------------------------------------------------------------
{
    echo "# splify custom IP list"
    echo "# Generated automatically"
    echo "#"
    echo "# Original ipsum source: $IPSUM_URL"
    echo "# Original ipsum:       $IPSUM_COUNT entries"
    echo "# YouTube source:       $YT_COUNT entries"
    echo "# Telegram source:      $TG_COUNT entries"
    echo "# Discord source:       $DC_COUNT entries"
    echo "# Discord Voice source: $DCVOICE_COUNT entries"
    echo "# Cloudflare IPv4:      $CF_COUNT entries"
    echo "# Discord/AnyDesk DNS:  $DNS_COUNT entries"
    echo "# Final unique IPv4:    $TOTAL"
    echo "#"
    echo "# Sources:"
    echo "# 1andrevich/Re-filter-lists (ipsum.lst)"
    echo "# xyzmean/ru-bypass-ipsets"
    echo "# fildunsky/clash_discord"
    echo "# 123jjck/cdn-ip-ranges/discord-voice"
    echo "# Cloudflare IPv4"
    echo "# Discord service DNS"
    echo "# AnyDesk service DNS (*.net.anydesk.com)"
    echo
    cat "$ALL"
} > "$OUT"

echo
echo "========== SUMMARY =========="
echo "Original ipsum:   $IPSUM_COUNT"
echo "YouTube:          $YT_COUNT"
echo "Telegram:         $TG_COUNT"
echo "Discord:          $DC_COUNT"
echo "Discord Voice:    $DCVOICE_COUNT"
echo "Cloudflare IPv4:  $CF_COUNT"
echo "Discord/AnyDesk:  $DNS_COUNT"
echo "Final unique:     $TOTAL"
echo "============================="
