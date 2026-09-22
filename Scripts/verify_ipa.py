#!/usr/bin/env python3
"""Fail the build unless the final ZIP contains the current app and icon."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    ipa_path = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / 'SafeLocation-unsigned.ipa')
    settings = (ROOT / 'project.yml').read_text()
    version = re.search(r'MARKETING_VERSION: "([^"]+)"', settings)[1]
    build = re.search(r'CURRENT_PROJECT_VERSION: "([^"]+)"', settings)[1]
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if os.environ.get('GITHUB_SHA'):
        assert head == os.environ['GITHUB_SHA'], 'Checkout does not match this Actions run'
    source_icon = ROOT / 'SafeLocation/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
    with tempfile.TemporaryDirectory(prefix='safelocation-ipa-') as temp:
        with zipfile.ZipFile(ipa_path) as archive:
            for name in archive.namelist():
                assert not Path(name).is_absolute() and '..' not in Path(name).parts
            assert archive.testzip() is None, 'Corrupt IPA ZIP'
            archive.extractall(temp)
        app = Path(temp) / 'Payload/Safe Location.app'
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        assert info['CFBundleIdentifier'] == 'com.safelocation.mobile'
        assert info['CFBundleShortVersionString'] == version
        assert info['CFBundleVersion'] == build
        assert info['SafeLocationCommit'] == head
        assert info['SafeLocationIconSHA256'] == sha(source_icon.read_bytes())
        assert (app / info['CFBundleExecutable']).is_file(), 'Missing executable'
        assert float(info['MinimumOSVersion']) >= 18
        icon = info['CFBundleIcons']['CFBundlePrimaryIcon']
        assert icon['CFBundleIconName'] == 'AppIcon', 'Wrong compiled primary icon'
        assert icon['CFBundleIconFiles'], 'No compiled icon files in Info.plist'
        car = app / 'Assets.car'
        assert car.is_file() and car.stat().st_size > 0
        assetutil = shutil.which('assetutil') or '/usr/bin/assetutil'
        records = json.loads(subprocess.check_output([assetutil, '--info', str(car)], text=True))
        app_icons = [r for r in records if str(r.get('Name', '')).startswith('AppIcon')]
        assert app_icons, 'Assets.car does not contain AppIcon renditions'
        compiled_icons = sorted(app.glob('AppIcon*.png'))
        assert compiled_icons, 'No packaged icon PNG fallbacks'
        for name in icon['CFBundleIconFiles']:
            assert any(p.name.startswith(name) for p in compiled_icons), f'Missing {name}'
        provenance = json.loads((app / 'BuildProvenance.json').read_text())
        assert provenance['commit'] == head
        assert provenance['source_icon_sha256'] == sha(source_icon.read_bytes())
        assert provenance['assets_car_sha256'] == sha(car.read_bytes())
        for name, digest in provenance['packaged_icons'].items():
            assert sha((app / name).read_bytes()) == digest
        # ImageIO decodes Apple's optimized PNGs; compare the packaged icon
        # against the current source at the same size, not just its name.
        subprocess.run(['swift', str(ROOT / 'Scripts/verify_icon_pixels.swift'),
                        str(source_icon), str(compiled_icons[0])], check=True)
        report = {
            'verified': True, 'commit': head, 'bundle_id': info['CFBundleIdentifier'],
            'version': version, 'build': build, 'sdk': info.get('DTSDKName'),
            'ipa_sha256': sha(ipa_path.read_bytes()),
            'source_icon_sha256': sha(source_icon.read_bytes()),
            'assets_car_sha256': sha(car.read_bytes()),
            'appicon_renditions': len(app_icons),
            'packaged_icon_files': [p.name for p in compiled_icons],
            'compiled_primary_icon': icon,
        }
        (ROOT / 'ipa-verification.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
