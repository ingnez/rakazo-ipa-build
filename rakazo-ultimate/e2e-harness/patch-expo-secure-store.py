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

body = r'''// E2E harness: durable file-backed SecureStore (CI simulator only; never in an IPA or OTA).
// Unsigned Release sims cannot use the Keychain, so the session lives in Documents.
//
// Durable on purpose: flows/persist.yaml kills the app and expects the session to survive, so
// every write is awaited and every failure is thrown (a store that swallows errors is what hid
// the log-out-on-kill bug: the old fake silently kept everything in memory).
// The first sign-out (the session token deleted while one is stored) flips the store to
// memory-only for the rest of the run (tombstone file): the screenshot flows were written
// against relaunches that start signed out.
// Keys and value lengths (never values) go to e2e-secure-store.log in Documents; the CI script
// copies it into the artifacts so a failure shows what the store did.
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
const LOG = `${DIR}e2e-secure-store.log`;
const SESSION_KEY = "rakazo.session_token";
let cache = null;
let ephemeral = false;
let loading = null;
let queue = Promise.resolve();
let logText = "";

function note(line) {
  logText += `${new Date().toISOString()} ${line}\n`;
  const snapshot = logText;
  // Diagnostics only: a failed log write must not change what the store does.
  writeAsStringAsync(LOG, snapshot).catch(() => undefined);
}

// One operation at a time, in call order, so a write is on disk before the next read.
function serial(task) {
  const run = queue.then(task);
  queue = run.then(() => undefined, () => undefined);
  return run;
}

async function load() {
  if (cache) return cache;
  // Fail loudly: with nowhere durable to write, a "working" store would only hide a log-out bug.
  if (!DIR.startsWith("file://")) {
    throw new Error("[e2e-secure-store] no documentDirectory: " + String(documentDirectory));
  }
  if (!loading) {
    loading = (async () => {
      // Keep the log of earlier launches: the kill/relaunch history is the point of it.
      try {
        if ((await getInfoAsync(LOG)).exists) logText = await readAsStringAsync(LOG);
      } catch {
        // Diagnostics only.
      }
      note("launch");
      const tomb = await getInfoAsync(TOMBSTONE);
      if (tomb.exists) {
        ephemeral = true;
        cache = {};
        note("load: ephemeral (tombstone present)");
        return cache;
      }
      const info = await getInfoAsync(PATH);
      cache = info.exists ? JSON.parse(await readAsStringAsync(PATH)) || {} : {};
      note(`load: durable file=${info.exists} keys=${Object.keys(cache).sort().join(",")}`);
      return cache;
    })();
  }
  return loading;
}

async function save() {
  if (ephemeral) return;
  await writeAsStringAsync(PATH, JSON.stringify(cache));
}

async function goEphemeral() {
  ephemeral = true;
  await writeAsStringAsync(TOMBSTONE, "1");
  await deleteAsync(PATH, { idempotent: true });
  note("sign-out: store is memory-only from now on");
}

export function getItemAsync(key, _options = {}) {
  return serial(async () => {
    const data = await load();
    const has = Object.prototype.hasOwnProperty.call(data, key);
    if (key === SESSION_KEY) note(`get ${key} present=${has}`);
    return has ? data[key] : null;
  });
}
export function setItemAsync(key, value, _options = {}) {
  return serial(async () => {
    const data = await load();
    data[key] = String(value);
    await save();
    if (key === SESSION_KEY) note(`set ${key} len=${String(value).length} durable=${!ephemeral}`);
  });
}
export function deleteItemAsync(key, _options = {}) {
  return serial(async () => {
    const data = await load();
    const signingOut = key === SESSION_KEY && Boolean(data[key]) && !ephemeral;
    delete data[key];
    if (key === SESSION_KEY) note(`delete ${key} wasStored=${signingOut}`);
    if (signingOut) await goEphemeral();
    else await save();
  });
}
export async function isAvailableAsync() {
  return true;
}
// Synchronous reads only see what this process already loaded or wrote.
export function getItem(key, _options = {}) {
  return cache && Object.prototype.hasOwnProperty.call(cache, key) ? cache[key] : null;
}
export function setItem(key, value, _options = {}) {
  void setItemAsync(key, value);
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
