#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path.cwd()
UPSTREAM = Path(sys.argv[1]).resolve()
UPSTREAM_COMMIT = "86de75b75c66f2c9b9de4299069068bd18f53766"

KEEP = [
    "lib/core/gh",
    "lib/core/github",
    "lib/core/security/protected_path.dart",
    "lib/core/workspace/workspace_store.dart",
    "lib/features/workspace/github_workspace_page.dart",
]

COPY_DIRS = ["lib", "dependencies", "android", "assets", "tool"]
COPY_FILES = [
    "pubspec.yaml",
    "pubspec.lock",
    "analysis_options.yaml",
    "l10n.yaml",
]

tmp = Path("/tmp/gradient-github-keep")
if tmp.exists():
    shutil.rmtree(tmp)
tmp.mkdir(parents=True)

for rel in KEEP:
    src = ROOT / rel
    if not src.exists():
        continue
    dst = tmp / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        shutil.copytree(src, dst)
    else:
        shutil.copy2(src, dst)

for rel in COPY_DIRS:
    dst = ROOT / rel
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(UPSTREAM / rel, dst)

for rel in COPY_FILES:
    src = UPSTREAM / rel
    if src.exists():
        shutil.copy2(src, ROOT / rel)

# Restore Gradient's GitHub-only engine without restoring its old chat/settings UI.
for rel in KEEP:
    src = tmp / rel
    if not src.exists():
        continue
    dst = ROOT / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    else:
        shutil.copy2(src, dst)

# Keep Kelivo's internal Dart package name so its package:Kelivo imports remain
# byte-for-byte. Android identity and user-facing branding belong to Gradient.
old_pkg = "com.psyche.kelivo"
new_pkg = "com.dude555afk.gradient"
old_scheme = "psyche.kelivo"
new_scheme = "dude555afk.gradient"

android = ROOT / "android"
for path in android.rglob("*"):
    if not path.is_file() or path.suffix.lower() not in {
        ".kt", ".kts", ".java", ".xml", ".gradle", ".properties"
    }:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    updated = text.replace(old_pkg, new_pkg).replace(old_scheme, new_scheme)
    if updated != text:
        path.write_text(updated, encoding="utf-8")

old_kotlin = android / "app/src/main/kotlin/com/psyche/kelivo"
new_kotlin = android / "app/src/main/kotlin/com/dude555afk/gradient"
if old_kotlin.exists():
    new_kotlin.parent.mkdir(parents=True, exist_ok=True)
    if new_kotlin.exists():
        shutil.rmtree(new_kotlin)
    shutil.move(str(old_kotlin), str(new_kotlin))
    # Remove now-empty old package parents when possible.
    for parent in [
        android / "app/src/main/kotlin/com/psyche",
        android / "app/src/main/kotlin/com",
    ]:
        try:
            parent.rmdir()
        except OSError:
            pass

# User-facing Android app name.
for path in [
    android / "app/src/main/AndroidManifest.xml",
    android / "app/src/main/res/values/strings.xml",
]:
    if path.exists():
        text = path.read_text(encoding="utf-8")
        text = text.replace('android:label="Kelivo"', 'android:label="Gradient"')
        text = text.replace(">Kelivo<", ">Gradient<")
        path.write_text(text, encoding="utf-8")

# Add only the native hook required by Gradient's bundled GitHub CLI.
activity = new_kotlin / "MainActivity.kt"
if not activity.exists():
    raise SystemExit(f"Kelivo MainActivity not found after package move: {activity}")
text = activity.read_text(encoding="utf-8")
needle = "        super.configureFlutterEngine(flutterEngine)\n"
hook = """        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gradient/native",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                else -> result.notImplemented()
            }
        }
"""
if '"gradient/native"' not in text:
    if needle not in text:
        raise SystemExit("Could not locate Kelivo configureFlutterEngine hook")
    text = text.replace(needle, hook, 1)
activity.write_text(text, encoding="utf-8")

# Chinese locale resources stay structurally present, but their values become
# English. This preserves locale plumbing while meeting Gradient's English-only
# product requirement.
l10n = ROOT / "lib/l10n"
en_arb = l10n / "app_en.arb"
if en_arb.exists():
    base = json.loads(en_arb.read_text(encoding="utf-8"))
    for filename, locale in [
        ("app_zh.arb", "zh"),
        ("app_zh_Hans.arb", "zh_Hans"),
        ("app_zh_Hant.arb", "zh_Hant"),
    ]:
        target = l10n / filename
        if target.exists():
            data = dict(base)
            data["@@locale"] = locale
            target.write_text(
                json.dumps(data, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )

(ROOT / "KELIVO_UPSTREAM").write_text(
    f"Kelivo upstream commit: {UPSTREAM_COMMIT}\n"
    "Migration policy: preserve upstream behavior; only Gradient branding, "
    "GitHub-specific integration, and English localization may differ.\n",
    encoding="utf-8",
)

print("Literal Kelivo application transplant staged.")
