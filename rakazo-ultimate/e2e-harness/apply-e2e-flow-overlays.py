#!/usr/bin/env python3
"""Copy final Maestro flow overlays onto the prepared src tree.

Do not stack needle-based YAML rewrites across patch scripts: the overlays are
the source of truth for settings / thread / sign-in. This script is idempotent
and asserts the final markers after copy.
"""
from __future__ import annotations

import pathlib
import sys

SRC = pathlib.Path(sys.argv[1])  # .../rakazo-ultimate/src
OVER = pathlib.Path(__file__).resolve().parent / "overlays" / "ios-screenshots"
DEST = SRC / "apps" / "mobile" / "e2e" / "ios-screenshots"

OVERLAYS = (
    "flows/settings.yaml",
    "flows/thread.yaml",
    "flows/compose.yaml",
    "subflows/sign-in.yaml",
    "subflows/open-thread.yaml",
)

MARKERS = {
    "flows/settings.yaml": (
        'id: "settings-account-hub"',
        'id: "settings-row-profile"',
        'id: "settings-row-vault"',
        'id: "settings-row-integrations"',
        "General|通用",
        'visible: ".*Screenshot User.*"',
        'id: "settings-row-profile"\n      - waitForAnimationToEnd',
        'id: "settings-models-screen"',
        'id: "settings-models-main"',
        'id: "settings-models-scenarios"',
        'id: "settings-models-error"',
        ".*(will be|are) deleted too.*",
    ),
    "flows/thread.yaml": (
        "runFlow: ../subflows/open-thread.yaml",
        'tapOn: "Chat actions"',
        "direction: UP\n    timeout: 60000\n    visibilityPercentage: 80\n    speed: 20\n    centerElement: true",
        'element: ".*The fixture workspace is ready.*"\n    direction: UP',
        'visible: ".*The fixture workspace is ready.*"',
        "takeScreenshot: 01-thread",
        "takeScreenshot: 04b-image-stack",
    ),
    "flows/compose.yaml": (
        "Give your Bot a name",
        "为 Bot 取个名字",
        "takeScreenshot: 11-new-bot-zh",
        ".*(Colour|Emblem).*",
    ),
    "subflows/sign-in.yaml": (
        "Could not save your sign-in",
        ".*Request timed out.*",
        'visible: "Account|.*How did you hear about us.*|Could not save your sign-in|.*Request timed out.*|Personal|Screenshot User"',
    ),
    "subflows/open-thread.yaml": (
        'visible: "Message Researcher"',
        ".*Could not reach the server.*",
    ),
}


def parse_ok(path: pathlib.Path, text: str) -> None:
    """Maestro YAML is multi-doc (---); require it to parse if PyYAML is present."""
    try:
        import yaml as _yaml
    except ImportError:
        # No PyYAML in the runner image is fine; marker asserts still run.
        if "---" not in text or "appId:" not in text:
            raise SystemExit(f"{path}: missing appId/--- (does not look like a Maestro flow)")
        return
    try:
        docs = list(_yaml.safe_load_all(text))
    except Exception as e:
        raise SystemExit(f"{path}: YAML parse failed: {e}") from e
    if not docs:
        raise SystemExit(f"{path}: empty YAML")
    # First doc is metadata; rest are command lists (or a single list after ---).
    print(f"parsed {path.relative_to(DEST)} docs={len(docs)}")


def main() -> None:
    if not OVER.is_dir():
        raise SystemExit(f"overlays missing: {OVER}")
    if not DEST.is_dir():
        raise SystemExit(f"screenshot flows missing: {DEST}")

    for rel in OVERLAYS:
        src = OVER / rel
        dst = DEST / rel
        if not src.is_file():
            raise SystemExit(f"overlay file missing: {src}")
        dst.parent.mkdir(parents=True, exist_ok=True)
        text = src.read_text()
        dst.write_text(text)
        print(f"overlay → {dst.relative_to(SRC)}")
        parse_ok(dst, text)
        missing = [m for m in MARKERS[rel] if m not in text]
        if missing:
            raise SystemExit(f"{rel}: missing final markers: {missing}")
        print(f"asserted markers in {rel}")

    print("apply-e2e-flow-overlays: ok")


if __name__ == "__main__":
    main()
