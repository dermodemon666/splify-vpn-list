#!/bin/sh
set -eu

OUT="splify.lst"

TMP="$(mktemp -d)"
DNS="$TMP/dns.lst"
ALL="$TMP/all.lst"

cleanup() {
    rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

touch "$DNS" "$ALL"

###############################################################################
# DNS discovery
#
# Resolve A records repeatedly. We deliberately store /32 only.
# This means we never turn a shared CDN range (Cloudflare/AWS/etc.) into
# "everything through VPN".
###############################################################################

resolve_domain() {
    domain="$1"

    echo "  $domain"

    # Several queries because CDN DNS answers can rotate.
    i=1
    while [ "$i" -le 3 ]; do
        dig +short A "$domain" 2>/dev/null |
            awk '
                /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {
                    print $0 "/32"
                }
            ' >> "$DNS" || true

        i=$((i + 1))
        sleep 1
    done
}

echo "========== LIVE DNS DISCOVERY =========="

###############################################################################
# YouTube / Google
###############################################################################

echo
echo "YouTube / Google:"

resolve_domain "youtube.com"
resolve_domain "www.youtube.com"
resolve_domain "m.youtube.com"
resolve_domain "youtube-nocookie.com"
resolve_domain "www.youtube-nocookie.com"
resolve_domain "googlevideo.com"
resolve_domain "www.googlevideo.com"
resolve_domain "ytimg.com"
resolve_domain "i.ytimg.com"
resolve_domain "s.ytimg.com"
resolve_domain "youtubei.googleapis.com"

###############################################################################
# Telegram
###############################################################################

echo
echo "Telegram:"

resolve_domain "telegram.org"
resolve_domain "www.telegram.org"
resolve_domain "t.me"
resolve_domain "telegram.me"
resolve_domain "web.telegram.org"
resolve_domain "api.telegram.org"
resolve_domain "core.telegram.org"
resolve_domain "cdn.telegram.org"

###############################################################################
# Discord
#
# Discord voice/video/streaming is intentionally handled separately.
###############################################################################

echo
echo "Discord:"

resolve_domain "discord.com"
resolve_domain "www.discord.com"
resolve_domain "discordapp.com"
resolve_domain "www.discordapp.com"
resolve_domain "discord.gg"
resolve_domain "gateway.discord.gg"
resolve_domain "cdn.discordapp.com"
resolve_domain "media.discordapp.net"
resolve_domain "images-ext-1.discordapp.net"
resolve_domain "images-ext-2.discordapp.net"
resolve_domain "cdn.discordapp.net"
resolve_domain "status.discord.com"

###############################################################################
# AnyDesk
#
# Official AnyDesk documentation recommends *.net.anydesk.com.
# We resolve known infrastructure names individually.
###############################################################################

echo
echo "AnyDesk:"

resolve_domain "anydesk.com"
resolve_domain "www.anydesk.com"
resolve_domain "net.anydesk.com"
resolve_domain "boot-01.net.anydesk.com"
resolve_domain "boot-02.net.anydesk.com"
resolve_domain "boot-03.net.anydesk.com"
resolve_domain "boot-04.net.anydesk.com"
resolve_domain "boot-05.net.anydesk.com"
resolve_domain "boot-06.net.anydesk.com"
resolve_domain "boot-07.net.anydesk.com"
resolve_domain "boot-08.net.anydesk.com"
resolve_domain "boot-09.net.anydesk.com"
resolve_domain "boot-10.net.anydesk.com"

###############################################################################
# WhatsApp / Meta
###############################################################################

echo
echo "WhatsApp / Meta:"

resolve_domain "whatsapp.com"
resolve_domain "www.whatsapp.com"
resolve_domain "web.whatsapp.com"
resolve_domain "whatsapp.net"
resolve_domain "www.whatsapp.net"
resolve_domain "wa.me"
resolve_domain "mmg.whatsapp.net"
resolve_domain "g.whatsapp.net"
resolve_domain "static.whatsapp.net"
resolve_domain "media-fra3-1.cdn.whatsapp.net"

resolve_domain "facebook.com"
resolve_domain "www.facebook.com"
resolve_domain "fb.com"
resolve_domain "fbcdn.net"
resolve_domain "facebook.net"
resolve_domain "messenger.com"

###############################################################################
# Instagram
###############################################################################

echo
echo "Instagram:"

resolve_domain "instagram.com"
resolve_domain "www.instagram.com"
resolve_domain "cdninstagram.com"
resolve_domain "www.cdninstagram.com"

###############################################################################
# X / Twitter
###############################################################################

echo
echo "X / Twitter:"

resolve_domain "x.com"
resolve_domain "www.x.com"
resolve_domain "twitter.com"
resolve_domain "www.twitter.com"
resolve_domain "t.co"
resolve_domain "twimg.com"
resolve_domain "pbs.twimg.com"
resolve_domain "video.twimg.com"

###############################################################################
# Proton
###############################################################################

echo
echo "Proton:"

resolve_domain "proton.me"
resolve_domain "www.proton.me"
resolve_domain "account.proton.me"
resolve_domain "mail.proton.me"
resolve_domain "drive.proton.me"
resolve_domain "calendar.proton.me"
resolve_domain "pass.proton.me"
resolve_domain "vpn.proton.me"
resolve_domain "api.proton.me"
resolve_domain "protonmail.com"
resolve_domain "protonmail.ch"
resolve_domain "pm.me"

###############################################################################
# 9GAG
#
# Do NOT add the whole Cloudflare network.
# Discover the actual addresses returned for 9GAG and its own assets.
###############################################################################

echo
echo "9GAG:"

resolve_domain "9gag.com"
resolve_domain "www.9gag.com"
resolve_domain "9cache.com"
resolve_domain "9gag.net"
resolve_domain "img-9gag-fun.9cache.com"

###############################################################################
# Blur Busters / TestUFO
###############################################################################

echo
echo "Blur Busters / TestUFO:"

resolve_domain "blurbusters.com"
resolve_domain "www.blurbusters.com"
resolve_domain "forums.blurbusters.com"
resolve_domain "testufo.com"
resolve_domain "www.testufo.com"
resolve_domain "old.testufo.com"

###############################################################################
# Rutracker
###############################################################################

echo
echo "Rutracker:"

resolve_domain "rutracker.org"
resolve_domain "www.rutracker.org"
resolve_domain "rutracker.net"
resolve_domain "www.rutracker.net"

###############################################################################
# Reddit
###############################################################################

echo
echo "Reddit:"

resolve_domain "reddit.com"
resolve_domain "www.reddit.com"
resolve_domain "old.reddit.com"
resolve_domain "redditmedia.com"
resolve_domain "redditstatic.com"
resolve_domain "redd.it"
resolve_domain "i.redd.it"
resolve_domain "v.redd.it"

###############################################################################
# Custom domains from domains.txt
###############################################################################

if [ -f domains.txt ]; then
    echo
    echo "========== domains.txt =========="

    while IFS= read -r domain; do
        case "$domain" in
            ""|\#*) continue ;;
        esac

        resolve_domain "$domain"

    done < domains.txt
fi

###############################################################################
# Download ONLY YouTube/Telegram fallback lists.
#
# Discord is deliberately no longer taken from xyzmean.
###############################################################################

echo
echo "========== FALLBACK LISTS =========="

YT="$TMP/youtube.lst"
TG="$TMP/telegram.lst"

echo "Downloading YouTube fallback..."
curl -fsSL \
    "https://raw.githubusercontent.com/xyzmean/ru-bypass-ipsets/main/lists/youtube.lst" \
    > "$YT"

echo "Downloading Telegram fallback..."
curl -fsSL \
    "https://raw.githubusercontent.com/xyzmean/ru-bypass-ipsets/main/lists/telegram.lst" \
    > "$TG"

###############################################################################
# Combine
###############################################################################

cat "$YT" "$TG" "$DNS" |
    awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }

        /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$/ {

            # Google public DNS must remain DIRECT.
            if ($0 == "8.8.4.0/24") next
            if ($0 == "8.8.8.0/24") next

            print
        }
    ' |
sort -u > "$ALL"

###############################################################################
# Statistics
###############################################################################

YT_COUNT=$(grep -Ec '^[0-9]+\.' "$YT" || true)
TG_COUNT=$(grep -Ec '^[0-9]+\.' "$TG" || true)
DNS_COUNT=$(grep -Ec '^[0-9]+\.' "$DNS" || true)
TOTAL=$(wc -l < "$ALL" | tr -d ' ')

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

###############################################################################
# Write result
###############################################################################

{
    echo "# splify custom IP list"
    echo "# Generated automatically"
    echo "#"
    echo "# YouTube fallback: $YT_COUNT entries"
    echo "# Telegram fallback: $TG_COUNT entries"
    echo "# Live DNS discovery: $DNS_COUNT entries"
    echo "# Final unique IPv4 CIDRs: $TOTAL"
    echo "#"
    echo "# IMPORTANT:"
    echo "# Discord is discovered by DNS rather than using a third-party IP list."
    echo "# AnyDesk uses live DNS discovery of its infrastructure."
    echo "# 9GAG uses live DNS discovery; no entire Cloudflare ranges are included."
    echo "#"
    echo "# Google DNS 8.8.4.0/24 and 8.8.8.0/24 are explicitly excluded."
    echo

    cat "$ALL"

} > "$OUT"

echo
echo "========== SUMMARY =========="
echo "YouTube fallback: $YT_COUNT"
echo "Telegram fallback: $TG_COUNT"
echo "Live DNS:          $DNS_COUNT"
echo "Final unique:      $TOTAL"
echo "============================="
