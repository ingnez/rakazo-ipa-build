#!/usr/bin/env bash
# v34 gates: the Lumen avatar, the new app icon, and the thread-wide image gallery.
# Run from the patched source tree root (build.sh calls it right after `git apply`), or on a
# copy of that tree to prove the checks fail when the work is missing.
set -euo pipefail

fail() { echo "::error::$1"; exit 1; }
want() { grep -q -- "$1" "$2" || fail "$3"; }
gone() { grep -Rqs -- "$1" "$2" && fail "$3" || true; }

APPS=apps/mobile

# --- 1. The Lumen engine and its 247 emblems ------------------------------------------------
test -f "$APPS/lib/lumen/lumen-avatar.ts" || fail "the Lumen engine is missing"
test -f "$APPS/lib/lumen/lumen-emblems.ts" || fail "the emblem library is missing"
test -f "$APPS/components/lumen-bot-avatar.tsx" || fail "the Lumen renderer is missing"
want "export function lumenFrame" "$APPS/lib/lumen/lumen-avatar.ts" "lumenFrame is missing"
want "export function lumenLookFor" "$APPS/lib/lumen/lumen-avatar.ts" "lumenLookFor is missing"
want "export function parseLumenLook" "$APPS/lib/lumen/lumen-avatar.ts" "parseLumenLook is missing"
want "export function threadImageGallery" "$APPS/lib/image-gallery-session.ts" "the thread gallery is missing"

COUNT="$(python3 - <<'PY'
import re, sys
src = open("apps/mobile/lib/lumen/lumen-emblems.ts", encoding="utf-8").read()
print(len(re.findall(r'\bid: "e\d{3}"', src)))
PY
)"
[ "$COUNT" = "247" ] || fail "the emblem library holds $COUNT emblems, not 247"

# --- 2. Every bot is drawn by it, and the retired bodies are gone ---------------------------
test -f "$APPS/components/bot-avatar.tsx" || fail "BotAvatar is missing"
want "LumenBotAvatar" "$APPS/components/bot-avatar.tsx" "BotAvatar no longer draws the Lumen body"
want 'lumenLookFor' "$APPS/components/bot-avatar.tsx" "BotAvatar does not resolve a Lumen look"
for retired in components/mochi-bot-avatar.tsx components/logo-avatar.tsx lib/logo-avatar-clock.ts; do
  [ -e "$APPS/$retired" ] && fail "the retired avatar renderer $retired is still in the tree"
done
if grep -Rqs -E '\bMochiBotAvatar\b|\bLogoAvatar\b' "$APPS/app" "$APPS/components" "$APPS/lib" \
  --include='*.ts' --include='*.tsx'; then
  fail "app code still draws a retired avatar"
fi
gone "mochiBodyPath" "$APPS/components/bot-look-picker.tsx" "the look picker still draws the old bodies"

# --- 3. Creating and editing a bot previews the new avatar ---------------------------------
want "lumenLookValue" "$APPS/components/bot-look-picker.tsx" "the picker does not store a Lumen look"
want "LUMEN_EMBLEMS" "$APPS/components/bot-look-picker.tsx" "the picker does not offer the emblem library"
want "LUMEN_PALETTE" "$APPS/components/bot-look-picker.tsx" "the picker does not offer the palette"
[ "$(grep -c 'name={name}' "$APPS/app/new-bot.tsx")" -ge 2 ] ||
  fail "the new-bot preview and its emblem picker do not both follow the typed name"
want "name={name}" "$APPS/app/bot-settings.tsx" "the appearance sheet does not follow the bot's name"
want "BotLookPicker" "$APPS/app/new-bot.tsx" "the new-bot sheet lost its look picker"
want "lumenLookFor" "$APPS/components/group-seats.tsx" "group seats still draw the old bodies"
want "LumenBotAvatar" "$APPS/components/avatar-review-gallery.tsx" "the review gallery does not show Lumen"

# --- 4. The icon, the splash and the notification mark are the new ones --------------------
python3 - <<'PY'
import json, sys
cfg = json.load(open("apps/mobile/app.json", encoding="utf-8"))["expo"]
if cfg.get("icon") != "./assets/bot-icon.png":
    print("::error::the app icon is not the new PNG")
    sys.exit(1)
if cfg.get("ios", {}).get("icon") != "./assets/bot-icon.png":
    print("::error::the iOS icon is not the new PNG")
    sys.exit(1)
splash = next((p for p in cfg.get("plugins", []) if isinstance(p, list) and p[0] == "expo-splash-screen"), None)
if not splash or splash[1].get("backgroundColor") != "#040C17":
    print("::error::the splash background is not the new night navy")
    sys.exit(1)
if splash[1].get("dark", {}).get("backgroundColor") != "#040C17":
    print("::error::the dark splash background is not the new night navy")
    sys.exit(1)
PY
[ -e "$APPS/assets/Bot.icon" ] && fail "the retired Icon Composer package is still in the tree"
[ -e "$APPS/assets/app-icon" ] && fail "the retired icon sources are still in the tree"
for asset in bot-icon splash-icon splash-icon-dark notification-icon monochrome-icon adaptive-icon icon-background favicon; do
  test -f "$APPS/assets/$asset.png" || fail "assets/$asset.png is missing"
done
python3 - <<'PY'
import hashlib, struct, sys

def png_size(path):
    with open(path, "rb") as handle:
        head = handle.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])

def sha(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()

app = "apps/mobile/assets"
size = png_size(f"{app}/bot-icon.png")
if size != (1024, 1024):
    print(f"::error::bot-icon.png is {size}, not 1024x1024")
    sys.exit(1)
splash = png_size(f"{app}/splash-icon.png")
if splash != (1024, 1024):
    print(f"::error::splash-icon.png is {splash}, not 1024x1024")
    sys.exit(1)
for name in ("bot-icon.png", "splash-icon.png", "splash-icon-dark.png"):
    # The splash is the icon itself, so the launch mark and the home-screen mark are one drawing.
    if sha(f"{app}/{name}") != sha(f"{app}/bot-icon.png"):
        print(f"::error::{name} is not the app icon")
        sys.exit(1)
PY

# --- 5. The image viewer: the whole thread, one gallery, a draggable filmstrip --------------
want "threadImageGallery(visibleMessages" "$APPS/components/thread/thread-screen.tsx" \
  "the viewer does not open the thread's whole gallery"
want "ImageThumbnailStrip" "$APPS/components/image-artifact-viewer.tsx" "the filmstrip is missing"
want "scheduleOnRN(hapticSelection)" "$APPS/components/image-artifact-viewer.tsx" \
  "dragging the filmstrip has no tick"
want "currentTarget.name" "$APPS/components/image-artifact-viewer.tsx" \
  "the picture on screen has no caption"
want "MessageImageStack" "$APPS/components/thread/message-bubble.tsx" \
  "a bot's pictures no longer stack"

echo "v34 gates passed"
