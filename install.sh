#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="KnockGate"
DEFAULT_REPO="leconio/knockport"
INSTALL_DIR="/usr/local/bin"

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
      if ! DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl tar nftables iproute2 libpcap0.8; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl tar nftables iproute2 libpcap0.8
      fi
      DEBIAN_FRONTEND=noninteractive apt-get install -y qrencode || yellow "Optional dependency qrencode was not installed; QR output will be skipped."
      ;;
    dnf)
      dnf install -y ca-certificates curl tar nftables iproute libpcap
      dnf install -y qrencode || yellow "Optional dependency qrencode was not installed; QR output will be skipped."
      ;;
    pacman)
      pacman -Sy --noconfirm ca-certificates curl tar nftables iproute2 libpcap
      pacman -S --noconfirm qrencode || yellow "Optional dependency qrencode was not installed; QR output will be skipped."
      ;;
  esac
}

release_asset() {
  local arch="$1"
  printf 'knockgate_linux_%s.tar.gz\n' "${arch}"
}

release_url() {
  local repo="${KNOCKGATE_REPO:-$DEFAULT_REPO}"
  local arch="$1"
  local asset
  asset="$(release_asset "$arch")"

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

verify_asset() {
  local file="$1"
  local checksum_file="$2"

  if [[ "${KNOCKGATE_SKIP_VERIFY:-}" == "1" ]]; then
    yellow "Skipping checksum verification because KNOCKGATE_SKIP_VERIFY=1."
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "${checksum_file}"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c "${checksum_file}"
  else
    die "missing sha256sum or shasum for checksum verification"
  fi
  [[ -s "${file}" ]] || die "downloaded asset is empty: ${file}"
}

download_file() {
  local url="$1"
  local output="$2"
  yellow "Downloading: ${url}"
  curl --fail --location --show-error \
    --connect-timeout "${KNOCKGATE_CONNECT_TIMEOUT:-15}" \
    --max-time "${KNOCKGATE_DOWNLOAD_TIMEOUT:-300}" \
    --retry "${KNOCKGATE_DOWNLOAD_RETRIES:-3}" \
    --retry-delay 2 \
    --retry-connrefused \
    "$url" -o "$output"
}

main() {
  require_root
  need_cmd uname
  need_cmd mktemp

  local arch asset url tmpdir
  arch="$(detect_arch)"
  asset="$(release_asset "$arch")"
  url="$(release_url "$arch")"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf '"$(printf '%q' "$tmpdir")" EXIT

  blue "${PROJECT_NAME} installer"
  yellow "Binary asset: ${url}"

  install_runtime_deps

  download_file "$url" "${tmpdir}/${asset}"
  download_file "${url}.sha256" "${tmpdir}/${asset}.sha256"
  (cd "$tmpdir" && verify_asset "${asset}" "${asset}.sha256")
  tar -xzf "${tmpdir}/${asset}" -C "$tmpdir"
  install -m 0755 "${tmpdir}/knockgate_linux_${arch}/knockgate" "${INSTALL_DIR}/knockgate"

  green "Installed:"
  printf '  %s\n' "${INSTALL_DIR}/knockgate"

  yellow "Run the server manager with: sudo knockgate"
}

main "$@"
