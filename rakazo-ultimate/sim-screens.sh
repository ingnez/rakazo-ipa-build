#!/usr/bin/env bash
# Review screenshots on a real iOS simulator, after build.sh has prepared `src` (prebuild + pods).
# Builds a second, simulator-only copy of the app whose JS bundle is compiled with
# EXPO_PUBLIC_AVATAR_REVIEW=1, so it opens on the avatar page (palette, bodies, a bot list) instead
# of sign-in, then photographs it in light and dark. The shipped .ipa is built without the flag.
set -euxo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/sim-screens"
rm -rf "$OUT" && mkdir -p "$OUT"
cd "$HERE/src/apps/mobile"

# The IPA's bundle was transformed without the flag: drop every transform cache so the flag is read.
rm -rf "${TMPDIR:-/tmp}"/metro-* "${TMPDIR:-/tmp}"/haste-map-* node_modules/.cache .expo || true
export EXPO_PUBLIC_AVATAR_REVIEW=1

xcrun simctl list devices available | tee "$OUT/devices.txt" >/dev/null
UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devs = [d for r, ds in json.load(sys.stdin)["devices"].items() if "iOS" in r for d in ds]
phones = [d for d in devs if d["name"].startswith("iPhone")]
pro = [d for d in phones if "Pro" in d["name"] and "Max" not in d["name"]]
print((pro or phones)[-1]["udid"])')"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b

cd ios
xcodebuild -workspace Rakazo.xcworkspace -scheme Rakazo -configuration Release \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build-sim \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build \
  > "$OUT/xcodebuild-sim.log" 2>&1 || { tail -60 "$OUT/xcodebuild-sim.log"; exit 1; }
tail -3 "$OUT/xcodebuild-sim.log"

APP="build-sim/Build/Products/Release-iphonesimulator/Rakazo.app"
BID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 || true

for mode in light dark; do
  xcrun simctl ui "$UDID" appearance "$mode"
  xcrun simctl terminate "$UDID" "$BID" || true
  sleep 2
  xcrun simctl launch "$UDID" "$BID"
  sleep 20
  xcrun simctl io "$UDID" screenshot "$OUT/avatar-gallery-$mode.png"
done
xcrun simctl spawn "$UDID" log show --last 3m --predicate "process == \"Rakazo\"" --style compact \
  > "$OUT/app-log.txt" 2>/dev/null || true
ls -la "$OUT"
