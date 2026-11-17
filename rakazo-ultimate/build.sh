#!/usr/bin/env bash
# Builds the private "Mac-58 ultimate" Rakazo iOS app: upstream at the commit the patch was made
# against, the client patch applied on top, then an unsigned .ipa with the app's own typeface,
# avatar shapes and interface sounds inside.
#
# The workflow only checks this branch out and calls this script, so a change here — a new patch,
# a fixed build step — needs no workflow edit: push the branch and re-dispatch the run.
set -euxo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The upstream tree this patch was made against, so a failed apply names the commit it was tried on.
UPSTREAM="elie222/rakazo"
BASE="12e6f5a7"

# The server baked into the JS bundle (EXPO_PUBLIC_API_URL); the login screen can still point the
# app at another server at runtime.
export EXPO_PUBLIC_API_URL="${EXPO_PUBLIC_API_URL:-https://rakazo.163ll.com}"
export EXPO_NO_TELEMETRY=1
export CI=1

cd "$HERE"
rm -rf src
git clone --filter=blob:none "https://github.com/${UPSTREAM}.git" src
cd src
git checkout "$BASE"
git log -1 --format='upstream %H %s'

git apply -v "$HERE/client.patch"
git diff --stat

# The build is worthless without the patch and its assets: fail here, not 25 minutes later.
test -f apps/mobile/lib/app-font.ts
test -f apps/mobile/lib/document-scanner.ts
test -f apps/mobile/modules/rakazo-document-scanner/ios/RakazoDocumentScannerModule.swift
# A live call is half native: without this module the phone has no microphone stream to send.
test -f apps/mobile/modules/rakazo-realtime-audio/ios/RakazoRealtimeAudioModule.swift
test -f apps/mobile/lib/realtime-call.ts
# This round's own files: the shelves an app belongs on and the row that shows it.
test -f apps/mobile/lib/integration-categories.ts
test -f apps/mobile/components/connect-app-row.tsx
test -f apps/mobile/assets/fonts/xvf/XVF-Regular.ttf
test -f apps/mobile/assets/sounds/grok/ping_4_chime_a.wav
# The phone's own connectors: five frameworks behind one native module, and the usage strings
# iOS shows when the person turns one on. A patch that lost any of them must fail here.
test -f apps/mobile/modules/rakazo-connectors/ios/RakazoConnectorsModule.swift
test -f apps/mobile/modules/rakazo-connectors/ios/PhoneAlarmKit.swift
test -f apps/mobile/modules/rakazo-connectors/ios/PhoneCalendarConnector.swift
test -f apps/mobile/lib/phone-connectors.ts
node -e 'const p=require("./apps/mobile/app.json");const ip=p.expo.ios.infoPlist;for(const k of ["NSAlarmKitUsageDescription","NSCalendarsFullAccessUsageDescription","NSRemindersFullAccessUsageDescription","NSContactsUsageDescription","NSLocationWhenInUseUsageDescription"]){if(!ip[k])throw new Error("missing "+k)}'
grep -q 'expo-font' apps/mobile/app.json
# The icon is shipped as an Icon Composer package and the splash as images: a patch that lost
# either would still compile, so fail here and name what is missing.
test -f apps/mobile/assets/Bot.icon/icon.json
test -f apps/mobile/assets/Bot.icon/Assets/bot-foreground.png
test -f apps/mobile/assets/splash-icon.png
test -f apps/mobile/assets/splash-icon-dark.png
grep -q 'assets/Bot.icon' apps/mobile/app.json
grep -q 'splash-icon-dark.png' apps/mobile/app.json
node -e 'const p=require("./apps/mobile/app.json");const f=(p.expo.plugins||[]).flat();if(!f.includes("expo-font"))throw new Error("expo-font plugin missing");'

npm i -g pnpm@12.18.0
pnpm install --frozen-lockfile

cd apps/mobile
# The config is dynamic, so a patch-level drift is reported rather than repaired.
pnpm exec expo install --check ||
  echo "::warning::expo patch-level version drift ignored (app.config.ts is dynamic, so --fix cannot write it)"
pnpm exec expo prebuild --platform ios --no-install

# Upstream ships an Icon Composer package of its own, and prebuild without --clean leaves it in
# the project: actool would then compile the retired ghost as the app icon and the app would show
# two marks on launch. Drop it, keep Bot.icon, and fail loudly if the project still names it.
rm -rf ios/Rakazo/Rakazo.icon
if grep -Rqs 'Rakazo\.icon' ios/Rakazo.xcodeproj/project.pbxproj; then
  echo "::error::the Xcode project still references Rakazo.icon after prebuild"
  exit 1
fi
if [ -d ios/Rakazo/Bot.icon ]; then
  grep -Eq 'ASSETCATALOG_COMPILER_APPICON_NAME = "?Bot"?' ios/Rakazo.xcodeproj/project.pbxproj ||
    { echo "::error::the app icon is not the Bot package"; exit 1; }
fi
# A stale upstream layer would resurface as the old ghost in a notification banner.
if grep -Rqs 'F97A10\|fb7a11\|FB7A11' ios/Rakazo/Images.xcassets 2>/dev/null; then
  echo "::warning::an upstream orange survived in Images.xcassets"
fi

# The typeface has to be in the built bundle, not merely in the source.
/usr/libexec/PlistBuddy -c 'Print :UIAppFonts' ios/Rakazo/Info.plist | tee /dev/stderr | grep -q 'XVF-Regular.ttf'

cd ios
pod install --repo-update || pod install
xcodebuild -workspace Rakazo.xcworkspace -scheme Rakazo -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build \
  | tee "$HERE/xcodebuild.log"

rm -rf Payload && mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/Rakazo.app Payload/
zip -qry "$HERE/Rakazo-unsigned.ipa" Payload

cd "$HERE"
unzip -l Rakazo-unsigned.ipa | head -20
ls -lh Rakazo-unsigned.ipa

# What the delivered package must carry, checked on the artifact itself.
IPA_PLIST="$(mktemp -d)"
unzip -q -o Rakazo-unsigned.ipa 'Payload/Rakazo.app/Info.plist' -d "$IPA_PLIST"
/usr/libexec/PlistBuddy -c 'Print :UIAppFonts' "$IPA_PLIST/Payload/Rakazo.app/Info.plist" | grep -q 'XVF-Regular.ttf'
/usr/libexec/PlistBuddy -c 'Print :CADisableMinimumFrameDurationOnPhone' "$IPA_PLIST/Payload/Rakazo.app/Info.plist" || true
unzip -l Rakazo-unsigned.ipa | grep -E 'XVF-Regular.ttf|ping_4_chime_a|RakazoDocumentScanner'

# The icon that ships is the one in the source tree, byte for byte, and no ghost PNG rides along.
for icon in monochrome-icon; do
  shipped="$(unzip -p Rakazo-unsigned.ipa "Payload/Rakazo.app/assets/assets/$icon.png" | shasum -a 256 | cut -d' ' -f1)"
  source_sum="$(shasum -a 256 "src/apps/mobile/assets/$icon.png" | cut -d' ' -f1)"
  [ "$shipped" = "$source_sum" ] || { echo "::error::$icon in the package is not the Bot mark"; exit 1; }
done
