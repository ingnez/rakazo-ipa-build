#!/usr/bin/env python3
"""List/fill missing translations in a Lingui .po. Usage: polmissing.py list <po> | fill <po> <json>"""
import json, re, sys

def parse(path):
    text = open(path, encoding="utf-8").read()
    blocks = text.split("\n\n")
    return text, blocks

def unq(lines):
    out = ""
    for l in lines:
        m = re.match(r'^(?:msgid|msgstr|msgid_plural|msgctxt|msgstr\[\d+\])?\s*"(.*)"$', l)
        out += m.group(1).encode().decode("unicode_escape") if False else m.group(1)
    return out

def entries(blocks):
    for i, b in enumerate(blocks):
        lines = b.split("\n")
        if any(l.startswith("#~") for l in lines): continue
        mid, mstr, cur, plural, strs = [], [], None, False, {}
        for l in lines:
            if l.startswith("msgid_plural "): cur = "plural"; plural = True; continue
            if l.startswith("msgid "): cur = "id"; mid = [l[6:]]; continue
            if l.startswith("msgctxt "): cur = "ctx"; continue
            m = re.match(r"^msgstr(?:\[(\d+)\])? (.*)$", l)
            if m: cur = ("str", m.group(1) or "0"); strs[cur[1]] = [m.group(2)]; continue
            if l.startswith('"'):
                if cur == "id": mid.append(l)
                elif isinstance(cur, tuple): strs[cur[1]].append(l)
        if not mid: continue
        idv = "".join(re.findall(r'"((?:[^"\\]|\\.)*)"', "\n".join(mid)))
        if idv == "": continue
        vals = {k: "".join(re.findall(r'"((?:[^"\\]|\\.)*)"', "\n".join(v))) for k, v in strs.items()}
        yield i, idv, vals, plural

def missing(path):
    text, blocks = parse(path)
    res = []
    for i, idv, vals, plural in entries(blocks):
        if not vals or any(v == "" for v in vals.values()):
            refs = [l[3:] for l in blocks[i].split("\n") if l.startswith("#: ")]
            res.append((i, idv, plural, refs))
    return text, blocks, res

if __name__ == "__main__":
    cmd, po = sys.argv[1], sys.argv[2]
    text, blocks, res = missing(po)
    if cmd == "list":
        for i, idv, plural, refs in res:
            print(json.dumps({"id": idv, "plural": plural, "refs": refs}, ensure_ascii=False))
        print(len(res), "missing", file=sys.stderr)
    elif cmd == "count":
        print(len(res))
