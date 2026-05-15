#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/_work"
BIN="$WORK/bin"
LOADERS="$WORK/loaders"

mkdir -p "$BIN" "$LOADERS"

if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y \
    autoconf \
    automake \
    build-essential \
    ca-certificates \
    curl \
    dosfstools \
    e2fsprogs \
    e2tools \
    git \
    jq \
    libusb-1.0-0-dev \
    mtools \
    pkg-config \
    python3 \
    rsync \
    unzip \
    xz-utils
else
  echo "Unsupported Linux package manager. Install the dependencies listed in this script manually." >&2
  exit 2
fi

if [[ ! -x "$BIN/rkdeveloptool" ]]; then
  SRC="$WORK/rkdeveloptool-src"
  if [[ ! -d "$SRC/.git" ]]; then
    git clone --depth 1 https://github.com/rockchip-linux/rkdeveloptool "$SRC"
  fi
  (
    cd "$SRC"
    ./autogen.sh
    ./configure
    make -j"$(nproc)"
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
