<div align="center">

<img src="images/logo.svg" width="116" height="116" alt="Glint Logo">

# Glint

**划词即译 · 划词即解 · 截图即解 —— 原生丝滑的 macOS 桌面 AI 助手**

选中文字，光标右下角即刻浮现「翻译 / 解释」；按下 ⌃⌥E 框选屏幕任意区域，让多模态大模型看图精讲。<br>
自带 API Key **直连你选择的模型服务商**，无中间服务器、不中转、不收集任何数据。

![macOS](https://img.shields.io/badge/macOS-12.0%2B%20Universal-141413?style=flat-square&logo=apple&logoColor=FAF9F5)
![Swift](https://img.shields.io/badge/Swift-5%20%7C%20AppKit-D97757?style=flat-square&logo=swift&logoColor=white)
![Protocols](https://img.shields.io/badge/协议-OpenAI%20%7C%20Anthropic%20%7C%20Gemini-2D2D2A?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-3DA639?style=flat-square)

<br>

<a href="images/demo.mp4">
  <img src="images/demo.gif" width="760" alt="Glint 演示：1. 到处都能划词翻译 · 2. 到处都能划词解释 · 3. 到处都能 ⌃⌥E 截图解释">
</a>

</div>

## Core ideas

- **选中即出，随手即用** —— 在任意应用中用鼠标选中文字，快捷悬浮条即刻出现在光标右下角，无需手动复制或来回切换窗口。
- **跨屏框选，看图精讲** —— 按下快捷键框选屏幕任意区域，无论是报错日志、架构图、论文公式还是外文界面，都能直接交由多模态模型为您拆解，并支持在面板底部连续追问。
- **暖纸书卷风阅读体验** —— 采用柔和护眼的暖米白纸感界面与精细的富文本排版，流式输出实时呈现，浮窗随内容自然延展，让技术与长文阅读更加从容。
- **多模型协议与主流服务商支持** —— 原生兼容 OpenAI、Gemini / Vertex AI 与 Anthropic 三大主流协议，内置 DeepSeek、Gemini、Vertex AI、MiMo 官方预设，并支持自由接入任意自定义网关。
- **纯粹原生，本机直连** —— 采用纯原生 Swift 与 AppKit 构建，轻量流畅且无第三方框架负担；所有配置与密钥仅保存在本机，划词与截图内容仅在主动触发时直发您选择的模型服务商。

| 交互场景 | 触发方式 | 行为说明 |
| :--- | :--- | :--- |
| **划词翻译** | 选中文本 → 点击 **「翻译」** | 自动识别源语言并译为设置中选定的目标语言（默认简体中文） |
| **划词解释** | 选中代码/概念 → 点击 **「解释」** | 流式输出回答，并以暖纸书卷风呈现清晰排版 |
| **多轮追问** | 解释浮窗底部输入框 → 回车 | 围绕当前选中文本或截图内容继续深入提问 |
| **截图解释** | 按下 ⌃⌥E → 框选区域 | 调用多模态模型对框选画面进行看图讲解 |
| **语言与提示词** | 菜单栏图标 → **「设置… → 语言」** | 统一设置目标回答语言，支持自定义翻译与解释提示词 |

## Get started

1. **安装或源码编译**
   - **直接安装**：前往 [Releases](https://github.com/nanzhi84/Glint/releases) 下载最新安装包，将 Glint 拖入「应用程序」文件夹（首次启动请**右键点击图标 → 打开**）。
   - **源码打包**：
     ```bash
     cd glint-app && bash build.sh
     ```
2. **配置模型服务商与 API Key**
   - 点击屏幕右上角菜单栏 **Glint 图标** → **「设置…」** → **「服务商」**。
   - 在下拉框中直接选择内置服务商（[DeepSeek](https://platform.deepseek.com/) / [Gemini](https://aistudio.google.com/) / [Vertex AI](https://cloud.google.com/vertex-ai) / [MiMo](https://platform.xiaomimimo.com/)）或点击「新增自定义…」，填入 API Key 并点击 **「保存」** 即可立即生效。
3. **开启系统权限与开机自启**
   - 在 **「设置… → 权限」** 页开启 **「辅助功能」**（全局划词监听必需）与 **「屏幕录制」**（截图解释必需）。
   - 在 **「设置… → 基础」** 页可勾选 **「在开机时启动」**，并查看当前激活的服务商与快捷键概览。

## Learn more

- **工程与架构文档**：
  - [项目定位与开发红线 (PROJECTS.md)](PROJECTS.md)
  - [全局架构现状与核心数据流 (docs/architecture/overview.md)](docs/architecture/overview.md)
  - [构建、安装与自验收手册 (docs/runbooks/build-and-verify.md)](docs/runbooks/build-and-verify.md)
- **架构决策记录 (ADR)**：
  - [ADR-0001：划词气泡与浮窗固定锚定于鼠标光标右下角](docs/adr/0001-cursor-bottom-right-placement.md)
  - [ADR-0002：多协议模型适配层与四大官方服务商预设方案](docs/adr/0002-multi-provider-protocol-adapter.md)
- **版本与开源协议**：
  - [版本变更记录 (CHANGELOG.md)](CHANGELOG.md) · 基于 [MIT License](LICENSE) 开源。
