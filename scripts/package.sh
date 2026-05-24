#!/usr/bin/env bash
# Build Pulsar as a distributable Pulsar.zip in the repo root.
# Used by CI on release tags and locally for one-off shareable builds.

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v swift >/dev/null 2>&1; then
    echo "error: \`swift\` not found." >&2
    exit 1
fi

swift build -c release

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/pulsar-pkg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

APP="$STAGE/Pulsar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 644 Sources/Pulsar/Info.plist "$APP/Contents/Info.plist"
install -m 755 .build/release/Pulsar    "$APP/Contents/MacOS/pulsar"
install -m 644 AppIcon.icns             "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --options runtime \
    --entitlements pulsar.entitlements \
    "$APP"

OUT="${OUT:-$PWD/Pulsar.zip}"
rm -f "$OUT"
( cd "$STAGE" && zip -qr "$OUT" Pulsar.app )

echo "Built $OUT"
echo "Open: open \"$OUT\""
