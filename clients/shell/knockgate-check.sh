#!/usr/bin/env bash
set -euo pipefail

PROTECTED_PORTS="${PROTECTED_PORTS:-5432}"
ORDINARY_PORT="${ORDINARY_PORT:-15555}"
CHECK_TIMEOUT="${CHECK_TIMEOUT:-3}"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") [--verbose] [--timeout SECONDS] SERVER [PORT[/tcp|/udp] ...]

Check connectivity only. This script does not send knock packets.

Port syntax:
  2345      check TCP, then send one UDP probe
  2345/tcp  check TCP only
  2345/udp  send one UDP probe only

Defaults when no ports are provided:
  PROTECTED_PORTS: ${PROTECTED_PORTS}
  ORDINARY_PORT:   ${ORDINARY_PORT}/tcp
  CHECK_TIMEOUT:   ${CHECK_TIMEOUT}s

Examples:
  $(basename "$0") SERVER_IP
  $(basename "$0") SERVER_IP 5432
  $(basename "$0") SERVER_IP 5432/tcp 5432/udp
  $(basename "$0") --timeout 5 SERVER_IP 5432/tcp

Results:
  OPEN      TCP handshake succeeded.
  REFUSED   TCP path reached host, but no service is listening.
  FILTERED  TCP timed out; usually firewall/network drop.
  UDP-SENT  UDP has no reliable handshake; packet was sent, not proven open.
  FAILED    Local tool or network command failed.
EOF
}

VERBOSE=0
while [[ "$#" -gt 0 ]]; do
    case "${1}" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -t|--timeout|--timeout-seconds)
            if [[ -z "${2:-}" ]]; then
                echo "Missing value for ${1}" >&2
                exit 2
            fi
            CHECK_TIMEOUT="$2"
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

if [[ "$#" -lt 1 ]]; then
    usage >&2
    exit 2
fi

SERVER="$1"
shift

if ! [[ "${CHECK_TIMEOUT}" =~ ^[0-9]+$ ]] || (( CHECK_TIMEOUT < 1 )); then
    echo "Invalid timeout: ${CHECK_TIMEOUT}" >&2
    exit 2
fi

is_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

parse_target() {
    local raw="$1"
    local port proto
    if [[ "${raw}" == */* ]]; then
        port="${raw%/*}"
        proto="${raw##*/}"
    else
        port="${raw}"
        proto="both"
    fi
    proto="$(printf '%s' "${proto}" | tr '[:upper:]' '[:lower:]')"
    if ! is_port "${port}"; then
        echo "Invalid port: ${raw}" >&2
        return 1
    fi
    case "${proto}" in
        tcp|udp|both)
            printf '%s %s\n' "${port}" "${proto}"
            ;;
        *)
            echo "Invalid protocol in ${raw}; use tcp or udp." >&2
            return 1
            ;;
    esac
}

run_nc_with_timeout() {
    local port="$1"
    local output_file="$2"
    local pid
    local elapsed=0

    (
        exec nc -vz -w "${CHECK_TIMEOUT}" "${SERVER}" "${port}"
    ) >"${output_file}" 2>&1 &
    pid=$!

    while kill -0 "${pid}" 2>/dev/null; do
        if (( elapsed >= CHECK_TIMEOUT )); then
            kill "${pid}" 2>/dev/null || true
            sleep 0.1
            kill -9 "${pid}" 2>/dev/null || true
            wait "${pid}" 2>/dev/null || true
            printf 'TIMEOUT after %ss\n' "${CHECK_TIMEOUT}" >>"${output_file}"
            return 124
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    wait "${pid}"
}

try_tcp() {
    local port="$1"
    local output output_file rc

    output_file="$(mktemp)"
    set +e
    run_nc_with_timeout "${port}" "${output_file}"
    rc=$?
    set -e
    output="$(cat "${output_file}")"
    rm -f "${output_file}"

    if [[ "${VERBOSE}" -eq 1 ]]; then
        echo
        echo "== TCP ${SERVER}:${port} =="
        echo "timeout: ${CHECK_TIMEOUT}s"
        printf '%s\n' "${output}"
    fi

    if [[ "${rc}" -eq 0 ]]; then
        echo "OPEN ${SERVER}:${port}/tcp"
    elif printf '%s\n' "${output}" | grep -qi "refused"; then
        echo "REFUSED ${SERVER}:${port}/tcp"
    elif [[ "${rc}" -eq 124 ]] || printf '%s\n' "${output}" | grep -Eqi "timed out|timeout|Operation now in progress"; then
        echo "FILTERED ${SERVER}:${port}/tcp"
    else
        echo "FAILED ${SERVER}:${port}/tcp"
        if [[ "${VERBOSE}" -eq 0 ]]; then
            printf '%s\n' "${output}" >&2
        fi
    fi
}

try_udp() {
    local port="$1"
    if command -v nc >/dev/null 2>&1; then
        printf 'knockgate-check\n' | nc -u -w "${CHECK_TIMEOUT}" "${SERVER}" "${port}" >/dev/null 2>&1 || true
        echo "UDP-SENT ${SERVER}:${port}/udp"
        return 0
    fi
    if command -v bash >/dev/null 2>&1; then
        SERVER="${SERVER}" PORT="${port}" bash -c 'printf "knockgate-check\n" >"/dev/udp/$SERVER/$PORT"' 2>/dev/null || true
        echo "UDP-SENT ${SERVER}:${port}/udp"
        return 0
    fi
    echo "FAILED ${SERVER}:${port}/udp"
    echo "Missing nc and bash /dev/udp support." >&2
}

check_one() {
    local raw="$1"
    local parsed port proto
    parsed="$(parse_target "${raw}")"
    port="${parsed%% *}"
    proto="${parsed##* }"
    case "${proto}" in
        tcp)
            try_tcp "${port}"
            ;;
        udp)
            try_udp "${port}"
            ;;
        both)
            try_tcp "${port}"
            try_udp "${port}"
            ;;
    esac
}

if [[ "$#" -gt 0 ]]; then
    for target in "$@"; do
        check_one "${target}"
    done
else
    check_one "${ORDINARY_PORT}/tcp"
    IFS=',' read -r -a defaults <<< "${PROTECTED_PORTS}"
    for target in "${defaults[@]}"; do
        check_one "${target}"
    done
fi
