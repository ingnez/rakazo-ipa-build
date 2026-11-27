#!/usr/bin/env python3
"""App fixes + stable testIDs for the Maestro flows (code-only, idempotent, needle-checked).

1. REAL APP BUG (run 46011113796): bot-settings renders the Advanced section while `bot` is still
   null (the screen's `bots/get` answers after the tap) and the 小组长 block dereferences
   `bot.sectionId`, so the whole screen falls into the error boundary ("Cannot read property
   'sectionId' of null"), and every later deep link shows the same boundary. Guard with `bot?.`.
2. testIDs (accessibilityIdentifier, invisible, no behaviour change) so flows stop depending on
   label text that accessible parents rewrite (file card, Advanced, Routines, Delete account, ...).
"""
import pathlib
import sys

src = pathlib.Path(sys.argv[1]) / "apps/mobile"
EDITS = {
    "app/bot-settings.tsx": [
        ("{bot.sectionId ? (", "{bot?.sectionId ? ("),
        ("value={leadSectionId === bot.sectionId}", "value={leadSectionId === bot?.sectionId}"),
        ("leadSave.update(value ? bot.sectionId : null);", "leadSave.update(value ? (bot?.sectionId ?? null) : null);"),
        ('          accessibilityLabel={t`Advanced`}\n',
         '          accessibilityLabel={t`Advanced`}\n          testID="bot-settings-advanced"\n'),
        ('              accessibilityLabel={t`Edit avatar`}\n',
         '              accessibilityLabel={t`Edit avatar`}\n              testID="bot-settings-avatar"\n'),
    ],
    "components/thread/file-attachment-card.tsx": [
        ('        accessibilityLabel={t`${ph({ name })}: ${ph({ detail })}`}\n',
         '        accessibilityLabel={t`${ph({ name })}: ${ph({ detail })}`}\n        testID="file-attachment-card"\n'),
    ],
    "app/bot-profile.tsx": [
        ('          key="routines"\n', '          key="routines"\n          testID="bot-profile-routines"\n'),
    ],
    "app/(settings)/profile.tsx": [
        ('            title={t`Delete account`}\n', '            testID="profile-delete-account"\n            title={t`Delete account`}\n'),
    ],
    "app/(settings)/general.tsx": [
        ('            accessibilityLabel={t`Language`}\n            accessibilityValue',
         '            accessibilityLabel={t`Language`}\n            testID="settings-language-row"\n            accessibilityValue'),
    ],
}
for rel, pairs in EDITS.items():
    path = src / rel
    text = path.read_text()
    for old, new in pairs:
        if new in text:
            continue
        if text.count(old) < 1:
            raise SystemExit(f"{rel}: needle missing: {old.strip()[:60]}")
        text = text.replace(old, new, 1) if "bot-settings.tsx" not in rel or "sectionId" not in old else text.replace(old, new)
    path.write_text(text)
    print("patched", rel)
