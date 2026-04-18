#!/usr/bin/env bash
#
# Build NotchyPrompter.app.
#
# Uses SwiftPM to fetch WhisperKit and compile the executable, then
# assembles a proper .app bundle with Info.plist and signs it with the
# stable "NotchyPrompter Dev" self-signed identity. The stable identity
# means TCC keeps the Screen Recording grant across rebuilds; ad-hoc
# signing (the previous behaviour) invalidated it on every build.
#
# First-time setup:
#   scripts/setup-dev-signing.sh
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
SIGN_IDENTITY="NotchyPrompter Dev"

# Fail fast if the developer hasn't run the one-time setup script. Without
# the stable identity, a fallback to ad-hoc would silently re-introduce
# the TCC-thrash problem this script was changed to avoid.
if ! security find-identity -v -p codesigning | grep -q "\"${SIGN_IDENTITY}\""; then
    echo "error: code-signing identity \"${SIGN_IDENTITY}\" not found." >&2
    echo "Run the one-time setup first:" >&2
    echo "  scripts/setup-dev-signing.sh" >&2
    exit 1
fi

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

echo "==> codesign ($SIGN_IDENTITY)"
codesign --force --sign "$SIGN_IDENTITY" --options runtime "$APP"

echo
echo "Built $APP"
echo "Run: open $APP"
