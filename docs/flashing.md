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
scripts/build-image.sh
```

Then flash:

```sh
scripts/flash-image.sh dist/bobcat300-rk3566-custom.img
```

The flash helper requires typing `FLASH-BOBCAT-CUSTOM` before it writes.

