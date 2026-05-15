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

## First Crank-Boot Field Logs

The `bobcat300-rk3566-crankboot-v3` image booted on the test Bobcat. Ethernet,
`systemd`, the web UI, `gateway-rs`, the ECC identity, and the Helium router
path were all alive:

- `helium_gateway` started as gateway-rs `1.3.0`
- the gateway API listened on `127.0.0.1:4467`
- the local UDP gateway listener started on `127.0.0.1:1680`
- the region watcher fetched US915 config from Helium mainnet

The remaining failure was in the packet forwarder wrapper. `lora_pkt_fwd`
starts from `/opt/bobcat-miner/pktfwd/run` and internally executes
`./reset_lgw.sh`, but the helper had only been installed one directory above.
The log showed `sh: 1: ./reset_lgw.sh: not found` followed by
`ERROR: failed to reset SX1302`. The wrapper now copies `reset_lgw.sh` into the
run directory and exports `CONCENTRATOR_RESET_PIN=149` before launching the
forwarder.

## V4 Field Logs

The `bobcat300-rk3566-crankboot-v4` image fixed the packet forwarder reset path.
Observed packet forwarder logs show the concentrator is running:

- `PUSH_ACK` and `PULL_ACK` are received from local `gateway-rs`
- `PUSH_DATA acknowledged: 100.00%`
- `PULL_DATA sent: 3 (100.00% acknowledged)`
- the SX1302 `INST` counter increments across status intervals
- `TX errors: 0`

Gateway-rs initially reported DNS/connectivity timeouts to Helium mainnet, then
recovered without service changes. It later fetched US915 region config and
initialized `beaconer` and `packet_router` conduit sessions. This indicates the
remaining early warnings are network/DNS availability during boot, not a broken
gateway configuration.

`RF packets received by concentrator: 0` is acceptable during quiet test windows;
it means no LoRa packets were heard in that interval, not that the concentrator
failed to initialize.
