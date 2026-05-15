# Bobcat 300 Helium Miner 2GB Custom Image

Community rebuild project for the Bobcat 300 RK3566 / 2 GB Helium miner.

The goal is a reproducible Linux image with:

- Rockchip RK3566 boot support for the Bobcat 300 board.
- Helium `gateway-rs` using the onboard ECC608 identity chip.
- SX1302 packet forwarder configured for the Bobcat radio.
- Local LAN web UI for status, logs, region config, and service restarts.
- No vendor cloud dependency.

## Current Status

This is early bring-up work. The repository is structured so the image can be
built locally, but hardware validation is still required on real Bobcat boards.
Do not flash a miner whose original eMMC has not been backed up.

The builder intentionally does not commit large vendor images or binaries. It
downloads public upstream releases during the build, extracts only the Bobcat
board-support pieces needed to boot, and writes a custom image to `dist/`.
Prebuilt images, when published, should be attached to GitHub Releases rather
than committed to the repository.

The latest field-tested path is the simple two-partition boot profile. On the
first test Bobcat, that image booted, brought up Ethernet, started
`gateway-rs`, initialized the SX1302 packet forwarder, and acknowledged local
`PUSH_DATA`/`PULL_DATA` traffic between the packet forwarder and gateway.

## Quick Start On macOS

Refer to Docs for Windows/Linux

Install dependencies and build `rkdeveloptool`:

```sh
scripts/bootstrap-macos.sh
```

On Linux or Windows via WSL2, use:

```sh
scripts/bootstrap-linux.sh
```

Windows-specific notes are in `docs/windows.md`.

Detect a Bobcat in Rockchip Loader/Maskrom mode:

```sh
scripts/bobcat-detect.sh
```

Read safe hardware info:

```sh
scripts/bobcat-info.sh
```

Build with the field-tested simple boot path:

```sh
SUPPORT_IMAGE_ZIP=/path/to/bobcat-rk3566-support.zip \
SIMPLE_BOOT_IMAGE_XZ=/path/to/bobcat-rk3566-reference.img.xz \
IMAGE_NAME=bobcat300-rk3566-simpleboot \
REGION=US915 PF_REGION=US915_SB2 \
scripts/build-image.sh
```

Flash only after you have a backup:

```sh
scripts/flash-image.sh dist/bobcat300-rk3566-custom.img
```

## Access After Boot

The image enables DHCP on Ethernet and Wi-Fi interfaces. Start with Ethernet if
possible.

The web UI listens on port `80`. Use the device IP from your router DHCP table.
mDNS/Avahi is not installed yet, so `bobcat300.local` may not resolve. The
builder writes generated credentials next to the image:

```text
dist/bobcat300-rk3566-custom.credentials.txt
```

By default, each local build generates a fresh web UI password and bakes it into
that one image. If you publish a prebuilt image for other people, build it in
first-run setup mode instead so everyone does not share the same password:

```sh
WEBUI_CREDENTIAL_MODE=setup \
SUPPORT_IMAGE_ZIP=/path/to/bobcat-rk3566-support.zip \
SIMPLE_BOOT_IMAGE_XZ=/path/to/bobcat-rk3566-reference.img.xz \
scripts/build-image.sh
```

In setup mode, no web UI password is baked into the image. The first visit to
`http://<dhcp-address>/` from a trusted LAN asks the user to create their own
admin login, then normal Basic Auth is enabled.

SSH can be enabled with your public key at build time. The image creates a
`bobcat` admin user for that key and grants passwordless `sudo`, so field fixes
can be applied without reflashing once SSH is reachable:

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
- Helium app Bluetooth onboarding is not implemented yet; see
  `docs/onboarding.md` for the planned Wi-Fi/BLE path.

## Repository Layout

- `scripts/` - host-side build, detect, dump, and flash helpers.
- `tools/` - small Python utilities used by the image builder.
- `image/rootfs-overlay/` - files injected into the Debian root filesystem.
- `docs/` - hardware notes, flashing workflow, Windows setup, onboarding notes,
  and research findings.
