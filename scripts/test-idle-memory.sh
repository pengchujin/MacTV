#!/bin/zsh
set -eu
cd "${0:A:h}/.."
mkdir -p build/tests
xcrun swiftc -O -parse-as-library -target arm64-apple-macos14.0 Sources/CECCore/*.swift App/SystemVolumeBridge.swift App/TVRemoteBridge.swift App/RemoteController.swift App/RemoteView.swift Tests/UI/IdleMemoryStress.swift -o build/tests/IdleMemoryStress -framework AppKit -framework IOKit
build/tests/IdleMemoryStress > build/tests/idle-memory.log 2>&1 &
stress_pid=$!
trap 'kill "$stress_pid" 2>/dev/null || true' EXIT
while ! rg -q 'STRESS DONE' build/tests/idle-memory.log; do
    kill -0 "$stress_pid"
    sleep 1
done
heap "$stress_pid" -sortBySize > build/tests/idle-memory-heap.txt
rg 'Physical footprint:|ObservationTracking.Id|ObservationTracking.Entry' build/tests/idle-memory-heap.txt
