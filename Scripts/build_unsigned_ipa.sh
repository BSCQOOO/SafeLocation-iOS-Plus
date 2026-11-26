#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required: brew install xcodegen" >&2
  exit 1
fi

bash "$ROOT/Scripts/bootstrap_vendor.sh"
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
