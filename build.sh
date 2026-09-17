#!/bin/zsh
set -eu
cd "${0:A:h}"
APP="$PWD/build/MacTV.app"
SIGN_IDENTITY="${SCREEN_REMOTE_SIGN_IDENTITY:--}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -O -parse-as-library -target arm64-apple-macos14.0 Sources/CECCore/CommandRunner.swift Sources/CECCore/Localization.swift Sources/CECCore/CECProtocol.swift Sources/CECCore/RemoteCommand.swift Sources/CECCore/VolumeKey.swift App/SystemVolumeBridge.swift App/RemoteController.swift App/RemoteView.swift App/AppDelegate.swift -o "$APP/Contents/MacOS/MacTV" -framework SwiftUI -framework AppKit
xcrun swiftc -O -target arm64-apple-macos14.0 Sources/CECCore/Localization.swift Sources/CECCore/CECProtocol.swift Sources/CECCore/NativeCEC.swift Sources/CECCore/RemoteCommand.swift CLI/main.swift -o "$APP/Contents/MacOS/MacTVCEC" -framework IOKit
cp -R Sources/CECCore/Resources/*.lproj "$APP/Contents/Resources/"
codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/MacTVCEC"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacTV</string>
<key>CFBundleIdentifier</key><string>uk.shenqi.maccec</string>
<key>CFBundleName</key><string>MacTV</string>
<key>CFBundleDisplayName</key><string>MacTV</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string><string>zh-Hant</string></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
mkdir -p build/AppIcon.iconset
sips -z 1024 1024 App/Resources/AppIcon.png --out build/icon.png >/dev/null
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" build/icon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" build/icon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$APP/Contents/Info.plist"
codesign --force --sign "$SIGN_IDENTITY" "$APP"
printf '%s\n' "$APP"
