#!/usr/bin/env python3
import json
import os
from pathlib import Path

BASE = Path("/opt/bobcat-miner/pktfwd")
RUN = BASE / "run"
TEMPLATES = BASE / "templates"


def read_env(path):
    values = {}
    try:
        for raw in Path(path).read_text().splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key] = value.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return values


def first_mac():
    preferred = ["eth0", "end0", "enP1p0s0", "wlan0"]
    candidates = preferred + sorted(p.name for p in Path("/sys/class/net").iterdir() if p.name != "lo")
    seen = set()
    for name in candidates:
        if name in seen:
            continue
        seen.add(name)
        path = Path("/sys/class/net") / name / "address"
        try:
            mac = path.read_text().strip().lower()
        except FileNotFoundError:
            continue
        if mac and mac != "00:00:00:00:00:00":
            return mac
    return "00:00:00:00:00:00"


def main():
    env = read_env("/etc/bobcat-miner/config.env")
    pf_region = env.get("BOBCAT_PF_REGION", env.get("BOBCAT_REGION", "US915_SB2"))
    spi_dev = env.get("BOBCAT_SPI_DEV", "/dev/spidev5.0")
    spi_path = spi_dev if spi_dev.startswith("/dev/") else f"/dev/{spi_dev}"

    global_path = TEMPLATES / f"global_conf.json.{pf_region}"
    local_path = TEMPLATES / "local_conf.json"
    if not global_path.exists():
        raise SystemExit(f"Missing packet forwarder template: {global_path}")
    if not local_path.exists():
        raise SystemExit(f"Missing packet forwarder template: {local_path}")

    merged = json.loads(global_path.read_text())
    local = json.loads(local_path.read_text())

    gateway_id = "0000" + first_mac().replace(":", "")
    local["gateway_conf"]["gateway_ID"] = gateway_id
    local["gateway_conf"]["description"] = "bobcat300-custom"
    local["gateway_conf"]["server_address"] = "127.0.0.1"
    local["gateway_conf"]["serv_port_up"] = 1680
    local["gateway_conf"]["serv_port_down"] = 1680

    merged.update(local)
    merged["SX130x_conf"]["com_path"] = spi_path

    RUN.mkdir(parents=True, exist_ok=True)
    (RUN / "global_conf.json").write_text(json.dumps(merged, indent=4) + "\n")
    (RUN / "local_conf.json").write_text(json.dumps(local, indent=4) + "\n")


if __name__ == "__main__":
    main()

