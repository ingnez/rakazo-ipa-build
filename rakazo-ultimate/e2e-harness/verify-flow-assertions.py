#!/usr/bin/env python3
"""Static check: every selector in the settings + thread Maestro flows against the app code.

For each text/regex selector (alternatives split on |) report whether some UI string exists in the
client source, the English message catalog, or the fixture seed; for each `id:` whether a testID
with that name exists. Usage: verify-flow-assertions.py <src-tree> [--strict]
Exit 1 only with --strict and a MISSING item. Matching is Maestro-like: full match, ignore case;
`partial` means only a substring of a longer string (accessibility labels join title + detail).
"""
import pathlib
import re
import sys

import yaml

src = pathlib.Path(sys.argv[1])
strict = "--strict" in sys.argv
flows_dir = src / "apps/mobile/e2e/ios-screenshots"
FILES = [
    "flows/settings.yaml", "flows/thread.yaml",
    "subflows/first-launch.yaml", "subflows/launch-app.yaml",
    "subflows/sign-in.yaml", "subflows/open-thread.yaml",
]
# Fixture-only text: seeded data or system UI that no app source contains.
SYSTEM = {"Open", "Cancel", "Not Now", "Don’t allow", "Don't allow", "Allow", "OK", "Copy"}

# ---- corpus ---------------------------------------------------------------------------------
corpus: set[str] = set()
lit = re.compile(r"""(?:"((?:[^"\\\n]|\\.)*)"|'((?:[^'\\\n]|\\.)*)'|`((?:[^`\\]|\\.)*)`)""")
jsx = re.compile(r">\s*([^<>{}\n][^<>{}]*?)\s*<")
roots = [src / "apps/mobile/app", src / "apps/mobile/components", src / "apps/mobile/lib",
         src / "packages/testkit/src/cli", src / "packages/testkit/src",
         src / "apps/api/src/fake-model", src / "packages/core/src"]
seen_files = set()
for root in roots:
    if not root.exists():
        continue
    for f in list(root.rglob("*.ts")) + list(root.rglob("*.tsx")):
        if f in seen_files or "node_modules" in f.parts or ".test." in f.name:
            continue
        seen_files.add(f)
        text = f.read_text(errors="ignore")
        for m in lit.finditer(text):
            s = next(g for g in m.groups() if g is not None)
            if 1 < len(s) < 300:
                corpus.add(re.sub(r"\$\{[^}]*\}", "§", s))
        for m in jsx.finditer(text):
            corpus.add(m.group(1))
po = src / "packages/i18n/locales/en/messages.po"
if po.exists():
    for m in re.finditer(r'^msg(?:id|str) "(.*)"$', po.read_text(), re.M):
        corpus.add(re.sub(r"\{[^}]*\}", "§", m.group(1)))
test_ids = set()
for f in seen_files:
    for m in re.finditer(r'testID=(?:"([^"]+)"|\{`([^`]+)`\}|\{"([^"]+)"\})', f.read_text(errors="ignore")):
        test_ids.add(next(g for g in m.groups() if g))
for f in (src / "apps/mobile").rglob("*.tsx"):
    if "node_modules" in f.parts:
        continue
    for m in re.finditer(r'testID=(?:"([^"]+)"|\{`([^`]+)`\}|\{"([^"]+)"\})', f.read_text(errors="ignore")):
        test_ids.add(next(g for g in m.groups() if g))
# Settings rows get `settings-row-<href without the leading slash, slashes as dashes>` from
# account.tsx's settingsLink(); derive the ids from the hrefs listed there.
_acc = src / "apps/mobile/app/(settings)/account.tsx"
if _acc.exists():
    for m in re.finditer(r'href: "(/[A-Za-z0-9/_-]+)"', _acc.read_text()):
        test_ids.add("settings-row-" + m.group(1).lstrip("/").replace("/", "-"))
corpus_l = [c for c in corpus if c]

def check_text(pattern: str) -> str:
    if pattern in SYSTEM:
        return "system"
    try:
        rx = re.compile(pattern, re.I | re.S)
    except re.error:
        return "BADREGEX"
    for c in corpus_l:
        if rx.fullmatch(c):
            return "exact"
    # Templates ("Message §"): a plain pattern may be one filled in at runtime.
    for c in corpus_l:
        if "§" in c and re.fullmatch(".+".join(re.escape(part) for part in c.split("§")), pattern, re.I | re.S):
            return "template"
    for c in corpus_l:
        if rx.search(c):
            return "partial"
    return "MISSING"

def check_id(name: str) -> str:
    if name in test_ids:
        return "exact"
    for t in test_ids:
        if "${" in t or "§" in t:
            if re.fullmatch(re.sub(r"\$\{[^}]*\}", ".+", re.escape(t).replace(r"\$\{", "${")), name):
                return "template"
    return "MISSING"

# ---- selectors ------------------------------------------------------------------------------
KEYS = {"assertVisible", "assertNotVisible", "tapOn", "longPressOn", "extendedWaitUntil",
        "scrollUntilVisible", "when", "doubleTapOn"}
found: list[tuple[str, str, str]] = []

def selectors(node, where):
    if isinstance(node, list):
        for item in node:
            selectors(item, where)
    elif isinstance(node, dict):
        for k, v in node.items():
            if k in ("visible", "notVisible", "element", "text", "id") or k in KEYS:
                if isinstance(v, str) and k not in ("when",):
                    found.append((where, "id" if k == "id" else "text", v))
                elif isinstance(v, dict):
                    for kk in ("text", "id"):
                        if isinstance(v.get(kk), str):
                            found.append((where, kk, v[kk]))
            selectors(v, where)

for rel in FILES:
    p = flows_dir / rel
    docs = list(yaml.safe_load_all(p.read_text()))
    for d in docs:
        selectors(d, rel)

bad = 0
printed = set()
for where, kind, value in found:
    key = (kind, value)
    if key in printed:
        continue
    printed.add(key)
    if kind == "id":
        res = [("", check_id(value))]
    else:
        # split alternatives on top-level | only
        alts = [a for a in value.split("|")] if "(" not in value else [value]
        res = [(a, check_text(a)) for a in alts]
    for alt, status in res:
        flag = "  " if status in ("exact", "system", "template") else "!!" if status in ("MISSING", "BADREGEX") else "? "
        if status in ("MISSING", "BADREGEX"):
            bad += 1
        print(f"{flag} {status:8} {kind:4} {alt or value!r}  [{where}]")
print(f"\n{len(printed)} unique selectors, {bad} MISSING/BADREGEX, corpus={len(corpus_l)} strings, testIDs={len(test_ids)}")
sys.exit(1 if strict and bad else 0)
