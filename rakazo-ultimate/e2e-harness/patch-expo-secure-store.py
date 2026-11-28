#!/usr/bin/env python3
"""Replace expo-secure-store with a file-backed store for E2E embeds (CI only).

In-memory Maps die when openLink relaunches JS. Keychain rejects unsigned
Release sims. expo-file-system Documents survive relaunch and need no Keychain.
"""
import pathlib
import sys
import os

if os.environ.get("GITHUB_ACTIONS") != "true" and os.environ.get("E2E_HARNESS_ALLOW_LOCAL") != "1":
    raise SystemExit(
        "refusing to patch expo-secure-store outside GitHub Actions: it rewrites the dependency in "
        "place, and an OTA exported from this tree would ship the fake store (users signed out on "
        "every app kill). Set E2E_HARNESS_ALLOW_LOCAL=1 only in a throwaway tree."
    )

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

body = r'''// E2E harness: file-backed SecureStore (CI simulator only; never in an IPA or OTA).
// Unsigned Release sims cannot use the Keychain, so the session lives in Documents.
//
// It persists for real across app kills, so flows/persist.yaml can prove a session survives a
// kill. The first sign-out (the session token deleted while one is stored) flips the store to
// memory-only for the rest of the run (tombstone file), which is what the screenshot flows were
// written against: each of their relaunches starts signed out.
// The import must be expo-file-system/legacy: on expo-file-system 58 the main entry's legacy
// functions throw, which silently made the old version of this store memory-only.
import {
  deleteAsync,
  documentDirectory,
  getInfoAsync,
  readAsStringAsync,
  writeAsStringAsync,
} from "expo-file-system/legacy";

const DIR = documentDirectory || "";
const PATH = `${DIR}e2e-secure-store.json`;
const TOMBSTONE = `${DIR}e2e-secure-store.ephemeral`;
const SESSION_KEY = "rakazo.session_token";
let cache = null;
let ephemeral = false;
let loading = null;
let writeChain = Promise.resolve();

async function load() {
  if (cache) return cache;
  if (!loading) loading = (async () => {
    let data = {};
    try {
      if ((await getInfoAsync(TOMBSTONE)).exists) {
        ephemeral = true;
      } else if ((await getInfoAsync(PATH)).exists) {
        data = JSON.parse(await readAsStringAsync(PATH)) || {};
      }
    } catch (error) {
      console.warn("[e2e-secure-store] load failed", String(error));
    }
    cache = cache || data;
    return cache;
  })();
  return loading;
}

function persist() {
  if (ephemeral) return writeChain;
  const snapshot = JSON.stringify(cache || {});
  writeChain = writeChain.then(async () => {
    if (ephemeral) return;
    try {
      await writeAsStringAsync(PATH, snapshot);
    } catch (error) {
      console.warn("[e2e-secure-store] write failed", String(error));
    }
  });
  return writeChain;
}

async function goEphemeral() {
  ephemeral = true;
  writeChain = writeChain.then(async () => {
    try {
      await writeAsStringAsync(TOMBSTONE, "1");
      await deleteAsync(PATH, { idempotent: true });
    } catch (error) {
      console.warn("[e2e-secure-store] tombstone failed", String(error));
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
  const signingOut = key === SESSION_KEY && Boolean(data[key]) && !ephemeral;
  delete data[key];
  cache = data;
  if (signingOut) await goEphemeral();
  else await persist();
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
