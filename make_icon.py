#!/usr/bin/env python3
"""生成 1024x1024 App 图标（纯标准库，无第三方依赖）。"""
import struct
import zlib
import math
import os

W = H = 1024
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "IPATemplate", "Assets.xcassets", "AppIcon.appiconset", "icon_1024.png")


def build_pixels():
    rows = []
    # 圆角矩形遮罩参数（iOS 会自动裁圆角，这里画满幅即可）
    corner = 0.0
    for y in range(H):
        row = bytearray()
        row.append(0)  # filter type: none
        for x in range(W):
            u = (x + 0.5) / W
            v = (y + 0.5) / H

            # 对角线渐变底色：深蓝 -> 靛紫
            t = min(1.0, max(0.0, (u * 0.55 + v * 0.45)))
            r = int(28 + (74 - 28) * t)
            g = int(44 + (52 - 44) * t)
            b = int(96 + (150 - 96) * t)

            # 中央"信息卡片"圆角矩形（亮色）
            cx, cy = 0.5, 0.47
            hw, hh = 0.235, 0.185
            rad = 0.035
            dx = abs(u - cx) - hw
            dy = abs(v - cy) - hh
            if dx < 0 and dy < 0:
                inside = True
            elif dx > 0 and dy > 0:
                qx, qy = dx - rad, dy - rad
                inside = (qx * qx + qy * qy) <= rad * rad
            else:
                inside = True
            if inside:
                r, g, b = 240, 243, 250

            # 卡片内三行"文本条"
            line_h = 0.026
            gap = 0.062
            for i, frac in enumerate((1.0, 0.72, 0.5)):
                ly = cy + (i - 1) * gap
                lw = hw * 2 * frac * 0.82
                lx0 = cx - hw + 0.028
                if abs(v - ly) < line_h / 2 and (lx0 <= u <= lx0 + lw):
                    if i == 0:
                        r, g, b = 28, 44, 96
                    else:
                        r, g, b = 140, 150, 175

            # 卡片下方一枚圆形"指示点"
            dxc, dyc = u - (cx - hw + 0.055), v - (cy + hh + 0.075)
            if dxc * dxc + dyc * dyc <= 0.026 * 0.026:
                r, g, b = 46, 204, 133

            row += bytes((r, g, b))
        rows.append(bytes(row))
    return b"".join(rows)


def write_png(path, raw):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", ihdr)
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
    return len(png)


if __name__ == "__main__":
    size = write_png(OUT, build_pixels())
    print("written:", OUT, size, "bytes")
