#!/usr/bin/env python3
"""Install the contract-gap fallback (unimplemented procedures answer 501, scenes answer empty).

Code-only and idempotent. Maestro flow YAML is owned by apply-e2e-flow-overlays.py.
"""
import pathlib
import shutil
import sys

src = pathlib.Path(sys.argv[1])
fixes = pathlib.Path(__file__).resolve().parent / "fixes"
api = src / "apps/api/src"
shutil.copy(fixes / "unimplemented-procedures.ts", api / "unimplemented-procedures.ts")
shutil.copy(fixes / "unimplemented-procedures.test.ts", api / "unimplemented-procedures.test.ts")
print("installed unimplemented-procedures.ts + test")

router = api / "router.ts"
t = router.read_text()
if "withUnimplementedProcedures" in t:
    print("router.ts already wired")
else:
    imp = 'import { modelsRoutes } from "./routes/models.js";\n'
    if imp not in t:
        raise SystemExit("router.ts models import needle missing")
    t = t.replace(imp, imp + 'import { withUnimplementedProcedures } from "./unimplemented-procedures.js";\n', 1)
    old = "  return os.router({\n    ...accountRoutes(ctx),"
    new = "  return os.router(\n    withUnimplementedProcedures(ctx.authed, {\n    ...accountRoutes(ctx),"
    if old not in t:
        raise SystemExit("router.ts os.router needle missing")
    t = t.replace(old, new, 1)
    old_end = "    ...spendingLimitRoutes(ctx),\n  });\n}"
    new_end = "    ...spendingLimitRoutes(ctx),\n    }),\n  );\n}"
    if old_end not in t:
        raise SystemExit("router.ts router end needle missing")
    t = t.replace(old_end, new_end, 1)
    router.write_text(t)
    print("wired router.ts")
