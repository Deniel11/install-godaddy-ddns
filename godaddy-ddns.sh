#!/bin/sh

VERSION="1.2.0"

CONFIG_FILE="/etc/godaddy-ddns.conf"
LOG_FILE="/var/log/godaddy-ddns.log"
SCRIPT_PATH="/usr/local/sbin/godaddy-ddns.sh"

API="https://api.godaddy.com/v3/domains/zones"

log()
{
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

die()
{
    log "ERROR: $*"
    printf '%s\n' "$*" >&2
    exit 1
}

load_config()
{
    if [ ! -f "$CONFIG_FILE" ]; then
        die "Configuration file not found: $CONFIG_FILE"
    fi

    # shellcheck disable=SC1090
    . "$CONFIG_FILE"

    [ -n "$DOMAIN" ] || die "DOMAIN is not configured."
    [ -n "$HOST" ] || die "HOST is not configured."
    [ -n "$TTL" ] || die "TTL is not configured."
    [ -n "$GODADDY_PAT" ] || die "GODADDY_PAT is not configured."
}

check_dependencies()
{
    command -v curl >/dev/null 2>&1 ||
        die "curl is required."

    command -v jq >/dev/null 2>&1 ||
        die "jq is required."
}

get_public_ip()
{
    curl -4 -fsSL "https://ifconfig.me"
}

get_dns_response()
{
    curl -fsSL \
        -H "Accept: application/json" \
        -H "Authorization: Bearer $GODADDY_PAT" \
        "$API/$DOMAIN/dns-records?type=A&name=$HOST"
}

get_dns_ip()
{
    printf '%s' "$1" | jq -r '.items[0].data // empty'
}

get_dns_record_id()
{
    printf '%s' "$1" | jq -r '.items[0].recordId // empty'
}

validate_config()
{
    case "$TTL" in
        *[!0-9]*)
            die "TTL must be a number."
            ;;
    esac

    if [ "$TTL" -lt 600 ] || [ "$TTL" -gt 86400 ]; then
        die "TTL must be between 600 and 86400."
    fi
}

save_config()
{
    umask 077

    cat > "$CONFIG_FILE" <<EOF
DOMAIN='$DOMAIN'
HOST='$HOST'
TTL='$TTL'
GODADDY_PAT='$GODADDY_PAT'
EOF

    chmod 600 "$CONFIG_FILE"
}

configure()
{
    printf 'GoDaddy DDNS configuration\n\n'

    printf 'Domain (example.com): '
    read -r DOMAIN

    printf 'Host (example.com or subdomain): '
    read -r HOST

    printf 'TTL [600]: '
    read -r TTL

    [ -n "$TTL" ] || TTL="600"

    printf 'GoDaddy Personal Access Token: '
    read -r GODADDY_PAT

    [ -n "$DOMAIN" ] || die "Domain cannot be empty."
    [ -n "$HOST" ] || die "Host cannot be empty."
    [ -n "$GODADDY_PAT" ] || die "GoDaddy PAT cannot be empty."

    validate_config
    save_config

    printf '\nConfiguration saved to %s\n' "$CONFIG_FILE"
}

run_ddns()
{
    load_config
    check_dependencies
    validate_config

    CURRENT_IP=$(get_public_ip) ||
        die "Unable to determine public IP."

    [ -n "$CURRENT_IP" ] ||
        die "Public IP lookup returned an empty result."

    DNS_RESPONSE=$(get_dns_response) ||
        die "Unable to retrieve DNS record from GoDaddy."

    DNS_IP=$(get_dns_ip "$DNS_RESPONSE")

    if [ -z "$DNS_IP" ]; then
        die "Unable to determine current DNS IP for $HOST.$DOMAIN."
    fi

    if [ "$CURRENT_IP" = "$DNS_IP" ]; then
        log "No update required. Current IP: $CURRENT_IP"
        exit 0
    fi

    RECORD_ID=$(get_dns_record_id "$DNS_RESPONSE")

    if [ -z "$RECORD_ID" ]; then
        die "Unable to determine GoDaddy DNS record ID."
    fi

    log "IP address changed: $DNS_IP -> $CURRENT_IP"
    log "Updating DNS record ID: $RECORD_ID"

    BODY=$(jq -n \
        --arg name "$HOST" \
        --arg data "$CURRENT_IP" \
        --argjson ttl "$TTL" \
        '{
            name: $name,
            type: "A",
            data: $data,
            ttl: $ttl
        }'
    ) || die "Unable to build DNS update payload."

    RESPONSE_FILE=$(mktemp)

    if curl -fsSL \
        -o "$RESPONSE_FILE" \
        -X PUT \
        -H "Accept: application/json" \
        -H "Authorization: Bearer $GODADDY_PAT" \
        -H "Content-Type: application/json" \
        --data "$BODY" \
        "$API/$DOMAIN/dns-records/$RECORD_ID"
    then
        log "DNS record updated successfully: $CURRENT_IP"
        rm -f "$RESPONSE_FILE"
        exit 0
    else
        log "Failed to update DNS record."
        if [ -s "$RESPONSE_FILE" ]; then
            log "GoDaddy response: $(cat "$RESPONSE_FILE")"
        fi
        rm -f "$RESPONSE_FILE"
        exit 1
    fi
}

check_dns()
{
    load_config
    check_dependencies

    DNS_RESPONSE=$(get_dns_response) ||
        die "Unable to retrieve DNS record from GoDaddy."

    DNS_IP=$(get_dns_ip "$DNS_RESPONSE")

    if [ -z "$DNS_IP" ]; then
        die "Unable to determine current DNS IP."
    fi

    printf 'DNS IP: %s\n' "$DNS_IP"
}

install_script()
{
    if [ "$(id -u)" -ne 0 ]; then
        die "This command must be run as root."
    fi

    mkdir -p "$(dirname "$SCRIPT_PATH")"

    cp "$0" "$SCRIPT_PATH"
    chmod 755 "$SCRIPT_PATH"

    printf 'Installed to %s\n' "$SCRIPT_PATH"
}

update_script()
{
    if [ "$(id -u)" -ne 0 ]; then
        die "This command must be run as root."
    fi

    TMP_FILE=$(mktemp)

    if ! curl -fsSL \
        "https://raw.githubusercontent.com/Deniel11/install-godaddy-ddns/main/godaddy-ddns.sh" \
        -o "$TMP_FILE"
    then
        rm -f "$TMP_FILE"
        die "Unable to download the latest script."
    fi

    if ! grep -q '^VERSION=' "$TMP_FILE"; then
        rm -f "$TMP_FILE"
        die "Downloaded file does not appear to be a valid DDNS script."
    fi

    if [ -f "$SCRIPT_PATH" ]; then
        cp "$SCRIPT_PATH" "$SCRIPT_PATH.bak"
    fi

    cp "$TMP_FILE" "$SCRIPT_PATH"
    chmod 755 "$SCRIPT_PATH"

    rm -f "$TMP_FILE"

    printf 'Script updated: %s\n' "$SCRIPT_PATH"
}

usage()
{
    cat <<EOF
GoDaddy DDNS updater v$VERSION

Usage:
  $0 --configure
  $0 --update
  $0 --check
  $0 --run

Options:
  --configure    Create or update the configuration file.
  --update       Download the latest version from GitHub.
  --check        Show the current GoDaddy DNS IP.
  --run          Update the DNS record if the public IP changed.
  --help         Show this help message.

Configuration:
  $CONFIG_FILE

Log:
  $LOG_FILE
EOF
}

main()
{
    case "${1:-}" in
        --configure)
            configure
            ;;
        --update)
            update_script
            ;;
        --check)
            check_dns
            ;;
        --run)
            run_ddns
            ;;
        --help|-h)
            usage
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"