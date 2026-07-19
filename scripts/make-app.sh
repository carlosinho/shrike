#!/bin/sh
# Builds the shrike-gui release binary and wraps it in a Shrike.app bundle
# (ad-hoc signed, for local use). Output: dist/Shrike.app
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product shrike-gui

APP="dist/Shrike.app"
mkdir -p dist
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/shrike-gui "$APP/Contents/MacOS/Shrike"
# SPM resource bundle (title-bar icon); Bundle.module finds it in Resources.
cp -R .build/release/Shrike_shrike-gui.bundle "$APP/Contents/Resources/"

# App icon from the project logo (512×512), via an intermediate .iconset.
ICONSET=".build/Shrike.iconset"
rm -rf "$ICONSET"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" docs/Shrike.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Shrike.icns"
rm -rf "$ICONSET"

# The GUI's version comes from its single source of truth, GUIVersion.current
# (independent of the CLI's version in Sources/shrike/Shrike.swift).
GUI_VERSION=$(sed -n 's/^ *static let current = "\(.*\)".*/\1/p' Sources/shrike-gui/Version.swift)
if [ -z "$GUI_VERSION" ]; then
    echo "error: could not read GUIVersion.current from Sources/shrike-gui/Version.swift" >&2
    exit 1
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Shrike</string>
    <key>CFBundleExecutable</key>      <string>Shrike</string>
    <key>CFBundleIdentifier</key>      <string>com.carlosinho.Shrike</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleIconFile</key>        <string>Shrike</string>
    <key>CFBundleShortVersionString</key> <string>${GUI_VERSION}</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
