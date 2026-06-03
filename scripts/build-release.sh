#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-dev}"
GOOS_TARGET="${GOOS:-linux}"
GOARCH_TARGET="${GOARCH:-$(go env GOARCH)}"
OUT_DIR="${OUT_DIR:-dist}"
PKG="knockgate_${GOOS_TARGET}_${GOARCH_TARGET}"

mkdir -p "${OUT_DIR}/${PKG}"

CGO_ENABLED="${CGO_ENABLED:-1}" \
GOOS="${GOOS_TARGET}" \
GOARCH="${GOARCH_TARGET}" \
go build -trimpath \
  -ldflags "-s -w -X main.version=${VERSION}" \
  -o "${OUT_DIR}/${PKG}/knockgate" ./cmd/knockgate

cp README.md README.zh-CN.md LICENSE install.sh "${OUT_DIR}/${PKG}/"
mkdir -p "${OUT_DIR}/${PKG}/clients"
cp -R clients/shell "${OUT_DIR}/${PKG}/clients/"
chmod 0755 "${OUT_DIR}/${PKG}/knockgate" "${OUT_DIR}/${PKG}/install.sh" "${OUT_DIR}/${PKG}/clients/shell/knockgate-knock.sh" "${OUT_DIR}/${PKG}/clients/shell/knockgate-check.sh"

tar -C "${OUT_DIR}" -czf "${OUT_DIR}/${PKG}.tar.gz" "${PKG}"
rm -rf "${OUT_DIR:?}/${PKG}"

if command -v sha256sum >/dev/null 2>&1; then
  (cd "${OUT_DIR}" && sha256sum "${PKG}.tar.gz" > "${PKG}.tar.gz.sha256")
else
  (cd "${OUT_DIR}" && shasum -a 256 "${PKG}.tar.gz" > "${PKG}.tar.gz.sha256")
fi

echo "${OUT_DIR}/${PKG}.tar.gz"
