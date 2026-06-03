#!/usr/bin/env bash
set -euo pipefail

DEFAULT_PORTS=()

usage() {
    cat <<EOF
Usage:
  $(basename "$0") SERVER PORT ...

Send the KnockGate TCP knock sequence.

Examples:
  $(basename "$0") SERVER_IP 38127 19452 47219 26083
  $(basename "$0") example.com 38127 19452 47219 26083

Notes:
  - SERVER must be the first argument.
  - Provide the exact knock ports printed by knockgate during install/reset.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ "$#" -lt 2 ]]; then
    usage >&2
    exit 2
fi

SERVER="$1"
shift
PORTS=("$@")

echo "Knocking ${SERVER}: ${PORTS[*]}"
for port in "${PORTS[@]}"; do
    echo "  -> ${port}/tcp"
    nc -z -w1 "${SERVER}" "${port}" >/dev/null 2>&1 || true
    sleep 0.25
done

echo "Done."
