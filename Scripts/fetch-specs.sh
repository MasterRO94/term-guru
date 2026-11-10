#!/bin/bash
# Downloads the MIT-licensed Fig completion specs from npm into Resources/specs.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
(cd "$TMP" && npm pack @withfig/autocomplete --silent >/dev/null && tar xzf withfig-autocomplete-*.tgz)
rm -rf Resources/specs
mkdir -p Resources
cp -R "$TMP/package/build" Resources/specs
cp "$TMP/package/LICENSE" Resources/specs/LICENSE
find Resources/specs -name '*.d.ts' -delete
echo "specs: $(find Resources/specs -name '*.js' | wc -l | tr -d ' ') files"
