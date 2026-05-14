#!/usr/bin/env python3
import argparse
import struct
from pathlib import Path

SECTOR = 512
HEADS = 255
SPT = 63


def chs(lba):
    cylinder = lba // (HEADS * SPT)
    if cylinder >= 1024:
        return b"\xfe\xff\xff"
    head = (lba // SPT) % HEADS
    sector = (lba % SPT) + 1
    return bytes([head, (sector & 0x3F) | ((cylinder >> 2) & 0xC0), cylinder & 0xFF])


def entry(status, ptype, start, sectors):
    end = start + sectors - 1
    return bytes([status]) + chs(start) + bytes([ptype]) + chs(end) + struct.pack("<II", start, sectors)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("--p1-start", type=int, required=True)
    parser.add_argument("--p1-sectors", type=int, required=True)
    parser.add_argument("--p2-start", type=int, required=True)
    parser.add_argument("--p2-sectors", type=int, required=True)
    args = parser.parse_args()

    with args.image.open("r+b") as fh:
        mbr = bytearray(fh.read(SECTOR))
        if len(mbr) != SECTOR:
            raise SystemExit("image is too small")
        table = (
            entry(0x80, 0x0E, args.p1_start, args.p1_sectors)
            + entry(0x00, 0x83, args.p2_start, args.p2_sectors)
            + b"\0" * 32
        )
        mbr[446:446 + 64] = table
        mbr[510:512] = b"\x55\xaa"
        fh.seek(0)
        fh.write(mbr)


if __name__ == "__main__":
    main()

