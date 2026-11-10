#!/bin/bash
# Builds TermGuru, installs it to ~/Applications and links the CLI into ~/.local/bin.
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/build.sh
DEST="$HOME/Applications/TermGuru.app"
"$DEST/Contents/MacOS/tgr" stop >/dev/null 2>&1 || true
pkill -x TermGuru 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/.local/bin"
rm -rf "$DEST"
cp -R build/TermGuru.app "$DEST"
ln -sf "$DEST/Contents/MacOS/tgr" "$HOME/.local/bin/tgr"
"$HOME/.local/bin/tgr" install "$@"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "! ~/.local/bin was not on PATH; new zsh/bash shells get it from the TermGuru line in ~/.zshrc and ~/.bashrc" ;;
esac
