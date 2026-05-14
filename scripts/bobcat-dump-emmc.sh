#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_rkdeveloptool.sh
source "$ROOT/scripts/_rkdeveloptool.sh"
TOOL="$(rkdeveloptool_path)"
OUT="${1:-$ROOT/backups/bobcat-emmc-$(date +%Y%m%d-%H%M%S).img}"
SECTORS="${2:-}"

if [[ -z "$SECTORS" ]]; then
  cat <<'MSG'
Usage:
  scripts/bobcat-dump-emmc.sh /path/to/backup.img <sector_count>

Run scripts/bobcat-info.sh first, then choose the sector count from the
device flash size. sector_count = total_bytes / 512.

This script reads from the Bobcat only. It does not erase or write flash.
MSG
  exit 2
fi

mkdir -p "$(dirname "$OUT")"

echo "About to READ $SECTORS sectors from LBA 0 into:"
echo "  $OUT"
echo
read -r -p "Type READBOBCAT to continue: " CONFIRM
if [[ "$CONFIRM" != "READBOBCAT" ]]; then
  echo "Cancelled."
  exit 1
fi

"$TOOL" rl 0 "$SECTORS" "$OUT"
shasum -a 256 "$OUT" > "$OUT.sha256"
echo "Backup complete:"
cat "$OUT.sha256"

