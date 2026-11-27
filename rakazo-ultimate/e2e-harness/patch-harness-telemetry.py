#!/usr/bin/env python3
"""Event-loop lag telemetry for the in-process screenshot API (code-only, idempotent).

Run 45966108508 showed 6-17s API stalls (db.pool.saturated with idle connections, `me` taking
17s) but nothing recorded whether the Node process or the whole runner stalled. This logs a
line whenever the process's own timer fires more than 1s late. A stall that shows up here is the
API process; one that does not is the runner (see sys-sample.log from sim-v37-ui-e2e.sh).
"""
import pathlib
import sys

src = pathlib.Path(sys.argv[1])
cli = src / "packages/testkit/src/cli/ios-app-screenshots.ts"
t = cli.read_text()
if "startLagMonitor" in t:
    print("lag monitor already present")
    raise SystemExit(0)
call_needle = "  await warmBackend(apiUrl);\n"
if call_needle not in t:
    raise SystemExit("run patch-harness-load.py first (warmBackend call missing)")
fn = '''
/** Logs `event_loop.lag` when this process's 250ms timer fires over 1s late. */
function startLagMonitor() {
  let last = Date.now();
  const timer = setInterval(() => {
    const now = Date.now();
    const lag = now - last - 250;
    last = now;
    if (lag > 1000)
      console.log(`${new Date().toISOString()} event_loop.lag ms=${lag} rss_mb=${Math.round(process.memoryUsage().rss / 1048576)}`);
  }, 250);
  timer.unref();
}
'''
t = t.replace(call_needle, call_needle + "  startLagMonitor();\n", 1)
marker = "\nasync function captureSections("
if marker not in t:
    raise SystemExit("captureSections marker missing")
t = t.replace(marker, fn + marker, 1)
cli.write_text(t)
print("lag monitor added")
