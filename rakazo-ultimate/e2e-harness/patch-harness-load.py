#!/usr/bin/env python3
"""Harness-only load fixes for the in-process screenshot API (code-only, idempotent).

1. DB_KEY_POOL_MAX: the space-key pool is hard-coded to 2 connections; default stays 2, the
   harness sets more so a burst of first-use key reads does not queue behind two sockets.
2. IOS_SCREENSHOT_LOG_LEVEL: the backend pins LOG_LEVEL=warn, so a slow sign-in leaves no
   duration in the log. Let the harness ask for info (request durations).
3. Warm the API (auth + RPC module graph) before the first Maestro flow, so the first real
   sign-in does not pay the lazy-import / cold-path cost on a busy 3-core runner.
"""
import pathlib
import sys

src = pathlib.Path(sys.argv[1])

# 1) key pool size
client = src / "packages/db/src/client.ts"
t = client.read_text()
old = "    max: 2,\n    connectionTimeoutMillis: CHECKOUT_TIMEOUT_MS,\n    idleTimeoutMillis: 30_000,"
new = (
    "    max: Number.parseInt(process.env.DB_KEY_POOL_MAX ?? \"\", 10) || 2,\n"
    "    connectionTimeoutMillis: CHECKOUT_TIMEOUT_MS,\n    idleTimeoutMillis: 30_000,"
)
if "DB_KEY_POOL_MAX" in t:
    print("key pool already configurable")
elif old in t:
    client.write_text(t.replace(old, new, 1))
    print("key pool configurable via DB_KEY_POOL_MAX (default 2)")
else:
    raise SystemExit("db client key pool needle missing")

# 2) log level
backend = src / "packages/testkit/src/cli/ios-screenshot-backend.ts"
t = backend.read_text()
old = '    LOG_LEVEL: "warn",\n'
new = '    LOG_LEVEL: process.env.IOS_SCREENSHOT_LOG_LEVEL || "warn",\n'
if "IOS_SCREENSHOT_LOG_LEVEL" in t:
    print("log level already configurable")
elif old in t:
    backend.write_text(t.replace(old, new, 1))
    print("log level configurable")
else:
    raise SystemExit("backend LOG_LEVEL needle missing")

# 3) warm-up
cli = src / "packages/testkit/src/cli/ios-app-screenshots.ts"
t = cli.read_text()
needle = "  const { apiUrl, databaseUrl } = backend;\n"
call = needle + "  await warmBackend(apiUrl);\n"
fn = '''
/**
 * First requests pay for lazy imports and cold auth/RPC paths. On a shared runner that took
 * seconds (a 401 `me` answered in 6.7s), longer than the app's 8s request timeout once sign-in
 * is added. Pay it here, before a person-facing flow starts.
 */
async function warmBackend(apiUrl: string) {
  const started = Date.now();
  const post = (route: string, body?: unknown) =>
    fetch(`${apiUrl}${route}`, {
      method: "POST",
      headers: { "content-type": "application/json", origin: "rakazo://" },
      body: JSON.stringify(body ?? {}),
    })
      .then((response) => response.status)
      .catch(() => 0);
  for (let round = 0; round < 2; round += 1) {
    await post("/api/auth/sign-in/email", {
      email: "ios-screenshots-warmup@example.test",
      password: "warmup-password-0000",
    });
    for (const route of ["me", "spaces/list", "models/scenarios", "threads/get", "usage/summary"])
      await post(`/rpc/${route}`);
  }
  console.log(`API warm-up took ${Date.now() - started}ms`);
}
'''
if "warmBackend" in t:
    print("warm-up already present")
elif needle in t:
    t = t.replace(needle, call, 1)
    marker = "\nasync function captureSections("
    if marker not in t:
        raise SystemExit("captureSections marker missing")
    t = t.replace(marker, fn + marker, 1)
    cli.write_text(t)
    print("warm-up added")
else:
    raise SystemExit("cli backend destructure needle missing")
