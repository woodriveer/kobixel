#!/usr/bin/env bash
#
# Bumps the version in package.json and builds a new
# kobixel-X.Y.Z.aseprite-extension, removing old builds.
#
# Usage:
#   ./release.sh            # bumps the patch version (0.1.0 -> 0.1.1)
#   ./release.sh minor      # 0.1.0 -> 0.2.0
#   ./release.sh major      # 0.1.0 -> 1.0.0
#
# Linux/macOS counterpart to release.ps1 (Windows). Keep both in sync.

set -euo pipefail

bump="${1:-patch}"
case "$bump" in
  major|minor|patch) ;;
  *)
    echo "Usage: $0 [major|minor|patch]" >&2
    exit 1
    ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")"

pkg_path="package.json"

if ! command -v zip >/dev/null 2>&1; then
  echo "error: 'zip' is required but not found in PATH" >&2
  exit 1
fi

version_line=$(grep -m1 -E '"version":[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$pkg_path" || true)
if [[ -z "$version_line" ]]; then
  echo "error: could not find a \"version\": \"X.Y.Z\" field in $pkg_path" >&2
  exit 1
fi

current_version=$(echo "$version_line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
IFS='.' read -r major minor patch <<< "$current_version"

case "$bump" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
esac

new_version="${major}.${minor}.${patch}"

# Regex replace in place (not a JSON round-trip via jq/python), so the rest
# of package.json's formatting (key order, spacing) doesn't get reshuffled.
# LC_ALL=C avoids sed choking on multibyte content in some locales; a plain
# ASCII-only pattern doesn't need it, but it's cheap insurance.
LC_ALL=C sed -i -E \
  "s/\"version\":[[:space:]]*\"[0-9]+\.[0-9]+\.[0-9]+\"/\"version\": \"${new_version}\"/" \
  "$pkg_path"
# package.json must stay BOM-less (Aseprite's JSON parser fails on one) -
# plain `sed -i` on Linux never adds a BOM, so no extra step is needed here
# (unlike release.ps1, which has to work around Windows PowerShell 5.1).

rm -f kobixel-*.aseprite-extension
zip_path="kobixel-${new_version}.zip"
ext_path="kobixel-${new_version}.aseprite-extension"
rm -f "$zip_path" "$ext_path"
zip -X -9 -q "$zip_path" package.json kobixel.lua
mv "$zip_path" "$ext_path"

echo "Built $ext_path (version $new_version)"
echo "Next: install it in Aseprite (Edit > Preferences > Extensions > Add Extension), remove the old version first, restart Aseprite."
