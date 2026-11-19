#!/usr/bin/env bash
# Launch check on a real iOS simulator, after build.sh has prepared `src` (prebuild + pods).
# Builds a Release simulator copy of the app, then launches it with several JS bundles:
#   - the bundle this tree compiles (what the .ipa from this tree ships),
#   - the shipped bundles from the given releases (BUNDLE_RELEASES), byte for byte,
# fresh, and as an upgrade over an earlier bundle's data (same container, data kept).
# The native binary and Info.plist of v23 and v24 are identical, so swapping main.jsbundle on one
# simulator build reproduces each release exactly. A run passes when the app is still alive 30 s
# after launch; crash reports and the app's log go to the artifact.
set -uxo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/sim-check"
rm -rf "$OUT" && mkdir -p "$OUT/bundles"
cd "$HERE/src/apps/mobile/ios"

UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devs = [d for r, ds in json.load(sys.stdin)["devices"].items() if "iOS" in r for d in ds]
phones = [d for d in devs if d["name"].startswith("iPhone")]
pro = [d for d in phones if "Pro" in d["name"] and "Max" not in d["name"]]
print((pro or phones)[-1]["udid"])')"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b

xcodebuild -workspace Rakazo.xcworkspace -scheme Rakazo -configuration Release \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build-sim \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build \
  > "$OUT/xcodebuild-sim.log" 2>&1 || { tail -80 "$OUT/xcodebuild-sim.log"; exit 1; }
tail -3 "$OUT/xcodebuild-sim.log"

APP="$PWD/build-sim/Build/Products/Release-iphonesimulator/Rakazo.app"
BID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
cp "$APP/main.jsbundle" "$OUT/bundles/tree.jsbundle"

for rel in ${BUNDLE_RELEASES:-}; do
  d="$(mktemp -d)"
  gh release download "$rel" -R "$GITHUB_REPOSITORY" -p 'Bot*.ipa' -D "$d" && \
    (cd "$d" && unzip -q -o ./*.ipa 'Payload/Rakazo.app/main.jsbundle') && \
    cp "$d/Payload/Rakazo.app/main.jsbundle" "$OUT/bundles/$rel.jsbundle"
done
ls -la "$OUT/bundles"

STAGE="$(mktemp -d)/Rakazo.app"
install_with() { # bundle-name
  rm -rf "$STAGE" && cp -R "$APP" "$STAGE"
  cp "$OUT/bundles/$1.jsbundle" "$STAGE/main.jsbundle"
  xcrun simctl install "$UDID" "$STAGE"
}
FAIL=0
launch_check() { # label
  local label="$1" start pid alive
  start="$(date '+%Y-%m-%d %H:%M:%S')"
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
  sleep 1
  pid="$(xcrun simctl launch "$UDID" "$BID" | awk '{print $NF}')"
  sleep 30
  if ps -p "$pid" >/dev/null 2>&1; then alive=ALIVE; else alive=CRASHED; fi
  # Only this tree's own bundle gates the step; an earlier release seeding data may crash itself.
  case "$label" in *tree*) [ "$alive" = ALIVE ] || FAIL=1 ;; esac
  xcrun simctl io "$UDID" screenshot "$OUT/$label.png" || true
  xcrun simctl spawn "$UDID" log show --start "$start" --predicate 'process == "Rakazo"' --style compact \
    > "$OUT/$label.log" 2>/dev/null || true
  grep -iE 'exception|fatal|TypeError|ReferenceError|invariant|RCTFatal|abort' "$OUT/$label.log" | head -40 \
    > "$OUT/$label.errors.txt" || true
  echo "$label pid=$pid $alive" | tee -a "$OUT/RESULTS.txt"
}

for b in $(cd "$OUT/bundles" && ls | sed 's/\.jsbundle$//'); do
  xcrun simctl uninstall "$UDID" "$BID" 2>/dev/null || true
  install_with "$b"
  launch_check "fresh-$b"
  launch_check "relaunch-$b"
done
# Upgrade: data left by the first listed release, then each other bundle installed over it.
FIRST="${BUNDLE_RELEASES%% *}"
if [ -n "$FIRST" ] && [ -f "$OUT/bundles/$FIRST.jsbundle" ]; then
  for b in $(cd "$OUT/bundles" && ls | sed 's/\.jsbundle$//'); do
    [ "$b" = "$FIRST" ] && continue
    xcrun simctl uninstall "$UDID" "$BID" 2>/dev/null || true
    install_with "$FIRST"
    launch_check "base-$FIRST-for-$b"
    install_with "$b"
    launch_check "upgrade-$FIRST-to-$b"
  done
fi
mkdir -p "$OUT/crash"
cp ~/Library/Logs/DiagnosticReports/Rakazo* "$OUT/crash/" 2>/dev/null || true
ls -la "$OUT/crash"
cat "$OUT/RESULTS.txt"
for f in "$OUT"/*.errors.txt; do echo "== $f"; cat "$f"; done
grep -q "tree.*ALIVE" "$OUT/RESULTS.txt" || FAIL=1
exit "$FAIL"
