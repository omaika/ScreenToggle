#!/bin/bash
# Builds ScreenToggle.app (requires Xcode Command Line Tools: xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"
APP=ScreenToggle.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/ScreenToggle"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ScreenToggle</string>
<key>CFBundleIdentifier</key><string>local.screentoggle</string>
<key>CFBundleExecutable</key><string>ScreenToggle</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" 2>/dev/null || true
echo "Built $APP  ->  open $APP"
