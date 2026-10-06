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


# Broader second pass for CJK that lives outside generated localization files.
literal_replacements = {
  "中文搜索 基准消息": "Search benchmark message",
  "|列|value|": "|column|value|",
  "|中文|English|": "|language|English|",
  "Streaming plain text 中文 English": "Streaming plain text English",
  "|index|中文|value|": "|index|text|value|",
  "|$index|行|value-$index|": "|$index|row|value-$index|",
  "%搜索%": "%search%",
  "%中文搜索%": "%english search%",
  "yyyy年M月d日 HH:mm:ss": "yyyy-MM-dd HH:mm:ss",
  "LLM排行榜": "LLM Rankings",
  "Aa字": "Aa",
  "代码": "Code",
  "晨间简报": "Morning brief",
  "每天": "Daily",
  "下次：明天 08:00": "Next: tomorrow 08:00",
  "结果已准备": "Result ready",
  "本地离线模型": "Local offline model",
  "本機離線模型": "Local offline model",
  "本地模型": "Local model",
  "本機模型": "Local model",
  "系统语音识别": "System speech recognition",
  "系統語音辨識": "System speech recognition",
  "系统": "System",
  "系統": "System",
  "DashScope 实时识别": "DashScope real-time recognition",
  "DashScope 即時辨識": "DashScope real-time recognition",
  "火山引擎语音识别": "Volcengine speech recognition",
  "火山引擎語音辨識": "Volcengine speech recognition",
  "火山引擎": "Volcengine",
  "MiMo 语音识别": "MiMo speech recognition",
  "MiMo 語音辨識": "MiMo speech recognition",
  "阶跃星辰语音识别": "StepFun speech recognition",
  "階躍星辰語音辨識": "StepFun speech recognition",
  "阶跃星辰": "StepFun",
  "階躍星辰": "StepFun",
  "日本語": "Japanese",
  "清空翻译": "Clear translation",
  "并发": "concurrency",
  "稍后": "later",
  "重试": "retry",
  "访问量过大": "too many requests",
  "繁忙": "busy",
  "限流": "rate limit",
  "超时": "timeout",
  "余额": "balance",
  "不足": "insufficient",
  "额度": "quota",
  "欠费": "billing",
  "未实名": "verification required",
  "随想AI中转站": "Suixiang AI Relay",
  "随想ai中转站": "suixiang ai relay",
  "官网：": "Website:",
  "SenseVoice int8 多语模型": "SenseVoice int8 multilingual model",
  "支持中文、英文、粤语、日语和韩语，下载约 166 MB": "Supports Mandarin, English, Cantonese, Japanese and Korean, approximately 166 MB",
  "Zipformer 中英 Mobile": "Zipformer Chinese-English Mobile",
  "中英双语流式识别，下载约 347 MB": "Chinese-English streaming recognition, approximately 347 MB",
  "模型文件不完整，请重新下载": "Model files are incomplete. Please download them again.",
  "这是用户最近的一些对话标题和摘要，你可以参考这些内容了解用户偏好和关注点": "These are some recent conversation titles and summaries. Use them as context for the user's preferences and interests.",
  "随想": "suixiang",
  "月之暗面": "moonshot",
  "智谱": "zhipu"
}

for path in list((ROOT / "lib").rglob("*.dart")) + list((ROOT / "tool").rglob("*.dart")):
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    original = text

    for old, new in literal_replacements.items():
        text = text.replace(old, new)

    # Collapse simple Chinese/English ternaries to the existing English branch.
    ternary = re.compile(
        r"""(?:zh|isZh|isChinese)\s*\?\s*(['"])(?P<cjk>.*?)\1\s*:\s*(['"])(?P<english>.*?)\3""",
        re.DOTALL,
    )
    def keep_english(match):
        if cjk.search(match.group("cjk")):
            return repr(match.group("english"))
        return match.group(0)
    text = ternary.sub(keep_english, text)

    cleaned = []
    for line in text.splitlines():
        # Keep English search aliases and drop Chinese-only keyword aliases.
        if "keywords:" in line and cjk.search(line):
            line = re.sub(r"[\u3400-\u9fff\uf900-\ufaff]+", " ", line)
            line = re.sub(r" {2,}", " ", line)

        # Translate inline comments without touching executable code.
        if "//" in line:
            code, comment = line.split("//", 1)
            if cjk.search(comment):
                line = code.rstrip() + " // Upstream comment translated to English."

        # Debug/benchmark fixtures are not runtime logic. Keep them English-only.
        rel = str(path.relative_to(ROOT))
        if cjk.search(line) and (
            rel.startswith("tool/")
            or "/test/" in rel
            or "debug_" in rel
            or "benchmark" in rel
        ):
            line = re.sub(r"[\u3400-\u9fff\uf900-\ufaff]+", " English ", line)
            line = re.sub(r" {2,}", " ", line)
        cleaned.append(line)

    text = "\n".join(cleaned) + ("\n" if original.endswith("\n") else "")
    if text != original:
        path.write_text(text, encoding="utf-8")

# Targeted production strings that are not dual-language branches.
targeted = {
    "lib/features/settings/pages/log_viewer_page.dart": {
        "RegExp(r'(打印|列印)$')": "RegExp(r'(Print)$')",
    },
    "lib/core/providers/settings_provider.dart": {
        "r'kimi|moonshot|月之暗面'": "r'kimi|moonshot'",
        "r'zhipu|智谱|glm'": "r'zhipu|glm'",
    },
    "lib/core/models/backup.dart": {
        "完全覆盖：清空本地后恢复": "Full overwrite: clear local data before restore",
        "增量合并：智能去重": "Incremental merge with deduplication",
    },
}
for rel, replacements in targeted.items():
    replace_text(ROOT / rel, replacements)

print("Second English replacement pass complete.")

print("Bulk English replacement pass complete.")
)": "RegExp(r'(Print)
    },
    "lib/core/providers/settings_provider.dart": {
        "r'kimi|moonshot|月之暗面'": "r'kimi|moonshot'",
        "r'zhipu|智谱|glm'": "r'zhipu|glm'",
    },
    "lib/core/models/backup.dart": {
        "完全覆盖：清空本地后恢复": "Full overwrite: clear local data before restore",
        "增量合并：智能去重": "Incremental merge with deduplication",
    },
}
for rel, replacements in targeted.items():
    replace_text(ROOT / rel, replacements)

print("Second English replacement pass complete.")

print("Bulk English replacement pass complete.")
)",
    },
    "lib/core/providers/settings_provider.dart": {
        "r'kimi|moonshot|月之暗面'": "r'kimi|moonshot'",
        "r'zhipu|智谱|glm'": "r'zhipu|glm'",
    },
    "lib/core/models/backup.dart": {
        "完全覆盖：清空本地后恢复": "Full overwrite: clear local data before restore",
        "增量合并：智能去重": "Incremental merge with deduplication",
    },
}
for rel, replacements in targeted.items():
    replace_text(ROOT / rel, replacements)

print("Second English replacement pass complete.")

print("Bulk English replacement pass complete.")
