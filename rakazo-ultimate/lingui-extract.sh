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
echo "lingui catalogs complete"
