#!/usr/bin/env python3
import re
import sys
from pathlib import Path

CONFIG = Path("/etc/bobcat-miner/config.env")
SETTINGS = Path("/etc/helium_gateway/settings.toml")


def update_env(path, updates):
    lines = []
    seen = set()
    if path.exists():
        lines = path.read_text().splitlines()
    out = []
    for line in lines:
        if "=" not in line or line.strip().startswith("#"):
            out.append(line)
            continue
        key = line.split("=", 1)[0]
        if key in updates:
            out.append(f"{key}={updates[key]}")
            seen.add(key)
        else:
            out.append(line)
    for key, value in updates.items():
        if key not in seen:
            out.append(f"{key}={value}")
    path.write_text("\n".join(out) + "\n")


def update_settings(path, region):
    text = path.read_text()
    if re.search(r'(?m)^region\s*=', text):
        text = re.sub(r'(?m)^region\s*=.*$', f'region = "{region}"', text)
    else:
        text += f'\nregion = "{region}"\n'
    path.write_text(text)


def main():
    region = sys.argv[1].strip()
    pf_region = sys.argv[2].strip()
    if not re.fullmatch(r"[A-Z0-9_]+", region):
        raise SystemExit("Region must contain only A-Z, 0-9, and underscore")
    if not re.fullmatch(r"[A-Z0-9_]+", pf_region):
        raise SystemExit("Packet forwarder region must contain only A-Z, 0-9, and underscore")
    update_env(CONFIG, {"BOBCAT_REGION": region, "BOBCAT_PF_REGION": pf_region})
    update_settings(SETTINGS, region)


if __name__ == "__main__":
    main()

