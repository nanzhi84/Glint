import Foundation

// ============================================================
// 配置模型与多协议适配层 (OpenAI / Anthropic / Gemini Compatible)
// 持久化到 ~/.config/glint/config.json。
// ============================================================

let kConfigDir = (("~/.config/glint" as NSString).expandingTildeInPath)
let kLogPath = kConfigDir + "/glint.log"

enum APIFormat: String, Codable, CaseIterable, Equatable {
    case openai = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"

    // 新增自定义服务商时开放全部三种协议格式
    static var customSelectableCases: [APIFormat] {
        [.openai, .anthropic, .gemini]
    }

    var displayName: String {
        switch self {
        case .openai:    return "OpenAI 兼容 (/chat/completions)"
        case .anthropic: return "Anthropic 兼容 (/v1/messages)"
        case .gemini:    return "Gemini 兼容 (/v1beta/models)"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openai:    return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini:    return "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    var defaultModelPlaceholder: String {
        switch self {
        case .openai:    return "deepseek-chat / mimo-v2.5 / gpt-4o"
        case .anthropic: return "claude-sonnet-4-5"
        case .gemini:    return "gemini-3.8-flash"
        }
    }
}

enum StreamEvent: Equatable {
    case ignore
    case delta(String)
    case done
    case error(String)
}

struct Provider: Codable, Equatable {
    var name: String
    var format: APIFormat
    var baseURL: String
    var apiKey: String
    var model: String
    var vision: Bool

    init(
        name: String,
        format: APIFormat = .openai,
        baseURL: String,
        apiKey: String,
        model: String,
        vision: Bool
    ) {
        self.name = name
        self.format = format
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.vision = vision
    }

    enum CodingKeys: String, CodingKey {
        case name, format, baseURL, apiKey, model, vision
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.baseURL = try c.decode(String.self, forKey: .baseURL)
        self.apiKey = try c.decode(String.self, forKey: .apiKey)
        self.model = try c.decode(String.self, forKey: .model)
        self.vision = try c.decode(Bool.self, forKey: .vision)
        self.format = (try? c.decode(APIFormat.self, forKey: .format)) ?? .openai
    }

    // 兼容旧属性名
    var chatURL: String { endpointURL(stream: false) }

    func endpointURL(stream: Bool = false) -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }

        let urlPath = URL(string: base)?.path ?? ""
        let hasOnlyRootPath = urlPath.isEmpty || urlPath == "/"

        switch format {
        case .openai:
            if base.hasSuffix("/chat/completions") { return base }
            if hasOnlyRootPath { return base + "/v1/chat/completions" }
            return base + "/chat/completions"

        case .anthropic:
            if base.hasSuffix("/messages") { return base }
            if hasOnlyRootPath { return base + "/v1/messages" }
            return base + "/messages"

        case .gemini:
            if base.contains("/models/") {
                var normalized = base
                if let colonRange = normalized.range(of: ":generateContent") ?? normalized.range(of: ":streamGenerateContent") {
                    normalized = String(normalized[..<colonRange.lowerBound])
                }
                return stream ? "\(normalized):streamGenerateContent?alt=sse" : "\(normalized):generateContent"
            }

            let vBase: String
            if base.contains("aiplatform.googleapis.com") {
                if hasOnlyRootPath {
                    vBase = base + "/v1/publishers/google"
                } else if !base.contains("/publishers/") {
                    vBase = base + "/publishers/google"
                } else {
                    vBase = base
                }
            } else {
                vBase = hasOnlyRootPath ? (base + "/v1beta") : base
            }
            let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelPath: String
            if cleanModel.hasPrefix("publishers/google/models/") && vBase.hasSuffix("/publishers/google") {
                modelPath = String(cleanModel.dropFirst("publishers/google/".count))
            } else if cleanModel.hasPrefix("models/") {
                modelPath = cleanModel
            } else {
                modelPath = "models/\(cleanModel)"
            }
            if stream {
                return "\(vBase)/\(modelPath):streamGenerateContent?alt=sse"
            } else {
                return "\(vBase)/\(modelPath):generateContent"
            }
        }
    }

    private static func parseDataURL(_ dataURL: String) -> (mimeType: String, base64Data: String)? {
        guard dataURL.hasPrefix("data:"),
              let commaIdx = dataURL.firstIndex(of: ",") else { return nil }
        let meta = String(dataURL[dataURL.index(dataURL.startIndex, offsetBy: 5)..<commaIdx])
        let b64 = String(dataURL[dataURL.index(after: commaIdx)...])
        let mime = meta.components(separatedBy: ";").first ?? "image/png"
        guard !b64.isEmpty else { return nil }
        return (mime.isEmpty ? "image/png" : mime, b64)
    }

    func buildRequest(
        messages: [[String: Any]],
        temperature: Double,
        maxTokens: Int,
        stream: Bool
    ) -> URLRequest? {
        guard let url = URL(string: endpointURL(stream: stream)) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if stream {
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        req.timeoutInterval = stream ? 60 : 30

        let body: [String: Any]
        switch format {
        case .openai:
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": model,
                "messages": messages,
                "temperature": temperature,
                "max_completion_tokens": maxTokens,
                "thinking": ["type": "disabled"],
                "stream": stream
            ]

        case .anthropic:
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            var systemPrompts: [String] = []
            var antMessages: [[String: Any]] = []

            for m in messages {
                guard let role = m["role"] as? String else { continue }
                if role == "system" {
                    if let s = m["content"] as? String, !s.isEmpty {
                        systemPrompts.append(s)
                    }
                    continue
                }
                if let textContent = m["content"] as? String {
                    antMessages.append(["role": role, "content": textContent])
                } else if let blocks = m["content"] as? [[String: Any]] {
                    var converted: [[String: Any]] = []
                    for b in blocks {
                        let bType = b["type"] as? String ?? ""
                        if bType == "text", let t = b["text"] as? String {
                            converted.append(["type": "text", "text": t])
                        } else if bType == "image_url",
                                  let imgObj = b["image_url"] as? [String: Any],
                                  let urlStr = imgObj["url"] as? String,
                                  let parsed = Provider.parseDataURL(urlStr) {
                            converted.append([
                                "type": "image",
                                "source": [
                                    "type": "base64",
                                    "media_type": parsed.mimeType,
                                    "data": parsed.base64Data
                                ]
                            ])
                        }
                    }
                    antMessages.append(["role": role, "content": converted])
                }
            }

            var b: [String: Any] = [
                "model": model,
                "messages": antMessages,
                "max_tokens": maxTokens,
                "temperature": temperature,
                "stream": stream
            ]
            if !systemPrompts.isEmpty {
                b["system"] = systemPrompts.joined(separator: "\n\n")
            }
            body = b

        case .gemini:
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedKey.lowercased().hasPrefix("bearer ") {
                let token = String(trimmedKey.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else if trimmedKey.hasPrefix("ya29.") {
                req.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            } else {
                req.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")
            }

            var systemPrompts: [String] = []
            var contents: [[String: Any]] = []

            for m in messages {
                guard let role = m["role"] as? String else { continue }
                if role == "system" {
                    if let s = m["content"] as? String, !s.isEmpty {
                        systemPrompts.append(s)
                    }
                    continue
                }
                let gemRole = (role == "assistant") ? "model" : "user"
                if let textContent = m["content"] as? String {
                    contents.append([
                        "role": gemRole,
                        "parts": [["text": textContent]]
                    ])
                } else if let blocks = m["content"] as? [[String: Any]] {
                    var parts: [[String: Any]] = []
                    for b in blocks {
                        let bType = b["type"] as? String ?? ""
                        if bType == "text", let t = b["text"] as? String {
                            parts.append(["text": t])
                        } else if bType == "image_url",
                                  let imgObj = b["image_url"] as? [String: Any],
                                  let urlStr = imgObj["url"] as? String,
                                  let parsed = Provider.parseDataURL(urlStr) {
                            parts.append([
                                "inline_data": [
                                    "mime_type": parsed.mimeType,
                                    "data": parsed.base64Data
                                ]
                            ])
                        }
                    }
                    contents.append([
                        "role": gemRole,
                        "parts": parts
                    ])
                }
            }

            var b: [String: Any] = [
                "contents": contents,
                "generationConfig": [
                    "temperature": temperature,
                    "maxOutputTokens": maxTokens
                ]
            ]
            if !systemPrompts.isEmpty {
                b["systemInstruction"] = [
                    "parts": [["text": systemPrompts.joined(separator: "\n\n")]]
                ]
            }
            body = b
        }

        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = data
        return req
    }

    func parseResponse(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        switch format {
        case .openai:
            guard let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let msg = first["message"] as? [String: Any],
                  let content = msg["content"] as? String else { return nil }
            return content

        case .anthropic:
            guard let content = json["content"] as? [[String: Any]] else { return nil }
            var accum = ""
            for block in content {
                if (block["type"] as? String) == "text", let t = block["text"] as? String {
                    accum += t
                }
            }
            return accum.isEmpty ? nil : accum

        case .gemini:
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            var accum = ""
            for part in parts {
                if (part["thought"] as? Bool) == true { continue }
                if let t = part["text"] as? String {
                    accum += t
                }
            }
            return accum.isEmpty ? nil : accum
        }
    }

    func parseStreamLine(_ line: String) -> StreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix(":") || trimmed.hasPrefix("event:") {
            return .ignore
        }
        guard trimmed.hasPrefix("data:") else { return .ignore }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let d = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return .ignore
        }

        if let errObj = json["error"] as? [String: Any],
           let msg = errObj["message"] as? String, !msg.isEmpty {
            return .error(msg)
        }

        switch format {
        case .openai:
            guard let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let piece = delta["content"] as? String, !piece.isEmpty else {
                return .ignore
            }
            return .delta(piece)

        case .anthropic:
            let evType = json["type"] as? String ?? ""
            if evType == "message_stop" { return .done }
            if evType == "error" {
                let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Anthropic 流式请求出错"
                return .error(msg)
            }
            if evType == "content_block_delta",
               let delta = json["delta"] as? [String: Any] {
                let dType = delta["type"] as? String ?? ""
                if (dType == "text_delta" || dType.isEmpty),
                   let piece = delta["text"] as? String, !piece.isEmpty {
                    return .delta(piece)
                }
            }
            return .ignore

        case .gemini:
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                return .ignore
            }
            var accum = ""
            for part in parts {
                if (part["thought"] as? Bool) == true { continue }
                if let t = part["text"] as? String {
                    accum += t
                }
            }
            return accum.isEmpty ? .ignore : .delta(accum)
        }
    }
}

struct SupportedLanguage: Equatable {
    let code: String
    let displayName: String
}

final class AppConfig {
    static let shared = AppConfig()
    static let languagePlaceholder = "<languages>"
    static let defaultLanguage = "Simplified Chinese"

    static let supportedLanguages: [SupportedLanguage] = [
        SupportedLanguage(code: "Simplified Chinese", displayName: "简体中文 (Simplified Chinese)"),
        SupportedLanguage(code: "Traditional Chinese", displayName: "繁體中文 (Traditional Chinese)"),
        SupportedLanguage(code: "English", displayName: "英语 (English)"),
        SupportedLanguage(code: "Japanese", displayName: "日语 (Japanese)"),
        SupportedLanguage(code: "Korean", displayName: "韩语 (Korean)"),
        SupportedLanguage(code: "Russian", displayName: "俄语 (Russian)"),
        SupportedLanguage(code: "French", displayName: "法语 (French)"),
        SupportedLanguage(code: "German", displayName: "德语 (German)"),
        SupportedLanguage(code: "Spanish", displayName: "西班牙语 (Spanish)"),
        SupportedLanguage(code: "Portuguese", displayName: "葡萄牙语 (Portuguese)"),
        SupportedLanguage(code: "Arabic", displayName: "阿拉伯语 (Arabic)")
    ]

    static let defaultTranslatePrompt = "You are a professional translation engine. Translate the user's text into <languages>. Output ONLY the translation itself — no explanations, no quotes, no extra words."

    static let defaultExplainPrompt = """
    你是一个善于把复杂概念和代码讲清楚的助手。请以 <languages> 回答,解释用户给出的内容,帮他真正理解。
    - 如果是代码:先说它整体在做什么,再逐步拆解关键逻辑,点出涉及的语法、库或设计意图,必要时给一句类比或小例子。
    - 如果是术语、论文或概念:先用 `## 整体在讲什么` 一两段话点透核心主旨,再用 `## 关键概念拆解` 配合 `### 子概念标题` 分模块讲清它是什么、为什么重要、怎么运作。
    - 如果是图片:先一句说清这张图整体是什么(截图/图表/报错/界面/照片/文档…),再解读其中关键信息。报错或代码截图就定位问题并给排查/解决方向;图表就读出趋势与要点;界面或流程就说清它在干什么。
    - 内容简短就简短回答(几句话点透),内容复杂就分点详解。直接开始,不要寒暄,不要复述原文。
    - 后续若有追问,延续上下文回答。
    """

    static func resolvePrompt(_ prompt: String, language: String) -> String {
        let lang = language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultLanguage : language
        return prompt.replacingOccurrences(of: languagePlaceholder, with: lang)
    }

    private(set) var providers: [Provider] = []
    private(set) var activeName: String = ""
    private(set) var language: String = AppConfig.defaultLanguage
    private(set) var translatePrompt: String = AppConfig.defaultTranslatePrompt
    private(set) var explainPrompt: String = AppConfig.defaultExplainPrompt
    private var path: String { kConfigDir + "/config.json" }

    var resolvedTranslatePrompt: String {
        AppConfig.resolvePrompt(translatePrompt, language: language)
    }

    var resolvedExplainPrompt: String {
        AppConfig.resolvePrompt(explainPrompt, language: language)
    }

    // 当前厂商:按名字找;找不到回退第一条(永不为 nil,只要至少一条)
    var active: Provider? { providers.first { $0.name == activeName } ?? providers.first }

    private struct Stored: Codable {
        var active: String
        var providers: [Provider]
        var language: String?
        var translatePrompt: String?
        var explainPrompt: String?
    }

    // 官方支持的四大预置厂商: DeepSeek、Gemini、Vertex AI、MiMo
    static func presets() -> [Provider] {
        [
            Provider(
                name: "DeepSeek",
                format: .openai,
                baseURL: "https://api.deepseek.com/v1",
                apiKey: "",
                model: "deepseek-chat",
                vision: false
            ),
            Provider(
                name: "Gemini",
                format: .gemini,
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                apiKey: "",
                model: "gemini-3.8-flash",
                vision: true
            ),
            Provider(
                name: "Vertex AI",
                format: .gemini,
                baseURL: "https://aiplatform.googleapis.com/v1/publishers/google",
                apiKey: "",
                model: "gemini-3.8-flash",
                vision: true
            ),
            Provider(
                name: "MiMo",
                format: .openai,
                baseURL: "https://api.xiaomimimo.com/v1",
                apiKey: "",
                model: "mimo-v2.5",
                vision: true
            )
        ]
    }

    // 查询是否为官方内置预设平台
    static func officialPreset(named name: String) -> Provider? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return presets().first { $0.name.lowercased() == trimmed }
    }

    static func isOfficialPreset(_ name: String) -> Bool {
        officialPreset(named: name) != nil
    }

    // 保留用户已有厂商配置(含自定义 API Key / 模型名),并自动补齐缺失的官方预置厂商
    static func mergeOfficialPresets(into existing: [Provider]) -> [Provider] {
        var result = existing.map { item -> Provider in
            if let preset = officialPreset(named: item.name) {
                return Provider(
                    name: preset.name,
                    format: preset.format,
                    baseURL: preset.baseURL,
                    apiKey: item.apiKey,
                    model: item.model.isEmpty ? preset.model : item.model,
                    vision: item.vision
                )
            }
            return item
        }
        for preset in presets() {
            let exists = result.contains { $0.name.lowercased() == preset.name.lowercased() }
            if !exists {
                result.append(preset)
            }
        }
        return result
    }

    // 启动调用一次。无文件/损坏 → 使用官方预置初始化并落盘;有文件 → 自动补齐新增官方预置与默认字段
    func load() {
        let fm = FileManager.default
        if let data = fm.contents(atPath: path),
           let stored = try? JSONDecoder().decode(Stored.self, from: data),
           !stored.providers.isEmpty {
            let merged = AppConfig.mergeOfficialPresets(into: stored.providers)
            providers = merged
            activeName = stored.active
            let rawLang = stored.language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            language = rawLang.isEmpty ? AppConfig.defaultLanguage : rawLang
            let rawTrans = stored.translatePrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            translatePrompt = rawTrans.isEmpty ? AppConfig.defaultTranslatePrompt : (stored.translatePrompt ?? AppConfig.defaultTranslatePrompt)
            let rawExplain = stored.explainPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isLegacyExplainDefault = rawExplain.contains("- 排版纪律:列表项 `- ` 内部**仅对核心术语或短标签保留加粗**")
            explainPrompt = (rawExplain.isEmpty || isLegacyExplainDefault) ? AppConfig.defaultExplainPrompt : (stored.explainPrompt ?? AppConfig.defaultExplainPrompt)
            if merged != stored.providers || stored.language == nil || stored.translatePrompt == nil || stored.explainPrompt == nil || isLegacyExplainDefault {
                save()
            }
            return
        }
        providers = AppConfig.presets()
        activeName = "MiMo"
        language = AppConfig.defaultLanguage
        translatePrompt = AppConfig.defaultTranslatePrompt
        explainPrompt = AppConfig.defaultExplainPrompt
        save()
    }

    @discardableResult
    func save() -> Bool {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = Stored(
            active: activeName,
            providers: providers,
            language: language,
            translatePrompt: translatePrompt,
            explainPrompt: explainPrompt
        )
        guard let data = try? enc.encode(payload) else { return false }
        try? FileManager.default.createDirectory(atPath: kConfigDir, withIntermediateDirectories: true, attributes: nil)
        do { try data.write(to: URL(fileURLWithPath: path), options: .atomic); return true }
        catch { return false }
    }

    // 落盘失败时回滚内存,保证内存与文件一致(避免「界面显示已保存、实际丢了」)
    @discardableResult
    func setProviders(_ ps: [Provider], active: String) -> Bool {
        let oldP = providers, oldA = activeName
        providers = ps
        activeName = active
        if save() { return true }
        providers = oldP; activeName = oldA
        return false
    }

    @discardableResult
    func setLanguageAndPrompts(language newLang: String, translatePrompt newTrans: String, explainPrompt newExplain: String) -> Bool {
        let oldL = language, oldT = translatePrompt, oldE = explainPrompt
        let cleanL = newLang.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanT = newTrans.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanE = newExplain.trimmingCharacters(in: .whitespacesAndNewlines)
        language = cleanL.isEmpty ? AppConfig.defaultLanguage : cleanL
        translatePrompt = cleanT.isEmpty ? AppConfig.defaultTranslatePrompt : newTrans
        explainPrompt = cleanE.isEmpty ? AppConfig.defaultExplainPrompt : newExplain
        if save() { return true }
        language = oldL; translatePrompt = oldT; explainPrompt = oldE
        return false
    }
}

enum LaunchAtLogin {
    static let defaultPlistPath = ("~/Library/LaunchAgents/com.yoryon.glint.plist" as NSString).expandingTildeInPath
    static let defaultExecutablePath = "/Applications/Glint.app/Contents/MacOS/Glint"
    static let label = "com.yoryon.glint"

    static func isEnabled(plistPath: String = defaultPlistPath) -> Bool {
        guard FileManager.default.fileExists(atPath: plistPath),
              let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any],
              (dict["RunAtLoad"] as? Bool) == true else {
            return false
        }
        return true
    }

    @discardableResult
    static func setEnabled(
        _ enabled: Bool,
        plistPath: String = defaultPlistPath,
        executablePath: String = defaultExecutablePath
    ) -> Bool {
        let fm = FileManager.default
        if enabled {
            let parent = (plistPath as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executablePath],
                "RunAtLoad": true,
                "ProcessType": "Interactive"
            ]
            guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
                return false
            }
            do {
                try data.write(to: URL(fileURLWithPath: plistPath), options: .atomic)
                return true
            } catch {
                return false
            }
        } else {
            if fm.fileExists(atPath: plistPath) {
                do {
                    try fm.removeItem(atPath: plistPath)
                    return true
                } catch {
                    return false
                }
            }
            return true
        }
    }
}
