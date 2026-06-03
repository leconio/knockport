#!/usr/bin/env bash
set -euo pipefail

SSH_PORT="${SSH_PORT:-22}"
PROTECTED_PORT="${PROTECTED_PORT:-5432}"
ORDINARY_PORT="${ORDINARY_PORT:-15555}"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") SERVER [PORT ...]

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
  SSH_PORT=2222 PROTECTED_PORT=5432 $(basename "$0") example.com
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ "$#" -lt 1 ]]; then
    usage >&2
    exit 2
fi

SERVER="$1"
shift

is_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

try_tcp() {
    local label="$1"
    local port="$2"
    local output

    echo
    echo "== ${label}: ${SERVER}:${port}/tcp =="
    set +e
    output="$(nc -vz -w2 "${SERVER}" "${port}" 2>&1)"
    local rc=$?
    set -e
    printf '%s\n' "${output}"

    if [[ "${rc}" -eq 0 ]]; then
        echo "RESULT: OPEN, TCP handshake succeeded."
    elif printf '%s\n' "${output}" | grep -qi "refused"; then
        echo "RESULT: REJECTED/REFUSED, firewall likely allowed it but no service is listening."
    elif printf '%s\n' "${output}" | grep -Eqi "timed out|timeout|Operation now in progress"; then
        echo "RESULT: FILTERED/TIMEOUT, firewall is dropping or network path is filtering."
    else
        echo "RESULT: FAILED, see nc output above."
    fi
}

echo "KnockGate connectivity check"
echo "This script does not send knock packets."
echo "Server: ${SERVER}"

if [[ "$#" -gt 0 ]]; then
    echo "Mode: custom port check"
    for port in "$@"; do
        if ! is_port "${port}"; then
            echo "Invalid port: ${port}" >&2
            exit 2
        fi
        try_tcp "Custom port check" "${port}"
    done
else
    echo "Mode: default KnockGate check"
    echo "SSH exception port: ${SSH_PORT}"
    echo "Protected port: ${PROTECTED_PORT}"
    echo "Ordinary unlisted port: ${ORDINARY_PORT}"

    try_tcp "SSH exception should be reachable" "${SSH_PORT}"
    try_tcp "Ordinary unlisted port should be filtered" "${ORDINARY_PORT}"
    try_tcp "Protected port current state" "${PROTECTED_PORT}"
fi

cat <<'EOF'

Interpretation:
- SSH exception should be OPEN.
- Ordinary unlisted port should be FILTERED/TIMEOUT.
- Before knock, protected port should be FILTERED/TIMEOUT.
- After a successful knock, protected port should be OPEN or REFUSED:
  - OPEN means a service is listening and firewall opened.
  - REFUSED means firewall opened, but no service is listening on that port.
  - FILTERED/TIMEOUT means knock did not open the allowlist from this network path.
EOF
