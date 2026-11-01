#!/bin/bash
# Builds ScreenToggle.app (requires Xcode Command Line Tools: xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"
APP=ScreenToggle.app
# The release workflow sets VERSION from the tag; local builds take it from git, e.g.
# VERSION=1.0.3, BUILD=1.0.3-2-gd2f7781-dirty (2 commits after v1.0.3, uncommitted changes).
VERSION=${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}
VERSION=${VERSION:-0.0.0}
BUILD=${BUILD:-$(git describe --tags --always --dirty 2>/dev/null | sed 's/^v//' || true)}
BUILD=${BUILD:-$VERSION}
MIN_MACOS=13.0              # SMAppService (Launch at Login) needs macOS 13
rm -rf "$APP" build; mkdir -p "$APP/Contents/MacOS" build
# Universal binary: Apple silicon + Intel.
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos$MIN_MACOS" main.swift -o "build/ScreenToggle-$arch"
done
lipo -create build/ScreenToggle-* -output "$APP/Contents/MacOS/ScreenToggle"
rm -rf build
mkdir -p "$APP/Contents/Resources"
cp AppIcon.icns "$APP/Contents/Resources/"   # regenerate with: swift make-icon.swift
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ScreenToggle</string>
<key>CFBundleIdentifier</key><string>local.screentoggle</string>
<key>CFBundleExecutable</key><string>ScreenToggle</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" 2>/dev/null || true
echo "Built $APP  ->  open $APP"
