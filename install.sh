#!/bin/sh

# GoDaddy DDNS for OPNsense
# GitHub installer / updater

set -eu

REPO_RAW="https://raw.githubusercontent.com/Deniel11/install-godaddy-ddns/main"

TARGET="/usr/local/sbin/godaddy-ddns.sh"
TMP="/tmp/godaddy-ddns.sh.$$"

cleanup()
{
    rm -f "$TMP"
}

trap cleanup EXIT INT TERM

command -v curl >/dev/null 2>&1 || {
    echo "ERROR: curl is required."
    exit 1
}

echo "Downloading GoDaddy DDNS script..."

if ! curl -fsSL -o "$TMP" "${REPO_RAW}/godaddy-ddns.sh"; then
    echo "ERROR: Could not download godaddy-ddns.sh"
    exit 1
fi

if [ ! -s "$TMP" ]; then
    echo "ERROR: Downloaded file is empty."
    exit 1
fi

if ! grep -q 'GoDaddy Dynamic DNS for OPNsense' "$TMP"; then
    echo "ERROR: Downloaded file does not look like the expected script."
    exit 1
fi

chmod 700 "$TMP"
mkdir -p /usr/local/sbin

if [ -f "$TARGET" ]; then
    cp "$TARGET" "${TARGET}.bak"
fi

mv "$TMP" "$TARGET"
chmod 700 "$TARGET"

echo ""
echo "Installed:"
echo "  $TARGET"
echo ""

if [ ! -f /etc/godaddy-ddns.conf ]; then
    "$TARGET" --configure
else
    echo "Existing configuration detected."
    echo "Configuration was preserved."
    echo ""
    echo "Run this to change it:"
    echo "  $TARGET --configure"
fi

echo ""
echo "Installation/update complete."
