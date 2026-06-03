#!/usr/bin/env bash
set -euo pipefail

KNOCK_DELAY="${KNOCK_DELAY:-0.25}"
KNOCK_PAYLOAD="${KNOCK_PAYLOAD:-knockgate}"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") [--delay SECONDS] SERVER PORT ...

Send the KnockGate UDP knock sequence.

Examples:
  $(basename "$0") SERVER_IP 38127 19452 47219 26083
  $(basename "$0") example.com 38127 19452 47219 26083
  $(basename "$0") --delay 0.5 SERVER_IP 38127 19452 47219 26083

Notes:
  - SERVER must be the first argument.
  - Provide the exact UDP knock ports printed by knockgate during install/reset.
  - UDP knocks do not need root privileges.
  - Delay between ports. Default: ${KNOCK_DELAY}s.
EOF
}

while [[ "$#" -gt 0 ]]; do
    case "${1}" in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--delay)
            if [[ -z "${2:-}" ]]; then
                echo "Missing value for ${1}" >&2
                exit 2
            fi
            KNOCK_DELAY="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: ${1}" >&2
            usage >&2
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

if [[ "$#" -lt 2 ]]; then
    usage >&2
    exit 2
fi

if ! [[ "${KNOCK_DELAY}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Invalid delay: ${KNOCK_DELAY}" >&2
    exit 2
fi

SERVER="$1"
shift
PORTS=("$@")

is_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

send_udp() {
    local port="$1"

    if ! printf '%s\n' "${KNOCK_PAYLOAD}" >"/dev/udp/${SERVER}/${port}" 2>/dev/null; then
        if command -v nc >/dev/null 2>&1; then
            printf '%s\n' "${KNOCK_PAYLOAD}" | nc -u -w1 "${SERVER}" "${port}" >/dev/null 2>&1 || true
        else
            echo "Failed to send UDP knock and nc fallback is unavailable." >&2
            return 1
        fi
    fi
}

for port in "${PORTS[@]}"; do
    if ! is_port "${port}"; then
        echo "Invalid port: ${port}" >&2
        exit 2
    fi
done

echo "UDP knocking ${SERVER}: ${PORTS[*]} (delay ${KNOCK_DELAY}s)"
for port in "${PORTS[@]}"; do
    echo "  -> ${port}/udp"
    send_udp "${port}"
    sleep "${KNOCK_DELAY}"
done

echo "Done."
