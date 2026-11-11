#!/usr/bin/env python3
"""Package the reviewed README and media as one portable, checked installer."""
import base64
import hashlib
import io
import json
from pathlib import Path
import subprocess
import textwrap
import zipfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/readme-overhaul'
OUT.mkdir(parents=True, exist_ok=True)
paths = [Path('README.md'), Path('docs/GUIDE.md'), Path('docs/social-preview.png'),
         Path('scripts/refresh-readme-media.sh')]
paths += sorted(p.relative_to(ROOT) for p in (ROOT / 'Tools/readme').iterdir() if p.is_file())
paths += sorted(p.relative_to(ROOT) for p in (ROOT / 'docs/readme').iterdir() if p.is_file())
manifest = []
for path in paths:
    old = subprocess.run(['git', 'show', f'HEAD:{path.as_posix()}'], cwd=ROOT,
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    manifest.append(dict(path=path.as_posix(),
        sha256=hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),
        base_sha256=hashlib.sha256(old.stdout).hexdigest() if old.returncode == 0 else None,
        executable=path.suffix == '.sh'))
buf = io.BytesIO()
with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    archive.writestr('MANIFEST.json', json.dumps(manifest, indent=2))
    for path in paths:
        archive.write(ROOT/path, path.as_posix())
payload = buf.getvalue()
(OUT/'readme-overhaul.zip').write_bytes(payload)

script = r'''#!/bin/bash
# CSL README makeover: checked assets, backup, documentation commit, normal push.
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MODE="${1:---publish}"
TARGET="${CSL_PROJECT_DIR:-$HOME/Documents/CSL}"
PAYLOAD_SHA="@PAYLOAD_SHA@"
die() { printf '%s\n' "$*" >&2; exit 1; }
case "$MODE" in --publish|--local|--check) ;; *) die "Aufruf: bash $0 [--publish|--local|--check]" ;; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/csl-readme.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

python3 - "$SCRIPT" "$WORK" "$PAYLOAD_SHA" <<'PY'
import base64, hashlib, io, json, sys, zipfile
from pathlib import Path
encoded = Path(sys.argv[1]).read_bytes().split(b'\n__CSL_README_PAYLOAD__\n', 1)[1]
data = base64.b64decode(encoded)
assert hashlib.sha256(data).hexdigest() == sys.argv[3], 'Installer-Prüfsumme stimmt nicht.'
dest = Path(sys.argv[2]).resolve()
with zipfile.ZipFile(io.BytesIO(data)) as z:
    for member in z.infolist():
        p = Path(member.filename)
        assert not p.is_absolute() and '..' not in p.parts, 'Ungültiger Archivpfad.'
        assert (member.external_attr >> 16) & 0o170000 != 0o120000, 'Keine Symlinks erlaubt.'
    z.extractall(dest)
for row in json.loads((dest/'MANIFEST.json').read_text()):
    f = dest / row['path']
    assert f.is_file() and hashlib.sha256(f.read_bytes()).hexdigest() == row['sha256'], row['path']
print('Alle README-Dateien und Bilder: Prüfsummen OK.')
PY

[[ -d "$TARGET/.git" || -f "$TARGET/.git" ]] || die "Kein Git-Projekt: $TARGET"
cd "$TARGET"
[[ "$(git branch --show-current)" == main ]] || die 'Bitte im Projekt zuerst Branch main auswählen.'
[[ -z "$(git status --porcelain)" ]] || die 'Lokale Änderungen vorhanden. Bitte zuerst sichern/committen.'
case "$(git remote get-url origin)" in
  https://github.com/SirCartaux/csl.git|https://github.com/SirCartaux/csl|git@github.com:SirCartaux/csl.git) ;;
  *) die 'origin zeigt nicht auf SirCartaux/csl. Nichts geändert.' ;;
esac
git merge-base --is-ancestor b67bc43232fd81fd3ad33ac348f0a039381cb6ba HEAD || die 'Bitte zuerst CSL 0.8.1 übernehmen.'

python3 - "$WORK" "$TARGET" <<'PY'
import hashlib, json, sys
from pathlib import Path
source, target = map(Path, sys.argv[1:])
for row in json.loads((source/'MANIFEST.json').read_text()):
    rel = Path(row['path'])
    assert rel.as_posix() == 'README.md' or rel.parts[0] in ('docs', 'Tools', 'scripts'), 'Unerwarteter Zielpfad.'
    f = target / rel
    assert f.resolve().is_relative_to(target.resolve()) and not f.is_symlink(), f'Unsicherer Zielpfad: {rel}'
    if f.exists():
        assert f.is_file(), f'Kein Dateiziel: {rel}'
        actual = hashlib.sha256(f.read_bytes()).hexdigest()
        assert actual in (row['base_sha256'], row['sha256']), f'{rel} wurde inzwischen geändert. Nichts überschrieben.'
print('Projektstand und Zieldateien geprüft.')
PY

if [[ "$MODE" == --check ]]; then
  printf '\nVorprüfung erfolgreich. Keine Projektdateien geändert.\n'
  exit 0
fi
if [[ "$MODE" == --publish ]]; then
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  if command -v gh >/dev/null 2>&1 && gh auth status --hostname github.com >/dev/null 2>&1; then
    gh auth setup-git --hostname github.com
  fi
  git fetch origin main
  git merge-base --is-ancestor origin/main HEAD || die 'GitHub enthält neuere Änderungen. Bitte zuerst git pull --ff-only ausführen.'
fi

python3 - "$WORK" "$TARGET" <<'PY'
from datetime import datetime
import hashlib, json, shutil, sys
from pathlib import Path
source, target = map(Path, sys.argv[1:])
backup = target/'build/readme-overhaul-backup'/datetime.now().strftime('%Y%m%d-%H%M%S-%f')
changed = 0
for row in json.loads((source/'MANIFEST.json').read_text()):
    rel = Path(row['path']); f = target/rel
    if f.is_file() and hashlib.sha256(f.read_bytes()).hexdigest() == row['sha256']:
        continue
    if f.exists():
        (backup/rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, backup/rel)
    f.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source/rel, f)
    f.chmod(0o755 if row['executable'] else 0o644)
    changed += 1
print(f'{changed} Dateien übernommen.')
if backup.exists(): print(f'Bisherige Dateien gesichert: {backup}')
PY

FILES=()
while IFS= read -r FILE; do FILES+=("$FILE"); done < <(python3 - "$WORK/MANIFEST.json" <<'PY'
import json, sys
for row in json.load(open(sys.argv[1])): print(row['path'])
PY
)
git add -- "${FILES[@]}"
git diff --cached --check
if ! git diff --cached --quiet; then
  git commit -m "Redesign README with native screenshots and new CSL artwork"
else
  printf 'Der README-Overhaul ist bereits übernommen.\n'
fi
if [[ "$MODE" == --publish ]]; then
  git push origin HEAD:refs/heads/main
  printf '\nREADME und Galerie veröffentlicht: https://github.com/SirCartaux/csl#readme\n'
else
  printf '\nREADME und Galerie lokal committed. Veröffentlichen: bash %q --publish\n' "$SCRIPT"
fi
exit 0
__CSL_README_PAYLOAD__
'''.replace('@PAYLOAD_SHA@', hashlib.sha256(payload).hexdigest())
installer = OUT/'overhaul-readme.command'
installer.write_text(script + '\n'.join(textwrap.wrap(base64.b64encode(payload).decode(), 76)) + '\n')
installer.chmod(0o755)
(OUT/'SHA256SUMS.txt').write_text('\n'.join(
    hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name for p in [installer, OUT/'readme-overhaul.zip'])+'\n')
print(f'Packaged {len(paths)} files: {installer} ({installer.stat().st_size:,} bytes)')
