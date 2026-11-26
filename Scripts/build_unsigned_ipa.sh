#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required: brew install xcodegen" >&2
  exit 1
fi

bash "$ROOT/Scripts/bootstrap_vendor.sh"

# Headers may describe more APIs than the pinned static archive exports.
# Inspect the actual arm64 definitions before enabling optional Swift calls.
SYMBOLS="$(mktemp)"
trap 'rm -f "$SYMBOLS"' EXIT
CONDITIONS='$(inherited)'
xcrun nm -arch arm64 -gU "$ROOT/Vendor/idevice/libidevice_ffi.a" > "$SYMBOLS"
has_symbol() { awk -v wanted="_$1" '$NF == wanted { found=1 } END { exit !found }' "$SYMBOLS"; }
if has_symbol afc_client_connect_rsd && has_symbol afc_client_free; then
  CONDITIONS="$CONDITIONS SAFELOCATION_HAS_AFC"
  echo "AFC: exported"
else
  echo "AFC: unavailable in pinned archive"
fi
if has_symbol installation_proxy_connect_rsd && has_symbol installation_proxy_client_free; then
  CONDITIONS="$CONDITIONS SAFELOCATION_HAS_INSTALLATION_PROXY"
  echo "InstallationProxy: exported"
else
  echo "InstallationProxy: unavailable in pinned archive"
fi
xcodegen generate
rm -rf build Payload SafeLocation-unsigned.ipa

xcodebuild \
  -project SafeLocation.xcodeproj \
  -scheme SafeLocation \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM="" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS="$CONDITIONS" \
  build

APP_PATH="$(find build/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' -print -quit)"
if [ -z "$APP_PATH" ]; then
  echo "Build succeeded but no .app was found." >&2
  exit 2
fi

# Stamp the compiled application, after actool has merged its icon keys.
# Nothing in the source Info.plist should override actool's CFBundleIcons.
python3 - "$APP_PATH" <<'STAMP'
import hashlib,json,os,plistlib,subprocess,sys
from pathlib import Path
app=Path(sys.argv[1])
head=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
assert not os.environ.get('GITHUB_SHA') or os.environ['GITHUB_SHA']==head
icon=Path('SafeLocation/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png')
hash_file=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
info=plistlib.loads((app/'Info.plist').read_bytes())
info['SafeLocationCommit']=head
info['SafeLocationIconSHA256']=hash_file(icon)
(app/'Info.plist').write_bytes(plistlib.dumps(info,fmt=plistlib.FMT_BINARY))
provenance={'commit':head,'run_number':os.environ.get('GITHUB_RUN_NUMBER'),
            'source_icon_sha256':hash_file(icon),
            'assets_car_sha256':hash_file(app/'Assets.car'),
            'packaged_icons':{p.name:hash_file(p) for p in app.glob('AppIcon*.png')}}
(app/'BuildProvenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
STAMP

mkdir Payload
cp -R "$APP_PATH" Payload/
zip -qry SafeLocation-unsigned.ipa Payload
rm -rf Payload
python3 "$ROOT/Scripts/verify_ipa.py" "$ROOT/SafeLocation-unsigned.ipa"

echo "Created and verified: $ROOT/SafeLocation-unsigned.ipa"
