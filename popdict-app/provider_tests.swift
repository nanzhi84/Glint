import Foundation

// Config.swift 多协议与多厂商适配层的黑盒单测（不进 App 打包；跑法：
//   swiftc -o /tmp/popdict_prov_test Config.swift provider_tests.swift -framework Foundation && /tmp/popdict_prov_test）

@main
struct ProviderTests {
    static var failures = 0

    static func expect(_ cond: Bool, _ name: String) {
        if cond {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func approx(_ a: Double, _ b: Double, eps: Double = 1e-6) -> Bool {
        abs(a - b) < eps
    }

    static func jsonDict(_ data: Data?) -> [String: Any]? {
        guard let data = data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func main() {
        // —— 1. 协议枚举 APIFormat 契约 ——
        expect(APIFormat.openai.rawValue == "openai"
                && APIFormat.anthropic.rawValue == "anthropic"
                && APIFormat.gemini.rawValue == "gemini"
                && APIFormat.allCases.count == 3,
               "APIFormat 枚举值: openai / anthropic / gemini")

        expect(APIFormat.openai.displayName.contains("OpenAI")
                && APIFormat.anthropic.displayName.contains("Anthropic")
                && APIFormat.gemini.displayName.contains("Gemini"),
               "APIFormat.displayName: 分别包含 OpenAI / Anthropic / Gemini")

        expect(!APIFormat.openai.defaultBaseURL.isEmpty
                && !APIFormat.anthropic.defaultBaseURL.isEmpty
                && !APIFormat.gemini.defaultBaseURL.isEmpty,
               "APIFormat.defaultBaseURL: 提供非空默认 BaseURL")

        expect(APIFormat.customSelectableCases == [.openai, .anthropic]
                && !APIFormat.customSelectableCases.contains(.gemini),
               "APIFormat.customSelectableCases: 自定义厂商仅开放 [.openai, .anthropic]，不含 .gemini")

        // —— 2. 流式事件枚举 StreamEvent 契约 ——
        expect(StreamEvent.ignore == .ignore
                && StreamEvent.done == .done
                && StreamEvent.delta("hi") == .delta("hi")
                && StreamEvent.delta("hi") != .delta("bye")
                && StreamEvent.error("err") == .error("err"),
               "StreamEvent Equatable: ignore / delta / done / error 相等性判定正确")

        // —— 3. Provider 构造器与旧版配置向后兼容反序列化 ——
        let defaultFmtProvider = Provider(
            name: "DefaultOpenAI",
            baseURL: "https://api.deepseek.com/v1",
            apiKey: "sk-default",
            model: "deepseek-chat",
            vision: false
        )
        expect(defaultFmtProvider.format == .openai,
               "Provider 默认构造器: 未显式传 format 时默认为 .openai")

        let legacyJSON = """
        {
            "name": "DeepSeek",
            "baseURL": "https://api.deepseek.com/v1",
            "apiKey": "sk-legacy-123",
            "model": "deepseek-chat",
            "vision": false
        }
        """.data(using: .utf8)!
        let decodedLegacy = try? JSONDecoder().decode(Provider.self, from: legacyJSON)
        expect(decodedLegacy != nil
                && decodedLegacy?.format == .openai
                && decodedLegacy?.name == "DeepSeek"
                && decodedLegacy?.baseURL == "https://api.deepseek.com/v1"
                && decodedLegacy?.apiKey == "sk-legacy-123"
                && decodedLegacy?.model == "deepseek-chat"
                && decodedLegacy?.vision == false,
               "Provider 向后兼容反序列化: 缺失 format 字段时默认解码为 .openai 并保留全部原字段")

        let geminiProvider = Provider(
            name: "Gemini",
            format: .gemini,
            baseURL: "https://generativelanguage.googleapis.com/v1beta",
            apiKey: "AIzaSyTest",
            model: "gemini-3.8-flash",
            vision: true
        )
        if let encoded = try? JSONEncoder().encode(geminiProvider),
           let roundtrip = try? JSONDecoder().decode(Provider.self, from: encoded) {
            expect(roundtrip == geminiProvider && roundtrip.format == .gemini,
                   "Provider Codable 往返序列化: 完整保留 .gemini 协议与字段")
        } else {
            expect(false, "Provider Codable 往返序列化: 完整保留 .gemini 协议与字段")
        }

        // —— 4. OpenAI 兼容请求构造 (.openai) ——
        let oaProviderV1 = Provider(
            name: "DeepSeek",
            format: .openai,
            baseURL: "https://api.deepseek.com/v1",
            apiKey: "sk-ds-key",
            model: "deepseek-chat",
            vision: false
        )
        let oaProviderSlash = Provider(
            name: "DeepSeekSlash",
            format: .openai,
            baseURL: "https://api.deepseek.com/v1/",
            apiKey: "sk-ds-key",
            model: "deepseek-chat",
            vision: false
        )
        let oaProviderDomainOnly = Provider(
            name: "DeepSeekDomain",
            format: .openai,
            baseURL: "https://api.deepseek.com",
            apiKey: "sk-ds-key",
            model: "deepseek-chat",
            vision: false
        )
        let simpleMsgs: [[String: Any]] = [
            ["role": "system", "content": "You are a translator."],
            ["role": "user", "content": "Hello"]
        ]
        let oaReq1 = oaProviderV1.buildRequest(messages: simpleMsgs, temperature: 0.2, maxTokens: 2000, stream: false)
        let oaReq2 = oaProviderSlash.buildRequest(messages: simpleMsgs, temperature: 0.2, maxTokens: 2000, stream: true)
        let oaReq3 = oaProviderDomainOnly.buildRequest(messages: simpleMsgs, temperature: 0.2, maxTokens: 2000, stream: false)

        expect(oaReq1?.url?.absoluteString == "https://api.deepseek.com/v1/chat/completions"
                && oaReq2?.url?.absoluteString == "https://api.deepseek.com/v1/chat/completions"
                && oaReq3?.url?.absoluteString == "https://api.deepseek.com/v1/chat/completions",
               "OpenAI buildRequest URL: 兼容 /v1、/v1/ 与纯域名自动补齐 /v1/chat/completions")

        expect(oaReq1?.httpMethod == "POST"
                && oaReq1?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ds-key"
                && oaReq1?.value(forHTTPHeaderField: "Content-Type") == "application/json"
                && oaReq2?.value(forHTTPHeaderField: "Accept") == "text/event-stream",
               "OpenAI buildRequest Header: Authorization Bearer、Content-Type 与流式 Accept 头正确")

        let oaBody = jsonDict(oaReq1?.httpBody)
        let oaBodyMsgs = oaBody?["messages"] as? [[String: Any]]
        expect(oaBody?["model"] as? String == "deepseek-chat"
                && oaBodyMsgs?.count == 2
                && approx((oaBody?["temperature"] as? Double) ?? -1, 0.2)
                && oaBody?["stream"] as? Bool == false
                && oaBody?["max_completion_tokens"] as? Int == 2000,
               "OpenAI buildRequest Body: 包含 model、messages、temperature、stream、max_completion_tokens")

        // —— 5. Anthropic 兼容请求构造 (.anthropic) ——
        let antProviderRoot = Provider(
            name: "ClaudeRoot",
            format: .anthropic,
            baseURL: "https://api.anthropic.com",
            apiKey: "sk-ant-key",
            model: "claude-sonnet-4-5",
            vision: true
        )
        let antProviderV1 = Provider(
            name: "ClaudeV1",
            format: .anthropic,
            baseURL: "https://api.anthropic.com/v1",
            apiKey: "sk-ant-key",
            model: "claude-sonnet-4-5",
            vision: true
        )
        let antProviderFull = Provider(
            name: "ClaudeFull",
            format: .anthropic,
            baseURL: "https://api.anthropic.com/v1/messages",
            apiKey: "sk-ant-key",
            model: "claude-sonnet-4-5",
            vision: true
        )
        let multimodalMsgs: [[String: Any]] = [
            ["role": "system", "content": "System prompt here"],
            ["role": "user", "content": [
                ["type": "image_url", "image_url": ["url": "data:image/png;base64,iVBORw0KGgo="]],
                ["type": "text", "text": "What is in this screenshot?"]
            ]],
            ["role": "assistant", "content": "It is a button."],
            ["role": "user", "content": "Explain further"]
        ]
        let antReq1 = antProviderRoot.buildRequest(messages: multimodalMsgs, temperature: 0.4, maxTokens: 1500, stream: true)
        let antReq2 = antProviderV1.buildRequest(messages: multimodalMsgs, temperature: 0.4, maxTokens: 1500, stream: false)
        let antReq3 = antProviderFull.buildRequest(messages: multimodalMsgs, temperature: 0.4, maxTokens: 1500, stream: false)

        expect(antReq1?.url?.absoluteString == "https://api.anthropic.com/v1/messages"
                && antReq2?.url?.absoluteString == "https://api.anthropic.com/v1/messages"
                && antReq3?.url?.absoluteString == "https://api.anthropic.com/v1/messages",
               "Anthropic buildRequest URL: 兼容纯域名、/v1 与已带 /messages 路径")

        expect(antReq1?.httpMethod == "POST"
                && antReq1?.value(forHTTPHeaderField: "x-api-key") == "sk-ant-key"
                && antReq1?.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01"
                && antReq1?.value(forHTTPHeaderField: "Content-Type") == "application/json",
               "Anthropic buildRequest Header: 包含 x-api-key、anthropic-version 与 Content-Type")

        let antBody = jsonDict(antReq1?.httpBody)
        let antMsgs = antBody?["messages"] as? [[String: Any]]
        let hasSystemInAntMsgs = antMsgs?.contains(where: { ($0["role"] as? String) == "system" }) ?? true
        let firstAntContent = antMsgs?.first?["content"] as? [[String: Any]]
        let antImgBlock = firstAntContent?.first(where: { ($0["type"] as? String) == "image" })
        let antImgSource = antImgBlock?["source"] as? [String: Any]
        let antTxtBlock = firstAntContent?.first(where: { ($0["type"] as? String) == "text" })

        expect(antBody?["system"] as? String == "System prompt here"
                && !hasSystemInAntMsgs
                && antMsgs?.count == 3
                && antImgSource?["type"] as? String == "base64"
                && antImgSource?["media_type"] as? String == "image/png"
                && antImgSource?["data"] as? String == "iVBORw0KGgo="
                && antTxtBlock?["text"] as? String == "What is in this screenshot?"
                && antBody?["max_tokens"] as? Int == 1500
                && approx((antBody?["temperature"] as? Double) ?? -1, 0.4)
                && antBody?["stream"] as? Bool == true,
               "Anthropic buildRequest Body: 提取顶层 system、转换 base64 图片块并携带 max_tokens/temperature/stream")

        // —— 6. Gemini 兼容请求构造 (.gemini) ——
        let gemReqNonStream = geminiProvider.buildRequest(messages: multimodalMsgs, temperature: 0.3, maxTokens: 2048, stream: false)
        let gemReqStream = geminiProvider.buildRequest(messages: multimodalMsgs, temperature: 0.3, maxTokens: 2048, stream: true)

        expect(gemReqNonStream?.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent"
                && gemReqStream?.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:streamGenerateContent?alt=sse",
               "Gemini buildRequest URL: 非流式 :generateContent 与流式 :streamGenerateContent?alt=sse 正确")

        expect(gemReqNonStream?.httpMethod == "POST"
                && gemReqNonStream?.value(forHTTPHeaderField: "x-goog-api-key") == "AIzaSyTest"
                && gemReqNonStream?.value(forHTTPHeaderField: "Content-Type") == "application/json",
               "Gemini buildRequest Header: 包含 x-goog-api-key 与 Content-Type")

        let gemBody = jsonDict(gemReqNonStream?.httpBody)
        let sysInst = gemBody?["systemInstruction"] as? [String: Any]
        let sysParts = sysInst?["parts"] as? [[String: Any]]
        let gemContents = gemBody?["contents"] as? [[String: Any]]
        let firstGemParts = gemContents?.first?["parts"] as? [[String: Any]]
        let gemInlineData = firstGemParts?.compactMap({ $0["inline_data"] as? [String: Any] }).first
        let gemTextPart = firstGemParts?.compactMap({ $0["text"] as? String }).first
        let secondGemRole = (gemContents != nil && gemContents!.count > 1) ? (gemContents![1]["role"] as? String) : nil
        let genConfig = gemBody?["generationConfig"] as? [String: Any]

        expect(sysParts?.first?["text"] as? String == "System prompt here"
                && gemContents?.count == 3
                && gemContents?.first?["role"] as? String == "user"
                && secondGemRole == "model"
                && gemInlineData?["mime_type"] as? String == "image/png"
                && gemInlineData?["data"] as? String == "iVBORw0KGgo="
                && gemTextPart == "What is in this screenshot?"
                && approx((genConfig?["temperature"] as? Double) ?? -1, 0.3)
                && genConfig?["maxOutputTokens"] as? Int == 2048,
               "Gemini buildRequest Body: systemInstruction、assistant->model 角色映射、inline_data 与 generationConfig 正确")

        // —— 6b. Vertex AI 端点 URL 与双认证头自适应 (.gemini) ——
        let vertexExpress = Provider(
            name: "Vertex AI",
            format: .gemini,
            baseURL: "https://aiplatform.googleapis.com/v1/publishers/google",
            apiKey: "AQ.VertexExpressKey123",
            model: "gemini-3.8-flash",
            vision: true
        )
        let vertexNonStream = vertexExpress.buildRequest(messages: simpleMsgs, temperature: 0.2, maxTokens: 1024, stream: false)
        let vertexStream = vertexExpress.buildRequest(messages: simpleMsgs, temperature: 0.2, maxTokens: 1024, stream: true)

        expect(vertexNonStream?.url?.absoluteString == "https://aiplatform.googleapis.com/v1/publishers/google/models/gemini-3.8-flash:generateContent"
                && vertexStream?.url?.absoluteString == "https://aiplatform.googleapis.com/v1/publishers/google/models/gemini-3.8-flash:streamGenerateContent?alt=sse",
               "Vertex AI buildRequest URL (Express 标准端点): 非流式 :generateContent 与流式 :streamGenerateContent?alt=sse 正确")

        let vertexRoot = Provider(
            name: "VertexRoot",
            format: .gemini,
            baseURL: "https://aiplatform.googleapis.com",
            apiKey: "AQ.VertexExpressKey123",
            model: "gemini-3.8-flash",
            vision: true
        )
        let vertexV1 = Provider(
            name: "VertexV1",
            format: .gemini,
            baseURL: "https://aiplatform.googleapis.com/v1",
            apiKey: "AQ.VertexExpressKey123",
            model: "gemini-3.8-flash",
            vision: true
        )
        let vertexRegional = Provider(
            name: "VertexRegional",
            format: .gemini,
            baseURL: "https://us-central1-aiplatform.googleapis.com/v1/projects/my-proj/locations/us-central1",
            apiKey: "ya29.a0AfH6SM_token",
            model: "gemini-3.8-flash",
            vision: true
        )
        let vertexBearer = Provider(
            name: "VertexBearer",
            format: .gemini,
            baseURL: "https://aiplatform.googleapis.com/v1/publishers/google",
            apiKey: "Bearer custom-oauth-token",
            model: "gemini-3.8-flash",
            vision: true
        )
        let vRootReq = vertexRoot.buildRequest(messages: simpleMsgs, temperature: 0.2, maxTokens: 1024, stream: false)
        let vV1Req = vertexV1.buildRequest(messages: simpleMsgs, temperature: 0.2, maxTokens: 1024, stream: false)
        let vRegReq = vertexRegional.buildRequest(messages: simpleMsgs, temperature: 0.2, maxTokens: 1024, stream: false)
        let vBearerReq = vertexBearer.buildRequest(messages: simpleMsgs, temperature: 0.2, maxTokens: 1024, stream: false)

        expect(vRootReq?.url?.absoluteString == "https://aiplatform.googleapis.com/v1/publishers/google/models/gemini-3.8-flash:generateContent"
                && vV1Req?.url?.absoluteString == "https://aiplatform.googleapis.com/v1/publishers/google/models/gemini-3.8-flash:generateContent"
                && vRegReq?.url?.absoluteString == "https://us-central1-aiplatform.googleapis.com/v1/projects/my-proj/locations/us-central1/publishers/google/models/gemini-3.8-flash:generateContent",
               "Vertex AI buildRequest URL 自适应: 简写根域名、/v1 与 GCP 项目区域端点自动补齐 /publishers/google")

        expect(vertexNonStream?.value(forHTTPHeaderField: "x-goog-api-key") == "AQ.VertexExpressKey123"
                && vertexNonStream?.value(forHTTPHeaderField: "Authorization") == nil
                && vRegReq?.value(forHTTPHeaderField: "Authorization") == "Bearer ya29.a0AfH6SM_token"
                && vRegReq?.value(forHTTPHeaderField: "x-goog-api-key") == nil
                && vBearerReq?.value(forHTTPHeaderField: "Authorization") == "Bearer custom-oauth-token"
                && vBearerReq?.value(forHTTPHeaderField: "x-goog-api-key") == nil,
               "Vertex AI buildRequest 认证头自适应: 普通 Key 走 x-goog-api-key，ya29./Bearer 令牌走 Authorization Bearer")

        let vertexFullGenerateURL = Provider(
            name: "VertexFull",
            format: .gemini,
            baseURL: "https://aiplatform.googleapis.com/v1/publishers/google/models/gemini-3.8-flash:generateContent",
            apiKey: "AQ.VertexExpressKey123",
            model: "gemini-3.8-flash",
            vision: true
        )
        let vertexProjectModelURL = Provider(
            name: "VertexProjectModel",
            format: .gemini,
            baseURL: "https://aiplatform.googleapis.com/v1/projects/optical-highway-512808-a9/locations/global/publishers/google/models/gemini-3.8-flash",
            apiKey: "AQ.VertexExpressKey123",
            model: "gemini-3.8-flash",
            vision: true
        )
        let vFullNonStream = vertexFullGenerateURL.buildRequest(messages: simpleMsgs, temperature: 0.2, maxTokens: 1024, stream: false)
        let vFullStream = vertexFullGenerateURL.buildRequest(messages: simpleMsgs, temperature: 0.2, maxTokens: 1024, stream: true)
        let vProjNonStream = vertexProjectModelURL.buildRequest(messages: simpleMsgs, temperature: 0.2, maxTokens: 1024, stream: false)
        let vProjStream = vertexProjectModelURL.buildRequest(messages: simpleMsgs, temperature: 0.2, maxTokens: 1024, stream: true)

        expect(vFullNonStream?.url?.absoluteString == "https://aiplatform.googleapis.com/v1/publishers/google/models/gemini-3.8-flash:generateContent"
                && vFullStream?.url?.absoluteString == "https://aiplatform.googleapis.com/v1/publishers/google/models/gemini-3.8-flash:streamGenerateContent?alt=sse"
                && vProjNonStream?.url?.absoluteString == "https://aiplatform.googleapis.com/v1/projects/optical-highway-512808-a9/locations/global/publishers/google/models/gemini-3.8-flash:generateContent"
                && vProjStream?.url?.absoluteString == "https://aiplatform.googleapis.com/v1/projects/optical-highway-512808-a9/locations/global/publishers/google/models/gemini-3.8-flash:streamGenerateContent?alt=sse",
               "Gemini/Vertex AI BaseURL 去重归一化: 已包含 /models/{model} 或 :generateContent 时不重复拼接")

        // —— 7. 非流式响应解析 parseResponse(data:) ——
        let oaRespData = """
        {"choices":[{"message":{"role":"assistant","content":"OpenAI 翻译结果"}}]}
        """.data(using: .utf8)!
        expect(oaProviderV1.parseResponse(data: oaRespData) == "OpenAI 翻译结果",
               "parseResponse (.openai): 解析 choices[0].message.content")

        let antRespData = """
        {"content":[{"type":"thinking","thinking":"先思考一下"},{"type":"text","text":"Anthropic "},{"type":"text","text":"翻译结果"}]}
        """.data(using: .utf8)!
        expect(antProviderV1.parseResponse(data: antRespData) == "Anthropic 翻译结果",
               "parseResponse (.anthropic): 提取并拼接 type == text 的文本块")

        let gemRespData = """
        {"candidates":[{"content":{"role":"model","parts":[{"text":"内部思考过程","thought":true},{"text":"Gemini "},{"text":"翻译结果"}]}}]}
        """.data(using: .utf8)!
        expect(geminiProvider.parseResponse(data: gemRespData) == "Gemini 翻译结果",
               "parseResponse (.gemini): 跳过 thought:true 分片并拼接正文 parts")

        // —— 8. 流式单行解析 parseStreamLine(_:) ——
        expect(oaProviderV1.parseStreamLine("") == .ignore
                && oaProviderV1.parseStreamLine("   ") == .ignore
                && oaProviderV1.parseStreamLine(": keep-alive") == .ignore
                && antProviderV1.parseStreamLine("event: content_block_delta") == .ignore,
               "parseStreamLine 通用规则: 空行、注释行与 event: 行返回 .ignore")

        expect(oaProviderV1.parseStreamLine("data: [DONE]") == .done
                && oaProviderV1.parseStreamLine(#"data: {"choices":[{"delta":{"content":"你好"}}]}"#) == .delta("你好")
                && oaProviderV1.parseStreamLine(#"data: {"choices":[{"delta":{"role":"assistant"}}]}"#) == .ignore,
               "parseStreamLine (.openai): 解析 delta.content 与 [DONE]")

        expect(antProviderV1.parseStreamLine(#"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"世界"}}"#) == .delta("世界")
                && antProviderV1.parseStreamLine(#"data: {"type":"message_stop"}"#) == .done
                && antProviderV1.parseStreamLine(#"data: {"type":"error","error":{"message":"invalid api key"}}"#) == .error("invalid api key"),
               "parseStreamLine (.anthropic): 解析 text_delta、message_stop 与 error 事件")

        expect(geminiProvider.parseStreamLine(#"data: {"candidates":[{"content":{"parts":[{"text":"思考中","thought":true}]}}]}"#) == .ignore
                && geminiProvider.parseStreamLine(#"data: {"candidates":[{"content":{"parts":[{"text":"流式分片"}]}}]}"#) == .delta("流式分片")
                && geminiProvider.parseStreamLine(#"data: {"candidates":[{"content":{"parts":[{"text":"思考中","thought":true},{"text":"可见分片"}]}}]}"#) == .delta("可见分片"),
               "parseStreamLine (.gemini): 解析 candidates parts 文本并自动跳过 thought:true 分片")

        // —— 9. 官方预置厂商与旧配置平滑合并 ——
        let presets = AppConfig.presets()
        let presetDS = presets.first(where: { $0.name == "DeepSeek" })
        let presetGem = presets.first(where: { $0.name == "Gemini" })
        let presetVertex = presets.first(where: { $0.name == "Vertex AI" })
        let presetMiMo = presets.first(where: { $0.name == "MiMo" })

        expect(presetDS != nil && presetDS?.format == .openai
                && presetGem != nil && presetGem?.format == .gemini && presetGem?.model == "gemini-3.8-flash" && presetGem?.vision == true
                && presetVertex != nil
                && presetVertex?.format == .gemini
                && presetVertex?.baseURL == "https://aiplatform.googleapis.com/v1/publishers/google"
                && presetVertex?.model == "gemini-3.8-flash"
                && presetVertex?.vision == true
                && presetMiMo != nil && presetMiMo?.format == .openai && presetMiMo?.vision == true,
               "AppConfig.presets(): 包含官方四大厂商 DeepSeek、Gemini、Vertex AI、MiMo 且协议与默认配置正确")

        let existingUserProviders = [
            Provider(name: "DeepSeek", format: .openai, baseURL: "https://api.deepseek.com/v1", apiKey: "sk-user-ds", model: "deepseek-reasoner", vision: false),
            Provider(name: "MiMo", format: .openai, baseURL: "https://api.xiaomimimo.com/v1", apiKey: "sk-user-mimo", model: "mimo-custom", vision: true)
        ]
        let merged = AppConfig.mergeOfficialPresets(into: existingUserProviders)
        let mergedDS = merged.first(where: { $0.name == "DeepSeek" })
        let mergedMiMo = merged.first(where: { $0.name == "MiMo" })
        let mergedGem = merged.first(where: { $0.name == "Gemini" })
        let mergedVertex = merged.first(where: { $0.name == "Vertex AI" })

        expect(mergedDS?.apiKey == "sk-user-ds"
                && mergedDS?.model == "deepseek-reasoner"
                && mergedMiMo?.apiKey == "sk-user-mimo"
                && mergedMiMo?.model == "mimo-custom"
                && mergedGem != nil
                && mergedGem?.format == .gemini
                && mergedGem?.model == "gemini-3.8-flash"
                && mergedGem?.vision == true
                && mergedVertex != nil
                && mergedVertex?.format == .gemini
                && mergedVertex?.baseURL == "https://aiplatform.googleapis.com/v1/publishers/google"
                && mergedVertex?.model == "gemini-3.8-flash"
                && mergedVertex?.vision == true,
               "AppConfig.mergeOfficialPresets(into:): 保留用户既有 DeepSeek/MiMo 自定义 key 与 model，自动补齐缺失的官方厂商 Gemini 与 Vertex AI")

        expect(AppConfig.isOfficialPreset("DeepSeek")
                && AppConfig.isOfficialPreset("gemini")
                && AppConfig.isOfficialPreset("Vertex AI")
                && AppConfig.isOfficialPreset("MIMO")
                && !AppConfig.isOfficialPreset("MyCustomOpenAI")
                && !AppConfig.isOfficialPreset("新厂商")
                && AppConfig.officialPreset(named: "Gemini")?.format == .gemini
                && AppConfig.officialPreset(named: "Gemini")?.baseURL == "https://generativelanguage.googleapis.com/v1beta"
                && AppConfig.officialPreset(named: "Vertex AI")?.format == .gemini
                && AppConfig.officialPreset(named: "Vertex AI")?.baseURL == "https://aiplatform.googleapis.com/v1/publishers/google"
                && AppConfig.officialPreset(named: "MyCustomOpenAI") == nil,
               "AppConfig.isOfficialPreset / officialPreset(named:): 准确识别官方四大预设并返回内置固定 format/baseURL，自定义厂商返回 false/nil")

        // —— 10. 开机启动管理器 LaunchAtLogin 契约 ——
        let tmpPlistPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("com.yoryon.popdict.test.\(UUID().uuidString).plist")
        let fakeExecPath = "/Applications/popdict.app/Contents/MacOS/popdict"
        defer { try? FileManager.default.removeItem(atPath: tmpPlistPath) }

        let enableOK = LaunchAtLogin.setEnabled(true, plistPath: tmpPlistPath, executablePath: fakeExecPath)
        let enabledAfterWrite = LaunchAtLogin.isEnabled(plistPath: tmpPlistPath)
        let plistDict = NSDictionary(contentsOfFile: tmpPlistPath) as? [String: Any]
        let plistLabel = plistDict?["Label"] as? String
        let plistRunAtLoad = plistDict?["RunAtLoad"] as? Bool
        let plistArgs = plistDict?["ProgramArguments"] as? [String]

        let disableOK = LaunchAtLogin.setEnabled(false, plistPath: tmpPlistPath, executablePath: fakeExecPath)
        let enabledAfterRemove = LaunchAtLogin.isEnabled(plistPath: tmpPlistPath)

        expect(enableOK
                && enabledAfterWrite
                && plistLabel == "com.yoryon.popdict"
                && plistRunAtLoad == true
                && plistArgs == [fakeExecPath]
                && disableOK
                && !enabledAfterRemove
                && !FileManager.default.fileExists(atPath: tmpPlistPath),
               "LaunchAtLogin.setEnabled / isEnabled: 写入包含 Label/RunAtLoad/ProgramArguments 的 LaunchAgent plist 并支持清理")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
        exit(failures == 0 ? 0 : 1)
    }
}
