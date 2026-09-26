#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
icon_work="$(mktemp -d "${TMPDIR:-/tmp}/mactv-icon.XXXXXX")"
trap 'rm -rf "$icon_work"' EXIT
swift "$repo_root/App/MakeIcon.swift" \
  "$repo_root/App/Resources/AppIcon.png" "$icon_work/AppIcon.iconset"
iconutil -c icns "$icon_work/AppIcon.iconset" \
  -o "$repo_root/App/Resources/AppIcon.icns"
