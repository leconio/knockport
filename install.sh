#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="KnockGate"
DEFAULT_REPO="OWNER/REPO"
DEFAULT_BRANCH="main"
INSTALL_DIR="/usr/local/bin"
INSTALL_CLIENT_HELPERS="${INSTALL_CLIENT_HELPERS:-0}"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
blue() { printf '\033[34m%s\033[0m\n' "$*"; }

die() {
  red "Error: $*"
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "please run as root, for example: curl -fsSL <install-url> | sudo bash"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

detect_pkg_family() {
  if [[ ! -r /etc/os-release ]]; then
    die "unsupported Linux distribution: missing /etc/os-release"
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) echo apt ;;
    rocky|almalinux|centos|rhel|fedora) echo dnf ;;
    arch) echo pacman ;;
    *)
      case " ${ID_LIKE:-} " in
        *" debian "*) echo apt ;;
        *" rhel "*|*" fedora "*) echo dnf ;;
        *" arch "*) echo pacman ;;
        *) die "unsupported Linux distribution: ID=${ID:-}, ID_LIKE=${ID_LIKE:-}" ;;
      esac
      ;;
  esac
}

install_build_deps() {
  local family
  family="$(detect_pkg_family)"
  case "$family" in
    apt)
      if ! DEBIAN_FRONTEND=noninteractive apt-get install -y golang-go gcc libc6-dev libpcap-dev nftables iproute2 qrencode; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y golang-go gcc libc6-dev libpcap-dev nftables iproute2 qrencode
      fi
      ;;
    dnf)
      dnf install -y golang gcc glibc-devel libpcap-devel nftables iproute qrencode
      ;;
    pacman)
      pacman -Sy --noconfirm go gcc glibc libpcap nftables iproute2 qrencode
      ;;
  esac
}

build_raw_base() {
  local repo="${KNOCKGATE_REPO:-$DEFAULT_REPO}"
  local branch="${KNOCKGATE_BRANCH:-$DEFAULT_BRANCH}"

  if [[ -n "${KNOCKGATE_RAW_BASE:-}" ]]; then
    printf '%s\n' "${KNOCKGATE_RAW_BASE%/}"
    return
  fi

  if [[ "$repo" == "$DEFAULT_REPO" ]]; then
    die "repository is not configured. Set KNOCKGATE_REPO=OWNER/REPO or replace OWNER/REPO after publishing."
  fi

  printf 'https://raw.githubusercontent.com/%s/%s\n' "$repo" "$branch"
}

download_file() {
  local raw_base="$1"
  local source_name="$2"
  local target_path="$3"

  blue "Downloading ${source_name}..."
  curl -fsSL "${raw_base}/${source_name}" -o "$target_path"
  chmod 0755 "$target_path"
}

download_source_tree() {
  local tmpdir="$1"
  local repo="${KNOCKGATE_REPO:-$DEFAULT_REPO}"
  local branch="${KNOCKGATE_BRANCH:-$DEFAULT_BRANCH}"
  local archive="${tmpdir}/source.tar.gz"

  if [[ "$repo" == "$DEFAULT_REPO" ]]; then
    die "repository is not configured. Set KNOCKGATE_REPO=OWNER/REPO or replace OWNER/REPO after publishing."
  fi

  blue "Downloading source archive..."
  curl -fsSL "https://github.com/${repo}/archive/refs/heads/${branch}.tar.gz" -o "$archive"
  tar -xzf "$archive" -C "$tmpdir" --strip-components=1
}

main() {
  require_root
  need_cmd curl
  need_cmd install
  need_cmd mktemp
  need_cmd tar

  local raw_base tmpdir
  raw_base="$(build_raw_base)"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  blue "${PROJECT_NAME} installer"
  yellow "Source: ${raw_base}"

  install_build_deps
  download_source_tree "$tmpdir"
  (cd "$tmpdir" && go build -trimpath -ldflags "-s -w" -o "${tmpdir}/knockgate" ./cmd/knockgate)
  install -m 0755 "${tmpdir}/knockgate" "${INSTALL_DIR}/knockgate"

  green "Installed:"
  printf '  %s\n' "${INSTALL_DIR}/knockgate"

  if [[ "${INSTALL_CLIENT_HELPERS}" == "1" ]]; then
    download_file "$raw_base" "rfcjp-knock.sh" "${tmpdir}/rfcjp-knock"
    download_file "$raw_base" "rfcjp-check.sh" "${tmpdir}/rfcjp-check"
    install -m 0755 "${tmpdir}/rfcjp-knock" "${INSTALL_DIR}/rfcjp-knock"
    install -m 0755 "${tmpdir}/rfcjp-check" "${INSTALL_DIR}/rfcjp-check"
    green "Installed optional client helpers:"
    printf '  %s\n' \
      "${INSTALL_DIR}/rfcjp-knock" \
      "${INSTALL_DIR}/rfcjp-check"
  else
    yellow "Client helpers were not installed. Set INSTALL_CLIENT_HELPERS=1 on client machines if needed."
  fi

  yellow "Run the server manager with: sudo knockgate"
}

main "$@"
