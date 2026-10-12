#!/bin/sh
set -eu

REPO_RAW="https://raw.githubusercontent.com/Deniel11/install-godaddy-ddns/main"
TARGET="/usr/local/sbin/godaddy-ddns.sh"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TMP="${TMPDIR:-/tmp}/godaddy-ddns.sh.$$"

cleanup() {
    rm -f "$TMP"
}
trap cleanup EXIT HUP INT TERM

[ "$(id -u)" -eq 0 ] || { printf 'Root privileges are required.\n' >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { printf 'Missing dependency: curl\n' >&2; exit 1; }
command -v sh >/dev/null 2>&1 || { printf 'Missing dependency: sh\n' >&2; exit 1; }

if [ -f "$SCRIPT_DIR/godaddy-ddns.sh" ]; then
    cp "$SCRIPT_DIR/godaddy-ddns.sh" "$TMP"
else
    curl -fsSL "$REPO_RAW/godaddy-ddns.sh" -o "$TMP"
fi
[ -s "$TMP" ] || { printf 'The downloaded file is empty.\n' >&2; exit 1; }
grep -q '^VERSION=' "$TMP" || { printf 'The downloaded file is not a valid DDNS script.\n' >&2; exit 1; }
sh -n "$TMP" || { printf 'The downloaded script has a syntax error.\n' >&2; exit 1; }
chmod 700 "$TMP"
mkdir -p "${TARGET%/*}"
if [ -f "$TARGET" ]; then
    cp "$TARGET" "$TARGET.bak.$(date '+%Y%m%d%H%M%S')"
fi
mv "$TMP" "$TARGET"
chmod 700 "$TARGET"

if [ ! -f /etc/godaddy-ddns.conf ]; then
    "$TARGET" --configure
else
    printf 'Existing configuration preserved: /etc/godaddy-ddns.conf\n'
fi

"$TARGET" --install-action
printf 'Installation complete. Check status with: %s --check\n' "$TARGET"
