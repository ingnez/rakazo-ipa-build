#!/usr/bin/env python3
"""Build gate: every message in the Chinese catalogs must have a translation, and no UI text may be
hardcoded English. Prints each offender and exits 1. Usage: check-i18n.py <src-tree>"""
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
import polmissing
src = sys.argv[1]
bad = 0
for loc in ("zh-CN", "zh-TW"):
    _, _, res = polmissing.missing(os.path.join(src, "packages/i18n/locales", loc, "messages.po"))
    for i, idv, plural, refs in res:
        print(f"::error::{loc} has no translation for: {idv[:120]}  ({refs[0] if refs else '?'})")
    bad += len(res)
r = subprocess.run(["node", os.path.join(os.path.dirname(__file__), "scan-english.cjs"), src], capture_output=True, text=True)
if r.returncode:
    for l in r.stdout.splitlines(): print("::error::hardcoded English UI text: " + l)
    bad += len(r.stdout.splitlines())
if bad:
    print(f"i18n gate FAILED: {bad} problem(s). Translate via i18n/translations.json (zh-CN and zh-TW) or wrap the text in t``.")
    sys.exit(1)
print("i18n gate ok: zh-CN and zh-TW complete, no hardcoded English UI text")
