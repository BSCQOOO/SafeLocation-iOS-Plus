#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "[1/10] Validate plist files"
python3 - <<'PY'
import plistlib
for p in ['SafeLocation/Resources/Info.plist','SafeLocation/Resources/SafeLocation.entitlements']:
    with open(p,'rb') as f:
        plistlib.load(f)
    print('OK', p)
PY

echo "[2/10] Validate YAML"
python3 - <<'PY'
try:
    import yaml
except ImportError:
    print('PyYAML unavailable; skipping YAML parser validation')
else:
    for p in ['project.yml','.github/workflows/build-unsigned-ipa.yml']:
        with open(p,'r',encoding='utf-8') as f:
            yaml.safe_load(f)
        print('OK', p)
PY

echo "[3/10] Check required files"
required=(
  SafeLocation/App/SafeLocationApp.swift
  SafeLocation/Engine/LocationEngine.swift
  SafeLocation/Engine/CellularTunnelBridge.swift
  SafeLocation/Engine/PairOnDeviceService.swift
  SafeLocation/Engine/SpoofController.swift
  SafeLocation/Features/RootView.swift
  SafeLocation/Features/ProfilesView.swift
  SafeLocation/Features/AutoRestoreSheet.swift
  SafeLocation/Features/Route/RoutePlanner.swift
  SafeLocation/Features/Route/RoutePlannerSheet.swift
  SafeLocation/Features/Joystick/JoystickPad.swift
  SafeLocation/Features/Joystick/JoystickSheet.swift
  SafeLocation/Features/Diagnostics/DiagnosticsView.swift
  SafeLocation/Support/GPXService.swift
  SafeLocation/Support/GlassUI.swift
  SafeLocation/Support/LocationProfile.swift
  SafeLocation/Support/MapLinkResolver.swift
  SafeLocation/Support/CoordinatePipeline.swift
  SafeLocation/Support/MapLocationProvider.swift
  Tests/CoordinatePipeline/main.swift
  Tests/SearchArchitecture/check.py
  SafeLocation/Support/PendingImportBridge.swift
  SafeLocation/Shortcuts/ImportLocationIntent.swift
  SHORTCUTS_SHARE_CN.md
  Scripts/bootstrap_vendor.sh
  Scripts/build_unsigned_ipa.sh
  Scripts/validate_app_icon.py
  Scripts/verify_ipa.py
  SafeLocation/Support/DrawerState.swift
  SafeLocation/Support/PersistentMapPanel.swift
)
for f in "${required[@]}"; do
  test -s "$f" || { echo "Missing: $f" >&2; exit 1; }
done

echo "[4/10] Parse Swift source"
if command -v swiftc >/dev/null 2>&1; then
  while IFS= read -r -d '' f; do
    swiftc -parse "$f"
    echo "OK $f"
  done < <(find SafeLocation -name '*.swift' -print0 | sort -z)
else
  echo "swiftc unavailable; skipping Swift parser validation"
fi

echo "[5/10] Check release version"
grep -q 'MARKETING_VERSION: "1.8.0"' project.yml
grep -q '<string>Safe Location</string>' SafeLocation/Resources/Info.plist
grep -q 'SafeLocation-unsigned-v' .github/workflows/build-unsigned-ipa.yml

echo "[6/10] Safety / packaging sanity"
! grep -R --line-number --exclude-dir=.git --exclude='quality_check.sh' -E 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|p12|password[[:space:]]*=' SafeLocation Scripts >/dev/null 2>&1 || {
  echo "Potential secret-like material found in source tree" >&2
  exit 1
}

echo "[7/10] Native Apple Maps drawer / icon checks"
python3 Scripts/validate_app_icon.py
python3 - <<'CHECK'
from pathlib import Path
import re
root=Path('SafeLocation/Features/RootView.swift').read_text()
glass=Path('SafeLocation/Support/GlassUI.swift').read_text()

assert '.sheet(' in root
assert 'isPresented: $controlSheetPresented' in root
assert '.presentationDetents(' in root
assert '.presentationDragIndicator(.visible)' in root
assert '.presentationBackgroundInteraction(.enabled)' in root
assert '.presentationContentInteraction(.resizes)' in root
assert '.interactiveDismissDisabled(true)' in root
assert 'AppleMapsSheetBackground()' in root
assert 'private var regularControlSheet' in root
assert 'private var bottomSearchBar' in root
assert '.safeGlassInteractive(in: Capsule())' in root
assert '.contentShape(Capsule())' in root
assert 'compactIdle ? 20 : 16' in root
assert 'PresentationDetent = .height(76)' in root
assert 'PresentationDetent = .fraction(0.47)' in root
assert 'struct AppleMapsSheetBackground' in glass
assert 'MapPanelWorkspace(state: $drawer)' not in root
assert not re.search(r'toggleThreeD\(\)\s*\n\s*toggleThreeD\(\)', root), '3D control toggles twice'
print('Native Apple Maps drawer/search layout invariants passed')
CHECK

echo "[8/10] Final UI regression checks"
grep -q 'private var joystickSheetContent' SafeLocation/Features/RootView.swift
grep -q 'MapLocationProvider' SafeLocation/Features/RootView.swift
grep -q 'UserAnnotation()' SafeLocation/Features/RootView.swift
grep -q 'private var mapLocationButton' SafeLocation/Features/RootView.swift
grep -q 'position.positionedByUser' SafeLocation/Features/RootView.swift
grep -q 'private func selectMapPoint' SafeLocation/Features/RootView.swift
grep -q 'suppressMapTapUntil' SafeLocation/Features/RootView.swift
grep -q 'Button("查看全部")' SafeLocation/Features/RootView.swift
grep -q 'favoriteSaved' SafeLocation/Features/RootView.swift
grep -q 'private var mapModeControls' SafeLocation/Features/RootView.swift
grep -q 'private func handleMapLocationButton' SafeLocation/Features/RootView.swift
grep -q 'position = .userLocation' SafeLocation/Features/RootView.swift
grep -q 'CoordinatePipeline.selectedFromMapKit' SafeLocation/Features/RootView.swift
grep -q 'CoordinatePipeline.dvtFromSelected' SafeLocation/Engine/LocationEngine.swift
grep -q 'enum CoordinatePipeline' SafeLocation/Support/CoordinatePipeline.swift
! grep -R --line-number -E 'MapCoordinateConverter|wgs84ToGcj|gcj02ToWgs|137\.8347|72\.004|55\.8271|0\.8293' SafeLocation >/dev/null 2>&1
! grep -q 'CoordinateSpace' SafeLocation/Support/MapLinkResolver.swift
grep -q 'private func toggleThreeD' SafeLocation/Features/RootView.swift
grep -q 'UserAnnotation()' SafeLocation/Features/RootView.swift
grep -q 'onMapCameraChange' SafeLocation/Features/RootView.swift
grep -q 'bestRealCoordinate' SafeLocation/Features/RootView.swift
grep -q 'isSimulatedBySoftware' SafeLocation/Support/MapLocationProvider.swift
grep -q 'kCLLocationAccuracyBestForNavigation' SafeLocation/Engine/BackgroundLocationKeeper.swift
grep -q 'guard location.horizontalAccuracy <= maxHorizontalAccuracy else' SafeLocation/Support/MapLocationProvider.swift
grep -q 'headingOrientation = .portrait' SafeLocation/Support/MapLocationProvider.swift
grep -q 'headingOrientation = .portrait' SafeLocation/Engine/BackgroundLocationKeeper.swift
grep -q 'locationManagerShouldDisplayHeadingCalibration' SafeLocation/Engine/BackgroundLocationKeeper.swift
grep -q 'isRestoringRealLocation' SafeLocation/Engine/SpoofController.swift
grep -q 'static func restore(' SafeLocation/Engine/LocationEngine.swift
grep -q 'recenterAfterRealLocationRestore' SafeLocation/Features/RootView.swift
grep -q 'pairingPath: pairing.pairingPath' SafeLocation/Features/RootView.swift
grep -q 'x-callback-url' SafeLocation/Engine/CellularTunnelBridge.swift
grep -q 'runAirplaneOnShortcut' SafeLocation/Engine/CellularTunnelBridge.swift
grep -q 'handleCellularDataOffCallback' SafeLocation/Engine/SpoofController.swift
grep -q 'handleForegroundReturnFromExternalFlow' SafeLocation/Engine/SpoofController.swift
grep -q 'cellular-off-ready' SafeLocation/App/SafeLocationApp.swift
grep -q 'SafeLocation Airplane On' SafeLocation/Engine/CellularTunnelBridge.swift
grep -q 'nanoseconds: 220_000_000' SafeLocation/Features/RootView.swift
grep -q 'setSearchContext' SafeLocation/Features/SearchController.swift
grep -q 'resolveAppleMapsStyleQuery' SafeLocation/Features/SearchController.swift
grep -q 'MKLocalSearchCompleter' SafeLocation/Features/SearchController.swift
grep -q 'completion: result.completion' SafeLocation/Features/SearchController.swift
grep -q 'priority: .required' SafeLocation/Features/SearchController.swift
grep -q 'struct LocalSearchResult' SafeLocation/Features/SearchController.swift
grep -q 'struct ResolvedPlace' SafeLocation/Features/SearchController.swift
grep -q 'scheduleSuggestionSearch' SafeLocation/Features/SearchController.swift
grep -q 'await search.resolve(result)' SafeLocation/Features/RootView.swift
grep -q 'refreshSearchCenter' SafeLocation/Features/RootView.swift
! grep -q 'private var connectionSection' SafeLocation/Features/RootView.swift
grep -q 'retention-days: 7' .github/workflows/build-unsigned-ipa.yml
grep -q 'retention-days: 3' .github/workflows/build-unsigned-ipa.yml
grep -q '<string>shortcuts</string>' SafeLocation/Resources/Info.plist

echo "[9/10] Search architecture regression tests"
python3 Tests/SearchArchitecture/check.py

echo "[10/10] Coordinate pipeline regression tests"
TMP_COORD_TEST="$(mktemp -d)"
trap 'rm -rf "$TMP_COORD_TEST"' EXIT
swiftc \
  SafeLocation/Support/CoordinatePipeline.swift \
  Tests/CoordinatePipeline/main.swift \
  -o "$TMP_COORD_TEST/coordinate-regression"
"$TMP_COORD_TEST/coordinate-regression"

echo "Quality checks passed."
