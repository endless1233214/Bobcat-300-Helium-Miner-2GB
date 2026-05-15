# Windows Build And Flashing

Windows users should use WSL2 for building images. The build scripts are Linux
shell scripts and need Linux filesystem tools such as `debugfs`, `e2tools`,
`mtools`, `dosfstools`, and `rsync`.

## Install WSL2

Open PowerShell as Administrator:

```powershell
wsl --install -d Ubuntu
```

Reboot if Windows asks, then open Ubuntu from the Start menu.

## Build In WSL2

Inside Ubuntu:

```sh
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/endless1233214/Bobcat-300-Helium-Miner-2GB.git
cd Bobcat-300-Helium-Miner-2GB
scripts/bootstrap-linux.sh
```

Copy the required Bobcat support/reference image files into the WSL filesystem,
not a mounted Windows path, before building. Building from `/home/<you>/...` is
much faster and avoids filesystem permission surprises.

Example:

```sh
mkdir -p ~/bobcat-inputs
cp /mnt/c/Users/<you>/Downloads/bobcat-rk3566-support.zip ~/bobcat-inputs/bobcat-support.zip
cp /mnt/c/Users/<you>/Downloads/bobcat-rk3566-reference.img.xz ~/bobcat-inputs/bobcat-rk3566-reference.img.xz

SUPPORT_IMAGE_ZIP=~/bobcat-inputs/bobcat-support.zip \
SIMPLE_BOOT_IMAGE_XZ=~/bobcat-inputs/bobcat-rk3566-reference.img.xz \
WEBUI_CREDENTIAL_MODE=setup \
IMAGE_NAME=bobcat300-rk3566-simpleboot-release \
REGION=US915 PF_REGION=US915_SB2 \
scripts/build-image.sh
```

The output image will be under `dist/`.

## Flashing From Windows

The simplest reliable path is:

1. Build the image in WSL2.
2. Copy `dist/*.img` to Windows Downloads.
3. Use a Windows Rockchip flashing tool or a Windows build of `rkdeveloptool`.

WSL2 USB passthrough can work with `usbipd-win`, but it is more fiddly than
building in WSL and flashing from native Windows. If you do want to use WSL USB
passthrough, install `usbipd-win`, attach the Rockchip device to WSL, then run
the same `scripts/bobcat-detect.sh` and `scripts/flash-image.sh` commands from
inside Ubuntu.

## Credentials

For public/shared images, build with `WEBUI_CREDENTIAL_MODE=setup`. Each user
creates their own web UI login on first visit to `http://<bobcat-dhcp-ip>/`.

For private images, omit `WEBUI_CREDENTIAL_MODE=setup`; the builder writes a
fresh random password to `dist/<image-name>.credentials.txt`.
