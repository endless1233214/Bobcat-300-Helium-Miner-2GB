#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATH="/opt/homebrew/opt/e2fsprogs/sbin:/opt/homebrew/opt/e2fsprogs/bin:$PATH"

WORK="$ROOT/_work"
DOWNLOADS="$ROOT/downloads"
DIST="$ROOT/dist"
TOOLS="$ROOT/tools"

IMAGE_NAME="${IMAGE_NAME:-bobcat300-rk3566-custom}"
IMAGE_SIZE_MIB="${IMAGE_SIZE_MIB:-4096}"
REGION="${REGION:-US915}"
PF_REGION="${PF_REGION:-US915_SB2}"

DEBIAN_BASE_URL="${DEBIAN_BASE_URL:-https://cloud.debian.org/images/cloud/bookworm/latest}"
DEBIAN_TAR="${DEBIAN_TAR:-debian-12-generic-arm64.tar.xz}"

NEBRA_TAG="${NEBRA_TAG:-v1.3.3-helium-bobcat-rk3566-2024-07-12-OpenFleet}"
NEBRA_ASSET="${NEBRA_ASSET:-helium-bobcat-rk3566-2024-07-12.zip}"
NEBRA_BASE_URL="${NEBRA_BASE_URL:-https://github.com/NebraLtd/helium-bobcat-rk3566/releases/download/$NEBRA_TAG}"

GATEWAY_VERSION="${GATEWAY_VERSION:-1.3.0}"
GATEWAY_TAR="${GATEWAY_TAR:-helium-gateway-${GATEWAY_VERSION}-aarch64-unknown-linux-musl.tar.gz}"
GATEWAY_URL="${GATEWAY_URL:-https://github.com/helium/gateway-rs/releases/download/v${GATEWAY_VERSION}/${GATEWAY_TAR}}"

P1_START=81920
P1_SECTORS=81920
P2_START=163840

LORA_PKT_FWD_PATH="/docker/overlay2/11a0e1435ce77ee2123246c602cf54ce796ad06fc207454dc1350eb15be1d0e0/diff/opt/sx1302/lora_pkt_fwd"
CHIP_ID_PATH="/docker/overlay2/11a0e1435ce77ee2123246c602cf54ce796ad06fc207454dc1350eb15be1d0e0/diff/opt/sx1302/chip_id"
RESET_LGW_PATH="/docker/overlay2/f8bc07a3453219e0cfd5b482069f5476349601e54fe0ac708531fd697a620886/diff/opt/reset_lgw.sh"
TEMPLATES_PATH="/docker/overlay2/15b5a7cb504fe2ad7ae4c19a9d8c941835c6f59eee8e1d00c5dfaae5bd5ec456/diff/opt/pktfwd/config/lora_templates_sx1302"
GATEWAY_MFR_PATH="/docker/overlay2/2a6cb8b223ef14ae95e6a1d5719d287a06fd4230cf0b848d98be3723bfaf9410/diff/opt/pktfwd-dependencies/hm_pyhelper/gateway_mfr_aarch64"

mkdir -p "$WORK" "$DOWNLOADS" "$DIST"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing dependency: $1" >&2
    echo "Run scripts/bootstrap-macos.sh first." >&2
    exit 2
  fi
}

download() {
  local url="$1"
  local out="$2"
  if [[ ! -f "$out" ]]; then
    echo "Downloading $(basename "$out")"
    curl -fL --progress-bar "$url" -o "$out"
  fi
}

extract_partition() {
  local image="$1"
  local index="$2"
  local out="$3"
  if [[ -f "$out" ]]; then
    return
  fi
  eval "$(python3 "$TOOLS/partinfo.py" "$image" --shell "$index")"
  echo "Extracting partition $index from $(basename "$image")"
  dd if="$image" of="$out" bs=512 skip="$START" count="$SECTORS" status=progress
}

debugfs_dump() {
  local image="$1"
  local src="$2"
  local dest="$3"
  rm -f "$dest"
  debugfs -R "dump $src $dest" "$image" >/dev/null
}

enable_service() {
  local rootfs="$1"
  local unit="$2"
  local wants="/etc/systemd/system/multi-user.target.wants/${unit}.service"
  debugfs -w -R "rm $wants" "$rootfs" >/dev/null 2>&1 || true
  debugfs -w -R "symlink $wants ../${unit}.service" "$rootfs" >/dev/null
}

for cmd in curl python3 shasum tar unzip dd truncate rsync mkfs.fat mcopy e2cp e2mkdir e2rm debugfs e2fsck resize2fs tune2fs; do
  need "$cmd"
done

DEBIAN_ARCHIVE="$DOWNLOADS/$DEBIAN_TAR"
DEBIAN_SUMS="$DOWNLOADS/SHA512SUMS"
download "$DEBIAN_BASE_URL/$DEBIAN_TAR" "$DEBIAN_ARCHIVE"
download "$DEBIAN_BASE_URL/SHA512SUMS" "$DEBIAN_SUMS"
DEBIAN_EXPECTED="$(awk -v f="$DEBIAN_TAR" '$2 == f {print $1}' "$DEBIAN_SUMS")"
DEBIAN_ACTUAL="$(shasum -a 512 "$DEBIAN_ARCHIVE" | awk '{print $1}')"
if [[ -z "$DEBIAN_EXPECTED" || "$DEBIAN_EXPECTED" != "$DEBIAN_ACTUAL" ]]; then
  echo "Debian SHA512 verification failed." >&2
  exit 1
fi

NEBRA_ZIP="$DOWNLOADS/$NEBRA_ASSET"
NEBRA_ZIP_SHA="$DOWNLOADS/$NEBRA_ASSET.sha512"
download "$NEBRA_BASE_URL/$NEBRA_ASSET" "$NEBRA_ZIP"
download "$NEBRA_BASE_URL/$NEBRA_ASSET.sha512" "$NEBRA_ZIP_SHA"
NEBRA_EXPECTED="$(awk '{print $1; exit}' "$NEBRA_ZIP_SHA")"
NEBRA_ACTUAL="$(shasum -a 512 "$NEBRA_ZIP" | awk '{print $1}')"
if [[ "$NEBRA_EXPECTED" != "$NEBRA_ACTUAL" ]]; then
  echo "Nebra reference image SHA512 verification failed." >&2
  exit 1
fi

GATEWAY_ARCHIVE="$DOWNLOADS/$GATEWAY_TAR"
download "$GATEWAY_URL" "$GATEWAY_ARCHIVE"

DEBIAN_RAW="$WORK/debian-12-generic-arm64.raw"
if [[ ! -f "$DEBIAN_RAW" ]]; then
  rm -rf "$WORK/debian-extract"
  mkdir -p "$WORK/debian-extract"
  tar -xJf "$DEBIAN_ARCHIVE" -C "$WORK/debian-extract"
  mv "$WORK/debian-extract/disk.raw" "$DEBIAN_RAW"
  rmdir "$WORK/debian-extract"
fi

NEBRA_IMG="$WORK/$NEBRA_ASSET.img"
if [[ ! -f "$NEBRA_IMG" ]]; then
  member="$(unzip -Z1 "$NEBRA_ZIP" | grep -E '\.img$' | head -1)"
  if [[ -z "$member" ]]; then
    echo "Could not find .img inside $NEBRA_ZIP" >&2
    exit 1
  fi
  unzip -p "$NEBRA_ZIP" "$member" > "$NEBRA_IMG"
fi

echo "Reference image partitions:"
python3 "$TOOLS/partinfo.py" "$NEBRA_IMG"

BOARD="$WORK/board-support"
PKTFWD="$WORK/pktfwd"
mkdir -p "$BOARD" "$PKTFWD"
NEBRA_P1="$WORK/nebra-part1-fat.img"
NEBRA_ROOTA="$WORK/nebra-rootA.img"
NEBRA_DATA="$WORK/nebra-data.img"
extract_partition "$NEBRA_IMG" 1 "$NEBRA_P1"
extract_partition "$NEBRA_IMG" 2 "$NEBRA_ROOTA"
extract_partition "$NEBRA_IMG" 6 "$NEBRA_DATA"

debugfs_dump "$NEBRA_ROOTA" "/boot/Image" "$BOARD/Image"
debugfs_dump "$NEBRA_ROOTA" "/boot/rk3566-bobcat.dtb" "$BOARD/rk3566-bobcat.dtb"
mcopy -i "$NEBRA_P1" ::idbloader.bin "$BOARD/idbloader.bin" >/dev/null 2>&1 || true
mcopy -i "$NEBRA_P1" ::uboot.img "$BOARD/uboot.img" >/dev/null 2>&1 || true

debugfs_dump "$NEBRA_DATA" "$LORA_PKT_FWD_PATH" "$PKTFWD/lora_pkt_fwd"
debugfs_dump "$NEBRA_DATA" "$CHIP_ID_PATH" "$PKTFWD/chip_id"
debugfs_dump "$NEBRA_DATA" "$RESET_LGW_PATH" "$PKTFWD/reset_lgw.sh"
debugfs_dump "$NEBRA_DATA" "$GATEWAY_MFR_PATH" "$PKTFWD/gateway_mfr_aarch64"
rm -rf "$PKTFWD/templates"
mkdir -p "$PKTFWD/templates.tmp"
debugfs -R "rdump $TEMPLATES_PATH $PKTFWD/templates.tmp" "$NEBRA_DATA" >/dev/null 2>&1 || true
if [[ -d "$PKTFWD/templates.tmp/lora_templates_sx1302" ]]; then
  mv "$PKTFWD/templates.tmp/lora_templates_sx1302" "$PKTFWD/templates"
else
  echo "Failed to extract SX1302 packet forwarder templates." >&2
  exit 1
fi
rm -rf "$PKTFWD/templates.tmp"
chmod 0755 "$PKTFWD/lora_pkt_fwd" "$PKTFWD/chip_id" "$PKTFWD/reset_lgw.sh" "$PKTFWD/gateway_mfr_aarch64"

GATEWAY_DIR="$WORK/gateway-rs"
rm -rf "$GATEWAY_DIR"
mkdir -p "$GATEWAY_DIR"
tar -xzf "$GATEWAY_ARCHIVE" -C "$GATEWAY_DIR"
chmod 0755 "$GATEWAY_DIR/helium_gateway"

ROOTFS_SRC="$WORK/debian-rootfs.ext4"
if [[ ! -f "$ROOTFS_SRC" ]]; then
  extract_partition "$DEBIAN_RAW" 1 "$ROOTFS_SRC"
fi

TOTAL_SECTORS=$(( IMAGE_SIZE_MIB * 1024 * 1024 / 512 ))
P2_SECTORS=$(( TOTAL_SECTORS - P2_START ))
ROOT_BYTES=$(( P2_SECTORS * 512 ))
ROOTFS="$WORK/rootfs-${IMAGE_NAME}.ext4"
rm -f "$ROOTFS"
cp "$ROOTFS_SRC" "$ROOTFS"
truncate -s "$ROOT_BYTES" "$ROOTFS"
e2fsck -fy "$ROOTFS" >/dev/null
resize2fs "$ROOTFS" >/dev/null
tune2fs -U random "$ROOTFS" >/dev/null
ROOT_UUID="$(tune2fs -l "$ROOTFS" | awk -F': ' '/Filesystem UUID/ {print $2}')"

STAGED="$WORK/rootfs-overlay"
rm -rf "$STAGED"
mkdir -p "$STAGED"
rsync -a "$ROOT/image/rootfs-overlay/" "$STAGED/"

python3 - "$STAGED" "$REGION" "$PF_REGION" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
replacements = {
    "__REGION__": sys.argv[2],
    "__PF_REGION__": sys.argv[3],
}
for path in root.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        continue
    for old, new in replacements.items():
        text = text.replace(old, new)
    path.write_text(text)
PY

mkdir -p "$STAGED/boot" "$STAGED/usr/local/bin" "$STAGED/opt/bobcat-miner/pktfwd/templates" "$STAGED/etc/bobcat-miner"
cp "$BOARD/Image" "$STAGED/boot/Image"
cp "$BOARD/rk3566-bobcat.dtb" "$STAGED/boot/rk3566-bobcat.dtb"
cp "$GATEWAY_DIR/helium_gateway" "$STAGED/usr/local/bin/helium_gateway"
cp "$PKTFWD/lora_pkt_fwd" "$STAGED/opt/bobcat-miner/pktfwd/lora_pkt_fwd"
cp "$PKTFWD/chip_id" "$STAGED/opt/bobcat-miner/pktfwd/chip_id"
cp "$PKTFWD/reset_lgw.sh" "$STAGED/opt/bobcat-miner/pktfwd/reset_lgw.sh"
cp "$PKTFWD/gateway_mfr_aarch64" "$STAGED/usr/local/bin/gateway_mfr"
cp "$PKTFWD/templates"/* "$STAGED/opt/bobcat-miner/pktfwd/templates/"

cat > "$STAGED/etc/fstab" <<EOF
UUID=$ROOT_UUID / ext4 defaults,noatime,errors=remount-ro 0 1
EOF

WEBUI_USER="${WEBUI_USER:-admin}"
WEBUI_PASSWORD="${WEBUI_PASSWORD:-$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(18))
PY
)}"
cat > "$STAGED/etc/bobcat-miner/webui.env" <<EOF
BOBCAT_WEBUI_USER=$WEBUI_USER
BOBCAT_WEBUI_PASSWORD=$WEBUI_PASSWORD
EOF
chmod 0600 "$STAGED/etc/bobcat-miner/webui.env"

if [[ -n "${AUTHORIZED_KEY_FILE:-}" ]]; then
  cp "$AUTHORIZED_KEY_FILE" "$STAGED/etc/bobcat-miner/authorized_keys"
  chmod 0600 "$STAGED/etc/bobcat-miner/authorized_keys"
fi

chmod 0755 \
  "$STAGED/usr/local/bin/helium_gateway" \
  "$STAGED/usr/local/bin/gateway_mfr" \
  "$STAGED/opt/bobcat-miner/pktfwd/lora_pkt_fwd" \
  "$STAGED/opt/bobcat-miner/pktfwd/chip_id" \
  "$STAGED/opt/bobcat-miner/pktfwd/reset_lgw.sh" \
  "$STAGED/usr/local/sbin/bobcat-firstboot" \
  "$STAGED/usr/local/sbin/bobcat-pktfwd" \
  "$STAGED/usr/local/sbin/bobcat-set-region" \
  "$STAGED/usr/local/lib/bobcat-miner/"*.py

python3 "$TOOLS/install_overlay.py" "$ROOTFS" "$STAGED"
enable_service "$ROOTFS" "bobcat-firstboot"
enable_service "$ROOTFS" "helium-gateway"
enable_service "$ROOTFS" "bobcat-pktfwd"
enable_service "$ROOTFS" "bobcat-webui"
e2fsck -fy "$ROOTFS" >/dev/null

BOOT_FAT="$WORK/boot-fat.img"
rm -f "$BOOT_FAT"
truncate -s $(( P1_SECTORS * 512 )) "$BOOT_FAT"
mkfs.fat -F 16 -n RESIN-BOOT "$BOOT_FAT" >/dev/null
BOOT_FILES="$WORK/boot-fat-files"
rm -rf "$BOOT_FILES"
mkdir -p "$BOOT_FILES"
touch "$BOOT_FILES/balena-image"
touch "$BOOT_FILES/extra_uEnv.txt"
cp "$BOARD/idbloader.bin" "$BOOT_FILES/idbloader.bin" 2>/dev/null || true
cp "$BOARD/uboot.img" "$BOOT_FILES/uboot.img" 2>/dev/null || true
for file in "$BOOT_FILES"/*; do
  [[ -f "$file" ]] || continue
  mcopy -i "$BOOT_FAT" "$file" "::$(basename "$file")"
done

OUT="$DIST/${IMAGE_NAME}.img"
TMP_OUT="$WORK/${IMAGE_NAME}.img"
rm -f "$TMP_OUT" "$OUT"
truncate -s "${IMAGE_SIZE_MIB}M" "$TMP_OUT"
dd if="$NEBRA_IMG" of="$TMP_OUT" bs=1048576 count=40 conv=notrunc status=none
dd if="$BOOT_FAT" of="$TMP_OUT" bs=1048576 seek=40 conv=notrunc status=none
dd if="$ROOTFS" of="$TMP_OUT" bs=1048576 seek=80 conv=notrunc status=progress
python3 "$TOOLS/write_mbr.py" "$TMP_OUT" \
  --p1-start "$P1_START" --p1-sectors "$P1_SECTORS" \
  --p2-start "$P2_START" --p2-sectors "$P2_SECTORS"

mv "$TMP_OUT" "$OUT"
shasum -a 256 "$OUT" > "$OUT.sha256"

CREDENTIALS="$DIST/${IMAGE_NAME}.credentials.txt"
cat > "$CREDENTIALS" <<EOF
Web UI:
  URL: http://bobcat300.local/ or http://<dhcp-address>/
  Username: $WEBUI_USER
  Password: $WEBUI_PASSWORD

Image:
  $OUT
  $(cat "$OUT.sha256")
EOF
chmod 0600 "$CREDENTIALS"

echo
echo "Built image:"
echo "  $OUT"
echo "  $OUT.sha256"
echo "Credentials:"
echo "  $CREDENTIALS"
