#!/usr/bin/env python3
"""Fail CI if transplanted Gradient source still contains CJK text.

The Kelivo port is intentionally English-only. Functionality may be copied
verbatim, but Chinese UI strings, comments, defaults, docs, labels, and test
fixtures must be translated to English before merge.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CJK = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")

TEXT_SUFFIXES = {
    ".arb",
    ".dart",
    ".java",
    ".json",
    ".kt",
    ".kts",
    ".md",
    ".py",
    ".sh",
    ".txt",
    ".yaml",
    ".yml",
}

SKIP_PARTS = {
    ".dart_tool",
    ".git",
    ".gradle",
    ".idea",
    "build",
}

violations: list[tuple[pathlib.Path, int, str]] = []

for path in ROOT.rglob("*"):
    if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
        continue
    if any(part in SKIP_PARTS for part in path.parts):
        continue
    rel_parts = path.relative_to(ROOT).parts
    if rel_parts and rel_parts[0] == "dependencies" and (
        "test" in rel_parts or "benchmark" in rel_parts
    ):
        continue
    if rel_parts[:4] == ("android", "app", "src", "test"):
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue

    for number, line in enumerate(text.splitlines(), 1):
        if CJK.search(line):
            violations.append((path.relative_to(ROOT), number, line.strip()))

if violations:
    print("English-only Kelivo port check failed. Translate these lines to English:")
    for path, number, line in violations[:200]:
        print(f"{path}:{number}: {line[:240]}")
    if len(violations) > 200:
        print(f"... and {len(violations) - 200} more")
    sys.exit(1)

print("English-only Kelivo port check passed.")
