#!/usr/bin/env python3
"""Install mimeType sanitization + fixture seed fix into the prepared src tree.

Maestro flow YAML is owned by apply-e2e-flow-overlays.py overlays — not this script.
"""
import pathlib
import shutil
import sys

src = pathlib.Path(sys.argv[1])  # .../rakazo-ultimate/src
fixes = pathlib.Path(__file__).resolve().parent / "fixes"

# 1) sanitize helper + test
api = src / "apps/api/src"
shutil.copy(fixes / "sanitize-message-blocks.ts", api / "sanitize-message-blocks.ts")
shutil.copy(fixes / "sanitize-message-blocks.test.ts", api / "sanitize-message-blocks.test.ts")
print("installed sanitize-message-blocks.ts")

# 2) wire toThreadMessage
pages = api / "thread-message-pages.ts"
t = pages.read_text()
if "sanitizeMessageBlocksForClient" not in t:
    old = 'import { MessageBlock as MessageBlockSchema } from "@rakazo/contracts";\n'
    if old not in t:
        raise SystemExit("thread-message-pages import needle missing")
    t = t.replace(
        old,
        old + 'import { sanitizeMessageBlocksForClient } from "./sanitize-message-blocks.js";\n',
        1,
    )
    old2 = '    blocks: row.blocks as ThreadMessage["blocks"],\n'
    if old2 not in t:
        raise SystemExit("blocks assign needle missing")
    t = t.replace(old2, "    blocks: sanitizeMessageBlocksForClient(row.blocks),\n", 1)
    pages.write_text(t)
    print("wired toThreadMessage")
else:
    print("toThreadMessage already wired")

# 3) fixture image mimeType
seed = src / "packages/testkit/src/cli/ios-screenshot-seed.ts"
st = seed.read_text()
old = """      ...input.imageIds.map((artifactId, index) => ({
        kind: "image" as const,
        artifactId,
        name: `stack-${index + 1}.png`,
      })),"""
new = """      ...input.imageIds.map((artifactId, index) => ({
        kind: "image" as const,
        artifactId,
        name: `stack-${index + 1}.png`,
        mimeType: "image/png",
      })),"""
if 'mimeType: "image/png"' in st and "stack-${index + 1}.png" in st and old not in st:
    print("seed mimeType already present")
elif old in st:
    seed.write_text(st.replace(old, new, 1))
    print("seed mimeType patched")
else:
    raise SystemExit("seed image stack map not found")

# Settings / thread Maestro YAML lives in e2e-harness/overlays/ and is applied by
# apply-e2e-flow-overlays.py — do not needle-rewrite those flows here.
