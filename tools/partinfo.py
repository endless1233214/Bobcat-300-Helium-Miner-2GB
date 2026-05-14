#!/usr/bin/env python3
import argparse
import json
import struct
import sys
from pathlib import Path

SECTOR = 512
EXTENDED_TYPES = {0x05, 0x0F, 0x85}


def read_lba(fh, lba, count=1):
    fh.seek(lba * SECTOR)
    data = fh.read(count * SECTOR)
    if len(data) != count * SECTOR:
        raise ValueError(f"short read at LBA {lba}")
    return data


def guid_from_le(raw):
    if raw == b"\0" * 16:
        return None
    a, b, c = struct.unpack("<IHH", raw[:8])
    d = raw[8:10].hex()
    e = raw[10:].hex()
    return f"{a:08x}-{b:04x}-{c:04x}-{d}-{e}"


def parse_gpt(fh):
    header = read_lba(fh, 1)
    if header[:8] != b"EFI PART":
        return []
    entries_lba = struct.unpack_from("<Q", header, 72)[0]
    entry_count = struct.unpack_from("<I", header, 80)[0]
    entry_size = struct.unpack_from("<I", header, 84)[0]
    table = read_lba(fh, entries_lba, ((entry_count * entry_size) + SECTOR - 1) // SECTOR)
    parts = []
    for i in range(entry_count):
        entry = table[i * entry_size:(i + 1) * entry_size]
        type_guid = guid_from_le(entry[:16])
        if not type_guid:
            continue
        start = struct.unpack_from("<Q", entry, 32)[0]
        end = struct.unpack_from("<Q", entry, 40)[0]
        name = entry[56:entry_size].decode("utf-16le", errors="ignore").rstrip("\0")
        parts.append({
            "index": i + 1,
            "scheme": "gpt",
            "type": type_guid,
            "start": start,
            "sectors": end - start + 1,
            "name": name,
        })
    return parts


def mbr_entries(sector):
    if sector[510:512] != b"\x55\xaa":
        return []
    out = []
    for i in range(4):
        raw = sector[446 + i * 16:446 + (i + 1) * 16]
        boot = raw[0]
        ptype = raw[4]
        start, sectors = struct.unpack_from("<II", raw, 8)
        if ptype and sectors:
            out.append({"slot": i + 1, "boot": boot, "type_id": ptype, "start": start, "sectors": sectors})
    return out


def parse_mbr(fh):
    mbr = read_lba(fh, 0)
    parts = []
    extended_base = None
    for entry in mbr_entries(mbr):
        parts.append({
            "index": entry["slot"],
            "scheme": "mbr",
            "type": f"0x{entry['type_id']:02x}",
            "start": entry["start"],
            "sectors": entry["sectors"],
            "bootable": entry["boot"] == 0x80,
        })
        if entry["type_id"] in EXTENDED_TYPES and extended_base is None:
            extended_base = entry["start"]

    if extended_base is None:
        return parts

    logical_index = 5
    ebr_lba = extended_base
    visited = set()
    while ebr_lba not in visited:
        visited.add(ebr_lba)
        ebr = read_lba(fh, ebr_lba)
        entries = mbr_entries(ebr)
        if not entries:
            break

        data = entries[0]
        if data["type_id"] not in EXTENDED_TYPES:
            parts.append({
                "index": logical_index,
                "scheme": "mbr-logical",
                "type": f"0x{data['type_id']:02x}",
                "start": ebr_lba + data["start"],
                "sectors": data["sectors"],
                "bootable": data["boot"] == 0x80,
            })
            logical_index += 1

        next_entries = [e for e in entries[1:] if e["type_id"] in EXTENDED_TYPES and e["sectors"]]
        if not next_entries:
            break
        ebr_lba = extended_base + next_entries[0]["start"]

    return parts


def partitions(path):
    with open(path, "rb") as fh:
        gpt = parse_gpt(fh)
        if gpt:
            return gpt
        return parse_mbr(fh)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--shell", type=int, help="print START/SECTORS/TYPE for one partition index")
    args = parser.parse_args()

    parts = partitions(args.image)
    if args.shell:
        match = next((p for p in parts if p["index"] == args.shell), None)
        if not match:
            raise SystemExit(f"partition {args.shell} not found")
        print(f"START={match['start']}")
        print(f"SECTORS={match['sectors']}")
        print(f"TYPE={json.dumps(match['type'])}")
        return

    if args.json:
        print(json.dumps(parts, indent=2))
        return

    for part in parts:
        print(f"{part['index']:>2} {part['scheme']:<11} {part['type']:<38} start={part['start']} sectors={part['sectors']}")


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.exit(0)

