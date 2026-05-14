#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_rkdeveloptool.sh
source "$ROOT/scripts/_rkdeveloptool.sh"
TOOL="$(rkdeveloptool_path)"
LOADER="$(rk356x_loader_path)"
LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"

echo "Device list before loader:"
"$TOOL" ld | tee "$LOG_DIR/${STAMP}-ld-before.txt" || true

if "$TOOL" ld | grep -q 'Maskrom'; then
  echo
  echo "Device is in Maskrom. Downloading temporary RK356x RAM loader:"
  "$TOOL" db "$LOADER" | tee "$LOG_DIR/${STAMP}-download-boot.txt" || true
else
  echo
  echo "Device is already in Loader mode; skipping temporary RAM loader download."
fi

echo
echo "Device list after loader:"
"$TOOL" ld | tee "$LOG_DIR/${STAMP}-ld-after.txt" || true

echo
echo "Chip info:"
"$TOOL" rci | tee "$LOG_DIR/${STAMP}-chip-info.txt" || true

echo
echo "Flash info:"
"$TOOL" rfi | tee "$LOG_DIR/${STAMP}-flash-info.txt" || true

echo
echo "Partition table:"
"$TOOL" ppt | tee "$LOG_DIR/${STAMP}-partitions.txt" || true

echo
echo "Logs saved under: $LOG_DIR"

