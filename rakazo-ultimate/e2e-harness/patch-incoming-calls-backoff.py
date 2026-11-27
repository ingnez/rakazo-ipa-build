#!/usr/bin/env python3
"""Back off the incoming-call stream when it never opens (code-only, idempotent).

With PHONE_CALLS_ENABLED=false the server answers `notifications/subscribeCalls` with an error
frame that the stream reader treats as an ignorable malformed frame, so the subscribe "succeeds"
without ever delivering a snapshot. `follow()` then reset its backoff to 250ms every time and
reconnected ~4 times a second for the life of the session (770 requests in run 45966108508).
Only reset the backoff once a snapshot actually arrived.
"""
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "apps/mobile/lib/incoming-calls.ts"
t = path.read_text()
old = "      retry = 250;\n      failure = undefined;\n    } catch (error) {"
new = (
    "      if (opened) {\n"
    "        retry = 250;\n"
    "        failure = undefined;\n"
    "      } else {\n"
    "        // The stream ended without a snapshot (calls disabled on this server): keep backing off.\n"
    '        failure = new Error("call stream ended before it opened");\n'
    "      }\n"
    "    } catch (error) {"
)
if "call stream ended before it opened" in t:
    print("incoming-calls backoff already patched")
elif old in t:
    path.write_text(t.replace(old, new, 1))
    print("incoming-calls backoff patched")
else:
    raise SystemExit("incoming-calls follow() needle missing")
