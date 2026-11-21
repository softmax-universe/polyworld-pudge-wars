#!/usr/bin/env python3
"""Stage Pudge Wars art from an existing Emscripten viewer.

Usage: python3 scripts/recover_art.py /path/to/viewer

The viewer directory supplies pw.js, pw.data, and any asset license notice.
The extracted files and required shared art are staged in build/polyworld_art.
"""

import argparse
import json
import re
import shutil
import tempfile
from pathlib import Path, PurePosixPath


def copy_missing(source: str, target: str) -> None:
    """Fills gaps in a UI directory while preserving original viewer assets."""
    if not Path(target).exists():
        shutil.copy2(source, target)


def unpack(viewer: Path, destination: Path) -> None:
    """Extract the file ranges indexed by the generated loader."""
    loader = (viewer / "pw.js").read_text()
    header = re.search(r'\bloadPackage\(\s*(\{\s*"files"\s*:)', loader)
    if header is None:
        raise ValueError("No Emscripten package index found in pw.js")
    index, _ = json.JSONDecoder().raw_decode(loader, header.start(1))
    with (viewer / "pw.data").open("rb") as payload:
        size = payload.seek(0, 2)
        if size != index["remote_package_size"]:
            raise ValueError("pw.data size differs from the pw.js package index")
        for entry in index["files"]:
            path = PurePosixPath(entry["filename"])
            if path.parts[:2] not in (
                ("/", "polyworld_data"), ("/", "polyworld_art")
            ):
                continue
            relative = path.parts[2:]
            start, end = entry["start"], entry["end"]
            if not relative or ".." in relative or not 0 <= start <= end <= size:
                raise ValueError(f"Invalid package entry: {entry}")
            target = destination.joinpath(*relative)
            target.parent.mkdir(parents=True, exist_ok=True)
            payload.seek(start)
            target.write_bytes(payload.read(end - start))
    notice = viewer / "ASSET-LICENSES.txt"
    if notice.is_file():
        shutil.copy2(notice, destination / notice.name)


def main() -> None:
    """Validate the complete stage against the Pudge Wars asset manifest."""
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("viewer", type=Path, help="Directory with pw.js and pw.data")
    parser.add_argument("--shared-art", type=Path, default=root.parent / "polyworld_art")
    parser.add_argument("--output", type=Path, default=root / "build/polyworld_art")
    args = parser.parse_args()
    manifest = root / "examples/pudge_wars/webdata.txt"
    try:
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            unpack(args.viewer, stage)
            for line in manifest.read_text().splitlines():
                entry = line.strip()
                if not entry or entry.startswith("#"):
                    continue
                target = stage / entry
                source = args.shared_art / entry
                if entry in ("icons", "themes/main", "ui") and source.is_dir():
                    shutil.copytree(source, target, dirs_exist_ok=True,
                                    copy_function=copy_missing)
                if target.exists():
                    continue
                if not source.exists():
                    raise FileNotFoundError(f"Missing required art: {entry}")
                target.parent.mkdir(parents=True, exist_ok=True)
                if source.is_dir():
                    shutil.copytree(source, target)
                else:
                    shutil.copy2(source, target)
            shutil.copytree(stage, args.output, dirs_exist_ok=True)
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    print(f"Staged Pudge Wars art in {args.output.resolve()}")


if __name__ == "__main__":
    main()
