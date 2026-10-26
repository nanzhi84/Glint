# 构建、安装与验收手册 (Build & Verify Runbook)

本手册规范 [popdict-app/](../../popdict-app) 的本地编译、签名校验、安装替换与自验收流程。

## 1. 几何、Markdown 与多协议适配单测验收

通过 `yoryon-harness run` 在隔离沙盒中编译并执行测试：

```bash
# 几何定位测试
yoryon-harness run geometry-tests -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/geo_test" popdict-app/Geometry.swift popdict-app/geometry_tests.swift -framework AppKit && "$HARNESS_WORK_DIR/geo_test"'

# Markdown 渲染测试
yoryon-harness run markdown-tests -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/md_test" popdict-app/Markdown.swift popdict-app/markdown_tests.swift -framework AppKit && "$HARNESS_WORK_DIR/md_test"'

# 多协议与多厂商适配测试
yoryon-harness run provider-tests -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/prov_test" popdict-app/Config.swift popdict-app/provider_tests.swift -framework Foundation && "$HARNESS_WORK_DIR/prov_test"'
```

## 2. 应用打包与安装替换

每次修改 [popdict-app/](../../popdict-app) 下的 Swift 源码后，必须按顺序执行：

```bash
# 1. 编译 Universal 二进制并打包 popdict.app 与 popdict.dmg
cd popdict-app && bash build.sh

# 2. 若 /Applications/popdict.app 已存在，停止运行中的进程、替换安装并重启
pkill -x popdict || true
rm -rf /Applications/popdict.app
cp -R popdict.app /Applications/popdict.app
codesign --verify --deep --strict --verbose=2 /Applications/popdict.app
open /Applications/popdict.app
```

## 3. UI 渲染与进程自验收

- **本地 UI 自测（无需联网）**：
  ```bash
  POPDICT_UITEST=translate /Applications/popdict.app/Contents/MacOS/popdict
  ```
- **运行状态与日志核查**：
  - 检查进程存活：`pgrep -fl /Applications/popdict.app/Contents/MacOS/popdict`
  - 检查运行日志：`tail -n 50 ~/.config/popdict/popdict.log`
