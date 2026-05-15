# Bobcat 300 RK3566 Hardware Notes

## Board

- Target: Bobcat 300 G290/G295 style board.
- SoC: Rockchip RK3566.
- RAM: 2 GB confirmed on the chip in the first test unit.
- eMMC: Samsung, reported through Rockchip loader as about 59.6 GB.
- USB recovery: Rockchip Loader/Maskrom over the board port marked
  `USB_OTG` / `FLASH USB`.

## Rockchip USB Modes

`rkdeveloptool ld` output seen on the test unit:

```text
DevNo=1 Vid=0x2207,Pid=0x350a,LocationID=101 Loader
```

This means the board is already in Rockchip Loader mode. If it shows Maskrom,
the scripts can download the RK356x RAM loader before doing eMMC operations.

## Vendor-Style Reference Partition Layout

One Bobcat RK3566 reference image and the tested board both use the same early
MBR layout:

| Partition | Type | Start LBA | Sectors | Notes |
| --- | --- | ---: | ---: | --- |
| 1 | `0x0e` | 81920 | 81920 | FAT boot marker partition |
| 2 | `0x83` | 163840 | 1179648 | vendor root A in reference image |
| 3 | `0x83` | 1343488 | 1179648 | vendor root B in reference image |
| 4 | `0x0f` | 2523136 | varies | Extended state/data partition |

The custom image keeps the Rockchip boot area and partition 1 start, then uses
partition 2 as a normal Debian root filesystem.

## Bobcat-Specific Runtime Values

Values extracted from the Bobcat RK3566 hardware definition in the reference
image:

| Setting | Value |
| --- | --- |
| SX1302 SPI device | `/dev/spidev5.0` |
| ECC key URI | `ecc://i2c-5:96?slot=0` |
| Onboarding key URI | `ecc://i2c-5:96?slot=0` |
| Concentrator reset GPIO | `149` |
| Status LED GPIO | `129` |
| Button GPIO | `6` |
| MAC interface hint | `wlan0` |

## Bootloader Behavior

The reference U-Boot environment loads:

- kernel from partition 2: `/boot/Image`
- device tree from partition 2: `/boot/rk3566-bobcat.dtb`
- root filesystem by the UUID of partition 2

It also looks for a vendor boot marker on partition 1. The builder creates a
small FAT partition containing that marker plus copied bootloader files for
traceability.
