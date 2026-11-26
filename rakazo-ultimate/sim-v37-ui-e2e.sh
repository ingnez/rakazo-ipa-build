#!/usr/bin/env bash
# v37 UI E2E on a real iOS simulator against the local fake-model screenshot API.
# Requires: build.sh already prepared `src/` (pods + prebuild). Captures settings
# (Connected apps) and thread (Speak message + picture stack) Maestro sections.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/src"
OUT="${SCREEN_DIR:-$HERE/sim-v37-ui}"
rm -rf "$OUT" && mkdir -p "$OUT"
export PATH="$HOME/.maestro/bin:/opt/homebrew/opt/postgresql@16/bin:/usr/local/opt/postgresql@16/bin:$PATH"
export CI=1
export EXPO_NO_TELEMETRY=1
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

test -d "$SRC/apps/mobile" || { echo "::error::src missing; run build.sh first"; exit 1; }
cd "$SRC"

echo "== postgres =="
if ! command -v pg_isready >/dev/null 2>&1; then
  brew install postgresql@16
  brew link --force postgresql@16 || true
fi
export PGDATA="${PGDATA:-$OUT/pgdata}"
if ! pg_isready -q 2>/dev/null; then
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

echo "== debug app install =="
# Metro-backed debug build so the screenshot harness can point at the local API.
cd "$SRC/apps/mobile"
export EXPO_PUBLIC_API_URL="http://127.0.0.1:3110"
# Ensure ios/ exists from build.sh prebuild; build Debug for simulator.
xcodebuild -workspace ios/Rakazo.xcworkspace -scheme Rakazo -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$OUT/derived-debug" \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build \
  > "$OUT/xcodebuild-debug.log" 2>&1 || { tail -100 "$OUT/xcodebuild-debug.log"; exit 1; }
APP="$OUT/derived-debug/Build/Products/Debug-iphonesimulator/Rakazo.app"
test -d "$APP" || { echo "::error::debug app missing"; exit 1; }
xcrun simctl uninstall "$UDID" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

echo "== ios screenshots (settings + thread) =="
cd "$SRC"
export IOS_SCREENSHOT_OUT="$OUT/shots"
# Fixture password is local-only and printed nowhere in artifacts beyond Maestro env.
set +e
pnpm ios:screenshots -- --section settings --section thread > "$OUT/screenshots.log" 2>&1
RC=$?
set -e
tail -80 "$OUT/screenshots.log"
# Collect screenshots to a flat folder for the artifact
mkdir -p "$OUT/screens"
find "$OUT/shots" -name '*.png' -print0 2>/dev/null | while IFS= read -r -d '' f; do
  cp "$f" "$OUT/screens/$(basename "$(dirname "$f")")-$(basename "$f")" 2>/dev/null || cp "$f" "$OUT/screens/"
done
ls -la "$OUT/screens" | tee "$OUT/screens-list.txt" || true
# Require the key shots
need=(07-integrations 04-message-actions)
# image stack shot optional-named 04b
MISSING=0
for n in "${need[@]}"; do
  if ! find "$OUT/shots" -name "*${n}*" | grep -q .; then
    echo "::error::missing screenshot $n"
    MISSING=1
  fi
done
if [ "$RC" -ne 0 ] || [ "$MISSING" -ne 0 ]; then
  echo "V37_UI_E2E=FAIL" | tee "$OUT/RESULTS.txt"
  exit 1
fi
echo "V37_UI_E2E=PASS" | tee "$OUT/RESULTS.txt"
# Stop postgres we started
pg_ctl -D "$PGDATA" stop -m fast 2>/dev/null || true
