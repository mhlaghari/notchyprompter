#!/usr/bin/env bash
#
# Build NotchyPrompter.app.
#
# Uses SwiftPM to fetch WhisperKit and compile the executable, then
# assembles a proper .app bundle with Info.plist and an ad-hoc signature
# (required on macOS 26 for private-entitlement apps launched from Finder).
#
# Usage:
#   cd NotchyPrompter && ./build.sh
#   open NotchyPrompter.app

set -euo pipefail

cd "$(dirname "$0")"

APP="NotchyPrompter.app"
BIN_NAME="NotchyPrompter"
BIN_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"
PLIST_DST="$APP/Contents/Info.plist"

echo "==> swift build (release)"
swift build -c release

BUILT_BIN="$(swift build -c release --show-bin-path)/$BIN_NAME"
if [[ ! -x "$BUILT_BIN" ]]; then
    echo "error: expected binary at $BUILT_BIN" >&2
    exit 1
fi

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$BIN_DIR" "$RES_DIR"
cp "$BUILT_BIN" "$BIN_DIR/$BIN_NAME"
cp Info.plist "$PLIST_DST"

echo "==> codesign (ad-hoc)"
codesign --force --sign - --options runtime "$APP"

echo
echo "Built $APP"
echo "Run: open $APP"
