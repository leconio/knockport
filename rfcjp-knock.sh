#!/usr/bin/env bash
set -euo pipefail

KNOCK_TIMEOUT="${KNOCK_TIMEOUT:-1}"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") [--timeout SECONDS] SERVER PORT ...

Send the KnockGate TCP knock sequence.

Examples:
  $(basename "$0") SERVER_IP 38127 19452 47219 26083
  $(basename "$0") example.com 38127 19452 47219 26083
  $(basename "$0") --timeout 2 SERVER_IP 38127 19452 47219 26083

Notes:
  - SERVER must be the first argument.
  - Provide the exact knock ports printed by knockgate during install/reset.
  - Each TCP knock has a hard timeout. Default: ${KNOCK_TIMEOUT}s.
EOF
}

while [[ "$#" -gt 0 ]]; do
    case "${1}" in
        -h|--help)
            usage
            exit 0
            ;;
        -t|--timeout)
            if [[ -z "${2:-}" ]]; then
                echo "Missing value for ${1}" >&2
                exit 2
            fi
            KNOCK_TIMEOUT="$2"
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

if ! [[ "${KNOCK_TIMEOUT}" =~ ^[0-9]+$ ]] || (( KNOCK_TIMEOUT < 1 )); then
    echo "Invalid timeout: ${KNOCK_TIMEOUT}" >&2
    exit 2
fi

SERVER="$1"
shift
PORTS=("$@")

is_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

knock_one() {
    local port="$1"
    local pid
    local elapsed=0

    ( exec nc -z -w "${KNOCK_TIMEOUT}" "${SERVER}" "${port}" ) >/dev/null 2>&1 &
    pid=$!

    while kill -0 "${pid}" 2>/dev/null; do
        if (( elapsed >= KNOCK_TIMEOUT )); then
            kill "${pid}" 2>/dev/null || true
            sleep 0.1
            kill -9 "${pid}" 2>/dev/null || true
            wait "${pid}" 2>/dev/null || true
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    wait "${pid}" >/dev/null 2>&1 || true
}

for port in "${PORTS[@]}"; do
    if ! is_port "${port}"; then
        echo "Invalid port: ${port}" >&2
        exit 2
    fi
done

echo "Knocking ${SERVER}: ${PORTS[*]} (timeout ${KNOCK_TIMEOUT}s each)"
for port in "${PORTS[@]}"; do
    echo "  -> ${port}/tcp"
    knock_one "${port}"
    sleep 0.25
done

echo "Done."
