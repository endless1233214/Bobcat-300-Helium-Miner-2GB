#!/usr/bin/env python3
import argparse
import os
import stat
import subprocess
from pathlib import Path


def run(args, check=True):
    return subprocess.run(args, check=check, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def e2path(image, path):
    posix = "/" + path.as_posix().lstrip("/")
    return f"{image}:{posix}"


def ensure_dir(image, rel, mode):
    if rel.as_posix() in ("", "."):
        return
    run(["e2mkdir", "-O", "0", "-G", "0", "-P", f"{mode:04o}", e2path(image, rel)], check=False)


def remove_path(image, rel):
    target = "/" + rel.as_posix().lstrip("/")
    run(["e2rm", e2path(image, rel)], check=False)
    run(["debugfs", "-w", "-R", f"rm {target}", image], check=False)


def copy_file(image, src, rel):
    mode = stat.S_IMODE(src.stat().st_mode)
    remove_path(image, rel)
    run(["e2cp", "-O", "0", "-G", "0", "-P", f"{mode:04o}", str(src), e2path(image, rel)])


def copy_symlink(image, src, rel):
    target = os.readlink(src)
    dest = "/" + rel.as_posix().lstrip("/")
    remove_path(image, rel)
    run(["debugfs", "-w", "-R", f"symlink {dest} {target}", image])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("image")
    parser.add_argument("overlay", type=Path)
    args = parser.parse_args()

    overlay = args.overlay
    image = args.image

    dirs = [p for p in overlay.rglob("*") if p.is_dir()]
    for directory in sorted(dirs, key=lambda p: len(p.relative_to(overlay).parts)):
        rel = directory.relative_to(overlay)
        mode = stat.S_IMODE(directory.stat().st_mode)
        ensure_dir(image, rel, mode)

    for path in sorted(overlay.rglob("*")):
        rel = path.relative_to(overlay)
        if path.is_dir():
            continue
        ensure_dir(image, rel.parent, 0o755)
        if path.is_symlink():
            copy_symlink(image, path, rel)
        elif path.is_file():
            copy_file(image, path, rel)


if __name__ == "__main__":
    main()

