# Changelog

本项目的所有重要版本变更、新特性汇总与修复记录均归档于此。

## [Unreleased]

### Added
- 初始化项目 Universal Harness 目录结构、架构全景图与工程规范。
- 新增多协议适配层（支持 `OpenAI 兼容`、`Anthropic 兼容`、`Gemini 兼容` 三种接口格式），内置官方支持 **DeepSeek**、**Gemini**（`gemini-3.8-flash`）、**Vertex AI**（`aiplatform.googleapis.com`）与 **MiMo** 四大服务商及前置彩色品牌 Logo。
- 新增「在开机时启动」（`LaunchAtLogin`）能力。
- 新增「语言」偏好设置标签页：内置 11 种常用目标语言（简体中文、繁体中文、英语、日语、韩语、俄语、法语、德语、西班牙语等），翻译与解释共用 `<languages>` 语言占位符，支持用户自定义编辑翻译与解释 Prompt（删除 `<languages>` 占位符后自动按自定义固定指令生效），彻底移除旧版「单汉字即判中译英」的误判逻辑。
- 全新设计 Claude 暖纸书卷风（`#FAF9F5` + `#D97757` 赤陶星芒 `✦`）品牌矢量 Logo（`images/logo.svg`）、macOS 原生应用图标（`popdict.icns`）与 18×18 自适应明暗菜单栏矢量图标（`BrandLogo.swift`）。

### Changed
- 重写 `README.md` 门面文档（居中品牌 Logo、三合一动态演示视频 `images/demo.mp4` / `images/demo.gif`、Core ideas、Get started、Learn more），集中展示任意应用划词翻译、划词解释与 `⌃⌥E` 截图解释三大核心工作流。
- 精简菜单栏下拉菜单（仅保留「设置…」与「退出」），并将偏好设置窗口升级为 macOS 原生工具栏图标样式的 **「基础」**、**「权限」**、**「服务商」**、**「语言」** 四 Tab 布局。
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
