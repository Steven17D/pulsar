#!/usr/bin/env bash
# Build Pulsar and install it as ~/Applications/Pulsar.app.
#
# Idempotent: safe to run repeatedly; replaces the existing bundle in
# place. Codesigns ad-hoc so the binary can claim its TCC entitlements
# without a paid Apple Developer ID. Spotlight reindexes the bundle at
# the end so the new build appears immediately.

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v swift >/dev/null 2>&1; then
    echo "error: \`swift\` not found. Install Xcode Command Line Tools first:" >&2
    echo "  xcode-select --install" >&2
    exit 1
fi

echo "==> building (release)"
swift build -c release

APP="${HOME}/Applications/Pulsar.app"
echo "==> staging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 644 Sources/Pulsar/Info.plist "$APP/Contents/Info.plist"
install -m 755 .build/release/Pulsar    "$APP/Contents/MacOS/pulsar"
install -m 644 AppIcon.icns             "$APP/Contents/Resources/AppIcon.icns"

echo "==> codesigning"
codesign --force --sign - --options runtime \
    --entitlements pulsar.entitlements \
    "$APP"

echo "==> spotlight reindex"
mdimport "$APP" >/dev/null 2>&1 || true

cat <<EOF

Installed: $APP

First-run permission: macOS will prompt for "Audio Capture" the first
time Pulsar launches. Approve via System Settings → Privacy & Security
→ Audio Capture → Pulsar.

Launch it with:
    open "$APP"

EOF
