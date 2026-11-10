#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
VERSION="$(tr -d '[:space:]' < VERSION)"
[ -d Resources/specs ] || Scripts/fetch-specs.sh
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/TermGuru.app/Contents"
rm -rf build/TermGuru.app
mkdir -p "$APP/MacOS" "$APP/Resources"
cp "$BIN/GuruApp" "$APP/MacOS/TermGuru"
cp "$BIN/tgr" "$APP/MacOS/tgr"
cp Resources/app/Info.plist "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Info.plist"
cp -R Resources/shell "$APP/Resources/shell"
cp -R Resources/specs "$APP/Resources/specs"

# Any installed JetBrains IDE can compile the plugin; some bundle a JDK but not the platform jars, so try each.
PLUGIN_BUILT=
for ide in "$HOME"/Applications/*.app /Applications/*.app; do
  [ -x "$ide/Contents/jbr/Contents/Home/bin/javac" ] || continue
  if Scripts/build-plugin.sh "$ide" >/dev/null 2>&1; then
    mkdir -p "$APP/Resources/jetbrains"
    cp -R build/jetbrains/termguru-caret "$APP/Resources/jetbrains/"
    PLUGIN_BUILT=1
    break
  fi
done
[ -n "$PLUGIN_BUILT" ] || echo "warning: no JetBrains IDE could build the caret plugin; it is not bundled" >&2

codesign --force --sign "${CODESIGN_IDENTITY:--}" build/TermGuru.app
echo "built build/TermGuru.app $VERSION"
