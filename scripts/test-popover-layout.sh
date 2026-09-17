#!/bin/zsh
set -eu
cd "${0:A:h}/.."
APP="$PWD/build/PopoverLayoutRegression.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R Sources/CECCore/Resources/*.lproj "$APP/Contents/Resources/"
xcrun swiftc -D LAYOUT_TEST -parse-as-library -target arm64-apple-macos14.0 Sources/CECCore/CommandRunner.swift Sources/CECCore/Localization.swift Sources/CECCore/CECProtocol.swift Sources/CECCore/RemoteCommand.swift Sources/CECCore/VolumeKey.swift Sources/CECCore/NativeCEC.swift Sources/CECCore/TVRemoteEvent.swift App/TVRemoteBridge.swift App/SystemVolumeBridge.swift App/RemoteController.swift App/RemoteView.swift App/AppDelegate.swift Tests/UI/PopoverLayoutRegression.swift -o "$APP/Contents/MacOS/PopoverLayoutRegression" -framework SwiftUI -framework AppKit
for language in en zh-Hans zh-Hant; do
    SCREEN_REMOTE_LANGUAGE="$language" "$APP/Contents/MacOS/PopoverLayoutRegression" --layout-test
done
