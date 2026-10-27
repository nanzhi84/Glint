#!/bin/bash
# Glint 打包脚本
#   bash build.sh            -> 用 adhoc 签名(自己这台 Mac 用,够了)
#   bash build.sh "证书名"   -> 用你在钥匙串里建的自签名证书(更新不丢权限)
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

APP="Glint.app"
BUNDLE_ID="com.yoryon.glint"
MIN_OS="12.0"

# 选签名身份:命令行指定 > 固定自签名证书(更新不丢权限)> adhoc
if [ -n "$1" ]; then
    SIGN_IDENTITY="$1"
elif security find-identity -p codesigning 2>/dev/null | grep -q "Glint Self Signed"; then
    SIGN_IDENTITY="Glint Self Signed"
else
    SIGN_IDENTITY="-"
fi

echo "==> 1/5 编译 universal 二进制 (arm64 + x86_64) 与生成品牌图标 (Glint.icns)"
SRCS="main.swift Geometry.swift Markdown.swift Screenshot.swift Config.swift Settings.swift BrandLogo.swift"
swiftc $SRCS -target arm64-apple-macos${MIN_OS}  -o /tmp/glint_arm64 -swift-version 5 -framework AppKit -framework ApplicationServices -framework Carbon -O
swiftc $SRCS -target x86_64-apple-macos${MIN_OS} -o /tmp/glint_x86   -swift-version 5 -framework AppKit -framework ApplicationServices -framework Carbon -O
lipo -create -output /tmp/glint_uni /tmp/glint_arm64 /tmp/glint_x86
echo "    架构: $(lipo -archs /tmp/glint_uni)"

ICONSET_TMP="$(mktemp -d)/Glint.iconset"
ICON_GEN_SRC="$(mktemp -d)/main.swift"
cat > "$ICON_GEN_SRC" <<'SWIFT'
import Foundation
let url = URL(fileURLWithPath: CommandLine.arguments[1])
try! BrandLogo.writeIconset(to: url)
SWIFT
swiftc BrandLogo.swift "$ICON_GEN_SRC" -o /tmp/glint_icongen -framework AppKit
/tmp/glint_icongen "$ICONSET_TMP"
iconutil -c icns "$ICONSET_TMP" -o "$HERE/Glint.icns"
rm -rf "$(dirname "$ICONSET_TMP")" "$(dirname "$ICON_GEN_SRC")" /tmp/glint_icongen

echo "==> 2/5 组装 $APP"
rm -rf "$APP" Glint.dmg
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp /tmp/glint_uni "$APP/Contents/MacOS/Glint"
chmod +x "$APP/Contents/MacOS/Glint"
[ -f Glint.icns ] && cp Glint.icns "$APP/Contents/Resources/Glint.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Glint</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>Glint</string>
    <key>CFBundleDisplayName</key><string>Glint</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>${MIN_OS}</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Glint</string>
    $( [ -f Glint.icns ] && echo "<key>CFBundleIconFile</key><string>Glint.icns</string>" )
</dict>
</plist>
PLIST

echo "==> 3/5 签名 (identity: ${SIGN_IDENTITY})"
codesign --force --deep -s "${SIGN_IDENTITY}" "$APP"
codesign -dvv "$APP" 2>&1 | grep -E 'Identifier|Signature|TeamIdentifier' || true

echo "==> 4/5 制作 dmg"
DMGDIR="$(mktemp -d)"
cp -R "$APP" "$DMGDIR/"
ln -s /Applications "$DMGDIR/Applications"
cat > "$DMGDIR/安装说明.txt" <<'TXT'
Glint 划词翻译 / 解释 / 截图解释 —— 安装 3 步

1) 把左边的 Glint.app 拖到右边的「Applications」文件夹里。
2) 打开「应用程序」,右键点 Glint → 选「打开」→ 再点「打开」(只需这一次,绕过未知开发者拦截)。
   开起来后屏幕右上角菜单栏会出现 Glint 图标。
3) 首次会弹「辅助功能」授权:
   系统设置 → 隐私与安全性 → 辅助功能 → 把 Glint 的开关打开。
   (这是划词监听必需的权限,不开就不会冒泡。)

填 API Key(图形界面,无需命令行):
   点菜单栏 Glint 图标 →「设置…」→「服务商」,里面预置了 DeepSeek、Gemini、Vertex AI、MiMo 四大服务商。
   在想用的那个里填上 API Key、点保存即可。

用法:
 - 划词:任意 App 里选中一段文字 → 光标右下角冒出「翻译」「解释」→ 点它出结果。
 - 截图解释:按 ⌃⌥E(Control+Option+E)→ 框选屏幕一块 → AI 看图讲解并支持继续追问。
   首次用要再授「屏幕录制」:系统设置 → 隐私与安全性 → 屏幕录制 → 打开 Glint(授完重开一次 App)。

排查:菜单栏 Glint 图标 →「设置… → 权限」看「辅助功能」「屏幕录制」是否都已授权。
   日志在 ~/.config/glint/glint.log
TXT

rm -f Glint.dmg
hdiutil create -volname "Glint" -srcfolder "$DMGDIR" -ov -format UDZO Glint.dmg
rm -rf "$DMGDIR"

echo "==> 5/5 完成"
echo "    App: $HERE/$APP"
echo "    DMG: $HERE/Glint.dmg"
