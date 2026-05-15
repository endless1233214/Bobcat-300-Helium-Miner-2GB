# Research Log

## Confirmed On First Test Unit

- Rockchip USB Loader mode works on macOS with `rkdeveloptool`.
- `rkdeveloptool ppt` does not understand the image's DOS/extended partition
  layout and may say no partition table even when LBA0 contains a valid MBR.
- Avoid parallel Rockchip operations. Concurrent `rkdeveloptool` reads caused
  communication errors; use one device operation at a time.
- The original eMMC had real Rockchip bootloader sectors and an MBR, but most
  OS partition samples read as `0xcc`, so the installed OS area appeared erased
  or filler-filled.

## Reference Image

- Latest reference image observed during this bring-up:
  `v1.3.3-helium-bobcat-rk3566-2024-07-12-OpenFleet`
- Kernel string from reference image:
  `Linux version 4.19.232-rockchip-standard`
- The reference U-Boot environment loads `/boot/Image` and
  `/boot/rk3566-bobcat.dtb` from partition 2.

## Builder Direction

The first custom image uses:

- Debian ARM64 cloud root filesystem for normal `systemd`, SSH, networking,
  Python, and package management.
- Bobcat kernel and device tree from the public Bobcat RK3566 reference image.
- Official Helium `gateway-rs` release for `helium_gateway`.
- Bobcat SX1302 packet forwarder files extracted from the reference image until
  the project replaces them with a from-source build.

## Known-Good Image Comparison

The Crankk Bobcat RK3566 image uses a simpler boot layout than Nebra/OpenFleet:

- partition 1 starts at LBA 40960 and contains `boot.scr`, `uEnv.txt`, `Image`,
  `initrd.gz`, and `rk3566-bobcat.dtb`
- partition 2 starts at LBA 204800 and is the root filesystem
- `boot.scr` sets `root=/dev/mmcblk0p2` and passes an initrd to `booti`

This is useful for a plain root filesystem because it avoids the Nebra/Balena
U-Boot environment that discovers the root partition by UUID and expects a
Balena-style boot marker.
