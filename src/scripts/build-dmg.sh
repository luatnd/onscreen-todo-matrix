#!/usr/bin/env bash
# Builds build/Glance-<version>.dmg (drag-to-Applications installer) from the ad-hoc signed app.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" scripts/Info.plist)"
DMG="build/Glance-$VERSION.dmg"

rm -rf build/dmg-staging "$DMG"
mkdir -p build/dmg-staging
cp -R build/Glance.app build/dmg-staging/
ln -s /Applications build/dmg-staging/Applications
hdiutil create -volname "Glance" -srcfolder build/dmg-staging -ov -format UDZO "$DMG"
rm -rf build/dmg-staging
hdiutil verify "$DMG"
echo "DMG: $(pwd)/$DMG"
