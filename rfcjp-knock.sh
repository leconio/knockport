#!/usr/bin/env bash
set -euo pipefail

KNOCK_DELAY="${KNOCK_DELAY:-0.25}"
KNOCK_SECRET="${KNOCK_SECRET:-}"
KNOCK_HMAC_WINDOW="${KNOCK_HMAC_WINDOW:-60}"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") --secret SECRET [--delay SECONDS] SERVER PORT ...
  $(basename "$0") --url 'knockgate://import/v1?...'

Send a KnockGate UDP HMAC knock sequence. No root privilege is required.

Examples:
  $(basename "$0") --secret BASE64URL_SECRET SERVER_IP 37708 31114 25880
  $(basename "$0") --url 'knockgate://import/v1?scheme=udp-hmac&host=example.com&knock_ports=37708%2C31114&secret=...'

Notes:
  - Earlier UDP packets only advance the server-side port sequence.
  - Only the final UDP packet carries KG1|step|timestamp|nonce|hmac.
  - The final HMAC covers the destination UDP port and final sequence step.
  - Timestamp is checked by the server; keep client clock reasonably correct.
EOF
}

url_decode() {
    local value="${1//+/ }"
    printf '%b' "${value//%/\\x}"
}

query_param() {
    local url="$1"
    local key="$2"
    local query pair name value
    query="${url#*\?}"
    IFS='&' read -r -a pairs <<< "${query}"
    for pair in "${pairs[@]}"; do
        name="${pair%%=*}"
        value="${pair#*=}"
        if [[ "${name}" == "${key}" ]]; then
            url_decode "${value}"
            return 0
        fi
    done
    return 1
}

b64url_to_hex() {
    local input="$1"
    local b64
    b64="${input//-/+}"
    b64="${b64//_/\/}"
    case $(( ${#b64} % 4 )) in
        2) b64="${b64}==" ;;
        3) b64="${b64}=" ;;
        1) echo "Invalid base64url secret." >&2; return 1 ;;
    esac
    printf '%s' "${b64}" | openssl enc -d -A -base64 | od -An -tx1 | tr -d ' \n'
}

b64url_mac() {
    local secret_hex="$1"
    local message="$2"
    printf '%s' "${message}" |
        openssl dgst -sha256 -mac HMAC -macopt "hexkey:${secret_hex}" -binary |
        openssl enc -A -base64 |
        tr '+/' '-_' |
        tr -d '='
}

nonce() {
    openssl rand -base64 18 | tr '+/' '-_' | tr -d '=\n'
}

send_udp() {
    local server="$1"
    local port="$2"
    local payload="$3"

    if ! printf '%s\n' "${payload}" >"/dev/udp/${server}/${port}" 2>/dev/null; then
        if command -v nc >/dev/null 2>&1; then
            printf '%s\n' "${payload}" | nc -u -w1 "${server}" "${port}" >/dev/null 2>&1 || true
        else
            echo "Failed to send UDP packet and nc fallback is unavailable." >&2
            return 1
        fi
    fi
}

is_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

IMPORT_URL=""
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --url)
            IMPORT_URL="${2:-}"
            shift 2
            ;;
        --secret)
            KNOCK_SECRET="${2:-}"
            shift 2
            ;;
        -d|--delay|--delay-seconds)
            KNOCK_DELAY="${2:-}"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

if [[ -n "${IMPORT_URL}" ]]; then
    SERVER="$(query_param "${IMPORT_URL}" host || true)"
    PORT_TEXT="$(query_param "${IMPORT_URL}" knock_ports || true)"
    KNOCK_SECRET="$(query_param "${IMPORT_URL}" secret || true)"
    KNOCK_HMAC_WINDOW="$(query_param "${IMPORT_URL}" hmac_window || printf '60')"
    IFS=',' read -r -a PORTS <<< "${PORT_TEXT}"
else
    if [[ "$#" -lt 2 ]]; then
        usage >&2
        exit 2
    fi
    SERVER="$1"
    shift
    PORTS=("$@")
fi

if [[ -z "${SERVER:-}" || -z "${KNOCK_SECRET}" || "${#PORTS[@]}" -eq 0 ]]; then
    echo "Missing server, secret, or knock ports." >&2
    usage >&2
    exit 2
fi
if ! command -v openssl >/dev/null 2>&1; then
    echo "Missing openssl." >&2
    exit 2
fi
if ! [[ "${KNOCK_DELAY}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Invalid delay: ${KNOCK_DELAY}" >&2
    exit 2
fi

for port in "${PORTS[@]}"; do
    if ! is_port "${port}"; then
        echo "Invalid port: ${port}" >&2
        exit 2
    fi
done

SECRET_HEX="$(b64url_to_hex "${KNOCK_SECRET}")"

echo "UDP HMAC knocking ${SERVER}: ${PORTS[*]} (delay ${KNOCK_DELAY}s)"
step=0
last_step=$((${#PORTS[@]} - 1))
for port in "${PORTS[@]}"; do
    if (( step == last_step )); then
        ts="$(date +%s)"
        nonce_value="$(nonce)"
        message="KG1|${port}|${step}|${ts}|${nonce_value}"
        mac="$(b64url_mac "${SECRET_HEX}" "${message}")"
        payload="KG1|${step}|${ts}|${nonce_value}|${mac}"
    else
        payload="KG0|${step}"
    fi
    echo "  -> step ${step} ${port}/udp"
    send_udp "${SERVER}" "${port}" "${payload}"
    step=$((step + 1))
    sleep "${KNOCK_DELAY}"
done

echo "Done."
