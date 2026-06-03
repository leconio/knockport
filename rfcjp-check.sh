#!/usr/bin/env bash
set -euo pipefail

SSH_PORT="${SSH_PORT:-22}"
PROTECTED_PORT="${PROTECTED_PORT:-5432}"
ORDINARY_PORT="${ORDINARY_PORT:-15555}"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") [--verbose] SERVER [PORT ...]

Check KnockGate connectivity only. This script does not send a knock sequence.
Run it before and after the knock script to compare behavior.

If PORT arguments are provided, only those ports are checked.
If no PORT arguments are provided, the default SSH/ordinary/protected checks run.

Defaults:
  SSH_PORT:       ${SSH_PORT}
  PROTECTED_PORT: ${PROTECTED_PORT}
  ORDINARY_PORT:  ${ORDINARY_PORT}

Override ports with environment variables:
  SSH_PORT=2222 PROTECTED_PORT=5432 ORDINARY_PORT=15555 $(basename "$0") SERVER_IP

Examples:
  $(basename "$0") SERVER_IP
  $(basename "$0") SERVER_IP 12345
  $(basename "$0") SERVER_IP 22 80 443 5432
  $(basename "$0") --verbose SERVER_IP 5432
  SSH_PORT=2222 PROTECTED_PORT=5432 $(basename "$0") example.com

Set KNOCKGATE_CHECK_NO_NET_WARN=1 to suppress local proxy/TUN warnings.

Results:
  OPEN      TCP handshake succeeded. A service is reachable.
  REFUSED   Firewall likely allowed the path, but no service is listening.
  FILTERED  Connection timed out. Firewall or network path is dropping.
  FAILED    nc returned another error.
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

warn_local_network_context() {
    [[ "${KNOCKGATE_CHECK_NO_NET_WARN:-0}" == "1" ]] && return 0
    [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]] || return 0

    local route_info iface proxy_info
    route_info="$(route -n get "${SERVER}" 2>/dev/null || true)"
    iface="$(printf '%s\n' "${route_info}" | awk '/interface:/ {print $2; exit}')"

    if [[ "${iface}" == utun* ]]; then
        echo "WARN route=${iface}; VPN/TUN/proxy may make closed ports look OPEN." >&2
    fi

    proxy_info="$(scutil --proxy 2>/dev/null || true)"
    if printf '%s\n' "${proxy_info}" | grep -Eq 'HTTPEnable[[:space:]]*:[[:space:]]*1|HTTPSEnable[[:space:]]*:[[:space:]]*1|SOCKSEnable[[:space:]]*:[[:space:]]*1'; then
        echo "WARN system proxy is enabled; test from a clean route if results look wrong." >&2
    fi
}

is_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

try_tcp() {
    local label="$1"
    local port="$2"
    local output

    set +e
    output="$(nc -vz -w2 "${SERVER}" "${port}" 2>&1)"
    local rc=$?
    set -e

    if [[ "${VERBOSE}" -eq 1 ]]; then
        echo
        echo "== ${label}: ${SERVER}:${port}/tcp =="
        printf '%s\n' "${output}"
    fi

    if [[ "${rc}" -eq 0 ]]; then
        echo "OPEN ${SERVER}:${port}/tcp"
    elif printf '%s\n' "${output}" | grep -qi "refused"; then
        echo "REFUSED ${SERVER}:${port}/tcp"
    elif printf '%s\n' "${output}" | grep -Eqi "timed out|timeout|Operation now in progress"; then
        echo "FILTERED ${SERVER}:${port}/tcp"
    else
        echo "FAILED ${SERVER}:${port}/tcp"
        if [[ "${VERBOSE}" -eq 0 ]]; then
            printf '%s\n' "${output}" >&2
        fi
    fi
}

warn_local_network_context

if [[ "$#" -gt 0 ]]; then
    for port in "$@"; do
        if ! is_port "${port}"; then
            echo "Invalid port: ${port}" >&2
            exit 2
        fi
        try_tcp "Custom port check" "${port}"
    done
else
    if [[ "${VERBOSE}" -eq 1 ]]; then
        echo "KnockGate connectivity check"
        echo "This script does not send knock packets."
        echo "Server: ${SERVER}"
        echo "SSH exception port: ${SSH_PORT}"
        echo "Protected port: ${PROTECTED_PORT}"
        echo "Ordinary unlisted port: ${ORDINARY_PORT}"
    fi

    try_tcp "SSH exception" "${SSH_PORT}"
    try_tcp "Ordinary unlisted port" "${ORDINARY_PORT}"
    try_tcp "Protected port" "${PROTECTED_PORT}"
fi
