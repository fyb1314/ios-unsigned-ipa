#!/usr/bin/env python3
"""工程自检：文件齐全性 + YAML/JSON 合法性 + Swift 基础检查。"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))

REQUIRED = [
    ".github/workflows/build-ipa.yml",
    "project.yml",
    "README.md",
    "build_ipa_local.sh",
    "IPATemplate/IPATemplateApp.swift",
    "IPATemplate/ContentView.swift",
    # 签名工具改造后新增的模块（原来是设备信息页的 DeviceInfoModel / InfoRow，已移除）
    "IPATemplate/SignView.swift",
    "IPATemplate/InspectView.swift",
    "IPATemplate/SettingsView.swift",
    "IPATemplate/Inspector.swift",
    "IPATemplate/ZipReader.swift",
    "IPATemplate/Backend.swift",
    "IPATemplate/Theme.swift",
    "IPATemplate/Components.swift",
    "IPATemplate/Assets.xcassets/Contents.json",
    "IPATemplate/Assets.xcassets/AppIcon.appiconset/Contents.json",
    "IPATemplate/Assets.xcassets/AppIcon.appiconset/icon_1024.png",
]

errors = []
warnings = []


def ok(msg):
    print(f"  [OK]   {msg}")


def err(msg):
    errors.append(msg)
    print(f"  [FAIL] {msg}")


def warn(msg):
    warnings.append(msg)
    print(f"  [WARN] {msg}")


print("== 1. 文件齐全性 ==")
for rel in REQUIRED:
    p = os.path.join(ROOT, rel)
    if os.path.isfile(p) and os.path.getsize(p) > 0:
        ok(f"{rel}  ({os.path.getsize(p)} B)")
    else:
        err(f"缺失或为空: {rel}")

print("\n== 2. JSON 合法性 ==")
for rel in [
    "IPATemplate/Assets.xcassets/Contents.json",
    "IPATemplate/Assets.xcassets/AppIcon.appiconset/Contents.json",
]:
    p = os.path.join(ROOT, rel)
    try:
        with open(p, "rb") as f:
            json.load(f)
        ok(f"{rel} 解析通过")
    except Exception as e:
        err(f"{rel} JSON 错误: {e}")

print("\n== 3. YAML 合法性（缩进/结构） ==")
p = os.path.join(ROOT, ".github/workflows/build-ipa.yml")
with open(p, "r", encoding="utf-8") as f:
    yml = f.read()

try:
    import yaml  # type: ignore
    with open(p, "r", encoding="utf-8") as f:
        doc = yaml.safe_load(f)
    ok("PyYAML 解析通过")
    jobs = doc.get("jobs", {})
    steps = jobs.get("build", {}).get("steps", [])
    ok(f"jobs.build.steps 数量 = {len(steps)}")
    for s in steps:
        if "name" in s:
            print(f"         - {s['name']}")
    if "on" not in doc and True not in doc:
        err("缺少 on: 触发器")
    else:
        ok("存在 on: 触发器")
except ImportError:
    warn("未安装 PyYAML，改用规则检查")
    if "\t" in yml:
        err("YAML 含 Tab 缩进（YAML 不允许）")
    else:
        ok("无 Tab 缩进")
    for key in ["name:", "on:", "jobs:", "runs-on:", "steps:", "- name:", "uses:"]:
        if key in yml:
            ok(f"含关键字段 {key!r}")
        else:
            err(f"缺少关键字段 {key!r}")

print("\n== 4. workflow 关键命令检查 ==")
must_have = [
    "xcodegen generate",
    "CODE_SIGNING_ALLOWED=NO",
    "CODE_SIGNING_REQUIRED=NO",
    "-sdk iphoneos",
    "_CodeSignature",
    "embedded.mobileprovision",
    "zip -qry IPATemplate-unsigned.ipa Payload",
    "actions/upload-artifact@v4",
]
for m in must_have:
    if m in yml:
        ok(f"包含 {m!r}")
    else:
        err(f"缺少 {m!r}")

print("\n== 5. Swift 源码基础检查 ==")
# 动态扫描，别写死文件名 —— 之前写死导致删掉 DeviceInfoModel/InfoRow 后这里直接崩溃
_src_dir = os.path.join(ROOT, "IPATemplate")
swift_files = sorted(
    "IPATemplate/" + f for f in os.listdir(_src_dir) if f.endswith(".swift")
)
for rel in swift_files:
    p = os.path.join(ROOT, rel)
    src = open(p, "r", encoding="utf-8").read()
    if "@main" in src and rel.endswith("IPATemplateApp.swift"):
        ok(f"{rel} 含 @main 入口")
    if src.count("{") != src.count("}"):
        err(f"{rel} 花括号不匹配: {{={src.count('{')} }}={src.count('}')}")
    else:
        ok(f"{rel} 花括号配对 ({src.count('{')} 对)")
    if src.count("(") != src.count(")"):
        err(f"{rel} 圆括号不匹配: (={src.count('(')} )={src.count(')')}")
    else:
        ok(f"{rel} 圆括号配对")
    if "import SwiftUI" not in src and "import UIKit" not in src and "import Foundation" not in src:
        warn(f"{rel} 无 import 语句")
    # 禁止使用 iOS 16+ only 的 NavigationStack（部署目标 15.0）
    if "NavigationStack" in src:
        err(f"{rel} 使用了 NavigationStack（需要 iOS 16，部署目标是 15.0）")
    else:
        ok(f"{rel} 未使用 iOS16+ 专属 API")

print("\n== 6. project.yml 检查 ==")
p = os.path.join(ROOT, "project.yml")
yml2 = open(p, "r", encoding="utf-8").read()
for key in [
    "name: IPATemplate",
    "type: application",
    "platform: iOS",
    'deploymentTarget: "15.0"',
    "PRODUCT_BUNDLE_IDENTIFIER: dev.ipa.toolbox",
    'CODE_SIGNING_ALLOWED: "NO"',
    "GENERATE_INFOPLIST_FILE",
    "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon",
]:
    if key in yml2:
        ok(f"含 {key!r}")
    else:
        err(f"缺少 {key!r}")

print("\n== 7. PNG 图标检查 ==")
import struct
p = os.path.join(ROOT, "IPATemplate/Assets.xcassets/AppIcon.appiconset/icon_1024.png")
d = open(p, "rb").read()
if d[:8] != b"\x89PNG\r\n\x1a\n":
    err("PNG 签名错误")
else:
    w, h, bd, ct = struct.unpack(">IIBB", d[16:26])
    if (w, h) == (1024, 1024):
        ok(f"尺寸 1024x1024")
    else:
        err(f"尺寸应为 1024x1024，实际 {w}x{h}")
    if ct == 2:
        ok("colortype=2 (真彩色，无 Alpha，符合 App Store 要求)")
    elif ct == 6:
        warn("colortype=6 带 Alpha，部分构建会警告")
    else:
        warn(f"colortype={ct}")

print("\n" + "=" * 56)
if errors:
    print(f"结果: {len(errors)} 个错误, {len(warnings)} 个警告")
    for e in errors:
        print("  FAIL:", e)
    sys.exit(1)
print(f"结果: 全部通过（{len(warnings)} 个警告）")
for w in warnings:
    print("  WARN:", w)
