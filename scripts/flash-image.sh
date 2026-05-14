#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_rkdeveloptool.sh
source "$ROOT/scripts/_rkdeveloptool.sh"
TOOL="$(rkdeveloptool_path)"
LOADER="$(rk356x_loader_path)"
IMAGE="${1:-$ROOT/dist/bobcat300-rk3566-custom.img}"

if [[ ! -f "$IMAGE" ]]; then
  echo "Missing image: $IMAGE" >&2
  exit 2
fi

echo "Current Rockchip device mode:"
"$TOOL" ld

if "$TOOL" ld | grep -q 'Maskrom'; then
  echo
  echo "Device is in Maskrom; loading temporary RK356x RAM loader first:"
  "$TOOL" db "$LOADER"
fi

echo
echo "This will WRITE the following image to Bobcat eMMC from LBA/address 0:"
echo "  $IMAGE"
echo
echo "It will overwrite the current eMMC contents."
read -r -p "Type FLASH-BOBCAT-CUSTOM to continue: " CONFIRM
if [[ "$CONFIRM" != "FLASH-BOBCAT-CUSTOM" ]]; then
  echo "Cancelled."
  exit 1
fi

"$TOOL" wl 0 "$IMAGE"
sync
"$TOOL" rd || true
echo "Flash command finished. Disconnect USB/power, reconnect normal power, and give it several minutes to boot."

