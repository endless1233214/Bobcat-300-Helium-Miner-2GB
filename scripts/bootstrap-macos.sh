#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/_work"
BIN="$WORK/bin"
LOADERS="$WORK/loaders"

mkdir -p "$BIN" "$LOADERS"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required on macOS: https://brew.sh" >&2
  exit 2
fi

brew install autoconf automake libusb pkg-config e2fsprogs e2tools mtools dosfstools dtc xz jq

if [[ ! -x "$BIN/rkdeveloptool" ]]; then
  SRC="$WORK/rkdeveloptool-src"
  if [[ ! -d "$SRC/.git" ]]; then
    git clone --depth 1 https://github.com/rockchip-linux/rkdeveloptool "$SRC"
  fi
  (
    cd "$SRC"
    ./autogen.sh
    ./configure
    make -j"$(sysctl -n hw.ncpu)" CXXFLAGS='-g -O2 -Wno-error=vla-cxx-extension'
  )
  cp "$SRC/rkdeveloptool" "$BIN/rkdeveloptool"
fi

LOADER="$LOADERS/rk356x_spl_loader_ddr1056_v1.10.111.bin"
if [[ ! -f "$LOADER" ]]; then
  curl -fL --progress-bar \
    https://dl.radxa.com/rock3/images/loader/rock-3b/rk356x_spl_loader_ddr1056_v1.10.111.bin \
    -o "$LOADER"
fi

echo "rkdeveloptool: $("$BIN/rkdeveloptool" -v 2>&1 | head -1)"
echo "loader: $LOADER"

