#!/usr/bin/env python3
"""Run locally (needs opencc) after filling the catalogs once: writes translations.json, the table
fill-zh.py applies in CI (no opencc there). Usage: gen-translations.py <src-tree>"""
import json, os, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
import polmissing
src = sys.argv[1]
out = {}
for loc in ("zh-CN", "zh-TW"):
    po = os.path.join(src, "packages/i18n/locales", loc, "messages.po")
    head = subprocess.run(["git", "-C", src, "show", f"HEAD:packages/i18n/locales/{loc}/messages.po"], capture_output=True, text=True).stdout
    with tempfile.NamedTemporaryFile("w", suffix=".po", delete=False) as f: f.write(head)
    _, hb = polmissing.parse(f.name)
    had = {i for _, i, v, p in polmissing.entries(hb) if v.get("0")}
    _, cb = polmissing.parse(po)
    out[loc] = {i: v["0"] for _, i, v, p in polmissing.entries(cb) if not p and v.get("0") and i not in had}
json.dump(out, open(os.path.join(os.path.dirname(__file__), "translations.json"), "w"), ensure_ascii=False, indent=0, sort_keys=True)
print({k: len(v) for k, v in out.items()})
