# Flashing Workflow

## Enter Loader Mode

1. Connect a data-capable micro-USB cable to the Bobcat board port marked
   `USB_OTG` / `FLASH USB`.
2. Remove Bobcat power.
3. Hold `Recovery`.
4. Plug in the normal Bobcat power adapter.
5. Release `Recovery` after about one second.

If that does not work, hold `Recovery`, tap `Reset`, then release `Recovery`
after about one second.

## Detect

```sh
scripts/bobcat-detect.sh
```

Expected output contains either `Loader` or `Maskrom`.

## Back Up eMMC

Get flash info:

```sh
scripts/bobcat-info.sh
```

For the first test unit, Rockchip reported:

```text
Flash Size: 59640 MB
Flash Size: 122142720 Sectors
```

Dump using the sector count:

```sh
scripts/bobcat-dump-emmc.sh backups/bobcat-emmc.img 122142720
```

## Flash

Build an image first:

```sh
SUPPORT_IMAGE_ZIP=/path/to/bobcat-rk3566-support.zip \
SIMPLE_BOOT_IMAGE_XZ=/path/to/bobcat-rk3566-reference.img.xz \
scripts/build-image.sh
```

Then flash:

```sh
scripts/flash-image.sh dist/bobcat300-rk3566-custom.img
```

The flash helper requires typing `FLASH-BOBCAT-CUSTOM` before it writes.

## If Ethernet LEDs Stay Dark

The first custom image build had a malformed `/etc/fstab` `UUID=` line that
could prevent normal systemd boot. Rebuild with the fixed builder and flash the
newer `dist/bobcat300-rk3566-custom-v2.img` or any later image.

If Ethernet LEDs still stay dark after the corrected image, collect the boot
console. The reference U-Boot passes:

```text
console=ttyFIQ0,1500000
```

So the UART speed to try is `1500000`, not `115200`.

There is also a simple boot profile in `scripts/build-image.sh`. It uses a
known-working Bobcat RK3566 preboot area and FAT boot script while keeping this
project's custom Debian root filesystem:

```sh
SUPPORT_IMAGE_ZIP=/path/to/bobcat-rk3566-support.zip \
SIMPLE_BOOT_IMAGE_XZ=/path/to/bobcat-rk3566-reference.img.xz \
IMAGE_NAME=bobcat300-rk3566-simpleboot \
scripts/build-image.sh
```
