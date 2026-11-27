#!/usr/bin/env python3
"""Wrap ios-screenshot-seed direct Prisma work in runAsSystem (RLS-safe)."""
import pathlib
import sys

p = pathlib.Path(sys.argv[1])
text = p.read_text()
if "runAsSystem(\"ios screenshot fixtures\"" in text or "runAsSystem('ios screenshot fixtures'" in text:
    print("seed already wrapped")
    raise SystemExit(0)

# Ensure import
if "runAsSystem" not in text.split("export async function seedIosScreenshotFixture")[0]:
    # Add to existing @rakazo/db import
    old = "import { allocateTicketNumber, createDb, createThreadMessage, ensureBoard } from \"@rakazo/db\";"
    new = "import { allocateTicketNumber, createDb, createThreadMessage, ensureBoard, runAsSystem } from \"@rakazo/db\";"
    if old not in text:
        # try alternate import shapes
        import re
        m = re.search(r'import \{([^}]+)\} from "@rakazo/db";', text)
        if not m:
            raise SystemExit("could not find @rakazo/db import")
        names = m.group(1)
        if "runAsSystem" not in names:
            text = text.replace(m.group(0), f'import {{{names.rstrip()}, runAsSystem }} from "@rakazo/db";', 1)
    else:
        text = text.replace(old, new, 1)

# Wrap the try body after createDb. Pattern:
#   const db = createDb(...);
#   try {
#     await ensureThreadCopy...
#     ...
#     return { ... };
#   } finally {
anchor = "  const db = createDb(input.databaseUrl, { applicationName: \"ios-screenshots\" });\n  try {\n"
if anchor not in text:
    raise SystemExit("createDb try anchor not found")
insert = (
    "  const db = createDb(input.databaseUrl, { applicationName: \"ios-screenshots\" });\n"
    "  try {\n"
    "    return await runAsSystem(\"ios screenshot fixtures\", async () => {\n"
)
text = text.replace(anchor, insert, 1)

# Close the runAsSystem callback before finally. Find the return { ... }; that ends the try.
# Look for the specific return block ending seed.
marker = "      cardsBotId: support.id,\n    };\n  } finally {"
if marker not in text:
    raise SystemExit("return/finally marker not found")
text = text.replace(
    marker,
    "      cardsBotId: support.id,\n    };\n    });\n  } finally {",
    1,
)
p.write_text(text)
print("patched", p)
