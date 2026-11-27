#!/usr/bin/env python3
"""Replace expo-secure-store with a file-backed store for E2E embeds.

In-memory Maps die when openLink relaunches JS. Keychain rejects unsigned
Release sims. expo-file-system Documents survive relaunch and need no Keychain.
"""
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

body = r'''// E2E harness: file-backed SecureStore (survives openLink relaunch; no Keychain).
import {
  documentDirectory,
  getInfoAsync,
  readAsStringAsync,
  writeAsStringAsync,
} from "expo-file-system";

const PATH = `${documentDirectory || ""}e2e-secure-store.json`;
let cache = null;
let writeChain = Promise.resolve();

async function load() {
  if (cache) return cache;
  try {
    const info = await getInfoAsync(PATH);
    if (info.exists) {
      cache = JSON.parse(await readAsStringAsync(PATH)) || {};
    } else {
      cache = {};
    }
  } catch {
    cache = {};
  }
  return cache;
}

function persist() {
  const snapshot = JSON.stringify(cache || {});
  writeChain = writeChain.then(async () => {
    try {
      await writeAsStringAsync(PATH, snapshot);
    } catch {
      // Keep the in-memory cache if the write fails.
    }
  });
  return writeChain;
}

export async function getItemAsync(key, _options = {}) {
  const data = await load();
  return Object.prototype.hasOwnProperty.call(data, key) ? data[key] : null;
}
export async function setItemAsync(key, value, _options = {}) {
  const data = await load();
  data[key] = String(value);
  cache = data;
  await persist();
}
export async function deleteItemAsync(key, _options = {}) {
  const data = await load();
  delete data[key];
  cache = data;
  await persist();
}
export async function isAvailableAsync() {
  return true;
}
export function getItem(key, _options = {}) {
  return cache && Object.prototype.hasOwnProperty.call(cache, key) ? cache[key] : null;
}
export function setItem(key, value, _options = {}) {
  cache = cache || {};
  cache[key] = String(value);
  void persist();
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
'''

for t in targets:
    bak = pathlib.Path(str(t) + ".pre-e2e")
    if not bak.exists():
        bak.write_bytes(t.read_bytes())
    t.write_text(body)
    print("replaced", t)
