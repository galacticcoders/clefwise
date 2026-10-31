#!/bin/bash
# Builds a release Clefwise.app into ./build.
# Usage: ./build-app.sh          build only
#        ./build-app.sh --open   build and launch
#        ./build-app.sh --install build and copy to ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Clefwise.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Clefwise" "$APP/Contents/MacOS/Clefwise"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Clefwise</string>
    <key>CFBundleDisplayName</key>
    <string>Clefwise</string>
    <key>CFBundleIdentifier</key>
    <string>local.clefwise</string>
    <key>CFBundleExecutable</key>
    <string>Clefwise</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.education</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS runs it without complaint on this machine.
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

case "${1:-}" in
    --open) open "$APP" ;;
    --install)
        mkdir -p ~/Applications
        rm -rf ~/Applications/Clefwise.app
        cp -R "$APP" ~/Applications/
        echo "Installed to ~/Applications/Clefwise.app"
        ;;
esac
