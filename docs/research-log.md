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

