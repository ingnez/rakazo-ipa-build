#!/usr/bin/env python3
"""Seed the fixture Gmail connection with the catalog's slug case (code-only, idempotent).

The Integrations screen marks a catalog app connected only when a connection row has
`connectorId === item.connectorId` and `provider === item.slug`, compared exactly. The offline
Composio catalog lists Gmail as slug "GMAIL" (and the app stores `item.slug` when a person
connects), but the seed wrote provider "gmail", so the row never matched and every app showed
Connect (run 45981903828). Write the row the way the app itself would.
"""
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "packages/testkit/src/cli/ios-screenshot-seed.ts"
t = path.read_text()
pairs = [
    ('where: { spaceId, userId, provider: "gmail", status: "connected" },',
     'where: { spaceId, userId, connectorId: "composio", provider: "GMAIL", status: "connected" },'),
    ('      provider: "gmail",\n      displayName: "Fixture Gmail",',
     '      provider: "GMAIL",\n      displayName: "Fixture Gmail",'),
]
if 'provider: "GMAIL"' in t and 'provider: "gmail",\n      displayName: "Fixture Gmail"' not in t:
    print("seed connection already uses the catalog slug")
    raise SystemExit(0)
for old, new in pairs:
    if old not in t:
        raise SystemExit(f"seed needle missing: {old[:50]}")
    t = t.replace(old, new, 1)
path.write_text(t)
print("seed connection now uses provider GMAIL")
