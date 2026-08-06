#!/usr/bin/env bash
# Godot exports an Xcode project for iOS, so deployment remains explicit and
# inspectable instead of hiding signing and wireless install steps in an IDE.

set -euo pipefail

GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Keep Xcode's optimized assets outside res:// so a later Godot import never
# mistakes Apple's CgBI PNGs for game assets.
OUT="${TMPDIR:-/tmp}/whoyoupeekin-ios"
TEAM="45MSS5RXML"
BUNDLE="com.lull.riftline"
DEVICE="${1:-}"

if [[ -z "$DEVICE" ]]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null \
    | grep -E "connected" | grep "iPhone" \
    | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" \
    | head -1)
fi

if [[ -z "$DEVICE" ]]; then
  echo "No connected iPhone found." >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
"$GODOT" --headless --path "$HERE" --export-debug "iOS" "$OUT/WhoYouPeekin.xcodeproj"

XCODE_PROJECT="$OUT/WhoYouPeekin.xcodeproj"
SCHEME=$(find "$XCODE_PROJECT/xcshareddata/xcschemes" -maxdepth 1 -name '*.xcscheme' -print -quit 2>/dev/null | sed 's#.*/##; s#\.xcscheme$##')
if [[ -z "$SCHEME" ]]; then
  SCHEME=$(xcodebuild -list -project "$XCODE_PROJECT" 2>/dev/null | awk '/Schemes:/{getline; gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit}')
fi
if [[ -z "$SCHEME" ]]; then
  echo "Could not discover the generated Xcode scheme." >&2
  exit 1
fi

xcodebuild -project "$XCODE_PROJECT" -scheme "$SCHEME" \
  -sdk iphoneos -destination "platform=iOS,id=$DEVICE" \
  -configuration Debug -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" \
  build

APP=$(find ~/Library/Developer/Xcode/DerivedData -name "${SCHEME}.app" \
  -path "*/Build/Products/Debug-iphoneos/*" -not -path "*Index.noindex*" \
  -newermt "-5 minutes" 2>/dev/null | head -1)

if [[ -z "$APP" ]]; then
  echo "Could not find the built app bundle." >&2
  exit 1
fi

xcrun devicectl device install app --device "$DEVICE" "$APP"
if ! xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE"; then
  # Wireless installs remain valid when iOS locks before the final launch.
  echo "WhoYouPeekin installed. Unlock the device and open WhoYouPeekin from the Home Screen." >&2
fi
