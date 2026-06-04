#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-dev}"
GOOS_TARGET="${GOOS:-linux}"
GOARCH_TARGET="${GOARCH:-$(go env GOARCH)}"
GOARM_TARGET="${GOARM:-}"
GOMIPS_TARGET="${GOMIPS:-}"
OUT_DIR="${OUT_DIR:-dist}"

suffix="${GOOS_TARGET}_${GOARCH_TARGET}"
if [[ -n "${GOARM_TARGET}" ]]; then
  suffix="${suffix}v${GOARM_TARGET}"
fi
if [[ -n "${GOMIPS_TARGET}" ]]; then
  suffix="${suffix}_${GOMIPS_TARGET}"
fi

PKG="knockgate_client_cli_${suffix}"
mkdir -p "${OUT_DIR}/${PKG}"

CGO_ENABLED=0 \
GOOS="${GOOS_TARGET}" \
GOARCH="${GOARCH_TARGET}" \
GOARM="${GOARM_TARGET}" \
GOMIPS="${GOMIPS_TARGET}" \
go build -trimpath \
  -ldflags "-s -w -X main.version=${VERSION}" \
  -o "${OUT_DIR}/${PKG}/knockgate-client" ./cmd/knockgate-client

cp README.md README.zh-CN.md LICENSE "${OUT_DIR}/${PKG}/"
chmod 0755 "${OUT_DIR}/${PKG}/knockgate-client"

tar -C "${OUT_DIR}" -czf "${OUT_DIR}/${PKG}.tar.gz" "${PKG}"
rm -rf "${OUT_DIR:?}/${PKG}"

if command -v sha256sum >/dev/null 2>&1; then
  (cd "${OUT_DIR}" && sha256sum "${PKG}.tar.gz" > "${PKG}.tar.gz.sha256")
else
  (cd "${OUT_DIR}" && shasum -a 256 "${PKG}.tar.gz" > "${PKG}.tar.gz.sha256")
fi

echo "${OUT_DIR}/${PKG}.tar.gz"
