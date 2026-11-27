#!/usr/bin/env python3
"""After Sign in, assert we did not hit the SecureStore save error (clearer CI signal)."""
import pathlib
import sys

p = pathlib.Path(sys.argv[1])
t = p.read_text()
if "Could not save your sign-in" in t:
    print("sign-in.yaml already has save-error guard")
    raise SystemExit(0)
needle = (
    '- tapOn: "Sign in"\n'
    "- tapOn:\n"
    '    text: "Not Now"\n'
    "    optional: true"
)
if needle not in t:
    raise SystemExit("sign-in.yaml Sign in / Not Now block not found")
guard = (
    '- tapOn: "Sign in"\n'
    "# If Keychain/SecureStore still fails, fail here with a clear screen instead of\n"
    "# timing out waiting for Account / onboarding survey.\n"
    "- extendedWaitUntil:\n"
    '    visible: "Account|.*How did you hear about us.*|Could not save your sign-in"\n'
    "    timeout: 20000\n"
    "- runFlow:\n"
    "    when:\n"
    '      visible: ".*Could not save your sign-in.*"\n'
    "    commands:\n"
    '      - assertVisible: "Account"\n'
    "- tapOn:\n"
    '    text: "Not Now"\n'
    "    optional: true"
)
p.write_text(t.replace(needle, guard, 1))
print("patched", p)
