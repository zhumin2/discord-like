#!/usr/bin/env python3
"""把 NotoSansSC 全量字体子集化为常用字版本。

为什么：全量 NotoSansSC 每个字重 11MB，Web 端首屏要下载 22MB 字体（两字重），
跨境网络下打开极慢。子集化后仅保留常用汉字 + 拉丁 + 标点，体积可降 70-85%。

覆盖范围（levels）：
  gb2312   —— GB2312 全部 6763 汉字 + 符号（覆盖现代中文约 99.7%）
  level1   —— GB2312 一级汉字 3755 个（最常用，体积更小，约 99.5% 覆盖）

用法：
  python scripts/fonts/subset_fonts.py level1
  python scripts/fonts/subset_fonts.py gb2312

输出覆盖 client/assets/fonts/NotoSansSC-{Regular,Bold}.ttf（原文件备份为
NotoSansSC-*.full.ttf.bak，可用 --restore 还原）。
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

FONTS_DIR = Path(__file__).resolve().parents[2] / "client" / "assets" / "fonts"
FILES = ["NotoSansSC-Regular.ttf", "NotoSansSC-Bold.ttf"]


def build_charset(level: str) -> str:
    chars = set()
    # ASCII 可打印
    chars.update(chr(c) for c in range(0x20, 0x7F))
    # 常用标点/符号（全角 + 常用中西文标点）
    chars.update("，。！？；：、“”‘’（）《》【】…—～·〈〉「」『』〔〕％＋－×÷＝")
    chars.update("°±×÷≤≥≠∞∑√∫≈×·•…‰℃℉№★☆○●◎△▲□■◇◆→←↑↓↔")
    # emoji 常用（字体里没有就自动忽略）
    chars.update("😀😄😂🥰👍🎉🔥🚀🤝✅❌🙏💯👀🤔😅😭")

    hanzi_ranges = []
    # 符号区 A1-A9
    hanzi_ranges.append((0xA1, 0xAA))
    if level == "gb2312":
        hanzi_ranges.append((0xB0, 0xF8))  # 全部汉字（一级+二级）
    elif level == "level1":
        hanzi_ranges.append((0xB0, 0xD8))  # 一级汉字（≈3755 个）
    else:
        raise SystemExit(f"未知级别: {level}（可选 gb2312 / level1）")

    for hi_start, hi_end in hanzi_ranges:
        for hi in range(hi_start, hi_end):
            for lo in range(0xA1, 0xFF):
                try:
                    chars.add(bytes([hi, lo]).decode("gb2312"))
                except UnicodeDecodeError:
                    pass
    return "".join(sorted(chars))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("level", nargs="?", default="level1", choices=["gb2312", "level1"])
    ap.add_argument("--restore", action="store_true", help="还原为全量字体")
    args = ap.parse_args()

    for name in FILES:
        src = FONTS_DIR / name
        bak = FONTS_DIR / (name + ".full.bak")
        if args.restore:
            if bak.exists():
                shutil.copy2(bak, src)
                print(f"还原 {name} ← {bak.name}")
            else:
                print(f"跳过 {name}（无备份）")
            continue
        if not src.exists():
            print(f"缺少 {src}")
            return 1
        if not bak.exists():
            shutil.copy2(src, bak)  # 首次运行备份全量字体

    if args.restore:
        return 0

    chars = build_charset(args.level)
    text_file = FONTS_DIR / ".subset-chars.txt"
    text_file.write_text(chars, encoding="utf-8")
    print(f"字符集: {args.level}，共 {len(chars)} 个字符")

    for name in FILES:
        src_full = FONTS_DIR / (name + ".full.bak")
        out = FONTS_DIR / name
        before = out.stat().st_size if out.exists() else 0
        cmd = [
            sys.executable, "-m", "fontTools.subset", str(src_full),
            f"--text-file={text_file}",
            f"--output-file={out}",
            "--layout-features=*",
            "--glyph-names",
            "--symbol-cmap",
            "--legacy-cmap",
            "--notdef-glyph",
            "--notdef-outline",
            "--recommended-glyphs",
            "--name-IDs=*",
            "--drop-tables+=DSIG",
        ]
        subprocess.run(cmd, check=True, capture_output=True)
        after = out.stat().st_size
        print(f"  {name}: {before/1048576:.1f}MB → {after/1048576:.1f}MB")

    text_file.unlink(missing_ok=True)
    print("完成。重新构建前端生效（flutter build web / windows）。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
