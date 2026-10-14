#!/usr/bin/env bash
# 本地构建未签名 IPA（需要 macOS + Xcode）
# 用法: ./build_ipa_local.sh [Release|Debug]
set -euo pipefail

CONFIG="${1:-Release}"
SCHEME="IPATemplate"
APP_NAME="IPATemplate"

cd "$(dirname "$0")"

echo "==> 准备 AppIcon（从 base64 解码）"
ICON_DIR="IPATemplate/Assets.xcassets/AppIcon.appiconset"
if [ -f "$ICON_DIR/icon_1024.b64" ]; then
  python3 -c "import base64;open('$ICON_DIR/icon_1024.png','wb').write(base64.b64decode(open('$ICON_DIR/icon_1024.b64','rb').read()))"
  echo "    icon_1024.png 已解码"
elif [ -f "$ICON_DIR/icon_1024.png" ]; then
  echo "    icon_1024.png 已存在"
else
  echo "    未找到图标，用 make_icon.py 生成占位图标"
  python3 make_icon.py
fi

echo "==> 检查依赖"
command -v xcodebuild >/dev/null || { echo "需要 Xcode 命令行工具: xcode-select --install"; exit 1; }
command -v xcodegen  >/dev/null || { echo "请先安装 xcodegen: brew install xcodegen"; exit 1; }

echo "==> 生成 Xcode 工程"
xcodegen generate

echo "==> 清理旧产物"
rm -rf build Payload "${APP_NAME}-unsigned.ipa"

echo "==> 编译 (iphoneos, 不签名)"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  clean build

APP_DIR="build/Build/Products/${CONFIG}-iphoneos/${APP_NAME}.app"
[ -d "$APP_DIR" ] || { echo "找不到 $APP_DIR"; exit 1; }

echo "==> 清除签名残留"
rm -rf "$APP_DIR/_CodeSignature"
rm -f  "$APP_DIR/embedded.mobileprovision"

echo "==> 组装 Payload"
mkdir -p Payload
cp -R "$APP_DIR" Payload/
find Payload -name ".DS_Store" -delete 2>/dev/null || true
find Payload -name "__MACOSX" -type d -exec rm -rf {} + 2>/dev/null || true
BIN="Payload/${APP_NAME}.app/${APP_NAME}"
[ -f "$BIN" ] && chmod 755 "$BIN"

echo "==> 打包 IPA"
zip -qry "${APP_NAME}-unsigned.ipa" Payload
rm -rf Payload

echo ""
echo "完成: $(pwd)/${APP_NAME}-unsigned.ipa"
echo "该 IPA 未签名，请用爱思助手等工具签名后安装。"
echo ""
echo "包内结构预览:"
unzip -l "${APP_NAME}-unsigned.ipa" | head -30
