#!/bin/zsh
set -eu
cd "${0:A:h}/.."
mkdir -p build/tests
xcrun swiftc -O -parse-as-library -target arm64-apple-macos14.0 Sources/CECCore/*.swift App/SystemVolumeBridge.swift App/TVRemoteBridge.swift Tests/UI/IdlePublicationRegression.swift -o build/tests/IdlePublicationRegression -framework AppKit -framework IOKit
build/tests/IdlePublicationRegression
