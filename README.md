<div align="center">

# 🌐 popdict

### 划词即译 · 截图即解 · 原生丝滑的 macOS 桌面 AI 助手

选中文字,旁边立刻冒出「翻译 / 解释」;框选屏幕一块,让 AI 看着图讲给你听。<br>
自带 Key **直连你选的模型 API**,popdict 自己不设服务器、不中转、不收集。

![macOS](https://img.shields.io/badge/macOS-12%2B-000000?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-3DA639?style=flat-square)
![价格](https://img.shields.io/badge/价格-免费-success?style=flat-square)
![模型](https://img.shields.io/badge/协议-OpenAI%20%7C%20Anthropic%20%7C%20Gemini-412991?style=flat-square)

<img src="images/explain.png" width="540" alt="popdict 解释结果:流式 + 完整 Markdown(含表格、代码块)">

</div>

## ✨ 特性

- 🖱️ **选中即出结果** —— 不用复制、不用切窗口,翻译/解释精确落在光标右下角。
- 📸 **截图让 AI 看图讲解** —— 报错截图、图表、外文界面、文档,框一下就讲。
- ⚡ **流式 + 富文本** —— 逐字输出,完整 Markdown(标题 / 列表 / **表格** / 代码块 / 引用),还能带上下文追问。
- 🎛️ **多协议与官方厂商直选** —— 官方内置 **DeepSeek**、**Google Gemini**、**Google Cloud Vertex AI**、**小米 MiMo**,同时兼容任意 **OpenAI 兼容**、**Anthropic 兼容**、**Gemini 兼容**接口,在「设置 → 自定义厂商」中一键切换。
- 🪟 **原生丝滑** —— 毛玻璃浮窗,可拖拽缩放并记住大小;纯 AppKit,无 Electron、无后台全家桶。

## 🚀 上手

1. **装**:[Releases](https://github.com/nanzhi84/popdict/releases) 下载 `popdict.dmg` → 拖进「应用程序」→ 首次**右键 → 打开**。或自己编译:`cd popdict-app && bash build.sh`。
2. **配 Key**:菜单栏 🌐 →「设置…」→「服务商」→ 直接选服务商([DeepSeek](https://platform.deepseek.com/) / [Gemini](https://aistudio.google.com/) / [Vertex AI](https://cloud.google.com/vertex-ai) / [MiMo](https://platform.xiaomimimo.com/),或新增自定义 OpenAI / Anthropic 兼容服务商)→ 填 API Key → 保存(立即生效)。
3. **授权与自启**:菜单栏 🌐 →「设置…」→「权限」开启「辅助功能」与「屏幕录制」权限;在「基础」页可勾选「在开机时启动」。

## 🧩 用法

| 操作 | 怎么做 |
|------|--------|
| **翻译** | 选中文字 → 「🌐 翻译」(含中文→英文,其它→简体中文) |
| **解释** | 选中代码/概念 → 「💡 解释」(流式 + Markdown) |
| **追问** | 解释浮窗底部输入框,回车继续问 |
| **截图解释** | `⌃⌥E` 框选屏幕 → AI 看图讲解(需「屏幕录制」权限,且当前厂商勾了「支持看图」) |

## ⚙️ 模型厂商与协议适配

原生支持三种主流大模型接口协议:
- **OpenAI 兼容**(`/chat/completions`):内置 **DeepSeek**(`deepseek-chat`)与 **MiMo**(`mimo-v2-pro`,支持看图)
- **Gemini / Vertex AI 兼容**(`:generateContent` & `:streamGenerateContent?alt=sse`):内置 **Gemini**(`gemini-3.8-flash`)与 **Vertex AI**(`https://aiplatform.googleapis.com/v1/publishers/google`,支持 Express Mode API Key 与标准 GCP 项目端点 OAuth Token)
- **Anthropic 兼容**(`/v1/messages`):支持 Claude 官方及各类 Anthropic 兼容网关

偏好设置窗口采用原生工具栏图标样式,分为「**基础**」(支持开机自启)、「**权限**」与「**服务商**」(内置官方品牌图标)三个标签页,菜单栏 🌐 保持极简(仅保留「设置…」与「退出」)。配置存本机 `~/.config/popdict/config.json`。

<div align="center"><img src="images/settings.png" width="440" alt="popdict 设置窗口:下拉选择模型厂商"></div>

## 🔒 隐私

popdict 是个 **API 客户端,不是本地大模型** —— 模型在你选的厂商云端跑。你选中的文字、截到的图,**只在你触发时直接发给你自己配置的那家厂商官方接口**;API Key 只存本机,popdict 自身没有服务器,不中转、不收集、不上传任何数据。

## 📄 License

[MIT](./LICENSE) · 仓库还附了 [PopClip](https://pilotmoon.com/popclip/) 扩展和 [Hammerspoon](https://www.hammerspoon.org/) 脚本两种轻量实现(走 DeepSeek)。如果它帮到你,点个 ⭐ 就是最大的鼓励。
