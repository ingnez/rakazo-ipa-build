#!/usr/bin/env python3
"""No-op: SecureStore durability is handled by patch-expo-secure-store.py (file-backed).

Previously this rewrote index.ts to an in-memory Map, which died on openLink relaunch.
"""
import pathlib
import sys

p = pathlib.Path(sys.argv[1])
print("skip index.ts memory shim; using file-backed expo-secure-store instead:", p)
