#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$1"
if [[ "${output_dir}" != /* && ! "${output_dir}" =~ ^[A-Za-z]:[\\/] ]] \
  || [[ "${output_dir}" == "/" || "${output_dir}" == "${repo_dir}" ]]; then
  echo "unsafe bundle output: ${output_dir}" >&2
  exit 1
fi

polyworld_root="${POLYWORLD_ROOT:-$(cd "${repo_dir}/.." && pwd)}"
if [[ ! -d "${polyworld_root}/examples/pudge_wars" ]]; then
  echo "polyworld root not found at ${polyworld_root}; set POLYWORLD_ROOT" >&2
  exit 1
fi
if [[ -n "${POLYWORLD_ART:-}" ]]; then
  data_dir="${POLYWORLD_ART}"
elif [[ -d "${polyworld_root}/build/polyworld_art" ]]; then
  data_dir="${polyworld_root}/build/polyworld_art"
else
  data_dir="${polyworld_root}/../polyworld_art"
fi
if [[ ! -d "${data_dir}" ]]; then
  echo "art directory not found at ${data_dir}; set POLYWORLD_ART or run scripts/recover_art.py" >&2
  exit 1
fi
export POLYWORLD_ART="$(cd "${data_dir}" && pwd)"
webdata="${polyworld_root}/examples/pudge_wars/webdata.txt"
if [[ -f "${webdata}" ]]; then
  missing=0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      ''|\#*) continue ;;
    esac
    if [[ ! -e "${data_dir}/${line}" ]]; then
      echo "missing replay-viewer asset: ${data_dir}/${line}" >&2
      missing=1
    fi
  done < "${webdata}"
  if [[ "${missing}" -ne 0 ]]; then
    echo "set POLYWORLD_ART to a complete asset directory or run scripts/recover_art.py" >&2
    exit 1
  fi
fi
if ! command -v emcc >/dev/null 2>&1; then
  echo "emcc is required to build the Pudge Wars replay viewer" >&2
  exit 1
fi
if ! command -v nim >/dev/null 2>&1; then
  echo "nim is required to build the Pudge Wars replay viewer" >&2
  exit 1
fi

rm -rf "${output_dir}"
mkdir -p "${output_dir}"

(
  cd "${polyworld_root}"
  nim c -d:emscripten examples/pudge_wars/pw.nim
)

src="${polyworld_root}/examples/pudge_wars/emscripten"
if [[ ! -f "${src}/pw.html" || ! -f "${src}/pw.wasm" || ! -f "${src}/pw.js" ]]; then
  echo "emscripten build did not produce pw.html/pw.wasm/pw.js in ${src}" >&2
  exit 1
fi

cp "${src}/pw.html" "${output_dir}/index.html"
cp "${src}/pw.js" "${output_dir}/pw.js"
cp "${src}/pw.wasm" "${output_dir}/pw.wasm"
for asset in recap-overlay.js boot-scene.js touch-input.js; do
  cp "${polyworld_root}/examples/pudge_wars/${asset}" "${output_dir}/${asset}"
  cp "${polyworld_root}/examples/pudge_wars/${asset}" "${src}/${asset}"
done
if [[ -f "${src}/pw.data" ]]; then
  cp "${src}/pw.data" "${output_dir}/pw.data"
fi
for notice in ASSET-LICENSES.txt LICENSE; do
  if [[ -f "${POLYWORLD_ART}/${notice}" ]]; then
    cp "${POLYWORLD_ART}/${notice}" "${output_dir}/${notice}"
  fi
done
sim_version="$(
  sed -n 's/^  ReplayGameVersion\* = \([0-9][0-9]*\).*/\1/p' \
    "${polyworld_root}/examples/pudge_wars/replays.nim" | head -1
)"
if [[ -z "${sim_version}" ]]; then
  echo "could not read ReplayGameVersion from replays.nim" >&2
  exit 1
fi
printf '{"game":"pudge_wars","simVersion":%s}\n' "${sim_version}" \
  > "${output_dir}/sim-version.json"
cp "${output_dir}/sim-version.json" "${src}/sim-version.json"
cover="${polyworld_root}/examples/pudge_wars/cover.webp"
if [[ -f "$cover" ]]; then
  cp "$cover" "${output_dir}/cover.webp"
  cp "$cover" "${src}/cover.webp"
fi
preview="${polyworld_root}/coworld/preview.jpg"
if [[ -f "$preview" ]]; then
  cp "$preview" "${output_dir}/preview.jpg"
fi
