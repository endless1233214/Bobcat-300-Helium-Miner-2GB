# Bobcat 300 Helium Miner 2GB Custom Image

Community rebuild project for the Bobcat 300 RK3566 / 2 GB Helium miner.

The goal is a reproducible Linux image with:

- Rockchip RK3566 boot support for the Bobcat 300 board.
- Helium `gateway-rs` using the onboard ECC608 identity chip.
- SX1302 packet forwarder configured for the Bobcat radio.
- Local LAN web UI for status, logs, region config, and service restarts.
- No Nebra, Crankk, BalenaCloud, or vendor cloud dependency.

## Current Status

This is early bring-up work. The repository is structured so the image can be
built locally, but hardware validation is still required on real Bobcat boards.
Do not flash a miner whose original eMMC has not been backed up.

The builder intentionally does not commit large vendor images or binaries. It
downloads public upstream releases during the build, extracts only the Bobcat
board-support pieces needed to boot, and writes a custom image to `dist/`.

## Quick Start On macOS

Install dependencies and build `rkdeveloptool`:

```sh
scripts/bootstrap-macos.sh
```

Detect a Bobcat in Rockchip Loader/Maskrom mode:

```sh
scripts/bobcat-detect.sh
```

Read safe hardware info:

```sh
scripts/bobcat-info.sh
```

Build the custom image:

```sh
REGION=US915 PF_REGION=US915_SB2 scripts/build-image.sh
```

Flash only after you have a backup:

```sh
scripts/flash-image.sh dist/bobcat300-rk3566-custom.img
```

## Access After Boot

The image enables DHCP on Ethernet and Wi-Fi interfaces. Start with Ethernet if
possible.

The web UI listens on port `80`. The builder writes generated credentials next
to the image:

```text
dist/bobcat300-rk3566-custom.credentials.txt
```

SSH can be enabled with your public key at build time:

```sh
AUTHORIZED_KEY_FILE=~/.ssh/id_ed25519.pub scripts/build-image.sh
```

## Important Safety Notes

- Back up the original eMMC first. Device identity lives in the ECC chip, but
  factory/vendor state may still be useful for recovery.
- This project does not overwrite your computer's SSH keys.
- Rockchip Loader/Maskrom USB is not UART serial. Bobcat UART console, when
  available, uses Rockchip's high baud boot console rather than ordinary
  115200 in many images.
- DIY Helium gateways are data-only unless approved by the Helium maker
  program.

## Repository Layout

- `scripts/` - host-side build, detect, dump, and flash helpers.
- `tools/` - small Python utilities used by the image builder.
- `image/rootfs-overlay/` - files injected into the Debian root filesystem.
- `docs/` - hardware notes, flashing workflow, and research findings.

