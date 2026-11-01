#!/bin/bash
# Builds ScreenToggle.app (requires Xcode Command Line Tools: xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"
APP=ScreenToggle.app
VERSION=${VERSION:-0.0.0}   # set by the release workflow from the git tag
MIN_MACOS=13.0              # SMAppService (Launch at Login) needs macOS 13
rm -rf "$APP" build; mkdir -p "$APP/Contents/MacOS" build
# Universal binary: Apple silicon + Intel.
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos$MIN_MACOS" main.swift -o "build/ScreenToggle-$arch"
done
lipo -create build/ScreenToggle-* -output "$APP/Contents/MacOS/ScreenToggle"
rm -rf build
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ScreenToggle</string>
<key>CFBundleIdentifier</key><string>local.screentoggle</string>
<key>CFBundleExecutable</key><string>ScreenToggle</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" 2>/dev/null || true
echo "Built $APP  ->  open $APP"
