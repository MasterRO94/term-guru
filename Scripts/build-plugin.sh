#!/bin/bash
# Compiles the JetBrains plugin against an installed IDE; no Gradle or SDK download needed.
set -euo pipefail
cd "$(dirname "$0")/.."

IDE="${1:-$HOME/Applications/PhpStorm.app}"
JBR="$IDE/Contents/jbr/Contents/Home/bin"
OUT="build/jetbrains"
rm -rf "$OUT"
mkdir -p "$OUT/classes" "$OUT/termguru-caret/lib"

"$JBR/javac" -nowarn --release 17 -cp "$IDE/Contents/lib/*" -d "$OUT/classes" \
  jetbrains-plugin/src/dev/termguru/*.java
cp -R jetbrains-plugin/resources/META-INF "$OUT/classes/"
sed -i '' "s|<version>.*</version>|<version>$(tr -d '[:space:]' < VERSION)</version>|" "$OUT/classes/META-INF/plugin.xml"
# JBR ships no jar tool; a jar is a plain zip.
(cd "$OUT/classes" && zip -qr "../termguru-caret/lib/termguru-caret.jar" .)
echo "built $OUT/termguru-caret"
