#!/usr/bin/env python3
"""After every openLink, optionally tap iOS 'Open' for the Open in "Bot"? dialog.
Also dismiss that dialog on launch-app / first-launch.
"""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])  # .../e2e/ios-screenshots
OPEN = (
    "- tapOn:\n"
    '    text: "Open"\n'
    "    optional: true"
)

def ensure_open_after_links(text: str) -> str:
    # Skip if already patched
    if 'text: "Open"\n    optional: true' in text and "openLink" in text:
        # Still may need per-link; check a simple heuristic
        pass
    lines = text.split("\n")
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        # Shorthand: - openLink: "..."
        if re.match(r'^- openLink:\s+"', line) or re.match(r"^- openLink:\s+'", line):
            # Avoid double-patch
            nxt = lines[i + 1] if i + 1 < len(lines) else ""
            if 'text: "Open"' not in nxt:
                out.append(OPEN)
            i += 1
            continue
        # Block form: - openLink:  then indented link:
        if line.strip() == "- openLink:":
            i += 1
            while i < len(lines) and (lines[i].startswith("    ") or lines[i].startswith("\t")):
                out.append(lines[i])
                i += 1
            # peek if Open already follows
            if i < len(lines) and 'text: "Open"' in lines[i]:
                continue
            out.append(OPEN)
            continue
        i += 1
    return "\n".join(out)

def patch_launch(text: str) -> str:
    if 'text: "Open"' in text and "Open in" in text:
        return text
    # After launchApp block, dismiss Open-in-Bot if present
    needle = "- launchApp:\n    stopApp: true\n"
    insert = (
        "- launchApp:\n"
        "    stopApp: true\n"
        # System deep-link confirm from a prior openLink can sit on top of TourStage.
        "- tapOn:\n"
        '    text: "Open"\n'
        "    optional: true\n"
        "- tapOn:\n"
        '    text: "Cancel"\n'
        "    optional: true\n"
    )
    if needle in text:
        return text.replace(needle, insert, 1)
    return text

changed = 0
for p in sorted(root.rglob("*.yaml")):
    t = p.read_text()
    orig = t
    if p.name in ("launch-app.yaml", "first-launch.yaml"):
        t = patch_launch(t)
    if "openLink" in t:
        t = ensure_open_after_links(t)
    if t != orig:
        p.write_text(t)
        print("patched", p.relative_to(root))
        changed += 1
print(f"done, {changed} files")
