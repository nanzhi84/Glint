# ADR-0002: 多协议适配层（OpenAI / Anthropic / Gemini Compatible）与官方四厂商直选

- **状态 (Status)**：Accepted
- **日期 (Date)**：2026-10-26

## 1. 背景与上下文 (Context)

`Glint` 早期仅支持单一的 OpenAI `/v1/chat/completions` 接口协议（预置 DeepSeek 与小米 MiMo）。随着模型生态演进，用户需要：
1. 在设置中**直接选择官方支持的四大厂商**：**DeepSeek**、**Gemini**、**Vertex AI**、**MiMo**。
2. 支持接入任意 **OpenAI Compatible**、**Anthropic Compatible**（`/v1/messages`）或 **Gemini / Vertex AI Compatible**（`:generateContent` 与 `:streamGenerateContent?alt=sse`）的官方或代理服务。
3. 平滑兼容已有 `~/.config/glint/config.json`（保留用户已配置的 DeepSeek / MiMo API Key 与自定义模型名，并自动补齐新增的官方预置厂商 `Gemini` 与 `Vertex AI`）。

## 2. 决策方案 (Decision)

1. **协议枚举 `APIFormat` 与 `Provider` 协议适配层（[glint-app/Config.swift](../../glint-app/Config.swift)）**：
   - 新增 `APIFormat`（`openai`、`anthropic`、`gemini`），在 `Provider` 的 `Codable` 反序列化中对缺失 `format` 字段的旧版配置默认回退为 `.openai`。
   - 将三种协议的请求构造（`buildRequest`）、非流式响应解析（`parseResponse`）与 SSE 流式增量解析（`parseStreamLine`）内聚到 `Provider` 中：
     - **OpenAI Compatible (`.openai`)**：`POST {baseURL}/chat/completions`，`Authorization: Bearer <key>`，支持 OpenAI 多模态 `image_url` Data URL 与 `choices[0].delta.content` 流式解析。
     - **Anthropic Compatible (`.anthropic`)**：`POST {baseURL}/messages`，`x-api-key: <key>` + `anthropic-version: 2023-06-01`，自动将 `system` 角色消息提升为顶层 `"system"` 字段，并将 Data URL 图片转换为 Anthropic `source: {type: "base64", media_type, data}` 格式，解析 `content_block_delta`（`text_delta`）与 `message_stop`。
     - **Gemini & Vertex AI Compatible (`.gemini`)**：`POST {baseURL}/models/{model}:generateContent`（非流式）与 `:streamGenerateContent?alt=sse`（SSE 流式）：
       - **Vertex AI URL 自适应**：当 `baseURL` 指向 `aiplatform.googleapis.com`（含 Express Mode 全局端点 `https://aiplatform.googleapis.com/v1/publishers/google`、`https://aiplatform.googleapis.com` 或标准项目区域端点 `https://{region}-aiplatform.googleapis.com/v1/projects/{project}/locations/{location}`）且尚未包含 `/publishers/` 时，自动补齐 `/publishers/google`，拼接 `/models/{model}:generateContent` 或 `:streamGenerateContent?alt=sse`。若用户直接粘贴了已含 `/models/{model}` 甚至带 `:generateContent` / `:streamGenerateContent` 后缀的完整 URL，自动剥离方法后缀并按 `stream` 参数拼接对应动作，不重复追加 `/models/`。
       - **Vertex AI / Gemini 双认证头自适应**：普通 API Key（如 AI Studio `AIza...` 或 Vertex AI Express Mode Key `AQ...`）发送 `x-goog-api-key: <key>`；若填入 GCP OAuth2 Access Token（以 `ya29.` 或 `Bearer ` 开头）则自动发送 `Authorization: Bearer <token>`。
       - 自动将 `system` 消息提升为 `systemInstruction`，将 `"assistant"` 角色映射为 `"model"`，将 Data URL 图片转换为 `inline_data`，并过滤 `thought: true` 思考分片。
2. **官方四大厂商预置与平滑合并（`AppConfig.presets()` / `mergeOfficialPresets`）**：
   - 官方预置包含：
     - `DeepSeek`（`format: .openai`，`https://api.deepseek.com/v1`，默认模型 `deepseek-chat`）
     - `Gemini`（`format: .gemini`，`https://generativelanguage.googleapis.com/v1beta`，默认模型 `gemini-3.8-flash`，`vision: true`）
     - `Vertex AI`（`format: .gemini`，`https://aiplatform.googleapis.com/v1/publishers/google`，默认模型 `gemini-3.8-flash`，`vision: true`）
     - `MiMo`（`format: .openai`，`https://api.xiaomimimo.com/v1`，默认模型 `mimo-v2-pro`，`vision: true`）
   - 启动加载既有 `config.json` 时，通过 `mergeOfficialPresets` 自动保留用户既有厂商配置并补齐缺失的官方预置厂商。
3. **偏好设置窗口、品牌图标与开机自启（[glint-app/Settings.swift](../../glint-app/Settings.swift)、[glint-app/Config.swift](../../glint-app/Config.swift)、[glint-app/main.swift](../../glint-app/main.swift)）**：
   - 菜单栏图标仅保留「设置…」与「退出」。
   - 偏好设置窗口顶部采用 macOS 原生工具栏图标样式 Tab 栏，包含：
     1. **「基础」**：提供「在开机时启动」复选框（通过 `LaunchAtLogin` 管理 `~/Library/LaunchAgents/com.yoryon.glint.plist` 与 `SMAppService`）。
     2. **「权限」**：展示辅助功能与屏幕录制权限状态及快捷跳转设置按钮。
     3. **「服务商」**：下拉菜单在 **Vertex AI**、**Gemini**、**DeepSeek**、**MiMo** 前置展示官方彩色品牌 Logo；选中官方预设平台时隐藏 `名字`、`接口格式`、`Base URL` 与 `删除此厂商`，仅在新增/编辑自定义厂商时展示（且自定义厂商「接口格式」仅提供 `OpenAI 兼容` 与 `Anthropic 兼容`）。

## 3. 影响与后果 (Consequences)

- **正面收益**：
  - 翻译（非流式）、解释与多轮追问（SSE 流式）、截图看图（多模态 Base64 图片）三大核心能力在 OpenAI、Anthropic、Gemini 三套协议下完全打通。
  - 既有用户的 `~/.config/glint/config.json` 零损升级，无需重新输入已有的 DeepSeek / MiMo Key。
- **边界约束**：
  - `Config.swift` 保持纯 `Foundation` 依赖，便于通过 [glint-app/provider_tests.swift](../../glint-app/provider_tests.swift) 独立编译执行黑盒协议单测。
