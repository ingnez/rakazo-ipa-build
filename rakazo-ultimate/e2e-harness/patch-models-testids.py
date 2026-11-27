#!/usr/bin/env python3
"""Stable testIDs on the Models page (code-only, idempotent).

The page title/section names are locale-dependent (the fork hard-codes 日常帮助 / 场景模型
next to lingui English), so Maestro must not match their text. Wrapping a child in a plain
View keeps the content container's child count, so the 28pt gap between groups is unchanged.
"""
import pathlib
import sys

src = pathlib.Path(sys.argv[1])
page = src / "apps/mobile/app/(settings)/models.tsx"
t = page.read_text()
if 'testID="settings-models-screen"' in t:
    print("models testIDs already present")
    raise SystemExit(0)

def swap(text: str, old: str, new: str, what: str) -> str:
    if old not in text:
        raise SystemExit(f"models.tsx needle missing: {what}")
    return text.replace(old, new, 1)

t = swap(
    t,
    'import { ActivityIndicator, ScrollView, StyleSheet, Text } from "react-native";',
    'import { ActivityIndicator, ScrollView, StyleSheet, Text, View } from "react-native";',
    "react-native import",
)
t = swap(
    t,
    "      <ScrollView\n        style={sideInsets}\n        contentContainerStyle={styles.content}",
    '      <ScrollView\n        testID="settings-models-screen"\n        style={sideInsets}\n        contentContainerStyle={styles.content}',
    "ScrollView",
)
t = swap(
    t,
    '<Text accessibilityRole="alert" style={styles.error}>',
    '<Text accessibilityRole="alert" testID="settings-models-error" style={styles.error}>',
    "error text",
)
t = swap(
    t,
    '''            <ModelRoleSettings
              {...shared}
              modelRole="main"
              title="日常帮助"
              defaultLabel={t`Choose a model`}
              onChanged={() => void load()}
            />
            <ScenarioModelSlots
              catalog={catalog}
              credentials={credentials}
              openPicker={shared.openPicker}
            />''',
    '''            <View testID="settings-models-main">
              <ModelRoleSettings
                {...shared}
                modelRole="main"
                title="日常帮助"
                defaultLabel={t`Choose a model`}
                onChanged={() => void load()}
              />
            </View>
            <View testID="settings-models-scenarios">
              <ScenarioModelSlots
                catalog={catalog}
                credentials={credentials}
                openPicker={shared.openPicker}
              />
            </View>''',
    "main + scenarios",
)
page.write_text(t)
print("patched models.tsx testIDs")
