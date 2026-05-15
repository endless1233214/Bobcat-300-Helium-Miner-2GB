# Release Notes

This repository tracks the reproducible builder and overlay files. Built disk
images are intentionally ignored by Git because they are large generated
artifacts. Publish tested images as GitHub Release assets instead.

## Public Image Credential Mode

Do not publish a public image built with the default credential mode unless you
intend every downloader to receive the same web UI password from the generated
`dist/*.credentials.txt` file.

For public images, build with first-run setup mode:

```sh
WEBUI_CREDENTIAL_MODE=setup \
SUPPORT_IMAGE_ZIP=/path/to/bobcat-rk3566-support.zip \
SIMPLE_BOOT_IMAGE_XZ=/path/to/bobcat-rk3566-reference.img.xz \
IMAGE_NAME=bobcat300-rk3566-simpleboot-release \
REGION=US915 PF_REGION=US915_SB2 \
scripts/build-image.sh
```

In this mode, the image does not contain `/etc/bobcat-miner/webui.env`. On first
boot, the web UI serves only the password-creation page until the user creates
their own admin login. After that, normal Basic Auth protects the status and
control pages.

Local/private builders can keep the default mode. It generates a random password
per build and writes it to `dist/<image-name>.credentials.txt`.

## Suggested Release Artifact Flow

```sh
xz -T0 -9 -k dist/bobcat300-rk3566-simpleboot-release.img
shasum -a 256 \
  dist/bobcat300-rk3566-simpleboot-release.img \
  dist/bobcat300-rk3566-simpleboot-release.img.xz \
  > dist/bobcat300-rk3566-simpleboot-release.sha256
```

Attach the compressed image and checksum file to the GitHub Release. Keep the
local `dist/*.credentials.txt` file out of public release assets when using
setup mode; it should only say that the user creates credentials on first visit.
