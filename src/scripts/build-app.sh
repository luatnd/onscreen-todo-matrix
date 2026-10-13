#!/usr/bin/env bash
# Builds "Onscreen Todo Matrix.app" (ad-hoc signed) into build/.
set -euo pipefail
cd "$(dirname "$0")/.."

(cd chart && npm ci && npm test && npm run build)
swift test
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

APP="build/Onscreen Todo Matrix.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/chart"
cp "$BIN/OnscreenTodoMatrix" "$APP/Contents/MacOS/"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp chart/dist/index.html chart/dist/style.css chart/dist/chart.js "$APP/Contents/Resources/chart/"
# SwiftPM resource bundles of dependencies (KeyboardShortcuts localizations)
find "$BIN" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;
ls "$APP"/Contents/Resources/KeyboardShortcuts_*.bundle >/dev/null 2>&1 \
  || { echo "ERROR: KeyboardShortcuts_*.bundle missing from app Resources" >&2; exit 1; }
codesign --force --deep --sign - "$APP"
echo "Built: $(pwd)/$APP"
