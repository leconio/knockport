#!/usr/bin/env bash
set -euo pipefail

KNOCK_TIMEOUT="${KNOCK_TIMEOUT:-1}"
KNOCK_DELAY="${KNOCK_DELAY:-0.25}"
KNOCK_METHOD="${KNOCK_METHOD:-auto}"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") [--method auto|nping|hping3|nc] [--timeout SECONDS] [--delay SECONDS] SERVER PORT ...

Send the KnockGate TCP knock sequence.

Examples:
  $(basename "$0") SERVER_IP 38127 19452 47219 26083
  $(basename "$0") example.com 38127 19452 47219 26083
  $(basename "$0") --timeout 2 SERVER_IP 38127 19452 47219 26083
  sudo $(basename "$0") --method nping SERVER_IP 38127 19452 47219 26083

Notes:
  - SERVER must be the first argument.
  - Provide the exact knock ports printed by knockgate during install/reset.
  - Default method is auto: nping, then hping3, then nc.
  - nping/hping3 send one TCP SYN packet and are preferred.
  - nping/hping3 usually require root privileges.
  - nc is a fallback and can be confused by TCP retransmits on dropped ports.
  - Each knock has a hard timeout. Default: ${KNOCK_TIMEOUT}s.
  - Delay between ports. Default: ${KNOCK_DELAY}s.
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
        -d|--delay)
            if [[ -z "${2:-}" ]]; then
                echo "Missing value for ${1}" >&2
                exit 2
            fi
            KNOCK_DELAY="$2"
            shift 2
            ;;
        -m|--method)
            if [[ -z "${2:-}" ]]; then
                echo "Missing value for ${1}" >&2
                exit 2
            fi
            KNOCK_METHOD="$2"
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

select_method() {
    case "${KNOCK_METHOD}" in
        auto)
            if command -v nping >/dev/null 2>&1; then
                KNOCK_METHOD="nping"
            elif command -v hping3 >/dev/null 2>&1; then
                KNOCK_METHOD="hping3"
            elif command -v nc >/dev/null 2>&1; then
                KNOCK_METHOD="nc"
            else
                echo "Missing knock sender: install nping, hping3, or nc." >&2
                exit 1
            fi
            ;;
        nping|hping3|nc)
            if ! command -v "${KNOCK_METHOD}" >/dev/null 2>&1; then
                echo "Missing ${KNOCK_METHOD}; install it or use --method auto." >&2
                exit 1
            fi
            ;;
        *)
            echo "Invalid method: ${KNOCK_METHOD}" >&2
            exit 2
            ;;
    esac
}

run_with_timeout() {
    local pid
    local elapsed=0

    ( "$@" ) >/dev/null 2>&1 &
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

knock_one() {
    local port="$1"

    case "${KNOCK_METHOD}" in
        nping)
            run_with_timeout nping --tcp -c 1 --flags syn -p "${port}" "${SERVER}"
            ;;
        hping3)
            run_with_timeout hping3 -S -c 1 -p "${port}" "${SERVER}"
            ;;
        nc)
            run_with_timeout nc -z -w "${KNOCK_TIMEOUT}" "${SERVER}" "${port}"
            ;;
    esac
}

for port in "${PORTS[@]}"; do
    if ! is_port "${port}"; then
        echo "Invalid port: ${port}" >&2
        exit 2
    fi
done

select_method

echo "Knocking ${SERVER}: ${PORTS[*]} (method ${KNOCK_METHOD}, timeout ${KNOCK_TIMEOUT}s each, delay ${KNOCK_DELAY}s)"
if [[ "${KNOCK_METHOD}" == "nc" ]]; then
    echo "WARN: nc may retransmit TCP SYN packets on filtered ports and break strict knock sequences." >&2
    echo "WARN: install nmap/nping or hping3 and run with sudo for more reliable single-SYN knocks." >&2
elif [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "WARN: ${KNOCK_METHOD} usually needs root privileges for raw SYN packets. Use sudo if this fails." >&2
fi

for port in "${PORTS[@]}"; do
    echo "  -> ${port}/tcp"
    knock_one "${port}"
    sleep "${KNOCK_DELAY}"
done

echo "Done."
