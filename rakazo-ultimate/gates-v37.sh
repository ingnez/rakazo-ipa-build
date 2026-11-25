#!/usr/bin/env bash
# v37 gates: OpenMinis avatars drawn in the client, no Lumen picture pack, no manifest fetch,
# photos still work, the chief has no extra star, and the body uses no Reanimated worklets.
set -euo pipefail

fail() { echo "::error::$1"; exit 1; }
want() { grep -q -- "$1" "$2" || fail "$3"; }
wantF() { grep -qF -- "$1" "$2" || fail "$3"; }
gone() { grep -Rqs -- "$1" "$2" && fail "$3" || true; }
goneF() { grep -RqsF -- "$1" "$2" && fail "$3" || true; }

APPS=apps/mobile
CORE=packages/core/src/openminis-avatar.ts
BODY="$APPS/components/openminis-bot-avatar.tsx"
AVATAR="$APPS/components/bot-avatar.tsx"
STORE="$APPS/lib/lumen/lumen-manifest-store.ts"
BUILTIN="$APPS/lib/lumen/lumen-builtin-avatars.ts"

test -f "$CORE" || fail "the OpenMinis drawing module is missing from @rakazo/core"
test -f packages/core/src/openminis-avatar.test.ts || fail "the OpenMinis drawing has no tests"
wantF 'export * from "./openminis-avatar.js";' packages/core/src/index.ts "core does not export the OpenMinis drawing"
want "OPENMINIS_ROLE_ROWS" "$CORE" "the twelve-role mapping is missing"
want "shape: 0, color: 10" "$CORE" "the chief is not the indigo circle"
want "suppressMainStar" "$CORE" "the chief's no-extra-star rule is missing"
want "openminisBodyPath" "$CORE" "the body paths are missing"
want "openminisSvg" "$CORE" "the SVG drawing is missing"
want "openminisBlinkWait" "$CORE" "the blink timing is missing"
want "OPENMINIS_DARK_INK" "$CORE" "dark-mode graphite black is missing"
want "OPENMINIS_CHIEF_LOOK" "$CORE" "the chief official face is missing"
want "OPENMINIS_CHIEF_BODY_DARK" "$CORE" "the chief dark-mode white body is missing"
want 'showMainStar = main && !spec.suppressMainStar' "$AVATAR" "the overlay star is no longer gated on suppressMainStar"

test -f "$BODY" || fail "the OpenMinis avatar component is missing"
want "openminisSvg" "$BODY" "the component does not use the shared drawing"
want "useLumenReducedMotion" "$BODY" "the component ignores Reduce Motion"
want "openminisBlinkWait" "$BODY" "the component does not blink"
gone "useAnimatedProps" "$BODY" "the avatar body animates SVG props on the UI thread"
gone "createAnimatedComponent" "$BODY" "the avatar body wraps SVG in an animated component"

want "OpenMinisBotAvatar" "$AVATAR" "BotAvatar does not draw the OpenMinis body"
want "data:image/" "$AVATAR" "a photo a bot was given no longer draws"
want "suppressMainStar" "$AVATAR" "the chief could get an extra star"
gone "lumenAvatarChoice" "$AVATAR" "BotAvatar still chooses a Lumen picture"
gone "LumenBotAvatar" "$AVATAR" "BotAvatar still draws the Lumen body"
gone "ManifestPicture" "$AVATAR" "BotAvatar still loads a manifest picture"

# The store must not fetch a picture manifest, and the picture table must not require 66 files.
gone "fetch(" "$STORE" "the avatar store still fetches a manifest"
gone "subscribeApiBase" "$STORE" "the avatar store still refetches when the server changes"
gone 'require("../../assets/lumen-avatars/' "$BUILTIN" "the picture table still requires Lumen art"
if [ -d "$APPS/assets/lumen-avatars" ]; then
  fail "apps/mobile/assets/lumen-avatars is still in the tree"
fi

echo "v37 gates passed"
