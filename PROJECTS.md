# PROJECTS.md

## 1. 项目定位

`popdict` 是一款纯原生 AppKit（Swift 5）编写的 macOS 菜单栏 AI 划词与截图助手（最低支持 macOS 12.0，Universal Binary `arm64 + x86_64`）。核心能力包括：
- **划词即译 / 即解**：全局监听鼠标划词，在光标右下角弹出「🌐 翻译」「💡 解释」气泡，支持流式 Markdown 富文本渲染与多轮上下文追问。
- **截图解释**：通过全局热键 `⌃⌥E` 框选屏幕区域，调用多模态大模型看图讲解并支持继续追问。
- **自带 Key 直连**：支持配置任意 OpenAI 兼容（`/chat/completions`）模型厂商，配置持久化于本机 `~/.config/popdict/config.json`，无中间服务器。

## 2. 仓库范围与命名约定

- **主工程目录**：[popdict-app/](popdict-app) 为唯一主力维护的原生 macOS 应用源码目录（直接通过 `swiftc` 编译打包，无 `.xcodeproj` 依赖）。
- **附属轻量实现**：根目录下的 [popdict.lua](popdict.lua)（Hammerspoon 脚本）与 [DeepSeek-Translate.popclipext/](DeepSeek-Translate.popclipext)（PopClip 扩展）为早期独立轻量实现，除非用户明确指定，日常功能迭代仅修改 [popdict-app/](popdict-app)。
- **Bundle 与日志标识**：应用 Bundle Identifier 固定为 `com.yoryon.popdict`，自签名证书名称优先匹配 `PopDict Self Signed`（避免重装丢失 macOS 辅助功能与屏幕录制授权），运行日志固定写入 `~/.config/popdict/popdict.log`。

## 3. 项目特异身份红线

- **语言红线**：始终用中文回复 `nanzhi`。只有在用户明确要求其他语言，或代码、命令、日志、文件内容需要原样保留时，才使用非中文片段。
- **构建产物同步红线**：每次修改 `popdict` 的应用源码后，都必须更新本机 App，运行 `cd popdict-app && bash build.sh` 生成最新 `popdict.app` 与 `popdict.dmg`。
- **本机安装替换红线**：如果 `/Applications/popdict.app` 已存在，且用户没有明确要求只改源码，则必须停止正在运行的 `popdict`、替换 `/Applications/popdict.app`、再重新打开。
- **自验收红线**：每次更新 App 后都要自己验收。至少确认编译/打包通过、安装版签名可验证、进程已重新启动；涉及 UI 的改动还要尽量做可执行的 UI/日志验收。
