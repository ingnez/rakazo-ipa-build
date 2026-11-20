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
# And a call that stays audible is the module listening to the audio graph: a patch that lost the
# route/configuration repair, or the tap before the start, must fail here and not 25 minutes later.
grep -q 'AVAudioEngineConfigurationChange' apps/mobile/modules/rakazo-realtime-audio/ios/RakazoRealtimeAudioModule.swift
grep -q 'private func repair(_ why: String)' apps/mobile/modules/rakazo-realtime-audio/ios/RakazoRealtimeAudioModule.swift
grep -q 'ArrayBuffer.isView(data)' apps/mobile/lib/realtime-call.ts
# A file's card shows what is inside the file: the parser, the sheet it is set on, and the page a
# PDF is drawn as. A patch that lost any of them would still compile a card that says nothing.
test -f apps/mobile/lib/file-preview.ts
test -f apps/mobile/components/thread/file-preview-paper.tsx
grep -q 'file-paper-fade' apps/mobile/components/thread/file-preview-paper.tsx
grep -q 'pdfThumbnail' apps/mobile/modules/rakazo-pdf-view/ios/RakazoPdfViewModule.swift
# A deck or a workbook has a page too, drawn by the system's reader: a patch that lost the call,
# the cache or the JS that asks for it would still compile a card that shows nothing for one.
test -f apps/mobile/lib/office-thumbnail.ts
test -f apps/mobile/lib/optional-native.ts
grep -q 'officeThumbnail' apps/mobile/modules/rakazo-pdf-view/ios/RakazoPdfViewModule.swift
grep -q 'office-page-thumbnails' apps/mobile/modules/rakazo-pdf-view/ios/RakazoPdfViewModule.swift
grep -q 'QLThumbnailGenerator' apps/mobile/modules/rakazo-pdf-view/ios/RakazoPdfViewModule.swift
# The eyes are two on every face: the clamp that keeps them apart is the patch's own, and a patch
# that lost it draws the one white bar the user photographed across the black body.
grep -q 'EYE_SKIN_SHARE' packages/core/src/babygrok-face.ts
grep -q 'babygrokBodyReach' packages/core/src/babygrok-face.ts
# This round's own files: the shelves an app belongs on and the row that shows it.
test -f apps/mobile/lib/integration-categories.ts
test -f apps/mobile/components/connect-app-row.tsx
test -f apps/mobile/assets/fonts/xvf/XVF-Regular.ttf
test -f apps/mobile/assets/sounds/grok/ping_4_chime_a.wav
# This round's own page and the numbers it is read from: a patch that lost either must fail here.
test -f "apps/mobile/app/(settings)/usage.tsx"
test -f apps/mobile/lib/usage-display.ts
grep -q 'usage/details' "apps/mobile/app/(settings)/usage.tsx"
grep -q 'USAGE_DETAIL_WINDOWS' packages/contracts/src/domain.ts
# The phone's own connectors: five frameworks behind one native module, and the usage strings
# iOS shows when the person turns one on. A patch that lost any of them must fail here.
test -f apps/mobile/modules/rakazo-connectors/ios/RakazoConnectorsModule.swift
test -f apps/mobile/modules/rakazo-connectors/ios/PhoneAlarmKit.swift
test -f apps/mobile/modules/rakazo-connectors/ios/PhoneCalendarConnector.swift
test -f apps/mobile/lib/phone-connectors.ts
node -e 'const p=require("./apps/mobile/app.json");const ip=p.expo.ios.infoPlist;for(const k of ["NSAlarmKitUsageDescription","NSCalendarsFullAccessUsageDescription","NSRemindersFullAccessUsageDescription","NSContactsUsageDescription","NSLocationWhenInUseUsageDescription","NSPhotoLibraryUsageDescription"]){if(!ip[k])throw new Error("missing "+k)}'
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

# This round's own speed: the inbox keeps a copy of its first chats so the first tap opens at once,
# and a chat draws a screenful of messages before the rest. A patch that lost either would still
# compile, and the app would feel slow again.
# Preload waits until first paint is idle, runs one chat at a time, and caps the cold-start wave
# at 5 so it cannot compete with startup; later idle waves fill up to 20, across Spaces.
test -f apps/mobile/lib/preload-chats.ts
test -f apps/mobile/lib/preload-chats.test.ts
test -f apps/mobile/lib/chat-rpc.ts
test -f apps/mobile/lib/saved-servers.ts
grep -q 'export const PRELOADED_CHATS = 20;' apps/mobile/lib/preload-chats.ts
grep -q 'export const COLD_START_PRELOAD_CHATS = 5;' apps/mobile/lib/preload-chats.ts
grep -q 'allowPreloadAfterFirstPaint' apps/mobile/lib/preload-chats.ts
grep -q 'allowPreloadAfterFirstPaint' apps/mobile/app/index.tsx
# v24 crashed on launch: React Native 0.88 ships no InteractionManager in release builds, and the
# home screen's after-first-paint hook called it. Idle work goes through run-when-idle.ts only.
test -f apps/mobile/lib/run-when-idle.ts
# This round: a back-office task draws as one gray status line under the opening reply.
test -f packages/core/src/status-line.ts
grep -q 'function TaskStatusLine' apps/mobile/components/thread/special-message-card.tsx
grep -q 'statusLinesAfterOpening' apps/mobile/lib/thread-transcript.ts
grep -q 'style !== "line"' apps/mobile/lib/message-presentation.ts
grep -q 'runWhenIdle' apps/mobile/lib/after-first-paint.ts
if grep -RnsE '\bInteractionManager\b' apps/mobile/app apps/mobile/components apps/mobile/lib apps/mobile/hooks \
  --include='*.ts' --include='*.tsx' --exclude='*.test.ts' --exclude='*.test.tsx' | grep -v '^\S*:[0-9]*: *\(//\|\*\)'; then
  echo "::error::app code uses InteractionManager, which React Native 0.88 removed from release builds"
  exit 1
fi
grep -q 'export function currentSavedChatsScope' apps/mobile/lib/saved-chats.ts
grep -q 'void preloadChats(inboxChats(listData))' apps/mobile/app/index.tsx
grep -q 'initialNumToRender={6}' apps/mobile/components/thread/thread-message-list.tsx
grep -q 'maxToRenderPerBatch={4}' apps/mobile/components/thread/thread-message-list.tsx

# This round: a third-party connection can refresh its model list, and each row shows
# known context size and image support (or unknown). A patch that lost either would
# still compile a page that never says it is working.
test -f apps/mobile/lib/model-capability-line.ts
test -f apps/mobile/lib/connection-model-list.test.tsx
grep -q 'models/refreshModels' "apps/mobile/app/(settings)/model-connection.tsx"
grep -q 't`Refresh models`' "apps/mobile/app/(settings)/model-connection.tsx"
grep -q 'showCapabilities' apps/mobile/components/connection-model-list.tsx
grep -q 'refreshModels:' packages/contracts/src/rpc.ts

# This round: only the orange star on the home hero, live avatars blink, the
# shipped mark is the Bot icon, and a chat shows stacked images plus a composer
# tray. The Photos/Vision native module has to be in the tree before prebuild.
test -f apps/mobile/lib/avatar-badges.ts
grep -q 'export const HERO_AVATAR_SIZE = 103;' apps/mobile/lib/avatar-badges.ts
test -f packages/core/src/mochi-avatar.ts
test -f packages/core/src/mochi-avatar.test.ts
test -f apps/mobile/components/mochi-bot-avatar.tsx
grep -q 'MochiBotAvatar' apps/mobile/components/bot-avatar.tsx
test -f apps/mobile/lib/after-first-paint.ts
grep -q 'useAfterFirstPaint' apps/mobile/components/mochi-bot-avatar.tsx
test -f apps/mobile/components/image-card-stack.tsx
test -f apps/mobile/components/composer-attach-tray.tsx
# The composer's own photo picker module: without it the shipped app falls back to the package,
# which reports a taken photo as a cancel on a current iOS and left the album looking dead.
test -f apps/mobile/modules/photo-picker/ios/PhotoPickerModule.swift
test -f apps/mobile/modules/photo-picker/ios/PhotoPicker.podspec
grep -q 'presentationControllerDidDismiss' apps/mobile/modules/photo-picker/ios/PhotoPickerModule.swift
grep -q 'hasNativePhotoPicker' apps/mobile/lib/pick-attachments.ts
# v27: a sheet that never appears, or a photo whose bytes never arrive, must end in an answer
# instead of the composer's "reading photos" line. The module names the sheet it could not show,
# bounds each read, and falls back to the library; the composer bounds the whole pick.
grep -q 'failed to present photo picker' apps/mobile/modules/photo-picker/ios/PhotoPickerModule.swift
grep -q 'LIBRARY_PICK_WATCHDOG_MS' apps/mobile/lib/pick-attachments.ts
PICKER=apps/mobile/modules/photo-picker/ios/PhotoPickerModule.swift
# v30: a photo that lives only in iCloud was the case the six-second read was wrong for — its
# file does not exist on this phone, so every route timed out at once. The library is the route
# such a photo takes, and it is asked for a 2048-pixel copy with twenty-five seconds to download:
# not for the original bytes, which have to arrive whole before anything can be drawn.
grep -q 'PHImageManager.default().requestImage(' "$PICKER"
grep -q 'targetSize: libraryTarget' "$PICKER"
grep -q 'private static let libraryTarget = CGSize(width: 2048, height: 2048)' "$PICKER"
grep -q 'static let libraryTimeout: TimeInterval = 25' "$PICKER"
grep -q 'static let dataTimeout: TimeInterval = 15' "$PICKER"
grep -q 'static let fileTimeout: TimeInterval = 2' "$PICKER"
if grep -n 'requestImageDataAndOrientation' "$PICKER"; then
  echo "::error::the photo library is asked for the original bytes again; that download is what never finished on a phone"
  exit 1
fi
# v30: the download says it is a download, a first rougher copy is not taken for the photo, and a
# download that ran out of time is cancelled and named as one.
grep -q 'options.progressHandler' "$PICKER"
grep -q 'trace.addOnce("icloud=downloading")' "$PICKER"
grep -q 'PHImageResultIsDegradedKey' "$PICKER"
grep -q 'progress.cancel()' "$PICKER"
grep -q 'request.cancel()' "$PICKER"
grep -q 'iCloud 照片下载超时' "$PICKER"
# v30: once the photo is read from the app's own library, the sheet is serving nothing, so it goes
# before the download — the person sees the composer's reading line instead of a still sheet. It is
# the only place outside settle that may take it away.
grep -q 'dismiss(sheet)' "$PICKER"
grep -q 'if result.assetIdentifier != nil, await canReadPhotoLibrary(trace: trace) {' "$PICKER"
if [ "$(grep -c 'dismiss(sheet)' "$PICKER")" != "2" ] \
  || ! grep -qx '    dismiss(sheet)' "$PICKER" \
  || ! grep -q 'Self.dismiss(sheet)' "$PICKER"; then
  echo "::error::the sheet is taken away somewhere other than settle and the library route"
  exit 1
fi
# v30: the library is tried before the provider's bytes, because a photo in iCloud has no file for
# the provider to hand over, and the bytes route only serves the sheet that is still up.
lib_line=$(grep -n 'switch await fromPhotoLibrary' "$PICKER" | head -1 | cut -d: -f1)
data_line=$(grep -n 'await readData(provider, type: type' "$PICKER" | head -1 | cut -d: -f1)
if [ -z "$lib_line" ] || [ -z "$data_line" ] || [ "$lib_line" -ge "$data_line" ]; then
  echo "::error::the provider's bytes are tried before the photo library; an iCloud photo has no file to hand over"
  exit 1
fi
# v29: the sheet is the process the photos are served from, so it has to still be up while they
# are read — v28 dismissed it first thing in didFinishPicking, and every read of that selection
# then timed out on a real phone. It is dismissed in settle, when the pick is over; nothing in the
# delegate may take it away before that.
grep -q 'weak var activePicker: PHPickerViewController?' apps/mobile/modules/photo-picker/ios/PhotoPickerModule.swift
if sed -n '/func picker(_ picker: PHPickerViewController, didFinishPicking/,/^  }$/p' "$PICKER" \
  | grep -n 'dismiss('; then
  echo "::error::the photo picker takes its sheet away before the photos are read; the sheet is what serves them"
  exit 1
fi
# v29: the photo is read the way expo-image-picker reads one — for its own registered type, one
# route at a time — and no longer as several loads racing on one item provider. A patch that went
# back to the race or to .compatible fails here.
grep -q 'configuration.preferredAssetRepresentationMode = .current' "$PICKER"
grep -q 'private static func preferredType(of provider: NSItemProvider) -> String' "$PICKER"
grep -q 'provider.loadFileRepresentation(forTypeIdentifier: type)' "$PICKER"
grep -q 'provider.loadDataRepresentation(forTypeIdentifier: type)' "$PICKER"
grep -q 'static let totalDeadline: TimeInterval = 30' "$PICKER"
if grep -n 'loadObject(ofClass: UIImage.self)' "$PICKER"; then
  echo "::error::the picker asks one item provider for the photo several ways at once again"
  exit 1
fi
# A failure names the steps it tried and how long each took, so a real phone tells which system
# call refused or timed out.
grep -q 'case unreadable(String)' "$PICKER"
grep -q 'case cloudTimeout(String)' "$PICKER"
grep -q 'final class ReadTrace' "$PICKER"
# v28 crashed on the first image card: a worklet method written inside ImageStackLayout's own
# object literal cannot see the object it belongs to, and the worklet build leaves it undefined.
# The literal may hold constants and module-level functions only.
if sed -n '/export const ImageStackLayout = {/,/} as const;/p' apps/mobile/lib/image-stack-layout.ts \
  | grep -nE "ImageStackLayout\.|'worklet'"; then
  echo "::error::ImageStackLayout's own methods must be module-level worklets, not methods in the literal"
  exit 1
fi
# v28: a previewed link draws the page's own picture, small, beside its title and domain.
grep -q 'export function linkPreviewCover' apps/mobile/lib/link-preview.ts
grep -q 'testID="link-card"' apps/mobile/components/thread/link-preview-card.tsx
grep -q 'cardCover' apps/mobile/components/thread/link-preview-card.tsx
# v31: that picture is the page's own banner across the top of a card wide as the message column,
# not a 96pt square cutting a 1280x640 banner down to its middle (`IMG_2989`).
grep -q 'aspectRatio: 2' apps/mobile/components/thread/link-preview-card.tsx
grep -q 'maxWidth: 310' apps/mobile/components/thread/link-preview-card.tsx
grep -q 'testID="link-card-cover"' apps/mobile/components/thread/link-preview-card.tsx
if grep -nE 'width: 96|height: 96' apps/mobile/components/thread/link-preview-card.tsx; then
  echo "::error::the link card squares the page's banner off again"
  exit 1
fi
# v31: the launch carries English and Simplified Chinese; the other fourteen catalogs are fetched
# the first time one is chosen, not built as objects before the first frame (`IMG_2997`).
grep -q 'import { messages as en } from "@rakazo/i18n/locales/en/messages.po"' apps/mobile/lib/i18n.ts
grep -q 'import { messages as zhCN } from "@rakazo/i18n/locales/zh-CN/messages.po"' apps/mobile/lib/i18n.ts
grep -q 'const lazyCatalogs' apps/mobile/lib/i18n.ts
if grep -nE '^import \{ messages as (de|es|fr|he|hi|ja|ko|nl|pl|ptBR|ru|tr|zhTW) \}' \
  apps/mobile/lib/i18n.ts; then
  echo "::error::i18n.ts imports a catalog the launch does not need again"
  exit 1
fi
# v31: the native splash waits for the server, the appearance and the language only. A preference
# that merely shapes a screen already up (streaming, the text weight, images, the inbox width) must
# not be back inside the awaited list, and the launch's Keychain reads are one round trip, not four.
grep -q 'const firstFrame = Promise.all' apps/mobile/app/_layout.tsx
if sed -n '/const firstFrame = Promise.all(/,/setReady(true)/p' apps/mobile/app/_layout.tsx \
  | grep -nE '"(streaming|font-weight|images|inbox)"'; then
  echo "::error::the native splash waits on preferences the first frame is not drawn with"
  exit 1
fi
if sed -n '/const firstFrame = Promise.all(/,/setReady(true)/p' apps/mobile/app/_layout.tsx \
  | grep -n "loadInboxWidth()}"; then
  echo "::error::a detail preference is awaited before the first frame again"
  exit 1
fi
grep -q 'trackMobileStartup("inbox", loadInboxWidth())' apps/mobile/app/_layout.tsx
grep -q 'applyStoredServerHeaders(apiBase, headers)' apps/mobile/lib/api-server.ts
grep -q 'readStoredServerHeaders(),' apps/mobile/lib/api-server.ts
if grep -n 'await loadServerHeaders(' apps/mobile/lib/api-server.ts; then
  echo "::error::the launch reads its Keychain entries one after another again"
  exit 1
fi
grep -q 'applyStoredServerHeaders' apps/mobile/lib/server-headers.ts
test -f apps/mobile/modules/message-image-actions/ios/MessageImageActionsModule.swift
test -f apps/mobile/modules/message-image-actions/ios/MessageImageActions.podspec
test -f apps/mobile/modules/message-image-actions/expo-module.config.json
grep -q 'stackOwnsLongPress' apps/mobile/components/thread/message-row.tsx
grep -q 'visibleThreadBlocks' apps/mobile/components/thread/message-bubble.tsx
grep -q 'NSPhotoLibraryAddUsageDescription' apps/mobile/app.json

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

# expo.name must remain Rakazo so prebuild still writes this folder and scheme.
# The home-screen label is CFBundleDisplayName (Bot), not the project name.
if [ -d ios/Bot ] && [ ! -d ios/Rakazo ]; then
  echo "::error::prebuild created ios/Bot; expo.name must stay Rakazo so the Xcode project stays Rakazo"
  exit 1
fi
test -f ios/Rakazo/Info.plist || { echo "::error::prebuild did not write ios/Rakazo/Info.plist"; exit 1; }

# The typeface has to be in the built bundle, not merely in the source.
/usr/libexec/PlistBuddy -c 'Print :UIAppFonts' ios/Rakazo/Info.plist | tee /dev/stderr | grep -q 'XVF-Regular.ttf'

cd ios
pod install --repo-update || pod install
grep -q 'MessageImageActions' Podfile.lock ||
  { echo "::error::message-image-actions was not autolinked"; exit 1; }
grep -q 'PhotoPicker' Podfile.lock ||
  { echo "::error::photo-picker was not autolinked"; exit 1; }
# A simulator-only check needs the prepared project, not the device build.
if [ -n "${PREPARE_ONLY:-}" ]; then exit 0; fi
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
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$IPA_PLIST/Payload/Rakazo.app/Info.plist" | grep -qx Bot
/usr/libexec/PlistBuddy -c 'Print :NSPhotoLibraryAddUsageDescription' "$IPA_PLIST/Payload/Rakazo.app/Info.plist" | grep -q 'photo library'
unzip -l Rakazo-unsigned.ipa | grep -E 'XVF-Regular.ttf|ping_4_chime_a|RakazoDocumentScanner'

# The icon that ships is the one in the source tree, byte for byte, and no ghost PNG rides along.
for icon in monochrome-icon; do
  shipped="$(unzip -p Rakazo-unsigned.ipa "Payload/Rakazo.app/assets/assets/$icon.png" | shasum -a 256 | cut -d' ' -f1)"
  source_sum="$(shasum -a 256 "src/apps/mobile/assets/$icon.png" | cut -d' ' -f1)"
  [ "$shipped" = "$source_sum" ] || { echo "::error::$icon in the package is not the Bot mark"; exit 1; }
done
