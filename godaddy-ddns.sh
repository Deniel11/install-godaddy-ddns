#!/bin/sh

VERSION="2.0.0"
CONFIG_FILE="/etc/godaddy-ddns.conf"
LOG_FILE="/var/log/godaddy-ddns.log"
SCRIPT_PATH="/usr/local/sbin/godaddy-ddns.sh"
OPNSENSE_ACTION_FILE="/usr/local/opnsense/service/conf/actions.d/actions_godaddy_ddns.conf"
API="https://api.godaddy.com/v3/domains/zones"
API_BODY=""
HTTP_CODE=""
TEMP_BODY=""

log() {
    MESSAGE="$*"
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    printf '%s %s\n' "$TIMESTAMP" "$MESSAGE" | tee -a "$LOG_FILE"
}

fail() {
    log "ERROR: $*"
    exit 1
}

need_tty() {
    [ -r /dev/tty ] && [ -w /dev/tty ] || fail "An interactive terminal is required for configuration."
}

ask() {
    ASK_PROMPT=$1
    ASK_DEFAULT=${2-}
    if [ -n "$ASK_DEFAULT" ]; then
        printf '%s [%s]: ' "$ASK_PROMPT" "$ASK_DEFAULT" > /dev/tty
    else
        printf '%s: ' "$ASK_PROMPT" > /dev/tty
    fi
    IFS= read -r ASK_VALUE < /dev/tty || fail "Could not read the input."
    if [ -z "$ASK_VALUE" ]; then
        ASK_VALUE=$ASK_DEFAULT
    fi
}

ask_secret() {
    need_tty
    printf '%s' "$1" > /dev/tty
    stty -echo < /dev/tty 2>/dev/null || true
    IFS= read -r ASK_VALUE < /dev/tty || ASK_VALUE=""
    stty echo < /dev/tty 2>/dev/null || true
    printf '\n' > /dev/tty
}

shell_quote() {
    printf "'"
    printf '%s' "$1" | sed "s/'/'\\\\''/g"
    printf "'"
}

valid_zone() {
    printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$'
}

valid_host() {
    [ "$1" = "@" ] && return 0
    printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9*]([A-Za-z0-9*-]*[A-Za-z0-9*])?(\.[A-Za-z0-9*]([A-Za-z0-9*-]*[A-Za-z0-9*])?)*$'
}

valid_ipv4() {
    case "$1" in
        ''|.*|*.|*..*|*[!0-9.]* ) return 1 ;;
    esac
    IPV4_OLD_IFS=$IFS
    IFS=.
    set -- $1
    IFS=$IPV4_OLD_IFS
    [ "$#" -eq 4 ] || return 1
    for IPV4_PART do
        case "$IPV4_PART" in ''|*[!0-9]*) return 1 ;; esac
        [ "${#IPV4_PART}" -le 3 ] || return 1
        [ "$IPV4_PART" -le 255 ] 2>/dev/null || return 1
    done
    return 0
}

is_public_ipv4() {
    valid_ipv4 "$1" || return 1

    case "$1" in
        0.*|10.*|127.*|169.254.*|192.0.0.*|192.0.2.*|192.168.*|198.18.*|198.19.*|198.51.100.*|203.0.113.*)
            return 1
            ;;
    esac

    IP_OLD_IFS=$IFS
    IFS=.
    set -- $1
    IFS=$IP_OLD_IFS

    [ "$1" -lt 224 ] || return 1

    if [ "$1" -eq 172 ] && [ "$2" -ge 16 ] && [ "$2" -le 31 ]; then
        return 1
    fi

    if [ "$1" -eq 100 ] && [ "$2" -ge 64 ] && [ "$2" -le 127 ]; then
        return 1
    fi

    return 0
}

validate_ttl() {
    case "$TTL" in ''|*[!0-9]*) return 1 ;; esac
    [ "$TTL" -ge 600 ] 2>/dev/null && [ "$TTL" -le 86400 ] 2>/dev/null
}

normalize_legacy_host() {
    LEGACY_HOST=$1
    LEGACY_DOMAIN=$2
    if [ "$LEGACY_HOST" = "$LEGACY_DOMAIN" ]; then
        printf '@'
    elif [ "$LEGACY_HOST" = "*.$LEGACY_DOMAIN" ]; then
        printf '*'
    elif [ "$LEGACY_HOST" = *".$LEGACY_DOMAIN" ]; then
        printf '%s' "${LEGACY_HOST%.$LEGACY_DOMAIN}"
    else
        printf '%s' "$LEGACY_HOST"
    fi
}

load_config() {
    [ -f "$CONFIG_FILE" ] || fail "Configuration file not found: $CONFIG_FILE. Run: $0 --configure"
    DOMAIN=""
    HOST=""
    TTL="600"
    GODADDY_PAT=""
    RECORDS=""
    . "$CONFIG_FILE"
    if [ -z "$RECORDS" ] && [ -n "$DOMAIN" ] && [ -n "$HOST" ]; then
        LEGACY_NORMALIZED=$(normalize_legacy_host "$HOST" "$DOMAIN")
        RECORDS="$DOMAIN|$LEGACY_NORMALIZED"
    fi
    [ -n "$RECORDS" ] || fail "The configuration does not contain a RECORDS setting. Run: $0 --configure"
    [ -n "$GODADDY_PAT" ] || fail "GODADDY_PAT is missing from the configuration."
    validate_ttl || fail "Invalid TTL: $TTL. It must be between 600 and 86400."
    OLD_IFS=$IFS
    IFS=';'
    for ENTRY in $RECORDS; do
        ENTRY_ZONE=${ENTRY%%|*}
        ENTRY_HOST=${ENTRY#*|}
        [ "$ENTRY" != "$ENTRY_ZONE" ] || fail "Invalid RECORDS entry: $ENTRY"
        valid_zone "$ENTRY_ZONE" || fail "Invalid DNS zone: $ENTRY_ZONE"
        valid_host "$ENTRY_HOST" || fail "Invalid record name: $ENTRY_HOST"
    done
    IFS=$OLD_IFS
    check_dependencies
}

check_dependencies() {
    command -v curl >/dev/null 2>&1 || fail "Missing dependency: curl"
    command -v jq >/dev/null 2>&1 || fail "Missing dependency: jq"
    command -v grep >/dev/null 2>&1 || fail "Missing dependency: grep"
}

save_config() {
    CONFIG_DIR=${CONFIG_FILE%/*}
    [ -d "$CONFIG_DIR" ] || mkdir -p "$CONFIG_DIR" || fail "Could not create the configuration directory."
    CONFIG_TMP="$CONFIG_FILE.tmp.$$"
    {
        printf 'TTL=%s\n' "$(shell_quote "$TTL")"
        printf 'GODADDY_PAT=%s\n' "$(shell_quote "$GODADDY_PAT")"
        printf 'RECORDS=%s\n' "$(shell_quote "$RECORDS")"
    } > "$CONFIG_TMP" || fail "Could not write the configuration file."
    chmod 600 "$CONFIG_TMP" || fail "Could not set configuration file permissions."
    mv "$CONFIG_TMP" "$CONFIG_FILE" || fail "Could not install the configuration file."
}

configure() {
    need_tty
    if [ -f "$CONFIG_FILE" ]; then
        DOMAIN=""
        HOST=""
        TTL="600"
        GODADDY_PAT=""
        RECORDS=""
        . "$CONFIG_FILE"
        if [ -z "$RECORDS" ] && [ -n "$DOMAIN" ] && [ -n "$HOST" ]; then
            LEGACY_NORMALIZED=$(normalize_legacy_host "$HOST" "$DOMAIN")
            RECORDS="$DOMAIN|$LEGACY_NORMALIZED"
        fi
    else
        TTL="600"
        GODADDY_PAT=""
        RECORDS=""
    fi
    printf 'Current records: %s\n' "${RECORDS:-nincs}" > /dev/tty
    ask "Replace the entire record list? y/N" "N"
    case "$ASK_VALUE" in y|Y|yes|YES) RECORDS="" ;; esac
    if [ -n "$RECORDS" ]; then
        ask "Add more records? y/N" "N"
        case "$ASK_VALUE" in y|Y|yes|YES) ADD_RECORDS=1 ;; *) ADD_RECORDS=0 ;; esac
    else
        ADD_RECORDS=1
    fi
    while [ "$ADD_RECORDS" -eq 1 ]; do
        ask "DNS zone (e.g. example.com)" ""
        NEW_ZONE=$ASK_VALUE
        [ -n "$NEW_ZONE" ] || { [ -n "$RECORDS" ] && break; fail "A DNS zone is required."; }
        valid_zone "$NEW_ZONE" || fail "Invalid DNS zone: $NEW_ZONE"
        ask "Record name (@ = zone apex, e.g. vpn or web-games-collection)" "@"
        NEW_HOST=$ASK_VALUE
        valid_host "$NEW_HOST" || fail "Invalid record name: $NEW_HOST"
        case ";$RECORDS;" in *";$NEW_ZONE|$NEW_HOST;"*) printf 'This record is already in the list.\n' > /dev/tty ;; *)
            if [ -n "$RECORDS" ]; then RECORDS="$RECORDS;$NEW_ZONE|$NEW_HOST"; else RECORDS="$NEW_ZONE|$NEW_HOST"; fi
        esac
        ask "Add another record? y/N" "N"
        case "$ASK_VALUE" in y|Y|yes|YES) ADD_RECORDS=1 ;; *) ADD_RECORDS=0 ;; esac
    done
    [ -n "$RECORDS" ] || fail "At least one DNS record is required."
    ask "TTL in seconds" "${TTL:-600}"
    TTL=$ASK_VALUE
    validate_ttl || fail "Invalid TTL. It must be between 600 and 86400."
    if [ -n "$GODADDY_PAT" ]; then
        ask "Keep the current GoDaddy PAT? Y/n" "Y"
        case "$ASK_VALUE" in n|N|no|NO) GODADDY_PAT="" ;; esac
    fi
    if [ -z "$GODADDY_PAT" ]; then
        ask_secret "GoDaddy Personal Access Token: "
        GODADDY_PAT=$ASK_VALUE
    fi
    [ -n "$GODADDY_PAT" ] || fail "The GoDaddy PAT cannot be empty."
    save_config
    log "Configuration saved: $CONFIG_FILE"
    log "Records: $RECORDS"
}

api_request() {
    API_METHOD=$1
    API_URL=$2
    API_DATA=${3-}
    TEMP_BODY=$(mktemp "${TMPDIR:-/tmp}/godaddy-ddns.XXXXXX") || return 1
    if [ "$API_METHOD" = "GET" ]; then
        HTTP_CODE=$(curl -sS -G -o "$TEMP_BODY" -w '%{http_code}' -H "Authorization: Bearer $GODADDY_PAT" -H 'Accept: application/json' --data-urlencode 'type=A' --data-urlencode "name=$CURRENT_HOST" --data-urlencode 'pageSize=100' "$API_URL") || HTTP_CODE=000
    else
        HTTP_CODE=$(curl -sS -o "$TEMP_BODY" -w '%{http_code}' -X "$API_METHOD" -H "Authorization: Bearer $GODADDY_PAT" -H 'Accept: application/json' -H 'Content-Type: application/json' --data "$API_DATA" "$API_URL") || HTTP_CODE=000
    fi
    API_BODY=$(cat "$TEMP_BODY" 2>/dev/null)
    rm -f "$TEMP_BODY"
    case "$HTTP_CODE" in 2??) return 0 ;; *) return 1 ;; esac
}

get_public_ip() {
    for IP_URL in \
        'https://ifconfig.me/ip' \
        'https://checkip.amazonaws.com' \
        'https://ipv4.icanhazip.com/' \
        'https://api.ipify.org'
    do
        IP_CANDIDATE=$(curl -4 -fsSL --connect-timeout 3 --max-time 8 "$IP_URL" 2>/dev/null) || IP_CANDIDATE=""

        if is_public_ipv4 "$IP_CANDIDATE"; then
            PUBLIC_IP=$IP_CANDIDATE
            log "Public IPv4 retrieved successfully from $IP_URL"
            return 0
        fi

        log "WARNING: Public IPv4 lookup failed or returned an invalid address: $IP_URL"
    done

    fail "Could not retrieve a valid public IPv4 address from any configured service."
}

build_record_body() {
    jq -cn --arg name "$CURRENT_HOST" --arg data "$PUBLIC_IP" --argjson ttl "$TTL" '{name:$name,type:"A",data:$data,ttl:$ttl}'
}

update_one_record() {
    CURRENT_ZONE=$1
    CURRENT_HOST=$2
    ZONE_URL="$API/$CURRENT_ZONE/dns-records"
    if ! api_request GET "$ZONE_URL"; then
        log "ERROR: Could not retrieve DNS records ($CURRENT_ZONE / $CURRENT_HOST), HTTP $HTTP_CODE: $API_BODY"
        return 1
    fi
    MATCHING=$(printf '%s' "$API_BODY" | jq -r --arg name "$CURRENT_HOST" '[.items[]? | select(.type == "A" and .name == $name)] | length') || MATCHING=0
    case "$MATCHING" in ''|*[!0-9]*) MATCHING=0 ;; esac
    BODY=$(build_record_body) || { log "ERROR: Could not generate JSON."; return 1; }
    if [ "$MATCHING" -eq 0 ]; then
        if api_request POST "$ZONE_URL" "$BODY"; then
            log "CREATED: $CURRENT_HOST.$CURRENT_ZONE -> $PUBLIC_IP (TTL $TTL)"
            return 0
        fi
        log "ERROR: Could not create the record ($CURRENT_HOST.$CURRENT_ZONE), HTTP $HTTP_CODE: $API_BODY"
        return 1
    fi
    RECORD_IDS=$(printf '%s' "$API_BODY" | jq -r --arg name "$CURRENT_HOST" '.items[]? | select(.type == "A" and .name == $name) | .recordId // empty') || return 1
    [ -n "$RECORD_IDS" ] || { log "ERROR: An A record was found, but it has no recordId ($CURRENT_HOST.$CURRENT_ZONE)."; return 1; }
    UPDATE_FAILED=0
    for RECORD_ID in $RECORD_IDS; do
        RECORD_IP=$(printf '%s' "$API_BODY" | jq -r --arg id "$RECORD_ID" '.items[]? | select(.recordId == $id) | .data' | head -n 1)
        if [ "$RECORD_IP" = "$PUBLIC_IP" ]; then
            log "UNCHANGED: $CURRENT_HOST.$CURRENT_ZONE -> $PUBLIC_IP"
            continue
        fi
        if api_request PUT "$ZONE_URL/$RECORD_ID" "$BODY"; then
            log "UPDATED: $CURRENT_HOST.$CURRENT_ZONE: ${RECORD_IP:-unknown} -> $PUBLIC_IP"
        else
            log "ERROR: Could not update the record ($CURRENT_HOST.$CURRENT_ZONE / $RECORD_ID), HTTP $HTTP_CODE: $API_BODY"
            UPDATE_FAILED=1
        fi
    done
    return "$UPDATE_FAILED"
}

run_ddns() {
    load_config
    get_public_ip
    log "Public IPv4: $PUBLIC_IP"
    FAILED=0
    OLD_IFS=$IFS
    IFS=';'
    for ENTRY in $RECORDS; do
        CURRENT_ZONE=${ENTRY%%|*}
        CURRENT_HOST=${ENTRY#*|}
        update_one_record "$CURRENT_ZONE" "$CURRENT_HOST" || FAILED=1
    done
    IFS=$OLD_IFS
    [ "$FAILED" -eq 0 ] || fail "One or more DNS record updates failed."
}

check_dns() {
    load_config
    FAILED=0
    OLD_IFS=$IFS
    IFS=';'
    for ENTRY in $RECORDS; do
        CURRENT_ZONE=${ENTRY%%|*}
        CURRENT_HOST=${ENTRY#*|}
        if api_request GET "$API/$CURRENT_ZONE/dns-records"; then
            RECORD_VALUES=$(printf '%s' "$API_BODY" | jq -r --arg name "$CURRENT_HOST" '[.items[]? | select(.type == "A" and .name == $name) | .data] | if length == 0 then "MISSING" else join(", ") end')
            printf '%s.%s -> %s\n' "$CURRENT_HOST" "$CURRENT_ZONE" "$RECORD_VALUES"
        else
            printf '%s.%s -> ERROR (HTTP %s): %s\n' "$CURRENT_HOST" "$CURRENT_ZONE" "$HTTP_CODE" "$API_BODY"
            FAILED=1
        fi
    done
    IFS=$OLD_IFS
    [ "$FAILED" -eq 0 ] || return 1
}

install_opnsense_action() {
    [ -d /usr/local/opnsense/service/conf/actions.d ] || { log "OPNsense configd directory not found; skipping integration."; return 0; }
    cat > "$OPNSENSE_ACTION_FILE" <<EOF_ACTION
[godaddy_ddns]
command:/usr/local/sbin/godaddy-ddns.sh --run
parameters:
description:Update GoDaddy Dynamic DNS records
EOF_ACTION
    chmod 644 "$OPNSENSE_ACTION_FILE"
    if command -v configctl >/dev/null 2>&1; then
        configctl configd restart >/dev/null 2>&1 || true
    fi
    log "OPNsense configd action installed."
}

uninstall_opnsense_action() {
    if [ -f "$OPNSENSE_ACTION_FILE" ]; then
        rm -f "$OPNSENSE_ACTION_FILE"
        if command -v configctl >/dev/null 2>&1; then configctl configd restart >/dev/null 2>&1 || true; fi
        log "OPNsense configd action removed."
    else
        log "No OPNsense configd action is installed."
    fi
}

install_script() {
    SOURCE_PATH=$0
    [ -f "$SOURCE_PATH" ] || fail "Could not locate the running script file."
    mkdir -p "${SCRIPT_PATH%/*}" || fail "Could not create the installation directory."
    if [ -f "$SCRIPT_PATH" ] && [ "$SOURCE_PATH" != "$SCRIPT_PATH" ]; then
        cp "$SCRIPT_PATH" "$SCRIPT_PATH.bak.$(date '+%Y%m%d%H%M%S')" || fail "Could not create a backup."
    fi
    cp "$SOURCE_PATH" "$SCRIPT_PATH.tmp.$$" || fail "Could not copy the script."
    chmod 700 "$SCRIPT_PATH.tmp.$$" || fail "Could not set script permissions."
    sh -n "$SCRIPT_PATH.tmp.$$" || fail "Script syntax validation failed."
    mv "$SCRIPT_PATH.tmp.$$" "$SCRIPT_PATH" || fail "Could not install the script."
    log "Installed: $SCRIPT_PATH"
    [ -f "$CONFIG_FILE" ] || "$SCRIPT_PATH" --configure
    install_opnsense_action
}

update_script() {
    command -v curl >/dev/null 2>&1 || fail "Missing dependency: curl"
    UPDATE_TMP=$(mktemp "${TMPDIR:-/tmp}/godaddy-ddns-update.XXXXXX") || fail "Could not create a temporary file."
    curl -fsSL 'https://raw.githubusercontent.com/Deniel11/install-godaddy-ddns/main/godaddy-ddns.sh' -o "$UPDATE_TMP" || { rm -f "$UPDATE_TMP"; fail "Could not download the update."; }
    grep -q '^VERSION=' "$UPDATE_TMP" || { rm -f "$UPDATE_TMP"; fail "The downloaded file does not appear to be a valid script."; }
    sh -n "$UPDATE_TMP" || { rm -f "$UPDATE_TMP"; fail "Syntax validation failed for the downloaded script."; }
    chmod 700 "$UPDATE_TMP"
    cp "$SCRIPT_PATH" "$SCRIPT_PATH.bak.$(date '+%Y%m%d%H%M%S')" 2>/dev/null || true
    mv "$UPDATE_TMP" "$SCRIPT_PATH" || fail "Could not install the update."
    log "Script updated."
    install_opnsense_action
}

usage() {
    cat <<EOF_USAGE
GoDaddy DDNS $VERSION

Usage: $0 [option]
  --configure       Interactive configuration
  --install         Install to /usr/local/sbin
  --install-action  Install the OPNsense configd action
  --uninstall-action Remove the OPNsense configd action
  --update          Update from the GitHub main branch
  --check           Check DNS records without making changes
  --run             Update DNS records or create missing A records
  --version         Print version
  --help            Show help
EOF_USAGE
}

case "${1:---run}" in
    --configure) configure ;;
    --install) install_script ;;
    --install-action) install_opnsense_action ;;
    --uninstall-action) uninstall_opnsense_action ;;
    --update) update_script ;;
    --check) check_dns ;;
    --run|--update-dns) run_ddns ;;
    --version) printf '%s\n' "$VERSION" ;;
    --help|-h) usage ;;
    *) usage >&2; exit 2 ;;
esac
