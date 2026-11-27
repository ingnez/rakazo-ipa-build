#!/usr/bin/env python3
"""Save the live UI hierarchy after every Maestro section (code-only, idempotent).

Maestro's failure text says "check the UI hierarchy in debug artifacts" but with
--flatten-debug-output none is kept, so a failing selector could only be guessed at (runs
45994571354, 46011113796). After each section, pass or fail, run `maestro hierarchy` and keep
hierarchy-<section>.json next to the screenshots (the screen the flow stopped on).
"""
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "packages/testkit/src/cli/ios-app-screenshots.ts"
t = path.read_text()
if "dumpHierarchy" in t:
    print("hierarchy dump already present")
    raise SystemExit(0)
needle = "        error: await describeFailure(work),\n      });\n    }\n"
if needle not in t:
    raise SystemExit("hierarchy patch: loop needle missing")
t = t.replace(needle, needle + "    await dumpHierarchy(udid, path.join(outDir, `hierarchy-${section.id}.json`));\n", 1)
probe_needle = "\n  const gallery = await galleryFromDisk(outDir, catalog);\n"
probe_call = (
    "\n  await probeThreadHierarchy(udid, outDir, env);\n"
)
if probe_needle not in t:
    raise SystemExit("hierarchy patch: gallery needle missing")
t = t.replace(probe_needle, probe_call + probe_needle, 1)
fn = '''
/** Best-effort `maestro hierarchy` of the screen the section ended on; never fails the run. */
async function dumpHierarchy(udid: string, file: string) {
  try {
    const { stdout } = await promisify(execFile)("maestro", ["--udid", udid, "hierarchy"], {
      timeout: 90_000,
      maxBuffer: 64 * 1024 * 1024,
    });
    await writeFile(file, stdout);
  } catch (error) {
    await writeFile(`${file}.err`, String(error)).catch(() => undefined);
  }
}

/**
 * The thread section ends wherever its flow stopped, so reopen the fixture thread, scroll to the
 * file card and save that screen's hierarchy too: the one dump that shows how the card's accessible
 * element really appears to Maestro.
 */
async function probeThreadHierarchy(udid: string, outDir: string, env: Record<string, string>) {
  try {
    const flow = path.join(CATALOG_DIR, "flows", "zz-probe-thread.yaml");
    await writeFile(
      flow,
      [
        "appId: com.rakazo.app",
        "---",
        "- runFlow: ../subflows/open-thread.yaml",
        "- scrollUntilVisible:",
        "    element:",
        "      id: file-attachment-card",
        "    direction: UP",
        "    timeout: 25000",
        "    optional: true",
        "- waitForAnimationToEnd:",
        "    timeout: 3000",
        "",
      ].join("\\n"),
    );
    await runProcess(
      "maestro",
      [
        "--udid",
        udid,
        "test",
        "--no-ansi",
        ...Object.entries(env).flatMap(([key, value]) => ["-e", `${key}=${value}`]),
        flow,
      ],
      process.env,
    );
  } catch (_error) {
    // The dump below still shows where the probe ended.
  }
  await dumpHierarchy(udid, path.join(outDir, "hierarchy-thread-probe.json"));
}
'''
marker = "\nasync function captureSections("
if marker not in t:
    raise SystemExit("hierarchy patch: captureSections marker missing")
t = t.replace(marker, fn + marker, 1)
path.write_text(t)
print("hierarchy dump added")
