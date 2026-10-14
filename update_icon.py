#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
update_icon.py — 用任意图片更新 App 图标

用法: python update_icon.py 图片路径 [--size 1024]

做的事：
  1. 中心裁剪成正方形
  2. 缩放到指定尺寸（默认 1024）
  3. 去掉 Alpha 通道（App Store 要求图标不透明）
  4. 写出 icon_1024.png（本地/构建用）和 icon_1024.b64（仓库里存的 base64 文本版）

依赖: pip install pillow
"""
import argparse
import base64
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
ICON_DIR = os.path.join(ROOT, "IPATemplate", "Assets.xcassets", "AppIcon.appiconset")


def main():
    ap = argparse.ArgumentParser(description="更新 App 图标")
    ap.add_argument("image", help="源图片路径（jpg/png 等）")
    ap.add_argument("--size", type=int, default=1024, help="输出边长，默认 1024")
    args = ap.parse_args()

    try:
        from PIL import Image
    except ImportError:
        sys.exit("缺少 Pillow，请先执行: pip install pillow")

    if not os.path.isfile(args.image):
        sys.exit("找不到图片: " + args.image)

    src = Image.open(args.image)
    print("源图: %dx%d %s" % (src.width, src.height, src.mode))

    w, h = src.size
    side = min(w, h)
    left, top = (w - side) // 2, (h - side) // 2
    img = src.crop((left, top, left + side, side))
    img = img.resize((args.size, args.size), Image.LANCZOS).convert("RGB")

    os.makedirs(ICON_DIR, exist_ok=True)
    png = os.path.join(ICON_DIR, "icon_1024.png")
    img.save(png, "PNG", optimize=True)

    data = open(png, "rb").read()
    b64 = base64.b64encode(data).decode("ascii")
    lines = [b64[i:i + 76] for i in range(0, len(b64), 76)]
    with open(os.path.join(ICON_DIR, "icon_1024.b64"), "w", encoding="ascii") as f:
        f.write("\n".join(lines) + "\n")

    print("已写出: %s (%d bytes)" % (png, len(data)))
    print("已写出: %s (%d bytes)" % (os.path.join(ICON_DIR, "icon_1024.b64"),
                                    os.path.getsize(os.path.join(ICON_DIR, "icon_1024.b64"))))
    print("图标更新完成。提交后 CI 会自动用新图标构建。")


if __name__ == "__main__":
    main()
