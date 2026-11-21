#!/usr/bin/env bash
## One-time toolchain setup for this repo: Nimby, Nim 2.2.10, locked
## packages, and the shared Polyworld engine.
##
##   scripts/setup.sh
##
## Run from anywhere; it cds to the repo root. After it finishes, put
## ~/.nimby/nim/bin on your PATH for this shell (the script prints the
## export) and build from the repo root.

set -euo pipefail

cd "$(dirname "$0")/.."
repo_root=$(pwd)

NIM_VERSION=2.2.10
NIMBY_VERSION=0.2.1

need_cmd() {
  command -v "$1" > /dev/null 2>&1
}

install_nimby() {
  local dest="$HOME/.local/bin/nimby"
  local url=""
  local uname_s uname_m
  uname_s=$(uname -s)
  uname_m=$(uname -m)
  case "$uname_s-$uname_m" in
    Darwin-arm64) url="https://github.com/treeform/nimby/releases/download/${NIMBY_VERSION}/nimby-macOS-ARM64" ;;
    Darwin-x86_64) url="https://github.com/treeform/nimby/releases/download/${NIMBY_VERSION}/nimby-macOS-X64" ;;
    Linux-x86_64) url="https://github.com/treeform/nimby/releases/download/${NIMBY_VERSION}/nimby-Linux-X64" ;;
    Linux-aarch64) url="https://github.com/treeform/nimby/releases/download/${NIMBY_VERSION}/nimby-Linux-ARM64" ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "error: on Windows download nimby-Windows-X64.exe from" >&2
      echo "  https://github.com/treeform/nimby/releases/tag/${NIMBY_VERSION}" >&2
      exit 1
      ;;
    *)
      echo "error: no nimby binary for $uname_s $uname_m" >&2
      echo "build from https://github.com/treeform/nimby or pick a release asset" >&2
      exit 1
      ;;
  esac
  mkdir -p "$(dirname "$dest")"
  echo "downloading nimby ${NIMBY_VERSION}..."
  curl -fsSL -o "$dest" "$url"
  chmod +x "$dest"
  echo "installed $dest"
}

if ! need_cmd curl; then
  echo "error: curl is required to install nimby" >&2
  exit 1
fi

if ! need_cmd nimby; then
  install_nimby
  export PATH="$HOME/.local/bin:$PATH"
fi

if ! need_cmd nimby; then
  echo "error: nimby is installed at ~/.local/bin/nimby but that directory is not on PATH" >&2
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" >&2
  exit 1
fi

echo "nimby $(nimby --version 2>/dev/null | head -1 || true)"
echo "installing Nim ${NIM_VERSION} into ~/.nimby/nim ..."
nimby use "$NIM_VERSION"

export PATH="$HOME/.nimby/nim/bin:$PATH"

if ! need_cmd nim; then
  echo "error: nim was installed under ~/.nimby/nim/bin but is not on PATH" >&2
  echo "  export PATH=\"\$HOME/.nimby/nim/bin:\$PATH\"" >&2
  exit 1
fi

echo "nim $(nim --version | head -1)"

if [[ ! -f "$repo_root/nimby.lock" ]]; then
  echo "error: missing nimby.lock in $repo_root" >&2
  exit 1
fi

lockfile="$repo_root/nimby.lock"
if [[ -n "${PUDGEWARS_POLYWORLD:-}" ]]; then
  if [[ ! -f "$PUDGEWARS_POLYWORLD/src/polyworld/common.nim" ]]; then
    echo "error: PUDGEWARS_POLYWORLD must point to a Polyworld checkout" >&2
    exit 1
  fi
  lockfile="$(mktemp "${TMPDIR:-/tmp}/pudgewars-lock.XXXXXXXX")"
  trap 'rm -f "$lockfile"' EXIT
  awk '$1 != "polyworld"' "$repo_root/nimby.lock" > "$lockfile"
fi
echo "syncing locked packages into ${NIMBY_HOME:-$HOME/.nimby}/pkgs ..."
nimby sync -g "$lockfile"

echo
echo "setup ok. For this shell and your profile:"
echo "  export PATH=\"\$HOME/.nimby/nim/bin:\$HOME/.local/bin:\$PATH\""
echo "  export PUDGEWARS_DEPS=\"${NIMBY_HOME:-$HOME/.nimby}/pkgs\""
if [[ -n "${PUDGEWARS_POLYWORLD:-}" ]]; then
  echo "  export PUDGEWARS_POLYWORLD=\"$PUDGEWARS_POLYWORLD\""
fi
echo
echo "then from the repo root:"
echo "  nim r examples/pudge_wars/pw.nim"
echo "  nim r tests/test_pw_sim.nim"
