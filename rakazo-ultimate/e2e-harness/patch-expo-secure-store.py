#!/usr/bin/env python3
"""Replace expo-secure-store's SecureStore.js with an in-memory Map for E2E embeds."""
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
found = []
for base in [root, root.parent, root.parent.parent]:
    nm = base / "node_modules"
    if not nm.is_dir():
        continue
    found.extend(nm.glob("**/expo-secure-store/build/SecureStore.js"))
    direct = nm / "expo-secure-store/build/SecureStore.js"
    if direct.is_file():
        found.append(direct)

targets = []
seen = set()
for p in found:
    try:
        rp = p.resolve()
    except Exception:
        continue
    if rp.is_file() and rp not in seen:
        seen.add(rp)
        targets.append(rp)

if not targets:
    raise SystemExit(f"expo-secure-store build/SecureStore.js not found under {root}")

# Match the package's ESM export style (Metro resolves main: build/SecureStore.js).
body = """// E2E harness replacement: in-memory SecureStore (see sim-v37-ui-e2e.sh).
const memory = new Map();
export async function getItemAsync(key, _options = {}) {
  return memory.has(key) ? memory.get(key) : null;
}
export async function setItemAsync(key, value, _options = {}) {
  memory.set(key, String(value));
}
export async function deleteItemAsync(key, _options = {}) {
  memory.delete(key);
}
export async function isAvailableAsync() {
  return true;
}
export function getItem(key, _options = {}) {
  return memory.has(key) ? memory.get(key) : null;
}
export function setItem(key, value, _options = {}) {
  memory.set(key, String(value));
}
export function canUseBiometricAuthentication() {
  return false;
}
export const AFTER_FIRST_UNLOCK = 0;
export const AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY = 1;
export const ALWAYS = 2;
export const ALWAYS_THIS_DEVICE_ONLY = 3;
export const WHEN_PASSCODE_SET_THIS_DEVICE_ONLY = 4;
export const WHEN_UNLOCKED = 5;
export const WHEN_UNLOCKED_THIS_DEVICE_ONLY = 6;
"""

for t in targets:
    bak = pathlib.Path(str(t) + ".pre-e2e")
    if not bak.exists():
        bak.write_bytes(t.read_bytes())
    t.write_text(body)
    print("replaced", t)
