#!/usr/bin/env bash
# v36 gates: the 96 pt home hero, the self-hosted OTA channel, and the web page drawing the (web) hero.
# Bundled Lumen pictures were retired in v37 (gates-v37.sh).
# Run from the patched source tree root (build.sh calls it right after `git apply` and the art
# copy), or on a copy of that tree to prove each check fails when the work is missing.
set -euo pipefail

fail() { echo "::error::$1"; exit 1; }
want() { grep -q -- "$1" "$2" || fail "$3"; }
wantF() { grep -qF -- "$1" "$2" || fail "$3"; }
gone() { grep -Rqs -- "$1" "$2" && fail "$3" || true; }
goneF() { grep -RqsF -- "$1" "$2" && fail "$3" || true; }

APPS=apps/mobile
CORE=packages/core/src/lumen-manifest.ts
ART="$APPS/assets/lumen-avatars"
BUILTIN="$APPS/lib/lumen/lumen-builtin-avatars.ts"
SOURCE="$APPS/lib/lumen/lumen-avatar-source.ts"

# --- 1. The home hero is 96 pt, top to bottom ------------------------------------------------
want "export const LUMEN_HERO_PT = 136;" "$CORE" "the hero's own size is not 136 pt"
want "heroSizePt" "$CORE" "the manifest cannot fix the hero's size"
wantF 'bot.heroSizePt ?? (chief ? LUMEN_HERO_PT : LUMEN_LIST_PT)' "$CORE" \
  "the hero ignores the manifest's own size"
want "export const LUMEN_CHIEF_LIST_PT = 96;" "$CORE" "the chief's list row lost its 96 pt size"
want "export const HERO_AVATAR_SIZE = 96;" "$APPS/lib/avatar-badges.ts" \
  "the home hero's footprint is not 96 pt"
wantF 'size={HERO_AVATAR_SIZE}' "$APPS/components/home-hero-body.tsx" \
  "the home screen does not draw the hero at its footprint"
wantF 'width: HERO_AVATAR_SIZE,' "$APPS/components/home-hero-body.tsx" \
  "the hero's wrap is not the avatar's footprint"
wantF 'paddingTop: 17,' "$APPS/components/home-hero-body.tsx" \
  "the hero has no room above it, so the 96 pt drawing is cropped"
wantF 'overflow: "visible"' "$APPS/components/home-hero-body.tsx" \
  "the hero's wrap clips the avatar"

# --- 2–3. (retired) bundled Lumen pictures and the picture underlay -------------------------
# Avatars are drawn in the client as of v37; see gates-v37.sh.

# --- 4. The OTA channel ------------------------------------------------------------------------
node - <<'JS' || fail "the app does not carry a self-hosted update channel"
const fs = require("node:fs");
const expo = JSON.parse(fs.readFileSync("apps/mobile/app.json", "utf8")).expo;
const updates = expo.updates ?? {};
if (updates.enabled !== true) throw new Error("updates are disabled");
if (updates.url !== "https://rakazo.163ll.com/ota/manifest") throw new Error(`updates.url ${updates.url}`);
if (updates.checkAutomatically !== "ON_LOAD") throw new Error(`checkAutomatically ${updates.checkAutomatically}`);
if (updates.fallbackToCacheTimeout !== 0) throw new Error("the launch can wait on an update");
if (!expo.runtimeVersion) throw new Error("no runtimeVersion");
JS
want "expo-updates" "$APPS/lib/client-update.ts" "the app has no update client"
want "Updates.reloadAsync" "$APPS/lib/client-update.ts" "a required update cannot be applied"
test -f "$APPS/package.json" && grep -q '"expo-updates"' "$APPS/package.json" \
  || fail "expo-updates is not a dependency"

# --- 5. The web draws the same hero ------------------------------------------------------------
want "lumenManifestPictureFor" packages/ui-web/src/bot-avatar.tsx "the web avatar ignores the manifest"
want "surface" packages/ui-web/src/bot-avatar.tsx "the web avatar has no surface rule"
wantF 'surface === "home-hero" && picture.size' packages/ui-web/src/bot-avatar.tsx \
  "the web hero ignores the size the art fixes"
wantF 'size: picture.size' packages/ui-web/src/lumen-manifest.ts \
  "the web never hears the size the art fixes"
wantF "<ManifestPicture src={picture.uri}" packages/ui-web/src/bot-avatar.tsx \
  "the web swaps its picture with nothing underneath it"
wantF 'onLoad={() => {' packages/ui-web/src/bot-avatar.tsx \
  "the web does not keep the last picture until the next has decoded"
wantF 'size={LUMEN_HERO_PT}' apps/web/src/pages/shell/bot-panel.tsx \
  "the web settings page does not lead with the 136 pt hero"
wantF 'surface="home-hero"' apps/web/src/pages/shell/bot-panel.tsx \
  "the web settings page does not draw the hero surface"
want "surface" apps/web/src/pages/shell/avatar-studio-popover.tsx \
  "the web's avatar editor cannot be told which surface it is on"
want "leadSectionId" apps/web/src/pages/shell/bot-panel.tsx "the web settings lost the folder lead"
want "小组长" apps/web/src/pages/shell/bot-settings-sections.tsx "the web settings hide the lead row"

echo "v36 gates passed"
