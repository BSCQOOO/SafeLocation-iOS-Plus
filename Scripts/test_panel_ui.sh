#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
xcodegen generate --spec Tests/PanelHarness/project.yml --project Tests/PanelHarness
mkdir -p test-results
xcrun simctl list devices available -j > test-results/devices.json
python3 - <<'PY' > test-results/destinations.txt
import json,re
from pathlib import Path
devices=json.loads(Path('test-results/devices.json').read_text())['devices']
choices=[]
for runtime, entries in devices.items():
    match=re.search(r'iOS-(\d+)-(\d+)',runtime)
    if not match or int(match[1])<18: continue
    phones=[d for d in entries if d.get('isAvailable') and d['name'].startswith('iPhone')]
    if phones: choices.append(((int(match[1]),int(match[2])),phones[0]['udid']))
assert choices,'No iOS simulator is installed'
choices.sort()
for version,udid in dict.fromkeys([choices[0],choices[-1]]):
    print(f'{version[0]}.{version[1]} {udid}')
PY
while read -r version device; do
  echo "Testing persistent panel on iOS $version ($device)"
  xcodebuild test \
    -project Tests/PanelHarness/PanelHarness.xcodeproj \
    -scheme PanelHarness \
    -destination "platform=iOS Simulator,id=$device" \
    -parallel-testing-enabled NO \
    -derivedDataPath build-panel-tests \
    -resultBundlePath "test-results/Panel-iOS-$version.xcresult" \
    CODE_SIGNING_ALLOWED=NO
done < test-results/destinations.txt
