#!/usr/bin/env python3
"""Harness: log real /rpc path + 500 body; InsetRow a11y; account testIDs.

Maestro flow YAML is owned by apply-e2e-flow-overlays.py — not this script.
"""
import pathlib
import sys

src = pathlib.Path(sys.argv[1])  # .../rakazo-ultimate/src

# ---------------------------------------------------------------------------
# 1) logging: matchedRoute must not collapse /rpc/threads/get → /rpc/*
# ---------------------------------------------------------------------------
hono = src / "packages/logging/src/hono.ts"
ht = hono.read_text()
old_mr = '''function matchedRoute(path: string, routePath: string): string {
  if (routePath && routePath !== "/*") return routePath;
  return path;
}'''
new_mr = '''function matchedRoute(path: string, routePath: string): string {
  // Wildcard mounts like /rpc/* hide the procedure name; keep the real path so a
  // 500 is searchable as /rpc/threads/get (and friends), not an opaque /rpc/*.
  if (routePath && routePath !== "/*" && !routePath.endsWith("/*")) return routePath;
  return path;
}'''
if "routePath.endsWith(\"/*\")" in ht or "routePath.endsWith('/*')" in ht:
    print("matchedRoute already prefers real path for /* mounts")
elif old_mr in ht:
    hono.write_text(ht.replace(old_mr, new_mr, 1))
    print("patched matchedRoute in logging/hono.ts")
else:
    raise SystemExit("matchedRoute needle missing in logging/hono.ts")

# Also stamp rpc.procedure + peek 500 body on the /rpc/* handler completion log.
# Enrich via requestLogging bindings by patching app.ts middleware.
app_ts = src / "apps/api/src/app.ts"
at = app_ts.read_text()
if 'enrichLogContext({ "rpc.procedure"' in at or "rpc.procedure" in at and "c.req.path.replace" in at:
    print("app.ts rpc.procedure enrich already present")
else:
    needle = '''  app.use("/rpc/*", async (c, next) => {
    const session = await requestSession(c.req.raw);
    const actor = session?.actor ?? null;
    const tooLarge = await limitRpcBody(c, actor !== null);
    if (tooLarge) return tooLarge;
    if (actor) {
      enrichLogContext({ "user.id": actor.userId, "space.id": actor.spaceId });
    }
    const { matched, response } = await rpc.handle(c.req.raw, {'''
    repl = '''  app.use("/rpc/*", async (c, next) => {
    const session = await requestSession(c.req.raw);
    const actor = session?.actor ?? null;
    const tooLarge = await limitRpcBody(c, actor !== null);
    if (tooLarge) return tooLarge;
    // Procedure path for logs: Hono's route is /rpc/*, which otherwise hides the name.
    const rpcProcedure = c.req.path.replace(/^\\/rpc\\/?/, "") || "*";
    enrichLogContext({ "rpc.procedure": rpcProcedure, "http.target": c.req.path });
    if (actor) {
      enrichLogContext({ "user.id": actor.userId, "space.id": actor.spaceId });
    }
    const { matched, response } = await rpc.handle(c.req.raw, {'''
    if needle not in at:
        raise SystemExit("app.ts /rpc/* middleware needle missing")
    at = at.replace(needle, repl, 1)
    # After handle, if 500, log a short body peek (ORPC message / validation text).
    needle2 = '''    if (!matched) return next();
    const reply = c.newResponse(response.body, response);
    if (requestHitDatabaseOutage())
      reply.headers.set("Retry-After", String(DATABASE_RETRY_AFTER_SECONDS));
    // A signed-in request that went through reached the database, so any outage is over.
    else if (actor && reply.status < 500) databaseOutage.succeeded();
    return reply;
  });'''
    repl2 = '''    if (!matched) return next();
    if (response.status >= 500) {
      let peek = "";
      try {
        peek = (await response.clone().text()).slice(0, 800);
      } catch {
        peek = "";
      }
      getLogger().error("rpc response 500", {
        "rpc.procedure": rpcProcedure,
        "http.target": c.req.path,
        "http.status": response.status,
        "error.message": peek || `HTTP ${response.status}`,
        "error.report": true,
      });
    }
    const reply = c.newResponse(response.body, response);
    if (requestHitDatabaseOutage())
      reply.headers.set("Retry-After", String(DATABASE_RETRY_AFTER_SECONDS));
    // A signed-in request that went through reached the database, so any outage is over.
    else if (actor && reply.status < 500) databaseOutage.succeeded();
    return reply;
  });'''
    if needle2 not in at:
        raise SystemExit("app.ts rpc reply needle missing")
    if "rpc response 500" not in at:
        at = at.replace(needle2, repl2, 1)
        print("patched app.ts rpc 500 body peek")
    app_ts.write_text(at)
    print("patched app.ts rpc.procedure enrich")

# ---------------------------------------------------------------------------
# 2) InsetRow a11y: hide decorative leading; stable accessibilityLabel
#    Real VoiceOver issue: SF Symbol / icon names leak into the row label.
# ---------------------------------------------------------------------------
inset = src / "apps/mobile/components/sand/inset-group.tsx"
it = inset.read_text()
if (
    "Decorative glyphs must not join the row" in it
    or "const spoken =" in it
):
    print("InsetRow leading a11y already patched")
else:
    old_lead = "      {leading}\n      <View style={styles.titleColumn}>"
    new_lead = (
        "      {leading ? (\n"
        "        // Decorative glyphs must not join the row's spoken / Maestro label\n"
        "        // (SF Symbol names otherwise become \"key Vault\", etc.).\n"
        '        <View accessibilityElementsHidden importantForAccessibility="no-hide-descendants">\n'
        "          {leading}\n"
        "        </View>\n"
        "      ) : null}\n"
        "      <View style={styles.titleColumn}>"
    )
    if old_lead not in it:
        raise SystemExit("InsetRow leading needle missing")
    it = it.replace(old_lead, new_lead, 1)

    # Pressable path: set an explicit accessibilityLabel from title (+ detail).
    old_press = '''  return (
    <Pressable
      {...props}
      android_ripple={androidRipple()}
      style={({ pressed }) => [
        styles.row,
        stacked && styles.compactRow,
        pressed && Platform.OS !== "android" && styles.pressed,
        dimmed && styles.dimmed,
      ]}
    >
      {content}
    </Pressable>
  );
}'''
    new_press = '''  const spoken =
    props.accessibilityLabel ??
    [title, detail].filter((part): part is string => Boolean(part && String(part).trim())).join(", ");
  return (
    <Pressable
      {...props}
      accessibilityLabel={spoken}
      android_ripple={androidRipple()}
      style={({ pressed }) => [
        styles.row,
        stacked && styles.compactRow,
        pressed && Platform.OS !== "android" && styles.pressed,
        dimmed && styles.dimmed,
      ]}
    >
      {content}
    </Pressable>
  );
}'''
    if old_press not in it:
        raise SystemExit("InsetRow Pressable needle missing")
    it = it.replace(old_press, new_press, 1)
    # Non-pressable View path: same spoken label when none provided.
    old_view = '''      <View
        accessible={props.accessible}
        accessibilityActions={props.accessibilityActions}
        accessibilityHint={props.accessibilityHint}
        accessibilityLabel={props.accessibilityLabel}
        accessibilityRole={props.accessibilityRole}
        accessibilityState={props.accessibilityState}
        accessibilityValue={props.accessibilityValue}
        onAccessibilityAction={props.onAccessibilityAction}
        style={[styles.row, stacked && styles.compactRow, dimmed && styles.dimmed]}
      >'''
    new_view = '''      <View
        accessible={props.accessible}
        accessibilityActions={props.accessibilityActions}
        accessibilityHint={props.accessibilityHint}
        accessibilityLabel={
          props.accessibilityLabel ??
          [title, detail]
            .filter((part): part is string => Boolean(part && String(part).trim()))
            .join(", ")
        }
        accessibilityRole={props.accessibilityRole}
        accessibilityState={props.accessibilityState}
        accessibilityValue={props.accessibilityValue}
        onAccessibilityAction={props.onAccessibilityAction}
        style={[styles.row, stacked && styles.compactRow, dimmed && styles.dimmed]}
      >'''
    if old_view not in it:
        raise SystemExit("InsetRow View a11y needle missing")
    it = it.replace(old_view, new_view, 1)
    inset.write_text(it)
    print("patched InsetRow leading a11y + accessibilityLabel")

# ---------------------------------------------------------------------------
# 3) Account hub testIDs for Maestro
# ---------------------------------------------------------------------------
account = src / "apps/mobile/app/(settings)/account.tsx"
ac = account.read_text()
if 'testID="settings-account-hub"' in ac:
    print("account testIDs already present")
else:
    # ScrollView gets a hub id
    old_sv = '''      <ScrollView
        style={sideInsets}
        contentContainerStyle={[styles.content, stacked && styles.compactContent]}
        contentInsetAdjustmentBehavior="automatic"
      >'''
    new_sv = '''      <ScrollView
        testID="settings-account-hub"
        style={sideInsets}
        contentContainerStyle={[styles.content, stacked && styles.compactContent]}
        contentInsetAdjustmentBehavior="automatic"
      >'''
    if old_sv not in ac:
        raise SystemExit("account ScrollView needle missing")
    ac = ac.replace(old_sv, new_sv, 1)

    old_profile = '''          <SettingsRow
            key="profile"
            accessibilityRole="button"
            chevron="right"
            detail={me?.email && account.label !== me.email ? me.email : undefined}
            disabled={signingOut}'''
    new_profile = '''          <SettingsRow
            key="profile"
            testID="settings-row-profile"
            accessibilityRole="button"
            chevron="right"
            detail={me?.email && account.label !== me.email ? me.email : undefined}
            disabled={signingOut}'''
    if old_profile not in ac:
        raise SystemExit("account profile SettingsRow needle missing")
    ac = ac.replace(old_profile, new_profile, 1)

    # settingsLink helper — add testID from href when string
    old_link = '''  const settingsLink = ({ title, href, icon: glyph }: SettingsLink) => (
    <SettingsRow
      key={typeof href === "string" ? href : href.pathname}
      accessibilityRole="button"
      chevron="right"
      disabled={signingOut}
      leading={icon(glyph)}'''
    new_link = '''  const settingsLink = ({ title, href, icon: glyph }: SettingsLink) => (
    <SettingsRow
      key={typeof href === "string" ? href : href.pathname}
      testID={
        typeof href === "string"
          ? `settings-row-${href.replace(/^\\//, "").replace(/\\//g, "-")}`
          : undefined
      }
      accessibilityRole="button"
      chevron="right"
      disabled={signingOut}
      leading={icon(glyph)}'''
    if old_link not in ac:
        raise SystemExit("account settingsLink needle missing")
    ac = ac.replace(old_link, new_link, 1)
    account.write_text(ac)
    print("patched account.tsx testIDs")

# Maestro flow YAML (settings/thread/sign-in) is owned by
# apply-e2e-flow-overlays.py — never needle-rewrite those files from this script.
print("patch-rpc-log-a11y-scroll done (code only; flows via overlays)")
