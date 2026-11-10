#!/bin/bash
# Tags the version in VERSION and publishes a GitHub release with its CHANGELOG section.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION must be X.Y.Z, got '$VERSION'" >&2; exit 1; }

NOTES="$(awk -v v="$VERSION" '
  /^## \[/ { printing = index($0, "## [" v "]") == 1; next }
  /^\[[^]]+\]: / { next }
  printing { print }
' CHANGELOG.md)"
[ -n "${NOTES//[[:space:]]/}" ] || { echo "CHANGELOG.md has no notes under '## [$VERSION]'" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "commit or stash your changes first" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "tag $TAG already exists; bump VERSION" >&2; exit 1; }

if [ "${1:-}" = "--dry-run" ]; then
  printf 'would release %s from %s with notes:\n%s\n' "$TAG" "$(git rev-parse --short HEAD)" "$NOTES"
  exit 0
fi

git tag -a "$TAG" -m "TermGuru $VERSION"
git push origin HEAD "$TAG"
gh release create "$TAG" --title "TermGuru $VERSION" --notes "$NOTES"
