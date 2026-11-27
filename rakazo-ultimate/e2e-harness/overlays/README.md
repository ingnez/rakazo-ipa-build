# Maestro flow overlays

These files are the **source of truth** for v37 UI E2E Maestro flows that diverge
from upstream. `apply-e2e-flow-overlays.py` copies them onto the prepared `src/`
tree and asserts final markers (testIDs, READY scroll, sign-in guard).

Do **not** add needle-based patch scripts that rewrite the same YAML blocks.
Code-only patches (mime sanitize, RPC logging, InsetRow a11y) stay separate.
`patch-open-in-bot.py` may add optional `Open` taps after overlays; it must not
rewrite hub waits.
