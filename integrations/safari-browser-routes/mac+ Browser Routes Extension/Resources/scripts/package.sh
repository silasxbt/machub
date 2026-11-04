#!/usr/bin/env bash
set -euo pipefail

# Package the extension into dist/laziest-browser-v<version>.zip
root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root_dir"

ver=$(node -p "require('./manifest.json').version")
mkdir -p dist

zip_name="dist/laziest-browser-v${ver}.zip"
echo "Packing -> ${zip_name}"
rm -f "$zip_name"

  zip -r "$zip_name" \
    manifest.json \
    background.js \
    content.js \
    options.html \
    options.css \
    options.js \
    welcome.html \
    welcome.css \
    welcome.js \
    README.md \
    LICENSE >/dev/null

echo "Done: ${zip_name}"
