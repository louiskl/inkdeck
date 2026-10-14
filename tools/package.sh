#!/bin/sh
# Build release archives into dist/:
#   inkdeck-<version>-plugin.zip  – just the KOReader plugin (copy into koreader/plugins/)
#   inkdeck-<version>-full.zip    – plugin + editor + bridge + docs
set -e
cd "$(dirname "$0")/.."
VERSION="$(sed -n 's/^Core.VERSION = "\(.*\)"/\1/p' inkdeck.koplugin/inkdeck/core.lua)"
rm -rf dist && mkdir -p dist
zip -qr "dist/inkdeck-$VERSION-plugin.zip" inkdeck.koplugin -x '*/.DS_Store'
zip -qr "dist/inkdeck-$VERSION-full.zip" inkdeck.koplugin editor bridge docs README.md README.de.md LICENSE CHANGELOG.md \
    -x '*/.DS_Store' '*/__pycache__/*'
ls -l dist
