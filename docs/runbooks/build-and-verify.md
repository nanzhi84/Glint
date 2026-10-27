# 构建、安装与验收手册 (Build & Verify Runbook)

本手册规范 [glint-app/](../../glint-app) 的本地编译、签名校验、安装替换与自验收流程。

## 1. 几何、Markdown 与多协议适配单测验收

通过 `yoryon-harness run` 在隔离沙盒中编译并执行测试：

```bash
# 几何定位测试
yoryon-harness run geometry-tests -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/geo_test" glint-app/Geometry.swift glint-app/geometry_tests.swift -framework AppKit && "$HARNESS_WORK_DIR/geo_test"'

# Markdown 渲染测试
yoryon-harness run markdown-tests -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/md_test" glint-app/Markdown.swift glint-app/markdown_tests.swift -framework AppKit && "$HARNESS_WORK_DIR/md_test"'

# 多协议与多厂商适配测试
yoryon-harness run provider-tests -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/prov_test" glint-app/Config.swift glint-app/provider_tests.swift -framework Foundation && "$HARNESS_WORK_DIR/prov_test"'
```

## 2. 应用打包与安装替换

每次修改 [glint-app/](../../glint-app) 下的 Swift 源码后，必须按顺序执行：

```bash
# 1. 编译 Universal 二进制并打包 Glint.app 与 Glint.dmg
cd glint-app && bash build.sh

# 2. 停止运行中的进程、替换安装 /Applications/Glint.app 并重启
pkill -x Glint || true
rm -rf /Applications/Glint.app
cp -R Glint.app /Applications/Glint.app
codesign --verify --deep --strict --verbose=2 /Applications/Glint.app
open /Applications/Glint.app
```

## 3. UI 渲染与进程自验收

- **本地 UI 自测（无需联网）**：
  ```bash
  GLINT_UITEST=translate /Applications/Glint.app/Contents/MacOS/Glint
  ```
- **运行状态与日志核查**：
  - 检查进程存活：`pgrep -fl /Applications/Glint.app/Contents/MacOS/Glint`
  - 检查运行日志：`tail -n 50 ~/.config/glint/glint.log`
