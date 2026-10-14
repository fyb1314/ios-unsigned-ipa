#!/usr/bin/env python3
"""
模拟 workflow 的打包步骤，验证最终 IPA 结构合规。
构造一个仿真的 Release-iphoneos/IPATemplate.app（含 Info.plist、
arm64 Mach-O 可执行、Frameworks 符号链接、_CodeSignature 残留、__MACOSX 垃圾），
然后按 workflow 逻辑打包，逐项断言。
"""
import os
import plistlib
import shutil
import struct
import sys
import tempfile
import zipfile

BASE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(BASE, "_packtest")

MACHO_ARM64 = struct.pack("<I", 0xFEEDFACF) + b"\x0c\x00\x00\x01" + b"\x00" * 24


def make_mock_app(app_dir):
    os.makedirs(app_dir, exist_ok=True)
    os.makedirs(os.path.join(app_dir, "Frameworks"), exist_ok=True)
    os.makedirs(os.path.join(app_dir, "_CodeSignature"), exist_ok=True)

    # Mach-O 可执行
    exe = os.path.join(app_dir, "IPATemplate")
    with open(exe, "wb") as f:
        f.write(MACHO_ARM64)

    # Info.plist（二进制格式，模拟 Xcode 产物）
    info = {
        "CFBundleExecutable": "IPATemplate",
        "CFBundleIdentifier": "dev.ipa.toolbox",
        "CFBundleName": "IPATemplate",
        "CFBundleDisplayName": "偶尔的PIA工具",
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "1",
        "CFBundlePackageType": "APPL",
        "MinimumOSVersion": "15.0",
        "UIRequiredDeviceCapabilities": ["arm64"],
    }
    with open(os.path.join(app_dir, "Info.plist"), "wb") as f:
        plistlib.dump(info, f, fmt=plistlib.FMT_BINARY)

    # PkgInfo
    with open(os.path.join(app_dir, "PkgInfo"), "w") as f:
        f.write("APPL????")

    # 签名残留（模拟 CODE_SIGNING_ALLOWED=NO 未清干净的情况）
    with open(os.path.join(app_dir, "_CodeSignature", "CodeResources"), "w") as f:
        f.write("<plist></plist>")
    with open(os.path.join(app_dir, "embedded.mobileprovision"), "wb") as f:
        f.write(b"fake-provision")

    # 资源
    with open(os.path.join(app_dir, "Assets.car"), "wb") as f:
        f.write(b"\x00" * 64)
    with open(os.path.join(app_dir, "Frameworks", "libswiftCore.dylib"), "wb") as f:
        f.write(b"\x00" * 32)

    # 符号链接（Frameworks 里常见的相对链接）
    link = os.path.join(app_dir, "Frameworks", "libswift_Current")
    if os.path.lexists(link):
        os.remove(link)
    try:
        os.symlink("libswiftCore.dylib", link)
        return True
    except (OSError, NotImplementedError, AttributeError):
        # Windows 无权限时跳过 symlink，其余断言不受影响
        return False


def package(app_dir, out_ipa):
    """复刻 workflow 的 Package unsigned IPA 步骤。"""
    # rm -rf _CodeSignature
    shutil.rmtree(os.path.join(app_dir, "_CodeSignature"), ignore_errors=True)
    # rm -f embedded.mobileprovision
    prov = os.path.join(app_dir, "embedded.mobileprovision")
    if os.path.exists(prov):
        os.remove(prov)

    payload = os.path.join(WORK, "Payload")
    shutil.rmtree(payload, ignore_errors=True)
    os.makedirs(payload)
    shutil.copytree(app_dir, os.path.join(payload, "IPATemplate.app"),
                    symlinks=True, ignore=shutil.ignore_patterns(".DS_Store"))

    # 去 macOS 垃圾
    for root, dirs, files in os.walk(payload):
        for d in list(dirs):
            if d == "__MACOSX":
                shutil.rmtree(os.path.join(root, d), ignore_errors=True)
                dirs.remove(d)
        for fn in files:
            if fn == ".DS_Store":
                os.remove(os.path.join(root, fn))

    # chmod 755 可执行
    exe = os.path.join(payload, "IPATemplate.app", "IPATemplate")
    os.chmod(exe, 0o755)

    if os.path.exists(out_ipa):
        os.remove(out_ipa)
    with zipfile.ZipFile(out_ipa, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        # 目录项在前，保证 Payload/ 位于根
        for root, dirs, files in os.walk(payload):
            dirs.sort()
            rel = os.path.relpath(root, WORK).replace(os.sep, "/")
            if rel != ".":
                zi = zipfile.ZipInfo(rel + "/")
                zi.external_attr = (0o40755 << 16) | 0x10
                z.writestr(zi, b"")
            for fn in sorted(files):
                fp = os.path.join(root, fn)
                arc = os.path.relpath(fp, WORK).replace(os.sep, "/")
                zi = zipfile.ZipInfo(arc)
                if os.path.islink(fp):
                    zi.external_attr = (0o120777 << 16)
                    z.writestr(zi, os.readlink(fp))
                else:
                    mode = 0o755 if os.access(fp, os.X_OK) else 0o644
                    zi.external_attr = (mode << 16)
                    with open(fp, "rb") as f:
                        z.writestr(zi, f.read())
    return out_ipa


def main():
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)

    app_dir = os.path.join(WORK, "build/Build/Products/Release-iphoneos/IPATemplate.app")
    os.makedirs(os.path.dirname(app_dir), exist_ok=True)
    has_symlink = make_mock_app(app_dir)
    print(f"[setup] mock app 构造完成 (symlink={'是' if has_symlink else '否，Windows 权限受限'})")

    # 额外塞入 macOS 垃圾，验证清理逻辑
    junk = os.path.join(app_dir, "__MACOSX")
    os.makedirs(junk, exist_ok=True)
    with open(os.path.join(app_dir, ".DS_Store"), "wb") as f:
        f.write(b"\x00\x01\x00\x00")

    ipa = package(app_dir, os.path.join(WORK, "IPATemplate-unsigned.ipa"))
    print(f"[pack]  已生成 {os.path.getsize(ipa)} 字节")

    results = []
    with zipfile.ZipFile(ipa) as z:
        names = z.namelist()
        print(f"[zip]   条目数 = {len(names)}")

        # 1. Payload/ 必须在根
        results.append(("Payload/ 位于根目录", names[0] == "Payload/"))
        # 2. Info.plist 存在
        results.append(("Info.plist 存在",
                        "Payload/IPATemplate.app/Info.plist" in names))
        # 3. 可执行文件存在
        results.append(("可执行文件存在",
                        "Payload/IPATemplate.app/IPATemplate" in names))
        # 4. 无 _CodeSignature
        results.append(("无 _CodeSignature（未签名）",
                        not any("_CodeSignature" in n for n in names)))
        # 5. 无 embedded.mobileprovision
        results.append(("无 embedded.mobileprovision",
                        not any("embedded.mobileprovision" in n for n in names)))
        # 6. 无 macOS 垃圾
        results.append(("无 __MACOSX / .DS_Store",
                        not any("__MACOSX" in n or ".DS_Store" in n for n in names)))
        # 7. Mach-O magic 正确
        magic = z.read("Payload/IPATemplate.app/IPATemplate")[:4]
        results.append(("Mach-O 为 arm64 (cffaedfe)",
                        magic == bytes.fromhex("cffaedfe")))
        # 8. Info.plist 可解析且字段正确
        info = plistlib.loads(z.read("Payload/IPATemplate.app/Info.plist"))
        results.append(("Info.plist 字段正确",
                        info["CFBundleIdentifier"] == "dev.ipa.toolbox"
                        and info["CFBundleDisplayName"] == "偶尔的PIA工具"
                        and info["MinimumOSVersion"] == "15.0"))
        # 9. 可执行权限位 755
        zi = z.getinfo("Payload/IPATemplate.app/IPATemplate")
        mode = (zi.external_attr >> 16) & 0o7777
        results.append(("可执行权限位 = 755", mode == 0o755))
        # 10. 目录项带目录标志
        d_zi = z.getinfo("Payload/")
        results.append(("Payload/ 带 MS-DOS 目录标志",
                        (d_zi.external_attr & 0x10) == 0x10))
        # 11. 符号链接保留
        if has_symlink:
            l_zi = z.getinfo("Payload/IPATemplate.app/Frameworks/libswift_Current")
            lmode = (l_zi.external_attr >> 16) & 0o170000
            results.append(("符号链接保留 (S_IFLNK)",
                            lmode == 0o120000 and
                            z.read("Payload/IPATemplate.app/Frameworks/libswift_Current")
                            == b"libswiftCore.dylib"))
        else:
            print("        (跳过符号链接断言：本机无法创建 symlink)")

    print("\n== 断言结果 ==")
    failed = 0
    for label, passed in results:
        print(f"  [{'OK' if passed else 'FAIL'}] {label}")
        if not passed:
            failed += 1

    print("\n== IPA 条目预览 ==")
    with zipfile.ZipFile(ipa) as z:
        for n in z.namelist():
            print("   ", n)

    shutil.rmtree(WORK, ignore_errors=True)
    if failed:
        print(f"\n结果: {failed} 项失败")
        sys.exit(1)
    print("\n结果: 全部通过")


if __name__ == "__main__":
    main()
