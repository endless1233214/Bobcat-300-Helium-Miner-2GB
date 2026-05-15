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
BOOT_PROFILE="${BOOT_PROFILE:-simple}"

DEBIAN_BASE_URL="${DEBIAN_BASE_URL:-https://cloud.debian.org/images/cloud/bookworm/latest}"
DEBIAN_TAR="${DEBIAN_TAR:-debian-12-generic-arm64.tar.xz}"

SUPPORT_IMAGE_ASSET="${SUPPORT_IMAGE_ASSET:-bobcat-rk3566-support.zip}"
SUPPORT_IMAGE_BASE_URL="${SUPPORT_IMAGE_BASE_URL:-}"

GATEWAY_VERSION="${GATEWAY_VERSION:-1.3.0}"
GATEWAY_TAR="${GATEWAY_TAR:-helium-gateway-${GATEWAY_VERSION}-aarch64-unknown-linux-musl.tar.gz}"
GATEWAY_URL="${GATEWAY_URL:-https://github.com/helium/gateway-rs/releases/download/v${GATEWAY_VERSION}/${GATEWAY_TAR}}"

case "$BOOT_PROFILE" in
  simple)
    P1_START=40960
    P1_SECTORS=61440
    P2_START=204800
    ;;
  *)
    echo "Unsupported BOOT_PROFILE=$BOOT_PROFILE. Use simple." >&2
    exit 2
    ;;
esac

LORA_PKT_FWD_PATH="/docker/overlay2/11a0e1435ce77ee2123246c602cf54ce796ad06fc207454dc1350eb15be1d0e0/diff/opt/sx1302/lora_pkt_fwd"
CHIP_ID_PATH="/docker/overlay2/11a0e1435ce77ee2123246c602cf54ce796ad06fc207454dc1350eb15be1d0e0/diff/opt/sx1302/chip_id"
RESET_LGW_PATH="/docker/overlay2/f8bc07a3453219e0cfd5b482069f5476349601e54fe0ac708531fd697a620886/diff/opt/reset_lgw.sh"
TEMPLATES_PATH="/docker/overlay2/15b5a7cb504fe2ad7ae4c19a9d8c941835c6f59eee8e1d00c5dfaae5bd5ec456/diff/opt/pktfwd/config/lora_templates_sx1302"
GATEWAY_MFR_PATH="/docker/overlay2/2a6cb8b223ef14ae95e6a1d5719d287a06fd4230cf0b848d98be3723bfaf9410/diff/opt/pktfwd-dependencies/hm_pyhelper/gateway_mfr_aarch64"

mkdir -p "$WORK" "$DOWNLOADS" "$DIST"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing dependency: $1" >&2
    echo "Run scripts/bootstrap-macos.sh or scripts/bootstrap-linux.sh first." >&2
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

SUPPORT_ZIP="$DOWNLOADS/$SUPPORT_IMAGE_ASSET"
SUPPORT_ZIP_SHA="$DOWNLOADS/$SUPPORT_IMAGE_ASSET.sha512"
if [[ -n "${SUPPORT_IMAGE_ZIP:-}" ]]; then
  SUPPORT_ZIP="$SUPPORT_IMAGE_ZIP"
elif [[ ! -f "$SUPPORT_ZIP" ]]; then
  if [[ -z "$SUPPORT_IMAGE_BASE_URL" ]]; then
    cat >&2 <<'MSG'
Missing support image zip.
Set SUPPORT_IMAGE_ZIP=/path/to/bobcat-rk3566-support.zip, or set
SUPPORT_IMAGE_BASE_URL and SUPPORT_IMAGE_ASSET to download it.
MSG
    exit 2
  fi
  download "$SUPPORT_IMAGE_BASE_URL/$SUPPORT_IMAGE_ASSET" "$SUPPORT_ZIP"
fi
if [[ -n "${SUPPORT_IMAGE_SHA512:-}" ]]; then
  SUPPORT_EXPECTED="$SUPPORT_IMAGE_SHA512"
elif [[ -f "$SUPPORT_ZIP_SHA" ]]; then
  SUPPORT_EXPECTED="$(awk '{print $1; exit}' "$SUPPORT_ZIP_SHA")"
elif [[ -n "$SUPPORT_IMAGE_BASE_URL" ]]; then
  download "$SUPPORT_IMAGE_BASE_URL/$SUPPORT_IMAGE_ASSET.sha512" "$SUPPORT_ZIP_SHA"
  SUPPORT_EXPECTED="$(awk '{print $1; exit}' "$SUPPORT_ZIP_SHA")"
else
  SUPPORT_EXPECTED=""
fi
if [[ -n "$SUPPORT_EXPECTED" ]]; then
  SUPPORT_ACTUAL="$(shasum -a 512 "$SUPPORT_ZIP" | awk '{print $1}')"
  if [[ "$SUPPORT_EXPECTED" != "$SUPPORT_ACTUAL" ]]; then
    echo "Support image SHA512 verification failed." >&2
    exit 1
  fi
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

SUPPORT_IMG="$WORK/$SUPPORT_IMAGE_ASSET.img"
if [[ ! -f "$SUPPORT_IMG" ]]; then
  member="$(unzip -Z1 "$SUPPORT_ZIP" | grep -E '\.img$' | head -1)"
  if [[ -z "$member" ]]; then
    echo "Could not find .img inside $SUPPORT_ZIP" >&2
    exit 1
  fi
  unzip -p "$SUPPORT_ZIP" "$member" > "$SUPPORT_IMG"
fi

need xz
SIMPLE_BOOT_IMG="$WORK/bobcat-rk3566-simpleboot-reference.img"
if [[ -n "${SIMPLE_BOOT_IMAGE:-}" ]]; then
  SIMPLE_BOOT_IMG="$SIMPLE_BOOT_IMAGE"
elif [[ -f "$SIMPLE_BOOT_IMG" ]]; then
  :
elif [[ -n "${SIMPLE_BOOT_IMAGE_XZ:-}" && -f "$SIMPLE_BOOT_IMAGE_XZ" ]]; then
  xz -dc "$SIMPLE_BOOT_IMAGE_XZ" > "$SIMPLE_BOOT_IMG"
elif [[ -f "$DOWNLOADS/bobcat-rk3566-simpleboot-reference.img.xz" ]]; then
  xz -dc "$DOWNLOADS/bobcat-rk3566-simpleboot-reference.img.xz" > "$SIMPLE_BOOT_IMG"
else
  cat >&2 <<'MSG'
BOOT_PROFILE=simple requires a Bobcat RK3566 simple boot reference image.
Set SIMPLE_BOOT_IMAGE=/path/to/bobcat-rk3566-reference.img or
SIMPLE_BOOT_IMAGE_XZ=/path/to/bobcat-rk3566-reference.img.xz.
MSG
  exit 2
fi

echo "Support image partitions:"
python3 "$TOOLS/partinfo.py" "$SUPPORT_IMG"
echo "Simple boot reference image partitions:"
python3 "$TOOLS/partinfo.py" "$SIMPLE_BOOT_IMG"

BOARD="$WORK/board-support"
PKTFWD="$WORK/pktfwd"
mkdir -p "$BOARD" "$PKTFWD"
SUPPORT_DATA="$WORK/support-data.img"
extract_partition "$SUPPORT_IMG" 6 "$SUPPORT_DATA"

SIMPLE_BOOT_P1="$WORK/simpleboot-part1-fat.img"
extract_partition "$SIMPLE_BOOT_IMG" 1 "$SIMPLE_BOOT_P1"

mcopy -i "$SIMPLE_BOOT_P1" ::Image "$BOARD/Image" >/dev/null
mcopy -i "$SIMPLE_BOOT_P1" ::rk3566-bobcat.dtb "$BOARD/rk3566-bobcat.dtb" >/dev/null

debugfs_dump "$SUPPORT_DATA" "$LORA_PKT_FWD_PATH" "$PKTFWD/lora_pkt_fwd"
debugfs_dump "$SUPPORT_DATA" "$CHIP_ID_PATH" "$PKTFWD/chip_id"
debugfs_dump "$SUPPORT_DATA" "$RESET_LGW_PATH" "$PKTFWD/reset_lgw.sh"
debugfs_dump "$SUPPORT_DATA" "$GATEWAY_MFR_PATH" "$PKTFWD/gateway_mfr_aarch64"
rm -rf "$PKTFWD/templates"
mkdir -p "$PKTFWD/templates.tmp"
debugfs -R "rdump $TEMPLATES_PATH $PKTFWD/templates.tmp" "$SUPPORT_DATA" >/dev/null 2>&1 || true
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
ROOT_UUID="$(tune2fs -l "$ROOTFS" | awk -F: '/Filesystem UUID/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')"
if [[ -z "$ROOT_UUID" ]]; then
  echo "Could not read root filesystem UUID." >&2
  exit 1
fi

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

WEBUI_CREDENTIAL_MODE="${WEBUI_CREDENTIAL_MODE:-build}"
WEBUI_USER="${WEBUI_USER:-admin}"
WEBUI_PASSWORD="${WEBUI_PASSWORD:-$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(18))
PY
)}"
case "$WEBUI_CREDENTIAL_MODE" in
  build)
    cat > "$STAGED/etc/bobcat-miner/webui.env" <<EOF
BOBCAT_WEBUI_USER=$WEBUI_USER
BOBCAT_WEBUI_PASSWORD=$WEBUI_PASSWORD
EOF
    chmod 0600 "$STAGED/etc/bobcat-miner/webui.env"
    ;;
  setup)
    rm -f "$STAGED/etc/bobcat-miner/webui.env"
    touch "$STAGED/etc/bobcat-miner/webui-first-run-setup"
    ;;
  *)
    echo "Unsupported WEBUI_CREDENTIAL_MODE=$WEBUI_CREDENTIAL_MODE. Use build or setup." >&2
    exit 2
    ;;
esac

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
if [[ "$BOOT_PROFILE" == "simple" ]]; then
  cp "$SIMPLE_BOOT_P1" "$BOOT_FAT"
fi

OUT="$DIST/${IMAGE_NAME}.img"
TMP_OUT="$WORK/${IMAGE_NAME}.img"
rm -f "$TMP_OUT" "$OUT"
truncate -s "${IMAGE_SIZE_MIB}M" "$TMP_OUT"
PREBOOT_IMAGE="$SIMPLE_BOOT_IMG"
dd if="$PREBOOT_IMAGE" of="$TMP_OUT" bs=512 count="$P1_START" conv=notrunc status=none
dd if="$BOOT_FAT" of="$TMP_OUT" bs=512 seek="$P1_START" conv=notrunc status=none
dd if="$ROOTFS" of="$TMP_OUT" bs=1048576 seek="$(( P2_START / 2048 ))" conv=notrunc status=progress
python3 "$TOOLS/write_mbr.py" "$TMP_OUT" \
  --p1-start "$P1_START" --p1-sectors "$P1_SECTORS" \
  --p2-start "$P2_START" --p2-sectors "$P2_SECTORS"

mv "$TMP_OUT" "$OUT"
shasum -a 256 "$OUT" > "$OUT.sha256"

CREDENTIALS="$DIST/${IMAGE_NAME}.credentials.txt"
if [[ "$WEBUI_CREDENTIAL_MODE" == "build" ]]; then
  cat > "$CREDENTIALS" <<EOF
Web UI:
  URL: http://<dhcp-address>/
  Username: $WEBUI_USER
  Password: $WEBUI_PASSWORD

Note:
  mDNS/Avahi is not installed yet, so bobcat300.local may not resolve.
  Use your router DHCP table or an ARP scan to find the address.

Image:
  $OUT
  $(cat "$OUT.sha256")
EOF
else
  cat > "$CREDENTIALS" <<EOF
Web UI:
  URL: http://<dhcp-address>/
  Credentials: create them on first visit from a trusted LAN.

Note:
  This image was built with WEBUI_CREDENTIAL_MODE=setup, so no shared web UI
  password is baked into the image. Use your router DHCP table or an ARP scan
  to find the address, open the web UI, and create the admin login.

Image:
  $OUT
  $(cat "$OUT.sha256")
EOF
fi
chmod 0600 "$CREDENTIALS"

echo
echo "Built image:"
echo "  $OUT"
echo "  $OUT.sha256"
echo "Credentials:"
echo "  $CREDENTIALS"
