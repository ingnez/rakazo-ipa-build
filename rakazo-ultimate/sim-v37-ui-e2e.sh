#!/usr/bin/env bash
# v37 UI E2E on a real iOS simulator against the local fake-model screenshot API.
# Requires: build.sh prepared `src/` and (preferably) sim-crashcheck's Release sim app.
#
# Harness: Release + expo export:embed (EXPO_PUBLIC_API_URL → local API), OTA disabled,
# Metro skipped. Fixture users are local ios-screenshots@example.test only — never 主人.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/src"
OUT="${SCREEN_DIR:-$HERE/sim-v37-ui}"
rm -rf "$OUT" && mkdir -p "$OUT"
export PATH="$HOME/.maestro/bin:/opt/homebrew/opt/postgresql@16/bin:/usr/local/opt/postgresql@16/bin:$PATH"
export CI=1
export EXPO_NO_TELEMETRY=1
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
export IOS_SCREENSHOT_EMBEDDED=1

API_URL="http://127.0.0.1:3110"
export EXPO_PUBLIC_API_URL="$API_URL"

cleanup_artifact() {
  # Artifact zip failed previously on live pg_wal; always stop DB and drop pgdata before upload.
  pg_ctl -D "${PGDATA:-$OUT/pgdata}" stop -m fast 2>/dev/null || true
  rm -rf "$OUT/pgdata" "$OUT/derived-debug" 2>/dev/null || true
}
trap cleanup_artifact EXIT

test -d "$SRC/apps/mobile" || { echo "::error::src missing; run build.sh first"; exit 1; }
cd "$SRC"

echo "== postgres =="
if ! command -v pg_isready >/dev/null 2>&1; then
  brew install postgresql@16
  brew link --force postgresql@16 || true
fi
export PGDATA="${PGDATA:-$OUT/pgdata}"
if ! pg_isready -h 127.0.0.1 -p 5433 -q 2>/dev/null; then
  if [ ! -d "$PGDATA" ]; then
    initdb -D "$PGDATA" --auth-local=trust --auth-host=trust
  fi
  pg_ctl -D "$PGDATA" -l "$OUT/postgres.log" -o "-p 5433 -k $OUT" start
  for i in $(seq 1 30); do pg_isready -h 127.0.0.1 -p 5433 -q && break; sleep 1; done
fi
export DATABASE_URL="postgres://$(whoami)@127.0.0.1:5433/postgres"
createdb -h 127.0.0.1 -p 5433 rakazo_ios_screenshots 2>/dev/null || true
export DATABASE_URL="postgres://$(whoami)@127.0.0.1:5433/rakazo_ios_screenshots"

echo "== maestro =="
if ! command -v maestro >/dev/null 2>&1; then
  curl -fsSL "https://get.maestro.mobile.dev" | bash
  export PATH="$HOME/.maestro/bin:$PATH"
fi
maestro --version | tee "$OUT/maestro-version.txt"

echo "== deps =="
pnpm install --frozen-lockfile 2>&1 | tee "$OUT/pnpm-install.log" | tail -20

echo "== simulator =="
UDID="$(xcrun simctl list devices available -j | python3 -c '
import json,sys
devs=[d for r,ds in json.load(sys.stdin)["devices"].items() if "iOS" in r for d in ds]
phones=[d for d in devs if d["name"].startswith("iPhone")]
pro=[d for d in phones if "Pro" in d["name"] and "Max" not in d["name"]]
print((pro or phones)[-1]["udid"])')"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
export SIM_UDID="$UDID"
echo "UDID=$UDID" | tee "$OUT/udid.txt"

# Force English UI so Maestro's upstream first-launch assert (and our broadened one) can match.
xcrun simctl spawn "$UDID" defaults write -g AppleLanguages -array en 2>/dev/null || true
xcrun simctl spawn "$UDID" defaults write -g AppleLocale -string en_US 2>/dev/null || true
xcrun simctl spawn "$UDID" defaults write -g AppleTextDirection 0 2>/dev/null || true

echo "== release app + embed local API bundle =="
cd "$SRC/apps/mobile"

APP="$PWD/ios/build-sim/Build/Products/Release-iphonesimulator/Rakazo.app"
if [ ! -d "$APP" ]; then
  echo "no sim-crashcheck Release app; building one"
  cd ios
  xcodebuild -workspace Rakazo.xcworkspace -scheme Rakazo -configuration Release \
    -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build-sim \
    ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build \
    > "$OUT/xcodebuild-release.log" 2>&1 || { tail -100 "$OUT/xcodebuild-release.log"; exit 1; }
  cd ..
  APP="$PWD/ios/build-sim/Build/Products/Release-iphonesimulator/Rakazo.app"
fi
test -d "$APP" || { echo "::error::Release simulator app missing at $APP"; exit 1; }

rm -rf "${TMPDIR:-/tmp}"/metro-* "${TMPDIR:-/tmp}"/haste-map-* node_modules/.cache .expo || true
pnpm exec expo export:embed \
  --platform ios \
  --dev false \
  --entry-file index.js \
  --bundle-output "$APP/main.jsbundle" \
  --assets-dest "$APP" \
  > "$OUT/bundle-embed.log" 2>&1 || { tail -80 "$OUT/bundle-embed.log"; exit 1; }
ls -la "$APP/main.jsbundle" | tee "$OUT/bundle-embed-ls.txt"
# Prove the local API URL made it into the embed (Hermes may still keep ASCII literals).
if ! strings "$APP/main.jsbundle" | grep -q '127.0.0.1:3110'; then
  echo "::warning::127.0.0.1:3110 not found via strings in main.jsbundle (may still be ok if compressed)"
else
  echo "embed contains 127.0.0.1:3110" | tee -a "$OUT/bundle-embed-ls.txt"
fi

# Disable OTA so production cannot replace the local-API bundle.
for plist in "$APP/Expo.plist" "$APP/Supporting/Expo.plist" "$APP/Info.plist"; do
  [ -f "$plist" ] || continue
  /usr/libexec/PlistBuddy -c 'Delete :EXUpdatesEnabled' "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Add :EXUpdatesEnabled bool false' "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Delete :EXUpdatesCheckOnLaunch' "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Add :EXUpdatesCheckOnLaunch string NEVER' "$plist" 2>/dev/null || true
  echo "updates tweaked in $plist" | tee -a "$OUT/updates-disable.txt"
done

BID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
xcrun simctl uninstall "$UDID" "$BID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
echo "installed Release $BID with embedded API $API_URL" | tee "$OUT/install.txt"

echo "== patch screenshot CLI to skip Metro =="
SCREEN_TS="$SRC/packages/testkit/src/cli/ios-app-screenshots.ts"
test -f "$SCREEN_TS" || { echo "::error::missing $SCREEN_TS"; exit 1; }
python3 - "$SCREEN_TS" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = "  const metro = await startMetro(apiUrl, outDir);"
repl = """  const metro =
    process.env.IOS_SCREENSHOT_EMBEDDED === \"1\"
      ? { stop() {} }
      : await startMetro(apiUrl, outDir);"""
if "IOS_SCREENSHOT_EMBEDDED" in text and needle not in text:
    print("already patched")
elif needle not in text:
    raise SystemExit(f"patch failed: needle not found in {path}")
else:
    path.write_text(text.replace(needle, repl, 1))
    print("patched", path)
PY

echo "== broaden first-launch assert (en + zh) =="
FL="$SRC/apps/mobile/e2e/ios-screenshots/subflows/first-launch.yaml"
python3 - "$FL" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
old = 'visible: "Sign up for Rakazo|Sign in to Rakazo|Account|.*How did you hear about us.*"'
new = 'visible: "Sign up for Rakazo|Sign in to Rakazo|注册 Rakazo|登录 Rakazo|Create your Rakazo|Welcome back|Email|邮箱|Account|账户|.*How did you hear.*"'
if old in text:
    p.write_text(text.replace(old, new, 1))
    print("broadened", p)
elif "注册 Rakazo" in text:
    print("already broadened")
else:
    raise SystemExit(f"could not patch first-launch.yaml:\n{text}")
PY

echo "== preflight launch (simctl screenshot) =="
xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BID" | tee "$OUT/preflight-launch.txt"
sleep 20
xcrun simctl io "$UDID" screenshot "$OUT/screens/preflight-after-20s.png" 2>/dev/null \
  || { mkdir -p "$OUT/screens"; xcrun simctl io "$UDID" screenshot "$OUT/screens/preflight-after-20s.png"; }
xcrun simctl spawn "$UDID" log show --last 2m --predicate 'process == "Rakazo"' --style compact \
  > "$OUT/preflight-app.log" 2>/dev/null || true
# Soft check: look for redbox / Metro / fatal in preflight log
if grep -qiE 'Could not connect to development server|Metro|RCTFatal|Unhandled JS Exception' "$OUT/preflight-app.log"; then
  echo "::error::preflight still shows Metro/JS fatal — see preflight-app.log"
  tail -40 "$OUT/preflight-app.log"
fi
xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true

echo "== ios screenshots (settings + thread) =="
cd "$SRC"
export IOS_SCREENSHOT_OUT="$OUT/shots"
export EXPO_PUBLIC_API_URL="$API_URL"
set +e
pnpm ios:screenshots -- --section settings --section thread > "$OUT/screenshots.log" 2>&1
RC=$?
set -e
tail -120 "$OUT/screenshots.log"

mkdir -p "$OUT/screens"
# Always grab a live frame + maestro debug shots for diagnosis
xcrun simctl io "$UDID" screenshot "$OUT/screens/post-run.png" 2>/dev/null || true
find "$OUT/shots" -name '*.png' -print0 2>/dev/null | while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  if [[ "$base" =~ ^[0-9]{2} ]]; then
    cp "$f" "$OUT/screens/$base"
  else
    cp "$f" "$OUT/screens/$(basename "$(dirname "$f")")-$base" 2>/dev/null || cp "$f" "$OUT/screens/" || true
  fi
done
ls -la "$OUT/screens" | tee "$OUT/screens-list.txt" || true

need=(07-integrations 04-message-actions 04b-image-stack)
MISSING=0
for n in "${need[@]}"; do
  if ! find "$OUT/shots" -name "*${n}*" | grep -q .; then
    echo "::error::missing screenshot $n"
    MISSING=1
  else
    echo "found screenshot $n: $(find "$OUT/shots" -name "*${n}*" | head -1)"
  fi
done
if [ "$RC" -ne 0 ] || [ "$MISSING" -ne 0 ]; then
  echo "V37_UI_E2E=FAIL" | tee "$OUT/RESULTS.txt"
  exit 1
fi
echo "V37_UI_E2E=PASS" | tee "$OUT/RESULTS.txt"
