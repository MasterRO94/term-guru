#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
VERSION="$(tr -d '[:space:]' < VERSION)"
[ -d Resources/specs ] || Scripts/fetch-specs.sh
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
"$BIN/tgr" --experimental-dump-help | "$BIN/tgr" _fig-spec > Resources/specs/tgr.js

APP="build/TermGuru.app/Contents"
rm -rf build/TermGuru.app
mkdir -p "$APP/MacOS" "$APP/Resources"
cp "$BIN/GuruApp" "$APP/MacOS/TermGuru"
cp "$BIN/tgr" "$APP/MacOS/tgr"
cp Resources/app/Info.plist "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Info.plist"
# The updater rebuilds from this checkout; the app runs under launchd and cannot inherit CODESIGN_IDENTITY.
/usr/libexec/PlistBuddy -c "Add :GuruSourcePath string $PWD" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Add :GuruCodesignIdentity string ${CODESIGN_IDENTITY:--}" "$APP/Info.plist"
cp Resources/app/AppIcon.icns "$APP/Resources/AppIcon.icns"
cp -R Resources/shell "$APP/Resources/shell"
cp -R Resources/specs "$APP/Resources/specs"
cp -R Resources/custom-specs "$APP/Resources/custom-specs"

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
