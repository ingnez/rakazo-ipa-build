#!/usr/bin/env python3
"""Patch apps/mobile/index.ts so E2E embeds can keep SecureStore in memory."""
import pathlib
import sys

p = pathlib.Path(sys.argv[1])
text = p.read_text()
if "EXPO_PUBLIC_E2E_MEMORY_STORE" in text:
    print("index.ts already patched")
    raise SystemExit(0)
needle = 'installMobileEarlyErrorReporting(require("expo-secure-store"), require("expo-application"));'
if needle not in text:
    raise SystemExit(f"index.ts needle missing:\n{text[:500]}")
shim = """// E2E-only: unsigned simulator Keychain often rejects SecureStore writes. When the
// embed sets EXPO_PUBLIC_E2E_MEMORY_STORE=1, keep session/space keys in memory so
// Maestro can sign in. Production / OTA embeds leave the flag unset.
if (process.env.EXPO_PUBLIC_E2E_MEMORY_STORE === "1") {
  const store = require("expo-secure-store");
  const memory = new Map();
  store.getItemAsync = async (key) => (memory.has(key) ? memory.get(key) : null);
  store.setItemAsync = async (key, value) => {
    memory.set(key, value);
  };
  store.deleteItemAsync = async (key) => {
    memory.delete(key);
  };
}
"""
p.write_text(text.replace(needle, shim + needle, 1))
print("patched", p)
