#!/usr/bin/env bash
# Put every UI string of the tree into the Lingui catalogs before any JS bundle is made (ipa build,
# e2e embed, OTA `expo export`). The fork added ~160 strings (file card "{name}: {detail}", usage
# rows, link previews, routine events, ...) without extracting them. A message that is not in the
# compiled catalog comes back raw, so people saw literal "{name}" instead of the value (run
# 46025550372). Extract WITHOUT --clean (nothing is removed); other locales fall back to the source
# text, with placeholders compiled. Usage: lingui-extract.sh <src-tree>
set -euo pipefail
SRC="${1:?src tree}"
cd "$SRC"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
(pnpm exec lingui extract || npx --no-install lingui extract) 2>&1 | tail -22
EN="packages/i18n/locales/en/messages.po"
for msg in '{name}: {detail}' 'Continue in {site}' 'Messages can be up to {limit} characters.' '{calls} 次调用 · 思考 {thinking} · 缓存 {cache}'; do
  grep -qF "msgid \"$msg\"" "$EN" || { echo "::error::message not catalogued after extract: $msg"; exit 1; }
done
# Extract adds every new message with an EMPTY translation, and the app then shows the English source
# (the new-bot sheet's "Colour" / "Emblem" shipped that way). Fill what i18n/translations.json knows,
# then FAIL the build on any message still empty in zh-CN / zh-TW and on any hardcoded English UI text.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$HERE/i18n/fill-zh.py" "$PWD"
python3 "$HERE/i18n/check-i18n.py" "$PWD"
echo "lingui catalogs complete"
