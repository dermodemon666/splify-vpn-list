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
DNS="$TMP/dns.lst"
ALL="$TMP/all.lst"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

echo "======================================"
echo " splify IP list generator"
echo "======================================"
echo

echo "Downloading original ipsum list..."
curl -fsSL "$IPSUM_URL" > "$IPSUM"

echo "Downloading YouTube list..."
curl -fsSL \
    "https://raw.githubusercontent.com/xyzmean/ru-bypass-ipsets/main/lists/youtube.lst" \
    > "$YT"

echo "Downloading Telegram list..."
curl -fsSL \
    "https://raw.githubusercontent.com/xyzmean/ru-bypass-ipsets/main/lists/telegram.lst" \
    > "$TG"

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

# Do NOT add the complete Cloudflare IPv4 feed here.
# Discord uses Cloudflare Edge extensively, but routing every Cloudflare
# address through WARP would also catch unrelated services.
#
# We therefore use:
#   1. Discord-specific IP lists;
#   2. Discord-specific service DNS;
#   3. the original ipsum list.
#
# This keeps the additional coverage narrow instead of routing arbitrary
# Cloudflare-hosted traffic through WARP.

echo
echo "Resolving Discord, 9GAG and AnyDesk service domains..."

resolve_domain() {
    domain="$1"
    echo "  $domain" >&2

    dig @1.1.1.1 +short A "$domain" 2>/dev/null || true
    dig @8.8.8.8 +short A "$domain" 2>/dev/null || true
    dig @9.9.9.9 +short A "$domain" 2>/dev/null || true
}

# Discord service endpoints.
#
# These cover the web client, gateway, CDN/media endpoints and common
# service domains that are not necessarily represented by the IP lists.
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

# 9GAG service endpoints.
#
# Keep this domain-specific. Do NOT add generic CDN/Cloudflare networks,
# because that would route unrelated websites through WARP.
NINEGAG_DOMAINS="
9gag.com
www.9gag.com
9gag.net
www.9gag.net
9cache.com
www.9cache.com
"

# AnyDesk service endpoints.
#
# AnyDesk uses *.net.anydesk.com for its service infrastructure.
# There is no reason to route the entire hosting/CDN provider through WARP,
# so resolve the known service names individually.
ANYDESK_DOMAINS="
anydesk.com
www.anydesk.com
net.anydesk.com
relay.net.anydesk.com
api.net.anydesk.com
client.net.anydesk.com
my.anydesk.com
boot-01.net.anydesk.com
boot-02.net.anydesk.com
boot-03.net.anydesk.com
boot-04.net.anydesk.com
boot-05.net.anydesk.com
boot-06.net.anydesk.com
boot-07.net.anydesk.com
boot-08.net.anydesk.com
boot-09.net.anydesk.com
boot-10.net.anydesk.com
"

for domain in $DISCORD_DOMAINS $NINEGAG_DOMAINS $ANYDESK_DOMAINS; do
    resolve_domain "$domain" >> "$DNS"
done

# Every downloaded list must contain actual IPv4 CIDRs.
for file in "$IPSUM" "$YT" "$TG" "$DC" "$DCVOICE"; do
    if ! grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' "$file"; then
        echo "ERROR: source list contains no valid IPv4 CIDRs: $file"
        exit 1
    fi
done

# DNS resolver output is plain IPv4 addresses. Convert them to /32.
awk '
    /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {
        print $0 "/32"
    }
' "$DNS" | sort -u > "$TMP/dns-clean.lst"

# Build the exact union.
#
# IMPORTANT:
# The original ipsum list remains a complete base source.
# Additional sources are added on top of it.
#
# No broad Cloudflare feed is included.
cat \
    "$IPSUM" \
    "$YT" \
    "$TG" \
    "$DC" \
    "$DCVOICE" \
    "$TMP/dns-clean.lst" |
awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$/ {
        print
    }
' |
sort -u > "$TMP/raw.lst"

# Collapse only when coverage remains EXACTLY the same.
#
# ipaddress.collapse_addresses() removes:
#   - duplicate networks;
#   - networks already covered by a larger network;
#   - adjacent networks that can be represented by a larger aligned CIDR.
#
# It does NOT intentionally widen the list.
python3 - "$TMP/raw.lst" "$ALL" <<'PY'
import ipaddress
import sys

src, dst = sys.argv[1:]

networks = []

with open(src, encoding="utf-8") as f:
    for line in f:
        line = line.strip()

        if not line:
            continue

        try:
            network = ipaddress.ip_network(line, strict=False)
        except ValueError:
            continue

        if network.version != 4:
            continue

        # Never route public Google DNS through this WARP list.
        #
        # These addresses are commonly used as DNS targets and should remain
        # directly reachable.
        if network.subnet_of(ipaddress.ip_network("8.8.8.0/24")):
            continue

        if network.subnet_of(ipaddress.ip_network("8.8.4.0/24")):
            continue

        networks.append(network)

collapsed = ipaddress.collapse_addresses(networks)

with open(dst, "w", encoding="utf-8") as out:
    for network in collapsed:
        if network.version == 4:
            out.write(f"{network}\n")
PY

# Statistics.
IPSUM_COUNT=$(grep -Ec '^[0-9]+\.' "$IPSUM" || true)
YT_COUNT=$(grep -Ec '^[0-9]+\.' "$YT" || true)
TG_COUNT=$(grep -Ec '^[0-9]+\.' "$TG" || true)
DC_COUNT=$(grep -Ec '^[0-9]+\.' "$DC" || true)
DCVOICE_COUNT=$(grep -Ec '^[0-9]+\.' "$DCVOICE" || true)
DNS_COUNT=$(grep -Ec '^[0-9]+\.' "$TMP/dns-clean.lst" || true)
TOTAL=$(wc -l < "$ALL" | tr -d ' ')

# Safety check: Google DNS must not accidentally survive aggregation.
if grep -qE '^8\.8\.(4|8)\.0/24$' "$ALL"; then
    echo "ERROR: Google DNS range is still present"
    exit 1
fi

# Final file.
{
    echo "# splify custom IP list"
    echo "# Generated automatically"
    echo "# Exact union + lossless CIDR aggregation; no broad Cloudflare feed"
    echo "#"
    echo "# Original ipsum source: $IPSUM_URL"
    echo "# Original ipsum:            $IPSUM_COUNT entries"
    echo "# YouTube source:            $YT_COUNT entries"
    echo "# Telegram source:           $TG_COUNT entries"
    echo "# Discord source:            $DC_COUNT entries"
    echo "# Discord Voice source:      $DCVOICE_COUNT entries"
    echo "# Discord/9GAG/AnyDesk DNS:  $DNS_COUNT entries"
    echo "# Final aggregated IPv4:     $TOTAL"
    echo "#"
    echo "# Sources:"
    echo "# 1andrevich/Re-filter-lists (ipsum.lst)"
    echo "# xyzmean/ru-bypass-ipsets (YouTube/Telegram)"
    echo "# fildunsky/clash_discord"
    echo "# 123jjck/cdn-ip-ranges/discord-voice"
    echo "# Discord service DNS"
    echo "# 9GAG service DNS"
    echo "# AnyDesk service DNS (*.net.anydesk.com)"
    echo
    cat "$ALL"
} > "$OUT"

echo
echo "========== SUMMARY =========="
echo "Original ipsum:       $IPSUM_COUNT"
echo "YouTube:              $YT_COUNT"
echo "Telegram:             $TG_COUNT"
echo "Discord:              $DC_COUNT"
echo "Discord Voice:        $DCVOICE_COUNT"
echo "Discord/9GAG/AnyDesk: $DNS_COUNT"
echo "Final aggregated:     $TOTAL"
echo "============================="
