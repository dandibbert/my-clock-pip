#!/bin/bash
set -euo pipefail
APP="${1:?Pass the built MyClockPiP.app path}"
OUT="${2:-dist}"
mkdir -p "$OUT"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/MyClockPiP.app"
python3 - "$STAGE/Payload/MyClockPiP.app" <<'PY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app / 'Info.plist').read_bytes())
exe = app / info['CFBundleExecutable']
assert exe.is_file(), 'Missing executable'
# Restore execute permission for every Mach-O; do not mark data/resources executable.
magics = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'}
for path in app.rglob('*'):
    if path.is_file() and not path.is_symlink():
        with path.open('rb') as handle:
            magic = handle.read(4)
        if magic in magics:
            path.chmod(path.stat().st_mode | 0o111)
assert exe.stat().st_mode & 0o111, 'Executable lacks execute permissions'
print('Validated app executable and Mach-O permissions')
PY
DEST="$(cd "$OUT" && pwd)"
(cd "$STAGE" && /usr/bin/zip -qr "$DEST/MyClockPiP-unsigned.ipa" Payload)
(cd "$OUT" && shasum -a 256 MyClockPiP-unsigned.ipa > SHA256SUMS.txt)
cp INSTALL.md "$OUT/INSTALL.md"
