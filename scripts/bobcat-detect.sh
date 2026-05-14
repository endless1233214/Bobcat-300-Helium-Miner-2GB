#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_rkdeveloptool.sh
source "$ROOT/scripts/_rkdeveloptool.sh"
TOOL="$(rkdeveloptool_path)"

echo "Rockchip devices seen by rkdeveloptool:"
"$TOOL" ld || true

echo
echo "macOS USB entries that look relevant:"
system_profiler SPUSBDataType | grep -Ei -C 4 'rockchip|2207|rk35|maskrom|loader|bobcat' || true

echo
echo "If no device appears:"
echo "  1. Use the Bobcat board port marked USB_OTG / FLASH USB, not the other micro-USB port."
echo "  2. Use a known data-capable micro-USB cable."
echo "  3. Power off, hold Recovery, apply the Bobcat power brick, release Recovery after about 1 second."
echo "  4. If that does not enter loader mode, hold Recovery, tap Reset, then release Recovery after about 1 second."

