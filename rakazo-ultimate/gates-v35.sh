#!/usr/bin/env bash
# v35 gates: the avatar manifest reader, the viewer's JS-thread gestures, per-picture cards,
# the folder lead, and the web page reading the same manifest.
# Run from the patched source tree root (build.sh calls it right after `git apply`), or on a copy
# of that tree to prove the checks fail when the work is missing.
set -euo pipefail

fail() { echo "::error::$1"; exit 1; }
want() { grep -q -- "$1" "$2" || fail "$3"; }
wantF() { grep -qF -- "$1" "$2" || fail "$3"; }
gone() { grep -Rqs -- "$1" "$2" && fail "$3" || true; }
goneF() { grep -RqsF -- "$1" "$2" && fail "$3" || true; }

APPS=apps/mobile
CORE=packages/core/src/lumen-manifest.ts
WEB=packages/ui-web/src/lumen-manifest.ts

# --- 1. The manifest reader: one pure module the phone and the web both use ------------------
test -f "$CORE" || fail "the manifest rules are missing from @rakazo/core"
want "export function parseLumenManifest" "$CORE" "the manifest is not parsed"
want "export function lumenManifestPicture" "$CORE" "the manifest does not pick a picture"
want "export function lumenManifestBot" "$CORE" "the manifest does not match a bot"
want "export function lumenManifestUrl" "$CORE" "the manifest address is not built"
want "listVariant" "$CORE" "the manifest ignores a row's list variant"
want "listSizePt" "$CORE" "the manifest ignores a row's own list size"
wantF 'other?.[kind]' "$CORE" "a missing picture does not fall through the other theme"
want "schemaVersion" "$CORE" "the manifest does not check its schema version"
want "url.protocol" "$CORE" "the manifest would load a path that is not a web address"
wantF 'export * from "./lumen-manifest.js";' packages/core/src/index.ts "core does not export the manifest rules"

test -f "$APPS/lib/lumen/lumen-manifest.ts" || fail "the phone's manifest module is missing"
want "@rakazo/core" "$APPS/lib/lumen/lumen-manifest.ts" "the phone reimplements the manifest rules"
test -f "$APPS/lib/lumen/lumen-manifest-store.ts" || fail "the manifest store is missing"
want "/lumen-avatars/manifest.json" "$CORE" "the manifest path changed"
want "lumen-manifest.json" "$APPS/lib/lumen/lumen-manifest-store.ts" "the store keeps no on-disk copy"
want "reduceMotionChanged" "$APPS/lib/lumen/lumen-manifest-store.ts" "the store ignores Reduce Motion"
want "subscribeApiBase" "$APPS/lib/lumen/lumen-manifest-store.ts" "the store ignores a server change"
test -f "$APPS/lib/lumen/lumen-manifest.test.ts" || fail "the manifest has no tests"

# --- 2. Every avatar draws from it, and a broken picture falls back --------------------------
want "lumenManifestPicture" "$APPS/components/bot-avatar.tsx" "BotAvatar ignores the manifest"
want "useLumenReducedMotion" "$APPS/components/bot-avatar.tsx" "BotAvatar ignores Reduce Motion"
want "onError" "$APPS/components/bot-avatar.tsx" "a picture that fails to load does not fall back"
want "LumenBotAvatar" "$APPS/components/bot-avatar.tsx" "the drawn body is gone (nothing to fall back to)"
want "drawMainStar" "$APPS/components/bot-avatar.tsx" "the chief's baked star would be drawn twice"
# A bot with no name and no id is a placeholder: it must wear a mark, never a question mark.
want 'LUMEN_EMBLEM_BY_ID.get("e012")' "$APPS/lib/lumen/lumen-avatar.ts" "the placeholder has no default emblem"
goneF 'look.initial ?? "?"' "$APPS/components/lumen-bot-avatar.tsx" "the placeholder still draws a question mark"

# --- 3. The avatar adds no Reanimated worklets to the body ----------------------------------
# v34's crash came from SVG props animated on the UI thread; the body draws on the JS clock.
gone "useAnimatedProps" "$APPS/components/lumen-bot-avatar.tsx" "the avatar body animates SVG props on the UI thread"
gone "createAnimatedComponent" "$APPS/components/lumen-bot-avatar.tsx" "the avatar body wraps SVG in an animated component"

# --- 4. The viewer's swipe runs on the JS thread, and the strip fills around the current one --
V="$APPS/components/image-artifact-viewer.tsx"
want "runOnJS(true)" "$V" "the viewer's swipe still runs a JS function on the UI thread"
want "galleryNeighbourOrder" "$V" "the strip does not fetch the neighbours first"
want "ImageViewerIndex.clamp(startIndex" "$V" "the viewer lost its index guard"
want "export function galleryNeighbourOrder" "$APPS/lib/image-stack-layout.ts" "the neighbour order is missing"

# --- 5. A message's pictures load one by one and show as they land --------------------------
S="$APPS/components/image-card-stack.tsx"
gone "Promise.all" "$S" "the cards still wait for every picture"
want "setUris((current)" "$S" "the cards are not filled in one at a time"
want "ActivityIndicator" "$S" "a picture that is still loading shows no spinner"

# --- 6. The folder lead: the field, the sheet, the settings page, and the badge --------------
want "leadSectionId" packages/contracts/src/domain.ts "the bot has no folder-lead field"
want "leadSectionId" "$APPS/components/bot-organize-modal.tsx" "the long-press sheet cannot make a lead"
want "小组长" "$APPS/components/bot-organize-modal.tsx" "the sheet's lead action is unlabelled"
want "leadSectionId" "$APPS/app/bot-settings.tsx" "the settings page cannot make a lead"
want "向主 Bot" "$APPS/app/bot-settings.tsx" "the settings page does not say what a lead may not do"
want 'kind === "lead"' "$APPS/components/bot-avatar.tsx" "the avatar draws no lead badge"
want "lead" "$APPS/lib/avatar-badges.ts" "the badge planner does not know a lead"
want "leadSectionId" "$APPS/components/inbox/inbox-rows.tsx" "the inbox rows never show the lead badge"

# --- 7. The web reads the same manifest and shows the same lead ------------------------------
test -f "$WEB" || fail "the web has no manifest reader"
want "lumenManifestPicture" "$WEB" "the web does not pick from the manifest"
want "sessionStorage" "$WEB" "the web caches no copy"
want "prefers-reduced-motion" "$WEB" "the web ignores Reduce Motion"
want "lumenManifestPictureFor" packages/ui-web/src/bot-avatar.tsx "the web avatar ignores the manifest"
want "LeadFlag" packages/ui-web/src/bot-avatar.tsx "the web avatar draws no lead badge"
want "leadSectionId" apps/web/src/pages/shell/bot-panel.tsx "the web settings cannot make a lead"
want "小组长" apps/web/src/pages/shell/bot-settings-sections.tsx "the web settings hide the lead row"

echo "v35 gates passed"
