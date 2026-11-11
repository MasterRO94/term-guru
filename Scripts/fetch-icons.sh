#!/bin/bash
# Downloads the MIT-licensed Material Icon Theme (file, folder and tool logos) from npm into Resources/icons.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="5.40.0"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
(cd "$TMP" && npm pack "material-icon-theme@$VERSION" --silent >/dev/null && tar xzf material-icon-theme-*.tgz)
rm -rf Resources/icons
mkdir -p Resources/icons
# Expanded-folder variants are never shown, and they are a quarter of the set.
find "$TMP/package/icons" -name '*.svg' ! -name '*-open.svg' ! -name '*-open.clone.svg' ! -name '*-open_light.svg' \
  -exec cp {} Resources/icons/ \;
cp "$TMP/package/dist/material-icons.json" Resources/icons/material-icons.json
cp "$TMP/package/LICENSE" Resources/icons/LICENSE
echo "icons: $(find Resources/icons -name '*.svg' | wc -l | tr -d ' ') files (material-icon-theme $VERSION)"
