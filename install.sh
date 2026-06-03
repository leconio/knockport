#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="KnockGate"
DEFAULT_REPO="leconio/knockport"
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

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
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

install_runtime_deps() {
  local family
  family="$(detect_pkg_family)"
  case "$family" in
    apt)
      if ! DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl tar nftables iproute2 libpcap0.8 qrencode; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl tar nftables iproute2 libpcap0.8 qrencode
      fi
      ;;
    dnf)
      dnf install -y ca-certificates curl tar nftables iproute libpcap qrencode
      ;;
    pacman)
      pacman -Sy --noconfirm ca-certificates curl tar nftables iproute2 libpcap qrencode
      ;;
  esac
}

release_url() {
  local repo="${KNOCKGATE_REPO:-$DEFAULT_REPO}"
  local arch="$1"
  local asset="knockgate_linux_${arch}.tar.gz"

  if [[ -n "${KNOCKGATE_ASSET_BASE:-}" ]]; then
    printf '%s/%s\n' "${KNOCKGATE_ASSET_BASE%/}" "${asset}"
    return
  fi

  if [[ -n "${KNOCKGATE_VERSION:-}" ]]; then
    printf 'https://github.com/%s/releases/download/%s/%s\n' "${repo}" "${KNOCKGATE_VERSION}" "${asset}"
  else
    printf 'https://github.com/%s/releases/latest/download/%s\n' "${repo}" "${asset}"
  fi
}

raw_base() {
  local repo="${KNOCKGATE_REPO:-$DEFAULT_REPO}"
  local branch="${KNOCKGATE_BRANCH:-main}"
  if [[ -n "${KNOCKGATE_RAW_BASE:-}" ]]; then
    printf '%s\n' "${KNOCKGATE_RAW_BASE%/}"
  else
    printf 'https://raw.githubusercontent.com/%s/%s\n' "${repo}" "${branch}"
  fi
}

main() {
  require_root
  need_cmd uname
  need_cmd mktemp

  local arch url tmpdir
  arch="$(detect_arch)"
  url="$(release_url "$arch")"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  blue "${PROJECT_NAME} installer"
  yellow "Binary asset: ${url}"

  install_runtime_deps

  curl -fsSL "$url" -o "${tmpdir}/knockgate.tar.gz"
  tar -xzf "${tmpdir}/knockgate.tar.gz" -C "$tmpdir"
  install -m 0755 "${tmpdir}/knockgate_linux_${arch}/knockgate" "${INSTALL_DIR}/knockgate"

  green "Installed:"
  printf '  %s\n' "${INSTALL_DIR}/knockgate"

  if [[ "${INSTALL_CLIENT_HELPERS}" == "1" ]]; then
    install -m 0755 "${tmpdir}/knockgate_linux_${arch}/rfcjp-knock.sh" "${INSTALL_DIR}/rfcjp-knock"
    install -m 0755 "${tmpdir}/knockgate_linux_${arch}/rfcjp-check.sh" "${INSTALL_DIR}/rfcjp-check"
    green "Installed optional client helpers:"
    printf '  %s\n' "${INSTALL_DIR}/rfcjp-knock" "${INSTALL_DIR}/rfcjp-check"
  else
    yellow "Client helpers were not installed. Set INSTALL_CLIENT_HELPERS=1 on client machines if needed."
  fi

  yellow "Run the server manager with: sudo knockgate"
}

main "$@"
