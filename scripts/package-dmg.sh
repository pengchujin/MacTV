#!/bin/bash
set -euo pipefail
# Package an already signed and notarized application without changing its contents.
APP_PATH="${1:?Usage: package-dmg.sh /path/to/MacTV.app /path/to/output.dmg}"
OUTPUT_PATH="${2:?Missing output DMG path}"
if [[ -e "$OUTPUT_PATH" ]]; then
  echo "Output already exists: $OUTPUT_PATH" >&2
  exit 1
fi
codesign --verify --deep --strict "$APP_PATH"
xcrun stapler validate "$APP_PATH"
STAGING_PATH=$(mktemp -d "${TMPDIR:-/tmp}/mactv-dmg.XXXXXX")
trap 'rm -rf "$STAGING_PATH"' EXIT
ditto "$APP_PATH" "$STAGING_PATH/MacTV.app"
ln -s /Applications "$STAGING_PATH/Applications"
hdiutil create -volname MacTV -srcfolder "$STAGING_PATH" -format UDZO "$OUTPUT_PATH"
hdiutil verify "$OUTPUT_PATH"
