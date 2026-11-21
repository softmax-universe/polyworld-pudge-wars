#!/usr/bin/env bash
# Build a self-contained Mac app. No repository or server is needed to play.
set -euo pipefail

root="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$root"
export PATH="${HOME}/.nimby/nim/bin:${HOME}/.local/bin:${PATH}"
mkdir -p tmp
nim c -d:release --hints:off -o:tmp/pw-desktop examples/pudge_wars/pw.nim

python3 - "$root" <<'PY'
import os
import plistlib
import shutil
import sys
from pathlib import Path

root = Path(sys.argv[1])
source = root / 'examples/pudge_wars/macos'
data = root / 'build/polyworld_art'
if not data.is_dir():
    data = root.parent / 'polyworld_art'
if os.environ.get('POLYWORLD_ART'):
    data = Path(os.environ['POLYWORLD_ART'])
entries = []
for line in (root / 'examples/pudge_wars/webdata.txt').read_text().splitlines():
    entry = line.strip()
    if entry and not entry.startswith('#'):
        entries.append(entry)
for entry in entries:
    if not (data / entry).exists():
        sys.exit(f'Missing art: {data / entry}. Set POLYWORLD_ART or run scripts/recover_art.py.')

app = root / 'tmp/desktop/Pudge Wars.app'
if app.exists():
    shutil.rmtree(app)
macos = app / 'Contents/MacOS'
resources = app / 'Contents/Resources'
game = resources / 'game'
macos.mkdir(parents=True)
game.mkdir(parents=True)
shutil.copy2(root / 'tmp/pw-desktop', macos / 'pw')
shutil.copy2(source / 'AppIcon.icns', resources / 'AppIcon.icns')
with (source / 'Info.plist').open('rb') as f:
    info = plistlib.load(f)
info['CFBundleExecutable'] = 'Pudge Wars'
with (app / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump(info, f)

art = resources / 'polyworld_art'
for entry in entries:
    origin = data / entry
    target = art / entry
    target.parent.mkdir(parents=True, exist_ok=True)
    if origin.is_dir():
        shutil.copytree(origin, target, dirs_exist_ok=True)
    else:
        shutil.copy2(origin, target)
for name in ('ASSET-LICENSES.txt', 'LICENSE'):
    if (data / name).is_file():
        shutil.copy2(data / name, art / name)
players = game / 'players'
players.mkdir()
for name in ('base', 'aggressive', 'sniper', 'challenger', 'denier', 'patient', 'support'):
    shutil.copy2(root / f'examples/pudge_wars/players/{name}.bas', players / f'{name}.bas')
example = game / 'examples/pudge_wars'
example.mkdir(parents=True)
(example / 'players').symlink_to('../../players', target_is_directory=True)
(example / 'macos').mkdir()
shutil.copy2(source / 'AppIcon.png', example / 'macos/AppIcon.png')
launcher = macos / 'Pudge Wars'
launcher.write_text('''#!/bin/bash
set -euo pipefail
contents="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$HOME/Library/Logs/Pudge Wars"
exec >> "$HOME/Library/Logs/Pudge Wars/game.log" 2>&1
cd "$contents/Resources/game"
exec "$contents/MacOS/pw" "$@"
''')
launcher.chmod(0o755)
print(app)
PY

codesign --force --deep --sign - "tmp/desktop/Pudge Wars.app"
echo "Ready: $root/tmp/desktop/Pudge Wars.app"
