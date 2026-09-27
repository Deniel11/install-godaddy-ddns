#!/bin/sh

# GoDaddy Dynamic DNS for OPNsense

VERSION="1.1.0"

CONFIG="/etc/godaddy-ddns.conf"
LOG="/var/log/godaddy-ddns.log"
TARGET="/usr/local/sbin/godaddy-ddns.sh"

REPO_RAW="https://raw.githubusercontent.com/Deniel11/install-godaddy-ddns/main"

DEFAULT_DOMAIN="your.domain"
DEFAULT_HOST="vpn"
DEFAULT_TTL="600"

umask 077

die()
{
    echo "ERROR: $*" >&2
    exit 1
}

require_command()
{
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

load_config()
{
    [ -f "$CONFIG" ] || return 0
    . "$CONFIG"
}

save_config()
{
    umask 077
    cat > "$CONFIG" <<EOF
DOMAIN='$DOMAIN'
HOST='$HOST'
TTL='$TTL'
GODADDY_PAT='$GODADDY_PAT'
EOF
    chmod 600 "$CONFIG"
}

ask_value()
{
    LABEL="$1"
    CURRENT="$2"
    DEFAULT="$3"

    if [ -n "$CURRENT" ]; then
        printf "%s [%s]: " "$LABEL" "$CURRENT" > /dev/tty
    else
        printf "%s [%s]: " "$LABEL" "$DEFAULT" > /dev/tty
    fi

    read -r VALUE < /dev/tty

    if [ -z "$VALUE" ]; then
        if [ -n "$CURRENT" ]; then
            VALUE="$CURRENT"
        else
            VALUE="$DEFAULT"
        fi
    fi

    printf '%s' "$VALUE"
}
configure()
{
    OLD_DOMAIN="${DOMAIN:-}"
    OLD_HOST="${HOST:-}"
    OLD_TTL="${TTL:-}"
    OLD_PAT="${GODADDY_PAT:-}"

    echo ""
    echo "======================================"
    echo " GoDaddy Dynamic DNS configuration"
    echo "======================================"
    echo ""

    DOMAIN=$(ask_value "Domain" "$OLD_DOMAIN" "$DEFAULT_DOMAIN")
    echo ""

    HOST=$(ask_value "Host" "$OLD_HOST" "$DEFAULT_HOST")
    echo ""

    TTL=$(ask_value "TTL" "$OLD_TTL" "$DEFAULT_TTL")
    echo ""

    if [ -n "$OLD_PAT" ]; then
        printf "GoDaddy Personal Access Token [configured]: "
        read -r NEW_PAT
        if [ -n "$NEW_PAT" ]; then
            GODADDY_PAT="$NEW_PAT"
        else
            GODADDY_PAT="$OLD_PAT"
        fi
    else
        printf "GoDaddy Personal Access Token: "
        read -r GODADDY_PAT
    fi

    echo ""

    [ -n "$DOMAIN" ] || die "Domain cannot be empty."
    [ -n "$HOST" ] || die "Host cannot be empty."
    [ -n "$TTL" ] || die "TTL cannot be empty."
    [ -n "$GODADDY_PAT" ] || die "GoDaddy Personal Access Token cannot be empty."

    case "$TTL" in
        *[!0-9]*) die "TTL must contain only numbers." ;;
    esac

    echo "Configuration:"
    echo "  DOMAIN = $DOMAIN"
    echo "  HOST   = $HOST"
    echo "  TTL    = $TTL"
    echo "  PAT    = ********"
    echo ""

    printf "Save configuration? [Y/n]: "
    read -r CONFIRM

    case "$CONFIRM" in
        n|N|no|NO)
            echo "Cancelled."
            exit 0
            ;;
    esac

    save_config

    echo ""
    echo "Configuration saved to:"
    echo "  $CONFIG"
}

check_dependencies()
{
    require_command curl
    require_command jq
}

get_public_ip()
{
    curl -fsSL "https://api.ipify.org"
}

get_dns_response()
{
    curl -fsSL \
        -H "Authorization: sso-key $GODADDY_PAT" \
        "$API?type=A&name=$HOST"
}

get_dns_ip()
{
    printf '%s' "$1" | jq -r '.items[0].data // empty'
}

run_ddns()
{
    load_config

    [ -n "${DOMAIN:-}" ] || die "No configuration found. Run: $TARGET --configure"
    [ -n "${HOST:-}" ] || die "HOST is missing from configuration."
    [ -n "${TTL:-}" ] || die "TTL is missing from configuration."
    [ -n "${GODADDY_PAT:-}" ] || die "GODADDY_PAT is missing from configuration."

    check_dependencies

    API="https://api.godaddy.com/v3/domains/zones/${DOMAIN}/dns-records"

    CURRENT_IP=$(get_public_ip) || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Could not determine public IP" >> "$LOG"
        exit 1
    }

    DNS_RESPONSE=$(get_dns_response) || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Could not read DNS record" >> "$LOG"
        exit 1
    }

    DNS_IP=$(get_dns_ip "$DNS_RESPONSE")

    if [ -z "$DNS_IP" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Could not parse DNS A record" >> "$LOG"
        echo "$DNS_RESPONSE" >> "$LOG"
        exit 1
    fi

    if [ "$CURRENT_IP" = "$DNS_IP" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') OK: IP unchanged: $CURRENT_IP" >> "$LOG"
        exit 0
    fi

    BODY="[\"{\\"data\\":\\"${CURRENT_IP}\\",\\"ttl\\":${TTL}}\"]"
    RESPONSE_FILE="/tmp/godaddy-ddns-response.$$.json"

    if curl -fsSL -o "$RESPONSE_FILE" \
        -X PUT \
        -H "Authorization: sso-key $GODADDY_PAT" \
        -H "Content-Type: application/json" \
        --data "$BODY" \
        "$API?type=A&name=$HOST"
    then
        echo "$(date '+%Y-%m-%d %H:%M:%S') UPDATED: $DNS_IP -> $CURRENT_IP" >> "$LOG"
        rm -f "$RESPONSE_FILE"
        exit 0
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: GoDaddy DNS update failed" >> "$LOG"
        [ -f "$RESPONSE_FILE" ] && cat "$RESPONSE_FILE" >> "$LOG"
        rm -f "$RESPONSE_FILE"
        exit 1
    fi
}

check()
{
    load_config

    [ -n "${DOMAIN:-}" ] || die "No configuration found. Run: $TARGET --configure"
    [ -n "${HOST:-}" ] || die "HOST is missing from configuration."
    [ -n "${GODADDY_PAT:-}" ] || die "GODADDY_PAT is missing from configuration."

    check_dependencies

    API="https://api.godaddy.com/v3/domains/zones/${DOMAIN}/dns-records"

    CURRENT_IP=$(get_public_ip) || die "Could not determine public IP."
    DNS_RESPONSE=$(get_dns_response) || die "Could not read GoDaddy DNS record."
    DNS_IP=$(get_dns_ip "$DNS_RESPONSE")

    echo ""
    echo "Domain : $DOMAIN"
    echo "Host   : $HOST"
    echo "Public : $CURRENT_IP"
    echo "DNS    : ${DNS_IP:-not found}"
    echo ""

    if [ "$CURRENT_IP" = "$DNS_IP" ]; then
        echo "Status : OK - IP is unchanged"
    else
        echo "Status : UPDATE REQUIRED"
    fi
}

update_script()
{
    TMP="/tmp/godaddy-ddns-update.$$.sh"

    echo "Downloading latest version from GitHub..."

    if ! curl -fsSL -o "$TMP" "${REPO_RAW}/godaddy-ddns.sh"; then
        rm -f "$TMP"
        die "Could not download latest version."
    fi

    [ -s "$TMP" ] || {
        rm -f "$TMP"
        die "Downloaded file is empty."
    }

    grep -q 'GoDaddy Dynamic DNS for OPNsense' "$TMP" || {
        rm -f "$TMP"
        die "Downloaded file does not look like the expected script."
    }

    chmod 700 "$TMP"

    if [ -f "$TARGET" ]; then
        cp "$TARGET" "${TARGET}.bak"
    fi

    mv "$TMP" "$TARGET"
    chmod 700 "$TARGET"

    echo "Updated: $TARGET"
    echo "Configuration preserved: $CONFIG"
}

usage()
{
    cat <<EOF
GoDaddy DDNS for OPNsense

Usage:
  $TARGET                 Update DNS if public IP changed
  $TARGET --configure     Configure or reconfigure
  $TARGET --check         Check public IP and DNS without updating
  $TARGET --update        Download the latest script from GitHub
  $TARGET --version       Show version
  $TARGET --help          Show this help

Configuration:
  $CONFIG

Log:
  $LOG
EOF
}

main()
{
    case "${1:-}" in
        --configure|-c)
            load_config
            configure
            ;;
        --check)
            check
            ;;
        --update)
            update_script
            ;;
        --version|-v)
            echo "$VERSION"
            ;;
        --help|-h)
            usage
            ;;
        "")
            run_ddns
            ;;
        *)
            echo "Unknown option: $1"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"
