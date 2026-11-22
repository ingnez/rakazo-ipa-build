#!/usr/bin/env bash
# v36 gates: the 136 pt hero, the finished art carried inside the app, no blank avatar while a
# picture arrives, the self-hosted OTA channel, and the web page drawing the same hero.
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

# --- 1. The home hero is 136 pt, top to bottom -----------------------------------------------
want "export const LUMEN_HERO_PT = 136;" "$CORE" "the hero's own size is not 136 pt"
want "heroSizePt" "$CORE" "the manifest cannot fix the hero's size"
wantF 'bot.heroSizePt ?? (chief ? LUMEN_HERO_PT : LUMEN_LIST_PT)' "$CORE" \
  "the hero ignores the manifest's own size"
want "export const LUMEN_CHIEF_LIST_PT = 96;" "$CORE" "the chief's list row lost its 96 pt size"
want "export const HERO_AVATAR_SIZE = 136;" "$APPS/lib/avatar-badges.ts" \
  "the home hero's footprint is not 136 pt"
wantF 'size={HERO_AVATAR_SIZE}' "$APPS/components/home-hero-body.tsx" \
  "the home screen does not draw the hero at its footprint"
wantF 'width: HERO_AVATAR_SIZE,' "$APPS/components/home-hero-body.tsx" \
  "the hero's wrap is not the avatar's footprint"
wantF 'paddingTop: 24,' "$APPS/components/home-hero-body.tsx" \
  "the hero has no room above it, so the 136 pt drawing is cropped"
wantF 'overflow: "visible"' "$APPS/components/home-hero-body.tsx" \
  "the hero's wrap clips the avatar"

# --- 2. The finished art is carried in the app -------------------------------------------------
test -f "$ART/manifest.json" || fail "the app does not carry an avatar manifest"
node - "$ART/manifest.json" <<'JS' || fail "the carried manifest is not the finished art"
const fs = require("node:fs");
const m = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (m.version !== "20261122-transparent") throw new Error(`manifest version ${m.version}`);
if (m.bots.length !== 11) throw new Error(`${m.bots.length} bots, expected 11`);
const chief = m.bots.find((bot) => bot.role === "chief");
if (!chief || chief.heroSizePt !== 136) throw new Error("the chief's hero size is not 136");
if (m.bots.some((bot) => bot.role !== "chief" && bot.heroSizePt !== 56)) {
  throw new Error("a member's hero size is not 56");
}
let pictures = 0;
for (const bot of m.bots) {
  for (const theme of Object.values(bot.themes)) {
    for (const path of Object.values(theme)) {
      if (!fs.existsSync(`apps/mobile/assets/lumen-avatars/${path}`)) throw new Error(`missing ${path}`);
      pictures += 1;
    }
  }
}
if (pictures !== 66) throw new Error(`${pictures} pictures named, expected 66`);
JS
[ "$(find "$ART" -type f ! -name manifest.json | wc -l)" = "66" ] \
  || fail "the app does not carry exactly the 66 finished pictures"
# The art is what makes the avatar instant; a build that quietly lost most of it must not ship.
size_kb=$(du -sk "$ART" | cut -f1)
[ "$size_kb" -gt 30000 ] || fail "the carried art is only ${size_kb} KB: the pictures are missing"
[ "$size_kb" -lt 60000 ] || fail "the carried art is ${size_kb} KB: it was not compressed to ~35 MB"

# One literal require per picture: Metro only bundles a picture the source names.
test -f "$BUILTIN" || fail "the app has no table of the pictures it carries"
[ "$(grep -c 'require("../../assets/lumen-avatars/' "$BUILTIN")" = "66" ] \
  || fail "the picture table does not name all 66 pictures"
want "LUMEN_BUILTIN_MANIFEST" "$BUILTIN" "the carried manifest is not parsed"
want "lumenBuiltinAssetFor" "$BUILTIN" "a manifest picture cannot be resolved to the bundle"
want "lumenBuiltinVersion" "$BUILTIN" "a manifest naming the carried art is not recognised"

# The store starts from the carried art, and keeps it while the server names the same version.
want "let manifest: LumenManifest | null = LUMEN_BUILTIN_MANIFEST;" \
  "$APPS/lib/lumen/lumen-manifest-store.ts" "the first frame does not start from the carried art"
want "lumenBuiltinVersion(parsed.version)" "$APPS/lib/lumen/lumen-manifest-store.ts" \
  "a server manifest naming the carried art is not recognised"
want "/lumen-avatars/manifest.json" "$CORE" "the server's own manifest path changed"
want "subscribeApiBase" "$APPS/lib/lumen/lumen-manifest-store.ts" \
  "the store no longer re-reads the manifest when the server changes"

# The avatar draws the carried picture, and keeps the server's newer art ahead of it.
want "lumenAvatarChoice" "$APPS/components/bot-avatar.tsx" "the avatar does not choose from the manifest"
want "local !== null ? candidate.local" "$APPS/components/bot-avatar.tsx" \
  "the avatar never draws a picture from the bundle"
want "lumenAvatarChoice" "$SOURCE" "the avatar's picture choice is missing"
wantF 'lumenManifestPicture(LUMEN_BUILTIN_MANIFEST, input)' "$SOURCE" \
  "a server manifest naming other art has no carried picture behind it"

# --- 3. A picture that is arriving is never a blank square -------------------------------------
wantF 'key={candidate.uri}' "$APPS/components/bot-avatar.tsx" \
  "the picture's view is not remounted when its address changes"
want "onLoad" "$APPS/components/bot-avatar.tsx" "the avatar never learns its picture has arrived"
wantF 'motion="still"' "$APPS/components/bot-avatar.tsx" \
  "nothing is drawn under a picture that has not arrived"
want "underlay" "$APPS/components/bot-avatar.tsx" "the underlay is gone"
want "onError" "$APPS/components/bot-avatar.tsx" "a picture that fails to load does not fall through"
want "LumenBotAvatar" "$APPS/components/bot-avatar.tsx" "the drawn body is gone"

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
