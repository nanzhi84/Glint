import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os.log

// ============================================================
// Glint —— 划词翻译 / 解释 / 截图解释 菜单栏小程序
// 选中文字 → 选区旁冒泡「🌐 翻译」「💡 解释」→ 点击 → 同处显示结果
//   翻译:自动识别源语言并翻译为「语言」设置中选定的目标语言
//   解释:以目标语言把概念/代码讲明白,流式逐字输出(打字机)
//   截图解释:⌃⌥E 框选屏幕 → 多模态看图讲解(可追问)
// ============================================================

// MARK: - 路径 / 配置目录(最先初始化,保证日志可写,常量见 Config.swift)

// MARK: - 模型后端(当前厂商由 AppConfig 决定,见 Config.swift)

let kMaxTokens = 4096                             // 单次输出上限(随请求体发送)

@discardableResult
func ensureConfigDir() -> Bool {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: kConfigDir, withIntermediateDirectories: true, attributes: nil)
    if !fm.fileExists(atPath: kLogPath) {
        fm.createFile(atPath: kLogPath, contents: nil)
    }
    return fm.fileExists(atPath: kConfigDir)
}

// 全局首次访问即建目录(Swift 全局 let 惰性且线程安全)
let _bootstrap: Bool = ensureConfigDir()

// MARK: - 日志(自愈 + NSLog 兜底)

let kLog = OSLog(subsystem: "com.yoryon.glint", category: "glint")

func tsNow() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}

func logLine(_ s: String) {
    _ = _bootstrap
    let line = "[\(tsNow())] " + s + "\n"
    os_log("%{public}@", log: kLog, type: .info, s)   // Console.app 兜底,文件写不出也能看
    guard let data = line.data(using: .utf8) else { return }
    if let fh = FileHandle(forWritingAtPath: kLogPath) {
        fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
    } else {
        ensureConfigDir()
        if let fh = FileHandle(forWritingAtPath: kLogPath) {
            fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
        } else {
            try? line.write(toFile: kLogPath, atomically: false, encoding: .utf8)
        }
    }
}

// MARK: - API Key 读取

// 当前厂商的 key(空算无);供菜单状态等处复用
func readAPIKey() -> String? {
    guard let k = AppConfig.shared.active?.apiKey, !k.isEmpty else { return nil }
    return k
}

// AppKit(左下原点)↔ Quartz(左上原点)翻转的基准高度:主屏的高度。
// 主屏 = AppKit 原点 (0,0) 所在那块(也是 Quartz 原点所在屏)。
// 注意:不能用「所有屏幕并集」高度,也不能用 NSScreen.main(那是焦点屏);多屏不等高时
// 用并集高度会让两块屏的截图都整体偏移。CGWindowListCreateImage 的坐标系正是以主屏左上为原点。
func primaryScreenHeight() -> CGFloat {
    return (NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.screens.first)?.frame.height ?? 0
}

// MARK: - 取选中文字(AX 优先,失败再模拟 Cmd+C)

func selectedTextViaAX() -> String? {
    let systemWide = AXUIElementCreateSystemWide()
    var focused: AnyObject?
    guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
    let axElement = element as! AXUIElement
    var selected: AnyObject?
    guard AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
          let text = selected as? String, !text.isEmpty else { return nil }
    return text
}

// 全类型快照 + 完整恢复,避免污染用户剪贴板;轮询 changeCount 而非死等
func selectedTextViaCopy() -> String? {
    let pb = NSPasteboard.general
    let oldChange = pb.changeCount

    // 1. 全类型快照(尽量保留富文本/图片/文件等)
    var snapshot: [NSPasteboardItem] = []
    if let items = pb.pasteboardItems {
        for item in items {
            let copy = NSPasteboardItem()
            for type in item.types {
                if let d = item.data(forType: type) {
                    copy.setData(d, forType: type)
                }
            }
            snapshot.append(copy)
        }
    }

    // 2. 模拟 Cmd+C
    let src = CGEventSource(stateID: .combinedSessionState)
    let keyC: CGKeyCode = 0x08
    let down = CGEvent(keyboardEventSource: src, virtualKey: keyC, keyDown: true); down?.flags = .maskCommand
    let up = CGEvent(keyboardEventSource: src, virtualKey: keyC, keyDown: false); up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)

    // 3. 轮询等待剪贴板变化(最多 ~700ms),变化后再读
    var copied: String? = nil
    for _ in 0..<35 {
        usleep(20_000)
        if pb.changeCount != oldChange {
            copied = pb.string(forType: .string)
            break
        }
    }

    // 4. 恢复用户原剪贴板
    if pb.changeCount != oldChange {
        pb.clearContents()
        if !snapshot.isEmpty { pb.writeObjects(snapshot) }
    }

    if let t = copied, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
    return nil
}

// MARK: - 翻译(支持 OpenAI / Anthropic / Gemini 兼容协议)

func translate(_ text: String, completion: @escaping (String?, String?) -> Void) {
    guard let prov = AppConfig.shared.active, !prov.apiKey.isEmpty else {
        completion(nil, "没配置 API Key。请点菜单栏 Glint 图标 →「设置…」→「服务商」填入当前服务商的 Key")
        return
    }
    let sys = AppConfig.shared.resolvedTranslatePrompt

    let messages: [[String: Any]] = [
        ["role": "system", "content": sys],
        ["role": "user", "content": text]
    ]
    guard let req = prov.buildRequest(messages: messages, temperature: 0.3, maxTokens: kMaxTokens, stream: false) else {
        completion(nil, "请求构造失败"); return
    }

    URLSession.shared.dataTask(with: req) { respData, resp, err in
        if let err = err {
            DispatchQueue.main.async { completion(nil, "网络错误:\(err.localizedDescription)") }
            return
        }
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            DispatchQueue.main.async { completion(nil, "\(prov.name) 出错(HTTP \(http.statusCode)),请检查 Key 或余额") }
            return
        }
        guard let respData = respData,
              let content = prov.parseResponse(data: respData) else {
            DispatchQueue.main.async { completion(nil, "返回解析失败") }
            return
        }
        DispatchQueue.main.async { completion(content.trimmingCharacters(in: .whitespacesAndNewlines), nil) }
    }.resume()
}

// MARK: - 解释 / 追问(支持 OpenAI / Anthropic / Gemini 流式 / SSE)

// 通用流式对话:messages 为完整消息数组(含 system);逐字回吐(打字机)。
// 返回可取消的 Task;无 key 等同步错误时回调 onError 并返回 nil。
@discardableResult
func chatStream(_ messages: [[String: Any]],
                onDelta: @escaping (String) -> Void,
                onDone: @escaping (String) -> Void,
                onError: @escaping (String) -> Void) -> Task<Void, Never>? {
    guard let prov = AppConfig.shared.active, !prov.apiKey.isEmpty else {
        onError("没配置 API Key。请点菜单栏 Glint 图标 →「设置…」→「服务商」填入当前服务商的 Key")
        return nil
    }
    guard let req = prov.buildRequest(messages: messages, temperature: 0.5, maxTokens: kMaxTokens, stream: true) else {
        onError("请求构造失败"); return nil
    }

    return Task {
        var accum = ""
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                await MainActor.run { onError("\(prov.name) 出错(HTTP \(http.statusCode)),请检查 Key 或余额") }
                return
            }
            var finished = false
            for try await line in bytes.lines {
                if Task.isCancelled || finished { break }
                switch prov.parseStreamLine(line) {
                case .ignore:
                    continue
                case .done:
                    finished = true
                case .error(let errMsg):
                    await MainActor.run { onError("\(prov.name) 出错:\(errMsg)") }
                    return
                case .delta(let piece):
                    accum += piece
                    let snapshot = piece
                    await MainActor.run { onDelta(snapshot) }
                }
            }
            if Task.isCancelled { return }
            let full = accum
            await MainActor.run {
                if full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onError("\(prov.name) 没有返回内容")
                } else {
                    onDone(full)
                }
            }
        } catch {
            if Task.isCancelled { return }
            let msg = error.localizedDescription
            await MainActor.run { onError("网络错误:\(msg)") }
        }
    }
}

// MARK: - 冒泡/译文浮窗

// 允许 nonactivatingPanel 在后台应用状态下也能正常切换鼠标光标(如译文/解释区的工字形 I-Beam 光标)
func enableBackgroundCursorSetting() {
    typealias CGSDefaultConnectionFunc = @convention(c) () -> Int32
    typealias CGSSetConnectionPropertyFunc = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    guard let handle = dlopen(nil, RTLD_LAZY),
          let connSym = dlsym(handle, "_CGSDefaultConnection"),
          let setSym = dlsym(handle, "CGSSetConnectionProperty") else { return }
    let getConn = unsafeBitCast(connSym, to: CGSDefaultConnectionFunc.self)
    let setProp = unsafeBitCast(setSym, to: CGSSetConnectionPropertyFunc.self)
    let cid = getConn()
    _ = setProp(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
}

// 可成为 key 的浮窗:让用户能在结果里拖选译文 + ⌘C(并禁止 AppKit 跨屏重定向已由 clampToScreen 计算好的坐标)
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

// 可选中文本视图:仅在鼠标位于真实文字字形上(或正在拖选文字)时显示工字形光标(I-Beam),空白区域保持箭头光标
final class SelectableTextView: NSTextView {
    private var cursorTrackingArea: NSTrackingArea?
    var rightScrollerGutter: CGFloat = 0 {
        didSet { updateContainerWidth() }
    }

    override var needsPanelToBecomeKey: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateContainerWidth()
    }

    private func updateContainerWidth() {
        guard rightScrollerGutter > 0, let tc = textContainer else { return }
        tc.widthTracksTextView = false
        let targetW = max(80, bounds.width - rightScrollerGutter)
        if abs(tc.size.width - targetW) > 0.5 {
            tc.size = NSSize(width: targetW, height: .greatestFiniteMagnitude)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = cursorTrackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(t)
        cursorTrackingArea = t
    }

    // 禁用 NSTextView 默认把整块 visibleRect 设为 I-Beam 的行为,完全按字形命中判定
    override func resetCursorRects() {}

    // 判断视图坐标 pt 是否精确落在可见文字字形上(排除行尾空白、段落下方空白、空行与图片附件)
    private func isPointOverText(_ pt: NSPoint) -> Bool {
        guard bounds.contains(pt),
              let lm = layoutManager,
              let tc = textContainer,
              let storage = textStorage,
              storage.length > 0 else { return false }
        lm.ensureLayout(for: tc)
        let containerPt = NSPoint(x: pt.x - textContainerOrigin.x, y: pt.y - textContainerOrigin.y)
        let used = lm.usedRect(for: tc)
        guard used.contains(containerPt) else { return false }

        var lineGlyphRange = NSRange(location: 0, length: 0)
        let glyphIdx = lm.glyphIndex(for: containerPt, in: tc, fractionOfDistanceThroughGlyph: nil)
        guard glyphIdx < lm.numberOfGlyphs else { return false }

        let lineUsed = lm.lineFragmentUsedRect(forGlyphAt: glyphIdx, effectiveRange: &lineGlyphRange)
        guard lineUsed.contains(containerPt) else { return false }

        let charIdx = lm.characterIndexForGlyph(at: glyphIdx)
        guard charIdx < storage.length else { return false }

        if storage.attribute(.attachment, at: charIdx, effectiveRange: nil) != nil {
            return false
        }

        let lineCharRange = lm.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
        let nsStr = storage.string as NSString
        let lineStr = nsStr.substring(with: lineCharRange)
        if lineStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        var firstVisibleGlyphX = lineUsed.minX
        for ci in lineCharRange.location ..< NSMaxRange(lineCharRange) {
            let ch = nsStr.character(at: ci)
            if ch != 0x20 && ch != 0x09 && ch != 0x0A && ch != 0x0D {
                let gi = lm.glyphIndexForCharacter(at: ci)
                let gr = lm.boundingRect(forGlyphRange: NSRange(location: gi, length: 1), in: tc)
                firstVisibleGlyphX = gr.minX
                break
            }
        }
        return containerPt.x >= firstVisibleGlyphX - 1 && containerPt.x <= lineUsed.maxX + 1
    }

    private func updateCursorForCurrentMouse() {
        guard let win = window else {
            NSCursor.arrow.set()
            return
        }
        let pt = convert(win.mouseLocationOutsideOfEventStream, from: nil)
        if isPointOverText(pt) {
            NSCursor.iBeam.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursorForCurrentMouse()
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursorForCurrentMouse()
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursorForCurrentMouse()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        updateCursorForCurrentMouse()
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard isPointOverText(pt) else {
            setSelectedRange(NSRange(location: 0, length: 0))
            NSCursor.arrow.set()
            return
        }
        window?.makeKey()
        NSCursor.iBeam.set()
        let dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { ev in
            NSCursor.iBeam.set()
            return ev
        }
        super.mouseDown(with: event)
        if let dragMonitor = dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
        }
        updateCursorForCurrentMouse()
    }
}

// 可拖动的 Claude 暖纸色背板(#FAF9F5 主底色 + 1px 暖细边框 + 圆角裁切;背景空白处可拖动窗口)
final class DraggablePaperView: NSView {
    var cornerRadius: CGFloat = 14 { didSet { layer?.cornerRadius = cornerRadius; needsDisplay = true } }
    var borderColor: NSColor = ClaudeTheme.windowBorder { didSet { needsDisplay = true } }

    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        ClaudeTheme.paperBg.setFill()
        path.fill()

        let strokeRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let strokePath = NSBezierPath(roundedRect: strokeRect, xRadius: max(0, cornerRadius - 0.5), yRadius: max(0, cornerRadius - 0.5))
        strokePath.lineWidth = 1.0
        borderColor.setStroke()
        strokePath.stroke()
    }
}

// 划词快捷悬浮条内嵌分段按钮(图2:无系统 Emoji,采用 1.5px 线性经纬地球 / 赤陶色四角星芒图标 + #EFECE6 独立悬停圆角块)
final class ActionPillButton: NSButton {
    enum Kind {
        case translate
        case explain
    }

    private var trackingAreaRef: NSTrackingArea?
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressing = false { didSet { needsDisplay = true } }
    let kind: Kind
    var labelText: String

    init(frame frameRect: NSRect, kind: Kind, labelText: String) {
        self.kind = kind
        self.labelText = labelText
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        wantsLayer = true
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingAreaRef = t
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
    override func mouseEntered(with event: NSEvent) { hovering = true; NSCursor.arrow.set() }
    override func mouseExited(with event: NSEvent) { hovering = false; pressing = false }
    override func mouseDown(with event: NSEvent) { pressing = true }
    override func mouseDragged(with event: NSEvent) {
        pressing = bounds.contains(convert(event.locationInWindow, from: nil))
    }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressing = false
        if inside, let action = action, let target = target {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let active = hovering || pressing
        if active {
            let bg = NSBezierPath(roundedRect: bounds, xRadius: 6.5, yRadius: 6.5)
            (pressing ? ClaudeTheme.pillBorder : ClaudeTheme.pillHoverBg).setFill()
            bg.fill()
        }

        let textColor = active ? ClaudeTheme.inkStrong : ClaudeTheme.inkBody
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: textColor
        ]
        let s = labelText as NSString
        let textSize = s.size(withAttributes: attrs)
        let iconBox: CGFloat = 15
        let gap: CGFloat = 6.5
        let totalW = iconBox + gap + textSize.width
        let startX = (bounds.width - totalW) / 2
        let midY = bounds.midY

        let iconRect = NSRect(x: startX, y: midY - iconBox / 2, width: iconBox, height: iconBox)
        let globeColor = active ? ClaudeTheme.inkStrong : NSColor(srgbRed: 92/255, green: 91/255, blue: 86/255, alpha: 1.0)
        switch kind {
        case .translate:
            drawGlobeIcon(in: iconRect, color: globeColor)
        case .explain:
            drawSparklesIcon(in: iconRect, color: ClaudeTheme.terracotta)
        }

        let textRect = NSRect(x: startX + iconBox + gap,
                              y: midY - textSize.height / 2,
                              width: textSize.width,
                              height: textSize.height)
        s.draw(in: textRect, withAttributes: attrs)
    }

    // 1.5px 线性地球经纬线图标(图2 左侧「翻译」:外圆 + 纵向经线椭圆 + 中央赤道横线)
    private func drawGlobeIcon(in r: NSRect, color: NSColor) {
        color.setStroke()
        let inset = r.insetBy(dx: 0.9, dy: 0.9)
        let circle = NSBezierPath(ovalIn: inset)
        circle.lineWidth = 1.4
        circle.stroke()

        // 纵向经线椭圆
        let meridianRect = NSRect(x: inset.midX - inset.width * 0.24,
                                  y: inset.minY,
                                  width: inset.width * 0.48,
                                  height: inset.height)
        let meridian = NSBezierPath(ovalIn: meridianRect)
        meridian.lineWidth = 1.3
        meridian.stroke()

        // 中央水平纬线
        let eq = NSBezierPath()
        eq.move(to: NSPoint(x: inset.minX + 0.4, y: inset.midY))
        eq.line(to: NSPoint(x: inset.maxX - 0.4, y: inset.midY))
        eq.lineWidth = 1.3
        eq.stroke()
    }

    // 1.5px 线性双四角星芒图标(图2 右侧「解释」,Anthropic 赤陶色 #D97757;注意 NSButton isFlipped=true,Y 向下增大)
    private func drawSparklesIcon(in r: NSRect, color: NSColor) {
        color.setStroke()
        // 主四角星(左上偏中:isFlipped 下 y 较小为上)
        let mainCenter = NSPoint(x: r.minX + r.width * 0.39, y: r.minY + r.height * 0.44)
        let mainStar = fourPointStarPath(center: mainCenter, radius: r.width * 0.40, waist: r.width * 0.105)
        mainStar.lineWidth = 1.4
        mainStar.lineJoinStyle = .round
        mainStar.lineCapStyle = .round
        mainStar.stroke()

        // 副四角星(右下角微缩点缀:isFlipped 下 y 较大为下)
        let subCenter = NSPoint(x: r.minX + r.width * 0.79, y: r.minY + r.height * 0.77)
        let subStar = fourPointStarPath(center: subCenter, radius: r.width * 0.21, waist: r.width * 0.055)
        subStar.lineWidth = 1.3
        subStar.lineJoinStyle = .round
        subStar.lineCapStyle = .round
        subStar.stroke()
    }

    private func fourPointStarPath(center c: NSPoint, radius R: CGFloat, waist w: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        let top    = NSPoint(x: c.x,     y: c.y + R)
        let right  = NSPoint(x: c.x + R, y: c.y)
        let bottom = NSPoint(x: c.x,     y: c.y - R)
        let left   = NSPoint(x: c.x - R, y: c.y)
        let tr     = NSPoint(x: c.x + w, y: c.y + w)
        let br     = NSPoint(x: c.x + w, y: c.y - w)
        let bl     = NSPoint(x: c.x - w, y: c.y - w)
        let tl     = NSPoint(x: c.x - w, y: c.y + w)

        p.move(to: top)
        p.curve(to: right,  controlPoint1: tr, controlPoint2: tr)
        p.curve(to: bottom, controlPoint1: br, controlPoint2: br)
        p.curve(to: left,   controlPoint1: bl, controlPoint2: bl)
        p.curve(to: top,    controlPoint1: tl, controlPoint2: tl)
        p.close()
        return p
    }
}

// 弹窗右上角悬浮线性圆形图标按钮(图1 右上角「复制」与「关闭 ×」按钮)
final class CircleIconButton: NSButton {
    enum IconKind {
        case copy
        case copied
        case close
    }

    private var trackingAreaRef: NSTrackingArea?
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressing = false { didSet { needsDisplay = true } }
    var iconKind: IconKind { didSet { needsDisplay = true } }

    init(frame frameRect: NSRect, iconKind: IconKind) {
        self.iconKind = iconKind
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        wantsLayer = true
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingAreaRef = t
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
    override func mouseEntered(with event: NSEvent) { hovering = true; NSCursor.arrow.set() }
    override func mouseExited(with event: NSEvent) { hovering = false; pressing = false }
    override func mouseDown(with event: NSEvent) { pressing = true }
    override func mouseDragged(with event: NSEvent) {
        pressing = bounds.contains(convert(event.locationInWindow, from: nil))
    }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressing = false
        if inside, let action = action, let target = target {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let circleRect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let circle = NSBezierPath(ovalIn: circleRect)
        let bg = (hovering || pressing) ? ClaudeTheme.pillHoverBg : ClaudeTheme.paperAltBg
        bg.setFill()
        circle.fill()
        ClaudeTheme.windowBorder.setStroke()
        circle.lineWidth = 1.0
        circle.stroke()

        let strokeColor: NSColor
        switch iconKind {
        case .copied:
            strokeColor = ClaudeTheme.terracotta
        case .copy, .close:
            strokeColor = (hovering || pressing) ? ClaudeTheme.inkStrong : ClaudeTheme.inkMuted
        }
        strokeColor.setStroke()

        let cx = bounds.midX, cy = bounds.midY
        switch iconKind {
        case .copy:
            // 双层叠圆角矩形复制图标
            let front = NSRect(x: cx - 3.6, y: cy - 5.2, width: 7.8, height: 8.6)
            let fp = NSBezierPath(roundedRect: front, xRadius: 1.6, yRadius: 1.6)
            fp.lineWidth = 1.35
            fp.stroke()

            let back = NSBezierPath()
            back.move(to: NSPoint(x: cx - 1.8, y: cy + 3.4))
            back.line(to: NSPoint(x: cx - 1.8, y: cy + 4.4))
            back.curve(to: NSPoint(x: cx - 0.4, y: cy + 5.6),
                       controlPoint1: NSPoint(x: cx - 1.8, y: cy + 5.2),
                       controlPoint2: NSPoint(x: cx - 1.2, y: cy + 5.6))
            back.line(to: NSPoint(x: cx + 4.2, y: cy + 5.6))
            back.curve(to: NSPoint(x: cx + 5.6, y: cy + 4.2),
                       controlPoint1: NSPoint(x: cx + 5.0, y: cy + 5.6),
                       controlPoint2: NSPoint(x: cx + 5.6, y: cy + 5.0))
            back.line(to: NSPoint(x: cx + 5.6, y: cy - 1.6))
            back.curve(to: NSPoint(x: cx + 4.4, y: cy - 2.8),
                       controlPoint1: NSPoint(x: cx + 5.6, y: cy - 2.4),
                       controlPoint2: NSPoint(x: cx + 5.0, y: cy - 2.8))
            back.lineWidth = 1.35
            back.lineCapStyle = .round
            back.stroke()

        case .copied:
            // NSButton isFlipped=true(Y 向下增大):对勾顶点在下方 cy + 3.4,右上角收尾在 cy - 3.4
            let check = NSBezierPath()
            check.move(to: NSPoint(x: cx - 4.5, y: cy + 0.4))
            check.line(to: NSPoint(x: cx - 1.2, y: cy + 3.6))
            check.line(to: NSPoint(x: cx + 4.8, y: cy - 3.4))
            check.lineWidth = 1.65
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()

        case .close:
            let r: CGFloat = 3.8
            let xPath = NSBezierPath()
            xPath.move(to: NSPoint(x: cx - r, y: cy - r))
            xPath.line(to: NSPoint(x: cx + r, y: cy + r))
            xPath.move(to: NSPoint(x: cx - r, y: cy + r))
            xPath.line(to: NSPoint(x: cx + r, y: cy - r))
            xPath.lineWidth = 1.4
            xPath.lineCapStyle = .round
            xPath.stroke()
        }
    }
}

// 4px 极细半透明暖灰滚动条(rgba(20, 20, 19, 0.15), 无轨道背景, 仅在滚动时轻盈浮现)
final class WarmScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        return 8
    }
    override func draw(_ dirtyRect: NSRect) {
        drawKnob()
    }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func drawKnob() {
        let k = rect(for: .knob)
        guard k.height > 4 else { return }
        let slim = NSRect(x: bounds.maxX - 6, y: k.minY + 2, width: 4, height: max(12, k.height - 4))
        let path = NSBezierPath(roundedRect: slim, xRadius: 2, yRadius: 2)
        ClaudeTheme.scrollbarThumb.setFill()
        path.fill()
    }
}

// 禁止窗口中心滚动区域触发背景拖拽移动窗口(仅外围边缘留白区可移动窗口)
final class NonDraggableClipView: NSClipView {
    override var mouseDownCanMoveWindow: Bool { false }
}

final class NonDraggableScrollView: NSScrollView {
    override var mouseDownCanMoveWindow: Bool { false }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let clip = NonDraggableClipView(frame: contentView.frame)
        clip.drawsBackground = false
        contentView = clip
    }
    required init?(coder: NSCoder) { fatalError() }
}

// 底部内嵌式悬浮胶囊追问容器(#FFFFFF 底 + 1px #E3E1D8 边框 + 12px 圆角,聚焦时过渡为赤陶色 #D97757)
final class CapsuleInputContainerView: NSView {
    var isFocused = false { didSet { needsDisplay = true } }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.6, dy: 0.6)
        let path = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
        NSColor.white.setFill()
        path.fill()
        (isFocused ? ClaudeTheme.terracotta : ClaudeTheme.codeBorder).setStroke()
        path.lineWidth = isFocused ? 1.25 : 1.0
        path.stroke()
    }
}

// 底部胶囊右侧赤陶色圆形发送按钮(↑)
final class SendArrowButton: NSButton {
    private var trackingAreaRef: NSTrackingArea?
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressing = false { didSet { needsDisplay = true } }

    override var isEnabled: Bool { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        wantsLayer = true
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingAreaRef = t
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
    override func mouseEntered(with event: NSEvent) { hovering = true; NSCursor.arrow.set() }
    override func mouseExited(with event: NSEvent) { hovering = false; pressing = false }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressing = true
    }
    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressing = false
        if inside, let action = action, let target = target {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        if isEnabled {
            let base = ClaudeTheme.terracotta
            (pressing ? base.blended(withFraction: 0.15, of: .black) ?? base : base).setFill()
        } else {
            ClaudeTheme.codeBorder.setFill()
        }
        circle.fill()

        // NSButton isFlipped=true(Y 向下增大):向上箭头尖端在上方 cy - 4.8,箭杆底端在 cy + 4.8
        NSColor.white.setStroke()
        let cx = bounds.midX, cy = bounds.midY
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: cx, y: cy + 4.8))
        arrow.line(to: NSPoint(x: cx, y: cy - 4.8))
        arrow.move(to: NSPoint(x: cx - 3.6, y: cy - 1.2))
        arrow.line(to: NSPoint(x: cx, y: cy - 4.8))
        arrow.line(to: NSPoint(x: cx + 3.6, y: cy - 1.2))
        arrow.lineWidth = 1.6
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.stroke()
    }
}

// 感知聚焦状态的无边框追问输入框(联动外层胶囊容器边框高亮为赤陶色 #D97757)
final class FocusAwareTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }
}

// 右下角拖拽握把:拖动改窗口尺寸(左上角不动),松手回调保存
final class ResizeGripView: NSView {
    var onCommit: (() -> Void)?
    private var startMouse: NSPoint = .zero
    private var startFrame: NSRect = .zero
    let minW: CGFloat = 320, minH: CGFloat = 200
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with e: NSEvent) { startMouse = NSEvent.mouseLocation; startFrame = window?.frame ?? .zero }
    override func mouseDragged(with e: NSEvent) {
        guard let win = window else { return }
        let now = NSEvent.mouseLocation
        let newW = max(minW, startFrame.width + (now.x - startMouse.x))
        let newH = max(minH, startFrame.height - (now.y - startMouse.y))   // 向下拖 → 高度增加
        win.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - newH, width: newW, height: newH), display: true)
    }
    override func mouseUp(with e: NSEvent) { onCommit?() }
    override func draw(_ r: NSRect) {
        ClaudeTheme.inkMuted.withAlphaComponent(0.42).setStroke()
        let p = NSBezierPath(); p.lineWidth = 1.15
        for off in stride(from: 4, through: 10, by: 3) {
            p.move(to: NSPoint(x: bounds.maxX - CGFloat(off) - 3, y: bounds.minY + 3))
            p.line(to: NSPoint(x: bounds.maxX - 3, y: bounds.minY + CGFloat(off) + 3))
        }
        p.stroke()
    }
}

final class PopupController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private var panel: NSPanel?
    private var body: NSView?
    private var pendingText: String?
    private var lastResult: String?
    private weak var copyButton: CircleIconButton?
    private weak var capsuleContainer: CapsuleInputContainerView?
    private weak var sendButton: SendArrowButton?
    private let appearDur: TimeInterval = 0.14
    private let dismissDur: TimeInterval = 0.10
    private let switchDur: TimeInterval = 0.16

    // 会话(解释 + 追问)状态
    private var convo: [(role: String, content: String)] = []   // 不含 system;首条 user 为原文
    private var attachedImageDataURL: String?                    // 截图解释:本轮会话附带的图(base64 data URL),整段会话期间保留、每轮重发
    private var convoTextView: NSTextView?                       // 整段对话的 transcript
    private var convoScroll: NSScrollView?
    private var askField: FocusAwareTextField?                   // 底部追问输入框
    private var convoTask: Task<Void, Never>?
    private var assistantStart = 0                               // 当前 assistant 流式段在 transcript 的起点
    private var assistantAccum = ""
    private var turnStartLoc = 0                                 // 本轮(含追问气泡)在 transcript 的起点,失败可整轮回滚
    private var generation = 0                                   // 递增令牌:关闭/新划词时 +1,作废在途的非流式回调(翻译)
    private var uiTestMode = false                               // POPDICT_UITEST:自测模式(程序化驱动 + 截图 + 长高日志)
    private let convoFont = NSFont.systemFont(ofSize: 14.5)
    private let convoW: CGFloat = 500
    private let convoPad: CGFloat = 24                           // 左右内边距 24px,增加阅读呼吸感
    private let headerTopH: CGFloat = 42                         // 顶部右上角悬浮复制/关闭按钮区高度
    private let inputBarH: CGFloat = 56                          // 底部悬浮胶囊输入栏高度
    private let transcriptBottomGap: CGFloat = 8                 // transcript 与底部胶囊之间的留白
    private var panelIsResizable = false                         // 当前态是否「可缩放/记忆」的内容浮窗(结果/会话)
    private var growTimer: Timer?                                // 会话浮窗随流式内容长高的节流定时器
    private var userResized = false                              // 本轮会话中用户手动改过尺寸 → 不再自动长高
    private var frameAnimations = 0                              // 进行中的窗口帧动画计数(>0 时 p.frame 是中间态,长高/存尺寸必须跳过)
    private var programmaticSize = NSSize.zero                   // 最近一次程序化 setFrame 的目标尺寸(识别假 live resize 用)
    private let kPopupSizeKey = "popupSize"
    private let minPopupSize = NSSize(width: 320, height: 200)
    private let defaultPopupSize = NSSize(width: 500, height: 460)

    var isVisible: Bool { panel != nil }
    func frame() -> NSRect? { panel?.frame }
    // 追问输入法正在合成(点候选词等):外部点击不应关闭会话
    var isComposingText: Bool { (askField?.currentEditor() as? NSTextView)?.hasMarkedText() ?? false }

    @objc func dismiss() {
        guard let p = panel else { return }
        NSCursor.arrow.set()
        generation += 1
        stopConversation()
        panel = nil; body = nil; pendingText = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = self.dismissDur
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }

    // 切换背板的圆角与边框色(快捷悬浮条:10pt 圆角 + #E3E1D8;展开大弹窗:14pt 圆角 + #E8E6DE)
    private func applyPaperStyle(isPill: Bool, to targetPanel: NSPanel?) {
        guard let paper = targetPanel?.contentView as? DraggablePaperView else { return }
        paper.cornerRadius = isPill ? 10 : 14
        paper.borderColor = isPill ? ClaudeTheme.pillBorder : ClaudeTheme.windowBorder
    }

    // 图2:划词后的快捷悬浮条(Segmented Pill:4px 内边距、无硬分割线、1.5px 线性图标、#EFECE6 独立悬停块)
    func showButton(text: String, fallbackPoint: NSPoint) {
        NSCursor.arrow.set()
        generation += 1
        stopConversation()
        if let old = panel {
            old.orderOut(nil)
            panel = nil
            body = nil
            frameAnimations = 0
        }
        panelIsResizable = false
        pendingText = text
        let pad: CGFloat = 4
        let gap: CGFloat = 2
        let bw: CGFloat = 76
        let bh: CGFloat = 30
        let w: CGFloat = pad * 2 + bw * 2 + gap
        let h: CGFloat = pad * 2 + bh
        let rect = buttonRect(w: w, h: h, at: fallbackPoint)
        logLine("  popup at cursor=(\(Int(fallbackPoint.x)),\(Int(fallbackPoint.y))) rect=\(NSStringFromRect(rect))")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        let tBtn = ActionPillButton(frame: NSRect(x: pad, y: pad, width: bw, height: bh),
                                    kind: .translate, labelText: "翻译")
        tBtn.target = self
        tBtn.action = #selector(onTranslateClicked)
        container.addSubview(tBtn)

        let eBtn = ActionPillButton(frame: NSRect(x: pad + bw + gap, y: pad, width: bw, height: bh),
                                    kind: .explain, labelText: "解释")
        eBtn.target = self
        eBtn.action = #selector(onExplainClicked)
        container.addSubview(eBtn)

        present(content: container, rect: rect, isPill: true)
    }

    // 首次显示淡入;已有面板则「帧动画到新尺寸 + 内容 crossfade」。
    // 帧动画期间新旧内容都临时改成「固定尺寸、贴住顶边」(.minYMargin),
    // 避免 autoresize 以动画中途的尺寸为基准把内容压缩/挤出可视区;动画完成后再恢复跟随窗口。
    private func present(content newBody: NSView, rect: NSRect, isPill: Bool = false) {
        programmaticSize = rect.size
        if let p = panel, let paper = p.contentView {
            applyPaperStyle(isPill: isPill, to: p)
            let finalMask = newBody.autoresizingMask
            newBody.autoresizingMask = [.minYMargin]
            newBody.frame = NSRect(x: 0, y: paper.bounds.height - rect.height,
                                   width: rect.width, height: rect.height)   // 贴顶、按最终尺寸布局
            newBody.alphaValue = 0
            paper.addSubview(newBody)
            let old = body
            old?.autoresizingMask = [.minYMargin]
            body = newBody
            frameAnimations += 1
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = self.switchDur
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                p.animator().setFrame(rect, display: true)
                old?.animator().alphaValue = 0
                newBody.animator().alphaValue = 1
            }, completionHandler: { [weak self] in
                old?.removeFromSuperview()
                guard let self = self else { return }
                self.frameAnimations -= 1
                guard self.body === newBody, let paper2 = self.panel?.contentView else { return }
                newBody.frame = paper2.bounds
                newBody.autoresizingMask = finalMask
            })
        } else {
            let p = makePanel(rect, isPill: isPill)
            newBody.frame = NSRect(origin: .zero, size: rect.size)
            p.contentView?.addSubview(newBody)
            body = newBody
            panel = p
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = self.appearDur
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                p.animator().alphaValue = 1
            })
        }
    }

    @objc private func onTranslateClicked() {
        guard let text = pendingText else { return }
        generation += 1   // 作废上一次在途回调(与解释/截图一致)
        let gen = generation
        showMessage("翻译中…", isError: false)
        translate(text) { [weak self] result, errMsg in
            guard let self = self, gen == self.generation else { return }   // 浮窗已被关闭/换词:丢弃结果
            if let errMsg = errMsg {
                self.showMessage(errMsg, isError: true)
            } else {
                self.showMessage(result ?? "(空)", isError: false, showCopy: true, markdown: true)
            }
        }
    }

    @objc private func onCopyClicked() {
        let textToCopy = lastResult ?? convoTextView?.string
        guard let s = textToCopy, !s.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        copyButton?.iconKind = .copied
        let btn = copyButton
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            btn?.iconKind = .copy
        }
    }

    // 在弹窗右上角安装悬浮「复制」与「关闭 ×」圆形线性按钮(如图1 右上角)
    private func addTopRightActions(to container: NSView, showCopy: Bool) {
        let btnSize: CGFloat = 28
        let topMargin: CGFloat = 12
        let rightMargin: CGFloat = 16
        let gap: CGFloat = 8
        let y = container.bounds.height - topMargin - btnSize

        let closeBtn = CircleIconButton(
            frame: NSRect(x: container.bounds.width - rightMargin - btnSize, y: y, width: btnSize, height: btnSize),
            iconKind: .close
        )
        closeBtn.target = self
        closeBtn.action = #selector(dismiss)
        closeBtn.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(closeBtn)

        if showCopy {
            let cpBtn = CircleIconButton(
                frame: NSRect(x: closeBtn.frame.minX - gap - btnSize, y: y, width: btnSize, height: btnSize),
                iconKind: .copy
            )
            cpBtn.target = self
            cpBtn.action = #selector(onCopyClicked)
            cpBtn.autoresizingMask = [.minXMargin, .minYMargin]
            container.addSubview(cpBtn)
            copyButton = cpBtn
        }
    }

    // 给滚动视图配置 4px 暖灰极细滚动条(默认隐藏,滚动时浮现)
    private func configureWarmScrollView(_ scroll: NSScrollView) {
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.verticalScroller = WarmScroller()
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
    }

    // MARK: 解释 / 追问(会话浮窗)

    @objc private func onExplainClicked() {
        guard let text = pendingText else { return }
        beginConversation(firstUserText: text)
    }

    // UI 自测入口(仅 POPDICT_UITEST 时调用):程序化冒按钮 → 解释 → 追问,验证整链路 + 截图 + 长高日志。
    func runDemoExplain() {
        uiTestMode = true
        let q = "用中文详细解释 Python 的装饰器(decorator):是什么、@ 语法糖的原理、不带参数和带参数的装饰器分别怎么写、以及 functools.wraps 的作用。请分小节、配多个代码例子。"
        let p = NSScreen.main.map { NSPoint(x: $0.frame.midX - 100, y: $0.frame.midY + 220) } ?? NSEvent.mouseLocation
        showButton(text: q, fallbackPoint: p)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.onExplainClicked() }
    }

    // Claude UI 视觉回归自测(POPDICT_UITEST=claude_ui):
    // 1) 渲染图2 划词快捷悬浮条到 ~/popdict_claude_pill.png
    // 2) 渲染图1 解释会话大弹窗到 ~/popdict_claude_explain.png
    func runDemoClaudeUI() {
        let p = NSScreen.main.map { NSPoint(x: $0.frame.midX - 180, y: $0.frame.midY + 260) } ?? NSEvent.mouseLocation
        showButton(text: "demo", fallbackPoint: p)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self else { return }
            self.capturePanel(to: "\(NSHomeDirectory())/popdict_claude_pill.png")
            self.installConversationPanel(topLeft: p)
            let sample = """
            # 整体在讲什么

            这段文字是在综述一个研究方向：**多镜头（多视角）联合生成**中，如何用**推理期计算扩展 (Inference-Time Scaling)**来弥补“开环生成”的不稳定性。

            核心引用是 Ma 等人 2025 年的论文，它重新思考了扩散模型在推理阶段该怎么花算力。

            ## 关键概念拆解

            ### 开环生成的不稳定性

            “开环”指生成过程没有反馈校正——模型一路生成到底，中间不检查、不纠错。多镜头联合生成要求多个视角在内容、几何上保持一致，一旦某一步跑偏，后面全歪，所以不稳定。

            ### 推理期计算扩展（Inference-Time Scaling）

            模型参数不变，只在**推理（生成）阶段多花算力**来换质量。类比：考试时题目难度不变，但给你更多草稿纸和时间反复检查，答案会更靠谱。

            ### Ma 等人的核心观点：算力别全堆在“深度”上，要分给“宽度”

            - **传统做法**：加去噪步数（50 步 → 200 步），即把算力堆在单条轨迹的深度上。
            - **问题**：边际收益递减 —— 步数加到一定程度，质量提升越来越小，纯属浪费。
            - **更优策略**：把预算转成**搜索空间的宽度** —— 在去噪早期并行采样多个候选噪声分支，相当于同时开多条生成轨迹。

            ### 外部视觉验证器（Verifier）+ 树搜索

            - 用 Verifier 对中间潜变量的去噪状态做**在线评估**（判断这条分支“看起来靠不靠谱”）。再用**树搜索**做动态剪枝（砍掉差的分支）和重采样（把算力补给好的分支）。

            > 一句话类比：不是让一个人把一道题反复算 200 遍，而是让多个人同时从不同思路入手，中途用裁判打分，淘汰差的、加码好的。
            """
            self.assistantStart = 0
            self.finishTurn(sample)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self = self, let win = self.panel else { return }
                win.setFrame(NSRect(x: win.frame.minX, y: win.frame.maxY - 620, width: 520, height: 620), display: true)
                self.syncTranscriptLayout()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard let self = self else { return }
                    self.capturePanel(to: "\(NSHomeDirectory())/popdict_claude_explain.png")
                    self.scrollTranscriptToBottom()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        self?.capturePanel(to: "\(NSHomeDirectory())/popdict_claude_explain_bottom.png")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { NSApp.terminate(nil) }
                    }
                }
            }
        }
    }

    // UI 自测入口(POPDICT_UITEST=translate):按钮 → 翻译中 → 短译文 → 长译文,
    // 验证自适应尺寸(短译文小窗、长译文到上限)+ 顶边固定向下生长 + 帧动画;不走网络。
    func runDemoTranslate() {
        let p = NSScreen.main.map { NSPoint(x: $0.frame.midX - 100, y: $0.frame.midY + 220) } ?? NSEvent.mouseLocation
        showButton(text: "hello world", fallbackPoint: p)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showMessage("翻译中…", isError: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.showMessage("你好,世界", isError: false, showCopy: true, markdown: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self = self else { return }
            logLine("UITEST translate short frame=\(NSStringFromRect(self.panel?.frame ?? .zero))")
            self.capturePanel(to: "\(NSHomeDirectory())/popdict_translate_short.png")
            let long = """
            **机器翻译**(Machine Translation)是利用计算机把一种自然语言转换为另一种自然语言的过程。

            核心内容解读:

            1. **什么是"逐轮循环"?**
                - 这是你最熟悉的交互方式:你发一条指令,AI 读代码、修改、测试,然后把结果交还给你。
                - 每一轮都由你手动触发,AI 自己判断何时停止。
            2. **关键问题:AI 如何判断"做完了"?**
                - 如果不明确告诉 AI 验证标准,它通常只以"代码没报错"作为完成标准。
            3. **解决方案:用 `SKILL.md` 文件定义验证清单**

            如今的大语言模型不仅能翻译,还能在保留语气、术语和格式的同时按需调整正式程度,\
            例如把口语化的产品公告改写成正式的新闻稿风格。
            """
            self.showMessage(long, isError: false, showCopy: true, markdown: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) { [weak self] in
            guard let self = self else { return }
            logLine("UITEST translate long frame=\(NSStringFromRect(self.panel?.frame ?? .zero))")
            self.capturePanel(to: "\(NSHomeDirectory())/popdict_translate_long.png")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        }
    }

    // App 把自己的浮窗内容渲染成 PNG(不需要屏幕录制权限),用于真实渲染自测
    private func capturePanel(to path: String) {
        if let cv = panel?.contentView, let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) {
            cv.cacheDisplay(in: cv.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path)); logLine("UITEST captured \(path)")
            }
        }
        if let tv = convoTextView {
            tv.drawsBackground = true
            tv.backgroundColor = ClaudeTheme.paperBg
            if let rep = tv.bitmapImageRepForCachingDisplay(in: tv.bounds) {
                tv.cacheDisplay(in: tv.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "_full.png")))
                }
            }
            tv.drawsBackground = false
        }
    }

    // 搭建会话浮窗骨架(右上角悬浮复制/关闭按钮 + transcript 滚动区 + 底部悬浮胶囊输入栏)
    private func installConversationPanel(topLeft: NSPoint) {
        panelIsResizable = true
        userResized = false
        let w = savedPopupSize().width
        let startH = minPopupSize.height
        let textW = w - convoPad * 2
        let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: startH))
        container.autoresizingMask = [.width, .height]

        // transcript(可选中、滚动、缩放时重排);顶部留出右上角悬浮按钮空间,底部留出胶囊输入栏,右侧留 14pt 给细滚动条
        let scrollerGutter: CGFloat = 14
        let scrollY = inputBarH + transcriptBottomGap
        let scrollH = max(40, startH - scrollY - headerTopH)
        let scroll = NonDraggableScrollView(frame: NSRect(x: convoPad, y: scrollY, width: textW + scrollerGutter, height: scrollH))
        configureWarmScrollView(scroll)
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        let tv = makeTranscriptView(width: textW, scrollerGutter: scrollerGutter)
        scroll.documentView = tv
        container.addSubview(scroll)
        convoScroll = scroll
        convoTextView = tv

        // 底部悬浮胶囊输入栏(无横贯分割线)
        container.addSubview(makeInputBar(width: w))

        // 右上角悬浮「复制」与「关闭 ×」圆形线性按钮
        addTopRightActions(to: container, showCopy: true)

        assistantStart = 0
        assistantAccum = ""
        turnStartLoc = 0

        addGrip(to: container)
        var rect = NSRect(x: topLeft.x, y: topLeft.y - startH, width: w, height: startH)
        rect = clampToScreen(rect, anchor: topLeft)
        present(content: container, rect: rect, isPill: false)
        startAutoGrow()
    }

    // —— 会话浮窗随内容长高 ——

    private func startAutoGrow() {
        growTimer?.invalidate()
        growTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in self?.growToFit() }
    }

    // 强制完整排版并同步 NSTextView 文档总高度(含上下内边距),确保滚动条能滑到最底端
    private func syncTranscriptLayout() {
        guard let tv = convoTextView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        tv.sizeToFit()
        let minH = ceil(lm.usedRect(for: tc).height + tv.textContainerInset.height * 2)
        if tv.frame.height < minH {
            tv.setFrameSize(NSSize(width: tv.frame.width, height: minH))
        }
        if let scroll = convoScroll {
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    // 顶边固定向下生长;只长不缩(防抖);上限见 popupHeightCap
    private func growToFit() {
        syncTranscriptLayout()
        guard frameAnimations == 0, panelIsResizable, !userResized, let p = panel, let tv = convoTextView,
              let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let contentH = ceil(lm.usedRect(for: tc).height + tv.textContainerInset.height * 2)
        let desired = headerTopH + contentH + transcriptBottomGap + inputBarH
        let vf = (p.screen ?? screenFor(point: NSPoint(x: p.frame.minX, y: p.frame.maxY))).visibleFrame
        let newH = min(max(desired, minPopupSize.height), popupHeightCap(vf))
        guard newH > p.frame.height + 1 else { return }
        let newY = max(p.frame.maxY - newH, vf.minY + kScreenEdgeGap)
        if uiTestMode { logLine("UITEST grow h=\(Int(p.frame.height))→\(Int(newH)) w=\(Int(p.frame.width))") }
        programmaticSize = NSSize(width: p.frame.width, height: newH)
        frameAnimations += 1
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(NSRect(x: p.frame.minX, y: newY, width: p.frame.width, height: newH), display: true)
        }, completionHandler: { [weak self] in self?.frameAnimations -= 1 })
    }

    // 建会话浮窗:transcript 滚动区 + 底部追问输入栏(解释时禁用),发起第一轮解释
    private func beginConversation(firstUserText: String) {
        generation += 1   // 作废在途的翻译回调(防止快速「翻译→解释」时旧译文污染会话)
        stopConversation()
        attachedImageDataURL = nil
        convo = [(role: "user", content: firstUserText)]
        let topLeft = panel.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) } ?? NSEvent.mouseLocation
        installConversationPanel(topLeft: topLeft)
        sendTurn()
    }

    // 截图解释:把图存为会话首条 user(每轮重发),顶部放缩略图 + 指令气泡,然后流式解释。
    func beginImageConversation(image: NSImage, instruction: String = "请解释这张图片的内容。") {
        generation += 1
        stopConversation()
        guard let dataURL = RegionCapture.encodeToDataURL(image) else {
            showMessage("图片编码失败,请重试", isError: true)
            return
        }
        attachedImageDataURL = dataURL
        convo = [(role: "user", content: instruction)]
        let vf = screenFor(point: NSEvent.mouseLocation).visibleFrame
        let topLeft = NSPoint(x: vf.midX - savedPopupSize().width / 2, y: vf.maxY - 80)
        installConversationPanel(topLeft: topLeft)
        if let tv = convoTextView, let storage = tv.textStorage {
            storage.append(thumbnailString(image, maxW: savedPopupSize().width - convoPad * 2))
            storage.append(NSAttributedString(string: instruction + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 14.5, weight: .semibold),
                .foregroundColor: ClaudeTheme.inkStrong,
                .paragraphStyle: MD.bodyStyle()]))
        }
        sendTurn()
    }

    // 把图缩放后做成行内附件(贴合浮窗内宽,高度上限 240),返回带尾随换行的富文本
    private func thumbnailString(_ image: NSImage, maxW: CGFloat) -> NSAttributedString {
        let iw = max(1, image.size.width), ih = max(1, image.size.height)
        var dw = min(maxW, iw)
        var dh = dw * ih / iw
        let maxH: CGFloat = 240
        if dh > maxH { dh = maxH; dw = dh * iw / ih }
        let att = NSTextAttachment()
        att.image = image
        att.bounds = CGRect(x: 0, y: 0, width: dw, height: dh)
        let m = NSMutableAttributedString(attributedString: NSAttributedString(attachment: att))
        m.append(NSAttributedString(string: "\n", attributes: [.font: convoFont, .paragraphStyle: MD.bodyStyle()]))
        return m
    }

    // 用自定义 CodeBlockLayoutManager 建可选中、可竖向自适应的 NSTextView(代码块满宽圆角底由它绘制)
    private func makeRenderingTextView(width textW: CGFloat) -> NSTextView {
        let storage = NSTextStorage()
        let lm = CodeBlockLayoutManager()
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: textW, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        lm.addTextContainer(container)
        let tv = SelectableTextView(frame: NSRect(x: 0, y: 0, width: textW, height: 22), textContainer: container)
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.maxSize = NSSize(width: textW, height: .greatestFiniteMagnitude)
        tv.autoresizingMask = [.width]
        return tv
    }

    private func makeTranscriptView(width textW: CGFloat, scrollerGutter: CGFloat = 14) -> NSTextView {
        let tv = makeRenderingTextView(width: textW + scrollerGutter)
        if let stv = tv as? SelectableTextView {
            stv.rightScrollerGutter = scrollerGutter
        }
        tv.textContainerInset = NSSize(width: 0, height: 8)
        tv.minSize = NSSize(width: textW + scrollerGutter, height: 0)
        tv.typingAttributes = [.font: convoFont, .foregroundColor: ClaudeTheme.inkBody, .paragraphStyle: MD.bodyStyle()]
        return tv
    }

    // 底部内嵌式悬浮胶囊输入栏(图1:移除贯穿左右的硬分割线,#FFFFFF 胶囊 + #E3E1D8 细边框 + 右侧赤陶色圆形 ↑ 发送按钮)
    private func makeInputBar(width w: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: w, height: inputBarH))
        bar.autoresizingMask = [.width, .maxYMargin]

        let capH: CGFloat = 38
        let capW = w - convoPad * 2
        let capsule = CapsuleInputContainerView(frame: NSRect(x: convoPad, y: 12, width: capW, height: capH))
        capsule.autoresizingMask = [.width]
        bar.addSubview(capsule)
        capsuleContainer = capsule

        let sendSize: CGFloat = 26
        let sendBtn = SendArrowButton(frame: NSRect(x: capW - sendSize - 6, y: (capH - sendSize) / 2, width: sendSize, height: sendSize))
        sendBtn.target = self
        sendBtn.action = #selector(onAskSubmit)
        sendBtn.isEnabled = false
        sendBtn.autoresizingMask = [.minXMargin]
        capsule.addSubview(sendBtn)
        sendButton = sendBtn

        let fieldH: CGFloat = 21
        let fieldW = capW - 14 - sendSize - 14
        let field = FocusAwareTextField(frame: NSRect(x: 14, y: (capH - fieldH) / 2 - 1, width: fieldW, height: fieldH))
        field.isBordered = false
        field.drawsBackground = false
        field.isEnabled = false
        field.font = NSFont.systemFont(ofSize: 13.5)
        field.textColor = ClaudeTheme.inkStrong
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(onAskSubmit)
        field.autoresizingMask = [.width]
        (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = false
        field.onFocusChange = { [weak capsule] focused in
            capsule?.isFocused = focused
        }
        capsule.addSubview(field)
        askField = field
        setInputPlaceholder("正在生成…")

        return bar
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        capsuleContainer?.isFocused = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        capsuleContainer?.isFocused = false
    }

    private func setInputPlaceholder(_ text: String) {
        guard let field = askField else { return }
        field.placeholderAttributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13.5),
                .foregroundColor: ClaudeTheme.inkMuted
            ]
        )
    }

    // 用当前 convo 发起一轮流式;在 transcript 末尾接续 assistant 段
    private func sendTurn() {
        assistantStart = convoTextView?.textStorage?.length ?? 0
        assistantAccum = ""
        setInputEnabled(false, placeholder: "正在生成…")
        let gen = generation   // 令牌:关窗/换会话(generation+1)后,旧流式回调一律作废,防止污染新会话
        var messages: [[String: Any]] = [["role": "system", "content": AppConfig.shared.resolvedExplainPrompt]]
        for (i, m) in convo.enumerated() {
            if i == 0, m.role == "user", let dataURL = attachedImageDataURL {
                let content: [[String: Any]] = [
                    ["type": "text", "text": m.content],
                    ["type": "image_url", "image_url": ["url": dataURL]]
                ]
                messages.append(["role": "user", "content": content])
            } else {
                messages.append(["role": m.role, "content": m.content])
            }
        }
        convoTask = chatStream(messages,
            onDelta: { [weak self] piece in guard let self = self, gen == self.generation else { return }; self.convoAppendDelta(piece) },
            onDone:  { [weak self] full  in guard let self = self, gen == self.generation else { return }; self.finishTurn(full) },
            onError: { [weak self] msg   in guard let self = self, gen == self.generation else { return }; self.convoError(msg) })
    }

    // 逐字追加(流式途中纯文本,避免半截 markdown 错乱);长高交给定时器节流
    private func convoAppendDelta(_ delta: String) {
        guard let tv = convoTextView, panel != nil else { return }
        assistantAccum += delta
        tv.textStorage?.append(NSAttributedString(string: delta, attributes: [
            .font: convoFont, .foregroundColor: ClaudeTheme.inkBody, .paragraphStyle: MD.bodyStyle()]))
        scrollTranscriptToBottom()
    }

    // 一轮完成:把刚流式的纯文本段替换为 markdown 重渲染,记入上下文,开放追问输入
    private func finishTurn(_ full: String) {
        convoTask = nil
        guard convoTextView != nil else { return }   // 会话已被关闭:忽略迟到的完成回调
        let text = full.trimmingCharacters(in: .whitespacesAndNewlines)
        convo.append((role: "assistant", content: text))
        lastResult = text
        if let tv = convoTextView, let storage = tv.textStorage {
            let len = max(0, storage.length - assistantStart)
            let rendered = MD.render(text, width: (panel?.frame.width ?? convoW) - convoPad * 2, baseFont: convoFont, textColor: ClaudeTheme.inkBody)
            storage.replaceCharacters(in: NSRange(location: assistantStart, length: len), with: rendered)
        }
        setInputEnabled(true, placeholder: "继续追问… (回车发送)")
        focusAskField()
        scrollTranscript(toLocation: turnStartLoc)   // 一轮完成后回到本轮开头(从头读)

        if uiTestMode {
            let asst = convo.filter { $0.role == "assistant" }.count
            if asst == 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self = self, let f = self.askField, f.isEnabled else { return }
                    f.stringValue = "为什么带参数的装饰器要写成三层嵌套函数?简短说。"
                    self.onAskSubmit()
                }
            } else {
                uiTestMode = false
                let users = convo.filter { $0.role == "user" }.count
                logLine("UITEST multiturn: users=\(users) assistants=\(asst)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.capturePanel(to: "\(NSHomeDirectory())/popdict_multiturn.png")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
                }
            }
        }
    }

    private func convoError(_ msg: String) {
        convoTask = nil
        guard convoTextView != nil else { return }   // 会话已被关闭:忽略迟到的错误回调
        let hasAssistant = convo.contains { $0.role == "assistant" }
        if !hasAssistant {
            stopConversation()
            showMessage(msg, isError: true)
            return
        }
        if convo.count > 1, convo.last?.role == "user" { convo.removeLast() }
        if let tv = convoTextView, let storage = tv.textStorage {
            let len = max(0, storage.length - turnStartLoc)
            if len > 0 { storage.deleteCharacters(in: NSRange(location: turnStartLoc, length: len)) }
            storage.append(NSAttributedString(string: "\n⚠️ \(msg)\n", attributes: [
                .font: convoFont, .foregroundColor: ClaudeTheme.terracotta, .paragraphStyle: MD.bodyStyle()]))
        }
        setInputEnabled(true, placeholder: "继续追问… (回车发送)")
        focusAskField()
        scrollTranscriptToBottom()
    }

    // 回车或点击右侧 ↑ 按钮发送追问
    @objc private func onAskSubmit() {
        guard let field = askField, field.isEnabled, let tv = convoTextView else { return }
        let q = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if uiTestMode { logLine("onAskSubmit FIRED q=\(q)") }
        field.stringValue = ""
        turnStartLoc = tv.textStorage?.length ?? 0   // 本轮起点(含追问气泡),失败整轮回滚
        appendUserBubble(q, to: tv)
        convo.append((role: "user", content: q))
        sendTurn()
    }

    // transcript 里追加一条「你的追问」气泡:赤陶色标签 + 浅赤陶暖底
    private func appendUserBubble(_ q: String, to tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let m = NSMutableAttributedString()
        m.append(NSAttributedString(string: "\n", attributes: [.font: convoFont, .paragraphStyle: MD.bodyStyle()]))
        let pLabel = NSMutableParagraphStyle()
        pLabel.firstLineHeadIndent = 12; pLabel.headIndent = 12; pLabel.tailIndent = -12
        pLabel.lineSpacing = 3
        pLabel.paragraphSpacingBefore = 24
        pLabel.paragraphSpacing = 3
        m.append(NSAttributedString(string: "你的追问\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: ClaudeTheme.terracotta,
            .paragraphStyle: pLabel, MD.userMsgKey: true]))
        let pBody = NSMutableParagraphStyle()
        pBody.firstLineHeadIndent = 12; pBody.headIndent = 12; pBody.tailIndent = -12
        pBody.lineSpacing = 4
        pBody.paragraphSpacing = 22
        m.append(NSAttributedString(string: q + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 14.5, weight: .semibold),
            .foregroundColor: ClaudeTheme.inkStrong,
            .paragraphStyle: pBody, MD.userMsgKey: true]))
        storage.append(m)
    }

    private func setInputEnabled(_ enabled: Bool, placeholder: String) {
        askField?.isEnabled = enabled
        sendButton?.isEnabled = enabled
        setInputPlaceholder(placeholder)
        if !enabled { capsuleContainer?.isFocused = false }
    }

    // 仅在用户已停留在本浮窗(已是 key window)时才自动聚焦输入框
    private func focusAskField() {
        guard let p = panel, p.isKeyWindow, let field = askField else { return }
        p.makeFirstResponder(field)
        capsuleContainer?.isFocused = true
    }

    private func screenFor(point: NSPoint) -> NSScreen {
        if let s = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return s
        }
        return NSScreen.screens.min(by: { sqDist(point, $0.frame) < sqDist(point, $1.frame) })
            ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func sqDist(_ p: NSPoint, _ r: NSRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }

    private func scrollTranscriptToBottom() {
        syncTranscriptLayout()
        guard let tv = convoTextView, let scroll = convoScroll else { return }
        let maxY = max(0, tv.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    // 把某字符位置滚到可视区顶部(一轮结束后从本轮开头开始读)
    private func scrollTranscript(toLocation loc: Int) {
        syncTranscriptLayout()
        guard let tv = convoTextView, let lm = tv.layoutManager, let tc = tv.textContainer,
              let scroll = convoScroll, let storage = tv.textStorage else { return }
        let safe = min(max(0, loc), storage.length)
        let gr = lm.glyphRange(forCharacterRange: NSRange(location: safe, length: 0), actualCharacterRange: nil)
        let rect = lm.boundingRect(forGlyphRange: gr, in: tc)
        let targetY = safe == 0 ? 0 : max(0, tv.textContainerOrigin.y + rect.minY - 2)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    // 彻底结束会话:取消网络、停定时器、清状态(失焦关闭 / 新划词 / 新会话时)
    private func stopConversation() {
        convoTask?.cancel(); convoTask = nil
        growTimer?.invalidate(); growTimer = nil
        convoTextView = nil
        convoScroll = nil
        askField = nil
        capsuleContainer = nil
        sendButton = nil
        convo = []
        attachedImageDataURL = nil
        assistantStart = 0
        assistantAccum = ""
    }

    // 真实测量换行后文本的自然宽高(对富文本同样准确;宽度用于短内容收窄窗口)
    private func measuredTextSize(_ attr: NSAttributedString, width: CGFloat) -> NSSize {
        let storage = NSTextStorage(attributedString: attr)
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let lm = NSLayoutManager()
        lm.addTextContainer(container)
        storage.addLayoutManager(lm)
        lm.ensureLayout(for: container)
        let used = lm.usedRect(for: container)
        return NSSize(width: ceil(used.width), height: ceil(used.height))
    }

    private func showMessage(_ message: String, isError: Bool, showCopy: Bool = false, markdown: Bool = false) {
        lastResult = showCopy ? message : nil
        copyButton = nil
        panelIsResizable = showCopy          // 译文结果:可缩放 + 记忆上限;翻译中/错误:瞬时小窗
        let topLeft = panel.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) } ?? NSEvent.mouseLocation

        let pad: CGFloat = showCopy ? 24 : 18
        let topInset: CGFloat = showCopy ? headerTopH : 16
        let bottomInset: CGFloat = showCopy ? 20 : 16
        let font = NSFont.systemFont(ofSize: 14.5)
        let textColor = isError ? ClaudeTheme.terracotta : ClaudeTheme.inkBody

        // 尺寸自适应:短译文紧凑但留出右上角悬浮按钮空间,长译文到上限后内部滚动
        let maxW: CGFloat = showCopy ? savedPopupSize().width : 420
        let minW: CGFloat = showCopy ? 280 : 112

        let attr = markdown
            ? MD.render(message, width: maxW - pad * 2, baseFont: font, textColor: textColor)
            : NSAttributedString(string: message, attributes: [.font: font, .foregroundColor: textColor, .paragraphStyle: MD.bodyStyle()])
        let natural = measuredTextSize(attr, width: maxW - pad * 2)
        let w = min(max(natural.width + pad * 2 + 4, minW), maxW)
        let textW = w - pad * 2

        let contentH = max(24, natural.height)
        let vf = (panel?.screen ?? screenFor(point: topLeft)).visibleFrame
        let maxContentH = showCopy
            ? popupHeightCap(vf) - topInset - bottomInset
            : min(440, vf.height - 140)
        let visibleH = max(32, min(contentH, maxContentH))
        let panelH = topInset + visibleH + bottomInset

        let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: panelH))
        if showCopy { container.autoresizingMask = [.width, .height] }
        let scroll = NonDraggableScrollView(frame: NSRect(x: pad, y: bottomInset, width: textW, height: visibleH))
        configureWarmScrollView(scroll)
        scroll.hasVerticalScroller = contentH > visibleH
        if showCopy { scroll.autoresizingMask = [.width, .height] }

        let tv = makeRenderingTextView(width: textW)
        tv.textColor = textColor
        tv.minSize = NSSize(width: textW, height: visibleH)
        tv.textStorage?.setAttributedString(attr)
        scroll.documentView = tv
        container.addSubview(scroll)

        // 译文结果:右上角悬浮「复制」与「关闭 ×」圆形线性按钮 + 右下握把(移除旧版底部横贯分割线)
        if showCopy {
            addTopRightActions(to: container, showCopy: true)
            addGrip(to: container)
        }

        var rect = NSRect(x: topLeft.x, y: topLeft.y - panelH, width: w, height: panelH)
        rect = clampToScreen(rect, anchor: topLeft)
        present(content: container, rect: rect, isPill: !showCopy)
        tv.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    // 内容浮窗自动长高的上限:默认 460;用户手动拉大后按记忆值抬高
    private func popupHeightCap(_ vf: NSRect) -> CGFloat {
        return min(max(savedPopupSize().height, defaultPopupSize.height), vf.height - 12)
    }

    private func savedPopupSize() -> NSSize {
        if let a = UserDefaults.standard.array(forKey: kPopupSizeKey) as? [CGFloat], a.count == 2,
           a[0] >= minPopupSize.width, a[1] >= minPopupSize.height {
            return NSSize(width: a[0], height: a[1])
        }
        return defaultPopupSize
    }
    private func savePopupSize(_ s: NSSize) { UserDefaults.standard.set([s.width, s.height], forKey: kPopupSizeKey) }

    // 给内容浮窗右下角加拖拽握把(松手存尺寸)
    private func addGrip(to container: NSView) {
        let g = ResizeGripView(frame: NSRect(x: container.bounds.width - 18, y: 0, width: 18, height: 18))
        g.autoresizingMask = [.minXMargin, .maxYMargin]
        g.onCommit = { [weak self] in
            guard let self = self, let p = self.panel else { return }
            self.userResized = true                 // 用户手动定了尺寸:本轮会话不再自动长高
            self.savePopupSize(p.frame.size)
        }
        container.addSubview(g)
    }

    func windowDidResize(_ notification: Notification) {
        syncTranscriptLayout()
    }

    // 边缘缩放结束:记住尺寸(仅内容浮窗),并交还尺寸控制权(本轮会话不再自动长高)。
    func windowDidEndLiveResize(_ notification: Notification) {
        syncTranscriptLayout()
        guard panelIsResizable, let p = panel, frameAnimations == 0 else { return }
        if abs(p.frame.width - programmaticSize.width) < 2,
           abs(p.frame.height - programmaticSize.height) < 2 { return }
        userResized = true
        savePopupSize(p.frame.size)
    }

    private func makePanel(_ rect: NSRect, isPill: Bool = false) -> NSPanel {
        let p = KeyablePanel(contentRect: rect,
                        styleMask: [.borderless, .nonactivatingPanel, .resizable],
                        backing: .buffered, defer: false)
        p.appearance = NSAppearance(named: .aqua)
        p.minSize = minPopupSize
        p.delegate = self
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true        // 输入框点击才取焦点;翻译/解释浮窗不抢焦点
        p.isMovableByWindowBackground = true   // 拖背景空白处即可移动窗口
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.animationBehavior = .none

        let paper = DraggablePaperView(frame: NSRect(origin: .zero, size: rect.size))
        paper.cornerRadius = isPill ? 10 : 14
        paper.borderColor = isPill ? ClaudeTheme.pillBorder : ClaudeTheme.windowBorder
        paper.autoresizingMask = [.width, .height]
        p.contentView = paper
        return p
    }

    // 按钮气泡定位(纯几何在 Geometry.swift,可单测):
    //   浮窗左上角 (minX, maxY) 精确落在鼠标释放光标右下角 (pt.x + 8, pt.y - 8);
    //   之后展开的翻译/解释浮窗保持该左上角锚点向右、向下生长,超出可视区时由 clampToScreen 夹紧。
    private func buttonRect(w: CGFloat, h: CGFloat, at point: NSPoint) -> NSRect {
        let vf = screenFor(point: point).visibleFrame
        return rectAtCursorBottomRight(point, visible: vf, w: w, h: h)
    }

    private func clampToScreen(_ rect: NSRect, anchor: NSPoint? = nil) -> NSRect {
        let refPoint = anchor ?? NSPoint(x: rect.minX, y: rect.maxY)
        let vf = (panel?.screen ?? screenFor(point: refPoint)).visibleFrame
        return clampRectToVisible(rect, visible: vf)
    }
}

// MARK: - 全局鼠标事件 tap(CGEventTap)+ 自愈 + 授权后重建

var gDownLoc: CGPoint = .zero
var gDownInsidePopup = false
var gEventTap: CFMachPort?
var gRunLoopSource: CFRunLoopSource?
var gTapPollTimer: Timer?
weak var gAppDelegate: AppDelegate?

let kDragThreshold: CGFloat = 12   // 提高门槛,过滤点选/微抖动误触
var gFetchInFlight = false         // 取词互斥(仅在主线程读写):同一时刻只跑一个,避免剪贴板并发竞态

func handleMouseUp(down: CGPoint, up: CGPoint) {
    let dist = hypot(up.x - down.x, up.y - down.y)
    logLine("tap mouseUp dist=\(String(format: "%.1f", dist))")
    if dist < kDragThreshold { return }
    if gFetchInFlight { logLine("  skip: fetch in flight"); return }   // 上一次取词还没完,丢弃这次
    gFetchInFlight = true
    // 取词放后台线程,避免 usleep 阻塞主 runloop 导致 tap 超时被禁用
    DispatchQueue.global(qos: .userInitiated).async {
        usleep(50_000)
        let ax = selectedTextViaAX()
        let text = ax ?? selectedTextViaCopy()
        logLine("  AX=\(ax != nil ? "ok" : "nil") final=\(text ?? "nil")")
        DispatchQueue.main.async {
            gFetchInFlight = false
            guard let text = text else { return }
            // 锚点用「释放那一刻」的光标位置(Quartz→AppKit 翻转),精确落在光标右下角
            let upAK = NSPoint(x: up.x, y: primaryScreenHeight() - up.y)
            gAppDelegate?.popup.showButton(text: text, fallbackPoint: upAK)
        }
    }
}

let gEventCallback: CGEventTapCallBack = { _, type, event, _ in
    // tap 被系统自动禁用时立即重新启用(自愈)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = gEventTap { CGEvent.tapEnable(tap: t, enable: true) }
        logLine("TAP_RE_ENABLED type=\(type.rawValue)")
        return Unmanaged.passUnretained(event)
    }

    let loc = event.location
    if type == .leftMouseDown {
        gDownLoc = loc
        DispatchQueue.main.async {
            gDownInsidePopup = false
            if let ad = gAppDelegate, ad.popup.isVisible, let f = ad.popup.frame() {
                if f.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) {
                    gDownInsidePopup = true        // 点在浮窗内:让用户选字/点按钮,不关、不当作新划词
                } else if ad.popup.isComposingText {
                    gDownInsidePopup = true        // 输入法候选窗在浮窗外:点候选词不关、不当作新划词
                } else {
                    ad.popup.dismiss()             // 点在浮窗外:失焦关闭
                }
            }
        }
    } else if type == .leftMouseUp {
        let down = gDownLoc
        DispatchQueue.main.async {
            if gDownInsidePopup { gDownInsidePopup = false; return }  // 在浮窗里的拖选,不触发新气泡
            handleMouseUp(down: down, up: loc)
        }
    }
    return Unmanaged.passUnretained(event)
}

@discardableResult
func setupEventTap() -> Bool {
    if let tap = gEventTap {                       // 已建过,确保启用
        CGEvent.tapEnable(tap: tap, enable: true)
        let ok = CGEvent.tapIsEnabled(tap: tap)
        logLine("EVENT_TAP_REENABLE enabled=\(ok)")
        return ok
    }
    let mask = (UInt64(1) << CGEventType.leftMouseDown.rawValue) | (UInt64(1) << CGEventType.leftMouseUp.rawValue)
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: CGEventMask(mask),
        callback: gEventCallback,
        userInfo: nil) else {
        logLine("EVENT_TAP_CREATE_FAILED trusted=\(AXIsProcessTrusted())")
        return false
    }
    let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    gEventTap = tap
    gRunLoopSource = src
    // listen-only tap 在无权限时 tapCreate 不返回 nil,但 tapIsEnabled 为 false
    let enabled = CGEvent.tapIsEnabled(tap: tap)
    logLine("EVENT_TAP_CREATED enabled=\(enabled) trusted=\(AXIsProcessTrusted())")
    return enabled
}

// MARK: - 全局热键(Carbon)

// 注册一个系统级热键(默认 ⌃⌥E),按下时在主线程触发回调(截图解释)。
// 用 Carbon RegisterEventHotKey:系统级、稳定、能消费按键、无需额外权限。
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handlerInstalled = false
    private static var actions: [UInt32: () -> Void] = [:]   // C 回调不能捕获上下文,按 id 查表

    @discardableResult
    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32, action: @escaping () -> Void) {
        HotKey.actions[id] = action
        if !HotKey.handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                var hkID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                HotKey.actions[hkID.id]?()
                return noErr
            }, 1, &spec, nil, nil)
            HotKey.handlerInstalled = true
        }
        let hkID = EventHotKeyID(signature: OSType(0x504f5044), id: id)   // 'POPD'
        let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { logLine("HOTKEY register failed status=\(status)"); return nil }
        logLine("HOTKEY registered id=\(id) keyCode=\(keyCode)")
    }
}

// macOS Tahoe 26 起会自动给「标准动作」菜单项配图标(如「设置…」的齿轮)。
// 通过关联对象仅允许显式调用 setExplicitIcon(_:) 的菜单项(如服务商下拉里的品牌 Logo)显示图标,
// 其余未显式设置图标的菜单项一律返回 nil,避免状态栏菜单出现自动图标与多余缩进。
private var kExplicitMenuIconKey: UInt8 = 0
extension NSMenuItem {
    func setExplicitIcon(_ img: NSImage?) {
        objc_setAssociatedObject(self, &kExplicitMenuIconKey, img, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        self.image = img
    }
    @objc func popdict_customImage() -> NSImage? {
        return objc_getAssociatedObject(self, &kExplicitMenuIconKey) as? NSImage
    }
    static func popdictDisableAutoIcons() {
        guard let o = class_getInstanceMethod(NSMenuItem.self, #selector(getter: NSMenuItem.image)),
              let r = class_getInstanceMethod(NSMenuItem.self, #selector(NSMenuItem.popdict_customImage)) else { return }
        method_exchangeImplementations(o, r)
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    let popup = PopupController()
    let settings = SettingsController()
    var statusItem: NSStatusItem?
    var hotKey: HotKey?
    var activeCapture: RegionCapture?      // 截图期间强持有 RegionCapture,避免遮罩提前释放

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = BrandLogo.appIconImage()
        enableBackgroundCursorSetting()        // 允许 nonactivatingPanel 在后台应用下切换工字形 I-Beam 光标
        NSMenuItem.popdictDisableAutoIcons()   // 关掉 macOS 26 的菜单自动图标(否则「设置…」齿轮致整菜单缩进)
        ensureConfigDir()
        AppConfig.shared.load()
        logLine("=== launch AX_TRUSTED=\(AXIsProcessTrusted()) configDir=\(FileManager.default.fileExists(atPath: kConfigDir)) ===")
        gAppDelegate = self
        setupMainMenu()

        // UI 截图自测(不建事件 tap / 不请求权限),便于截屏验证真实渲染:
        //   GLINT_UITEST=translate → 翻译流程(本地、不走网络)
        //   GLINT_UITEST=settings  → 设置窗口四 Tab 自检
        //   其它值 → 解释会话流程(走真实 API)
        if let mode = ProcessInfo.processInfo.environment["GLINT_UITEST"] ?? ProcessInfo.processInfo.environment["POPDICT_UITEST"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self = self else { return }
                if mode == "translate" {
                    self.popup.runDemoTranslate()
                } else if mode == "claude_ui" {
                    self.popup.runDemoClaudeUI()
                } else if mode == "settings" {
                    self.settings.show(tab: 0)
                    logLine("UITEST settings tab=0 (基础) frame=\(self.settings.windowObject?.frame ?? .zero)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        self.settings.selectTab(1)
                        logLine("UITEST settings tab=1 (权限) frame=\(self.settings.windowObject?.frame ?? .zero)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            self.settings.selectTab(2)
                            logLine("UITEST settings tab=2 (服务商) frame=\(self.settings.windowObject?.frame ?? .zero)")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                self.settings.selectTab(3)
                                logLine("UITEST settings tab=3 (语言) frame=\(self.settings.windowObject?.frame ?? .zero)")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    NSApp.terminate(nil)
                                }
                            }
                        }
                    }
                } else if mode == "capture_screens" {
                    let rc = RegionCapture()
                    self.activeCapture = rc
                    rc.capture { _ in }
                    let screenFrames = NSScreen.screens.map { NSStringFromRect($0.frame) }
                    let winFrames = rc.activeWindowFrames().map { NSStringFromRect($0) }
                    logLine("UITEST capture_screens screens=\(screenFrames) windows=\(winFrames)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NSApp.terminate(nil)
                    }
                } else {
                    self.popup.runDemoExplain()
                }
            }
            return
        }

        setupStatusItem()

        // 全局热键 ⌃⌥E 触发截图解释(与划词监听互不依赖)
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_E),
                        modifiers: UInt32(controlKey | optionKey),
                        id: 1) { [weak self] in
            DispatchQueue.main.async { self?.onScreenshotExplain() }
        }

        if AXIsProcessTrusted() {
            setupEventTap()
        } else {
            requestAccessibility()          // 弹一次系统授权提示
            startWaitingForAccessibility()  // 轮询,授权后自动建 tap
        }
    }

    func startWaitingForAccessibility() {
        logLine("waiting for accessibility…")
        gTapPollTimer?.invalidate()
        gTapPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            if AXIsProcessTrusted() {
                let ok = setupEventTap()
                logLine("accessibility granted, tap setup ok=\(ok)")
                if ok {
                    t.invalidate()
                    gTapPollTimer = nil
                }
                self?.refreshMenu()
            }
        }
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        return menu
    }

    // accessory App 不显示菜单栏,但有了 mainMenu 后 ⌘C/⌘V/⌘X/⌘A/撤销 的 key equivalent 才能在追问框生效
    func setupMainMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        editItem.submenu = edit
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = mainMenu
    }

    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = item.button {
            btn.image = BrandLogo.menuBarIcon()
            btn.imagePosition = .imageOnly
            btn.toolTip = "Glint"
        }
        item.menu = buildMenu()
        statusItem = item
    }

    func refreshMenu() {
        statusItem?.menu = buildMenu()
        settings.refreshPermissions()
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    @objc func openAXSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // 截图解释:无屏幕录制权限先引导,否则弹框选遮罩,截完交给图片会话浮窗
    @objc func onScreenshotExplain() {
        guard AppConfig.shared.active?.vision == true else {
            let a = NSAlert()
            a.messageText = "当前服务商不支持看图"
            a.informativeText = "当前使用的「\(AppConfig.shared.active?.name ?? "?")」没有勾选「支持看图」。请点菜单栏 Glint 图标 →「设置…」→「服务商」,切换到一个支持看图的服务商(如 Vertex AI、Gemini、MiMo)或勾选「支持看图」。"
            a.addButton(withTitle: "打开设置"); a.addButton(withTitle: "取消")
            NSApp.activate(ignoringOtherApps: true)
            if a.runModal() == .alertFirstButtonReturn { settings.show(tab: 2) }
            return
        }
        if !RegionCapture.hasScreenRecordingPermission() {
            let granted = RegionCapture.requestScreenRecordingPermission()
            let a = NSAlert()
            NSApp.activate(ignoringOtherApps: true)
            if granted {
                // 用户刚在系统弹窗里授权:本进程通常要重开 App 才真正生效
                a.messageText = "屏幕录制权限已授予"
                a.informativeText = "权限已开启。首次授予后通常需要重新打开 Glint 才会真正生效,然后再用 ⌃⌥E 截图解释。"
                a.addButton(withTitle: "好的")
                a.runModal()
            } else {
                // 之前已被拒绝(系统不再弹窗)或刚拒绝:引导去设置手动打开
                a.messageText = "需要「屏幕录制」权限"
                a.informativeText = "截图解释要用到屏幕录制权限。请在 系统设置 → 隐私与安全性 → 屏幕录制 里打开 Glint。\n\n注意:首次授予后通常需要重新打开 Glint 才会生效。"
                a.addButton(withTitle: "打开设置")
                a.addButton(withTitle: "取消")
                if a.runModal() == .alertFirstButtonReturn { openScreenRecordingSettings() }
            }
            refreshMenu()
            return
        }
        let rc = RegionCapture()
        activeCapture = rc
        rc.capture { [weak self] image in
            self?.activeCapture = nil
            guard let self = self, let image = image else { return }
            self.popup.beginImageConversation(image: image)
        }
    }

    @objc func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openSettings() { settings.show() }

    @objc func recheck() {
        logLine("manual recheck AX_TRUSTED=\(AXIsProcessTrusted())")
        if AXIsProcessTrusted() {
            setupEventTap()
            gTapPollTimer?.invalidate(); gTapPollTimer = nil
        } else if gTapPollTimer == nil {
            requestAccessibility()
            startWaitingForAccessibility()
        }
        refreshMenu()
    }

    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - 启动

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
