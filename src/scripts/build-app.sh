#!/usr/bin/env bash
# Builds "Glance.app" (ad-hoc signed) into build/.
set -euo pipefail
cd "$(dirname "$0")/.."

(cd chart && npm ci && npm test && npm run build)
swift test
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

APP="build/Glance.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/chart"
cp "$BIN/OnscreenTodoMatrix" "$APP/Contents/MacOS/"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp chart/dist/index.html chart/dist/style.css chart/dist/chart.js "$APP/Contents/Resources/chart/"
# No SwiftPM resource bundles may be needed: Bundle.module cannot find them inside a signed .app
# (KeyboardShortcuts is vendored without its bundle for that reason).
if find "$BIN" -maxdepth 1 -name '*.bundle' | grep -q .; then
  echo "ERROR: a dependency ships a SwiftPM resource bundle; Bundle.module would trap in the app" >&2; exit 1
fi
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
# Self-test from a copy outside the build tree: must not trap on a missing resource.
T="$(mktemp -d)"; cp -R "$APP" "$T/"
GLANCE_SELFTEST=1 "$T/Glance.app/Contents/MacOS/OnscreenTodoMatrix" 2>/dev/null | grep -q "selftest ok" \
  || { echo "ERROR: app self-test failed" >&2; exit 1; }
rm -rf "$T"
echo "Built: $(pwd)/$APP"
