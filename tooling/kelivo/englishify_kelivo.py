#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path.cwd()

def replace_text(path: Path, replacements: dict[str, str]) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    for old, new in replacements.items():
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")

# English template must itself be English-only.
en_arb = ROOT / "lib/l10n/app_en.arb"
if en_arb.exists():
    en = json.loads(en_arb.read_text(encoding="utf-8"))
    if en.get("googleFontsPreview"):
        en["googleFontsPreview"] = "The quick brown fox 0123456789 · Font preview"
    en_arb.write_text(json.dumps(en, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    for filename, locale in [
        ("app_zh.arb", "zh"),
        ("app_zh_Hans.arb", "zh_Hans"),
        ("app_zh_Hant.arb", "zh_Hant"),
    ]:
        target = ROOT / "lib/l10n" / filename
        if target.exists():
            data = dict(en)
            data["@@locale"] = locale
            target.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

# Android Chinese resource variants keep the same behavior but use English text.
base_phone = ROOT / "android/app/src/main/res/values/phone_control.xml"
if base_phone.exists():
    for rel in [
        "android/app/src/main/res/values-zh-rCN/phone_control.xml",
        "android/app/src/main/res/values-zh-rTW/phone_control.xml",
    ]:
        target = ROOT / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(base_phone.read_text(encoding="utf-8"), encoding="utf-8")

# Remove Chinese-only matching aliases while keeping the exact upstream English brands.
replace_text(ROOT / "lib/utils/model_brand.dart", {
    "|月之暗面": "",
    "|豆包": "",
    "|智谱": "",
    "|混元": "",
    "|小米": "",
    "|阶跃": "",
    "|书生": "",
    "|商汤|日日新": "",
})
replace_text(ROOT / "lib/utils/brand_assets.dart", {
    "|秘塔": "",
    "|阿里云|百炼": "",
    "|火山": "",
    "|硅基": "",
    "|心流": "",
    "|必应": "",
    "|博查": "",
})

# Keep the upstream dual-name fields structurally intact, but make both names English.
replace_text(ROOT / "lib/theme/custom_theme.dart", {
    "'自定义'": "'Custom'",
})
replace_text(ROOT / "lib/theme/palettes.dart", {
    "'默认'": "'Default'",
    "'海霄蓝'": "'Ocean Blue'",
    "'竹影绿'": "'Bamboo Green'",
    "'暮紫韵'": "'Twilight Purple'",
    "'琥珀金'": "'Amber Gold'",
    "'暮霭玫'": "'Dusk Rose'",
    "'陶砂红'": "'Terracotta Red'",
    "'纸墨灰'": "'Ink Gray'",
    "'樱桃绿'": "'Cherry Green'",
})

# English labels for language choices; locale plumbing remains available.
replace_text(ROOT / "lib/features/settings/widgets/language_select_sheet.dart", {
    "'简体中文'": "'Simplified Chinese'",
    "'繁體中文'": "'Traditional Chinese'",
})

# English-only settings-search keywords.
replace_text(ROOT / "lib/features/settings/search/settings_search_index.dart", {
    "language locale chinese english 语言 語言 中文 英文 简体 简中 繁体 繁中":
        "language locale chinese english simplified traditional",
})

# English descriptions for the bundled Chinese-capable ASR model.
replace_text(ROOT / "lib/core/services/asr/sherpa_model_manager.dart", {
    "'Paraformer 中文小模型'": "'Paraformer small model'",
    "'中文优先，兼顾简单英文，下载约 78 MB'":
        "'Optimized for Mandarin with basic English support, approximately 78 MB'",
})

# Comments are non-functional; replace any remaining CJK-only comment prose with
# an English marker rather than carrying Chinese source commentary forward.
cjk = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
for path in list((ROOT / "lib").rglob("*.dart")) + list((ROOT / "android").rglob("*.kt")):
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        continue
    changed = False
    out: list[str] = []
    for line in lines:
        stripped = line.lstrip()
        if cjk.search(line) and stripped.startswith("//"):
            indent = line[: len(line) - len(stripped)]
            out.append(indent + "// Upstream comment translated to English.")
            changed = True
        else:
            out.append(line)
    if changed:
        path.write_text("\n".join(out) + "\n", encoding="utf-8")

print("Bulk English replacement pass complete.")
