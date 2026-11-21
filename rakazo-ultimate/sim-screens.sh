#!/usr/bin/env bash
# Review screenshots of the avatar system on a real iOS simulator.
#
# It reuses the simulator build sim-crashcheck.sh already made (no second xcodebuild): only the JS
# bundle is rebuilt with EXPO_PUBLIC_AVATAR_REVIEW=1, swapped into the .app, and launched, so the
# app opens on the avatar page (Lumen team, the seven states, the palette, the appearance picker
# and a bot list) instead of sign-in. Photographed in light and dark. The shipped .ipa is built
# without the flag.
set -euxo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Called from sim-crashcheck.sh with the launch check's own folder, so the avatar page rides in
# the artifact that check already uploads.
OUT="${SCREEN_DIR:-$HERE/sim-screens}"
mkdir -p "$OUT"
cd "$HERE/src/apps/mobile"

APP="$PWD/ios/build-sim/Build/Products/Release-iphonesimulator/Rakazo.app"
if [ ! -d "$APP" ]; then
  echo "::error::no simulator build to photograph (sim-crashcheck must run first)"
  exit 1
fi

# The IPA's bundle was transformed without the flag: drop every transform cache so the flag is read.
rm -rf "${TMPDIR:-/tmp}"/metro-* "${TMPDIR:-/tmp}"/haste-map-* node_modules/.cache .expo || true
export EXPO_PUBLIC_AVATAR_REVIEW=1

BUNDLED=0
if pnpm exec expo export:embed \
  --platform ios \
  --dev false \
  --entry-file index.js \
  --bundle-output "$APP/main.jsbundle" \
  --assets-dest "$APP" \
  > "$OUT/bundle.log" 2>&1; then
  BUNDLED=1
  ls -la "$APP/main.jsbundle"
else
  # The bundle could not be swapped into the existing build: compile a review copy instead, the
  # way earlier rounds did. Slower, and only on this path.
  tail -40 "$OUT/bundle.log" || true
  cd ios
  xcodebuild -workspace Rakazo.xcworkspace -scheme Rakazo -configuration Release \
    -destination "platform=iOS Simulator,id=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devs = [d for r, ds in json.load(sys.stdin)["devices"].items() if "iOS" in r for d in ds]
phones = [d for d in devs if d["name"].startswith("iPhone")]
pro = [d for d in phones if "Pro" in d["name"] and "Max" not in d["name"]]
print((pro or phones)[-1]["udid"])')" \
    -derivedDataPath build-sim-review \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build \
    > "$OUT/xcodebuild-sim.log" 2>&1 || { tail -60 "$OUT/xcodebuild-sim.log"; exit 1; }
  cd ..
  APP="$PWD/ios/build-sim-review/Build/Products/Release-iphonesimulator/Rakazo.app"
fi
echo "bundle swapped: $BUNDLED"

UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devs = [d for r, ds in json.load(sys.stdin)["devices"].items() if "iOS" in r for d in ds]
phones = [d for d in devs if d["name"].startswith("iPhone")]
pro = [d for d in phones if "Pro" in d["name"] and "Max" not in d["name"]]
print((pro or phones)[-1]["udid"])')"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b

BID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
xcrun simctl terminate "$UDID" "$BID" || true
xcrun simctl uninstall "$UDID" "$BID" || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 || true

for mode in light dark; do
  xcrun simctl ui "$UDID" appearance "$mode"
  xcrun simctl terminate "$UDID" "$BID" || true
  sleep 2
  xcrun simctl launch "$UDID" "$BID"
  sleep 18
  xcrun simctl io "$UDID" screenshot "$OUT/avatar-gallery-$mode.png"
  # A second frame a moment later: the two differ only where the bodies moved, which is how a
  # still screenshot can still prove the states are playing.
  sleep 1
  xcrun simctl io "$UDID" screenshot "$OUT/avatar-gallery-$mode-later.png"
done
xcrun simctl spawn "$UDID" log show --last 3m --predicate "process == \"Rakazo\"" --style compact \
  > "$OUT/app-log.txt" 2>/dev/null || true
ls -la "$OUT"
