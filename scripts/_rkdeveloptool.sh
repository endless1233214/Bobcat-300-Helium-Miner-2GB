#!/usr/bin/env bash
set -euo pipefail

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

rkdeveloptool_path() {
  local root
  root="$(repo_root)"
  if [[ -n "${RKDEVELOPTOOL:-}" ]]; then
    echo "$RKDEVELOPTOOL"
  elif [[ -x "$root/_work/bin/rkdeveloptool" ]]; then
    echo "$root/_work/bin/rkdeveloptool"
  elif [[ -x "$root/rkdeveloptool/rkdeveloptool" ]]; then
    echo "$root/rkdeveloptool/rkdeveloptool"
  elif command -v rkdeveloptool >/dev/null 2>&1; then
    command -v rkdeveloptool
  else
    echo "rkdeveloptool not found. Run scripts/bootstrap-macos.sh first." >&2
    return 1
  fi
}

rk356x_loader_path() {
  local root
  root="$(repo_root)"
  if [[ -n "${RK356X_LOADER:-}" ]]; then
    echo "$RK356X_LOADER"
  elif [[ -f "$root/_work/loaders/rk356x_spl_loader_ddr1056_v1.10.111.bin" ]]; then
    echo "$root/_work/loaders/rk356x_spl_loader_ddr1056_v1.10.111.bin"
  elif [[ -f "$root/loaders/rk356x_spl_loader_ddr1056_v1.10.111.bin" ]]; then
    echo "$root/loaders/rk356x_spl_loader_ddr1056_v1.10.111.bin"
  else
    echo "RK356x RAM loader not found. Run scripts/bootstrap-macos.sh first." >&2
    return 1
  fi
}

