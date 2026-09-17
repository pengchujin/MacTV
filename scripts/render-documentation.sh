#!/bin/zsh
set -eu
cd "${0:A:h}/.."
APP="$PWD/build/Documentation.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" docs/images
cp -R Sources/CECCore/Resources/*.lproj "$APP/Contents/Resources/"
xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 Sources/CECCore/CommandRunner.swift Sources/CECCore/Localization.swift Sources/CECCore/CECProtocol.swift Sources/CECCore/RemoteCommand.swift Sources/CECCore/VolumeKey.swift Sources/CECCore/NativeCEC.swift Sources/CECCore/TVRemoteEvent.swift App/TVRemoteBridge.swift App/SystemVolumeBridge.swift App/RemoteController.swift App/RemoteView.swift scripts/RenderDocumentation.swift -o "$APP/Contents/MacOS/RenderDocumentation" -framework SwiftUI -framework AppKit
SCREEN_REMOTE_LANGUAGE=zh-Hans "$APP/Contents/MacOS/RenderDocumentation"
