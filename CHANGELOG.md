# Changelog

本项目的所有重要版本变更、新特性汇总与修复记录均归档于此。

## [Unreleased]

### Added
- 初始化项目 Universal Harness 目录结构、架构全景图与工程规范。
- 新增多协议适配层（支持 `OpenAI 兼容`、`Anthropic 兼容`、`Gemini 兼容` 三种接口格式），内置官方支持 **DeepSeek**、**Gemini**（`gemini-3.8-flash`）、**Vertex AI**（`aiplatform.googleapis.com`）与 **MiMo** 四大服务商及前置彩色品牌 Logo。
- 新增「在开机时启动」（`LaunchAtLogin`）能力。

### Changed
- 精简菜单栏 🌐 下拉菜单（仅保留「设置…」与「退出」），并将偏好设置窗口升级为 macOS 原生工具栏图标样式的 **「基础」**、**「权限」**、**「服务商」** 三 Tab 布局。
- 改进划词气泡与浮窗落点定位逻辑，精确锚定于鼠标光标右下角。

### Fixed
- 修复双显示器/多显示器下触发截图解释（`⌃⌥E`）时遮罩窗口被系统单屏空间裁切与 `visibleFrame` 收缩、导致只能截取单个显示器局部区域的 Bug：改为按每块显示器独立创建全屏遮罩窗口（`CaptureWindow`），支持在任意显示器上首击直接拖选，并在截图所在显示器弹出解释浮窗。

## [1.0.0] - 2026-07-07

### Added
- 原生 macOS 菜单栏划词助手（`popdict-app`）：支持划词「🌐 翻译」与「💡 解释」（SSE 流式打字机输出 + 多轮上下文追问）。
- 完整块级 Markdown 富文本渲染（`Markdown.swift`）：支持标题、多级嵌套列表、GFM 表格、引用、任务列表及圆角底色代码块。
- 多模态「📷 截图解释」（`Screenshot.swift`）：支持 `⌃⌥E` 框选屏幕区域交由视觉模型讲解并追问。
- 多厂商配置管理 GUI（`Config.swift` / `Settings.swift`）：内置 DeepSeek 与小米 MiMo，支持自定义任意 OpenAI 兼容接口。
- 结果与会话浮窗支持自由拖拽缩放、尺寸上限记忆与随内容自适应生长。
