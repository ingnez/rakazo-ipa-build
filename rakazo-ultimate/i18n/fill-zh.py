#!/usr/bin/env python3
"""Fill the empty zh-CN / zh-TW msgstr that `lingui extract` leaves for the fork's messages, from
translations.json (a Chinese-source message is its own zh-CN text). Never overwrites a translation.
Anything still empty afterwards is reported by check-i18n.py, which fails the build.
To translate a new message: add it to translations.json for BOTH zh-CN and zh-TW.
Usage: fill-zh.py <src-tree>"""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
import polmissing

CJK = re.compile(r"[\u4e00-\u9fff]")
table = json.load(open(os.path.join(os.path.dirname(__file__), "translations.json"), encoding="utf-8"))

def main(src):
    for loc in ("zh-CN", "zh-TW"):
        po = os.path.join(src, "packages/i18n/locales", loc, "messages.po")
        text, blocks, res = polmissing.missing(po)
        filled = 0
        for i, idv, plural, refs in res:
            val = table[loc].get(idv) or (idv if loc == "zh-CN" and CJK.search(idv) else None)
            if val is None or plural: continue
            lines = blocks[i].split("\n")
            for k, l in enumerate(lines):
                if l == 'msgstr ""' and (k + 1 == len(lines) or not lines[k + 1].startswith('"')):
                    lines[k] = 'msgstr "%s"' % val; filled += 1
                    break
            blocks[i] = "\n".join(lines)
        open(po, "w", encoding="utf-8").write("\n\n".join(blocks))
        print(f"{loc}: filled {filled} of {len(res)} empty")

main(sys.argv[1])
