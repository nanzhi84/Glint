import AppKit

// ============================================================
// Claude Blog (Anthropic 官网专栏) 暖纸色调与排版主题
// ============================================================

enum ClaudeTheme {
    static let paperBg        = NSColor(srgbRed: 250/255, green: 249/255, blue: 245/255, alpha: 1.0) // #FAF9F5 暖米白主背景
    static let paperAltBg     = NSColor(srgbRed: 245/255, green: 244/255, blue: 239/255, alpha: 1.0) // #F5F4EF 次级暖底
    static let pillHoverBg    = NSColor(srgbRed: 239/255, green: 236/255, blue: 230/255, alpha: 1.0) // #EFECE6 按钮悬停暖色块
    static let calloutBg      = NSColor(srgbRed: 243/255, green: 239/255, blue: 230/255, alpha: 1.0) // #F3EFE6 引用卡片暖底
    static let calloutBorder  = NSColor(srgbRed: 232/255, green: 227/255, blue: 215/255, alpha: 1.0) // #E8E3D7 引用卡片细边框
    static let codeBg         = NSColor(srgbRed: 242/255, green: 239/255, blue: 232/255, alpha: 1.0) // #F2EFE8 代码块暖底
    static let codeBorder     = NSColor(srgbRed: 227/255, green: 225/255, blue: 216/255, alpha: 1.0) // #E3E1D8 代码块/输入框边框
    static let windowBorder   = NSColor(srgbRed: 232/255, green: 230/255, blue: 222/255, alpha: 1.0) // #E8E6DE 弹窗外边框与分割线
    static let pillBorder     = NSColor(srgbRed: 227/255, green: 225/255, blue: 216/255, alpha: 1.0) // #E3E1D8 快捷悬浮条外边框
    static let inkStrong      = NSColor(srgbRed: 20/255,  green: 20/255,  blue: 19/255,  alpha: 1.0) // #141413 标题与强调纯深色
    static let inkBody        = NSColor(srgbRed: 45/255,  green: 45/255,  blue: 42/255,  alpha: 1.0) // #2D2D2A 正文暖深炭灰
    static let inkMuted       = NSColor(srgbRed: 115/255, green: 114/255, blue: 108/255, alpha: 1.0) // #73726C 次要文字与占位符
    static let terracotta     = NSColor(srgbRed: 217/255, green: 119/255, blue: 87/255,  alpha: 1.0) // #D97757 Anthropic 赤陶色
    static let terracottaSoft = NSColor(srgbRed: 217/255, green: 119/255, blue: 87/255,  alpha: 0.14)
    static let scrollbarThumb = NSColor(srgbRed: 20/255,  green: 20/255,  blue: 19/255,  alpha: 0.15) // rgba(20,20,19,0.15)

    // 衬线标题字体(优先思源宋体 / 宋体-简 Bold / 系统衬线体,营造 Claude Blog 书卷感)
    static func serifHeadingFont(size: CGFloat) -> NSFont {
        let candidates = [
            "SourceHanSerifSC-Bold",
            "NotoSerifCJKsc-Bold",
            "STSongti-SC-Bold",
            "STSongti-SC-Black",
            "Songti SC",
            "Georgia-Bold"
        ]
        for name in candidates {
            if let f = NSFont(name: name, size: size) {
                let bold = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask)
                return bold
            }
        }
        if let desc = NSFont.systemFont(ofSize: size, weight: .bold).fontDescriptor.withDesign(.serif),
           let f = NSFont(descriptor: desc, size: size) {
            return f
        }
        return NSFont.boldSystemFont(ofSize: size)
    }

    static func boldFont(from base: NSFont) -> NSFont {
        let converted = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        if converted.fontDescriptor.symbolicTraits.contains(.bold) {
            return converted
        }
        let d = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.bold))
        if let f = NSFont(descriptor: d, size: base.pointSize),
           f.fontDescriptor.symbolicTraits.contains(.bold) {
            return f
        }
        return NSFont.boldSystemFont(ofSize: base.pointSize)
    }
}

// ============================================================
// 轻量 Markdown → NSAttributedString 渲染器(块级 + 行内)
// 块级:标题 # ~ ######、无序/有序列表、代码块 ```、分隔线 ---、引用 >、表格 | a | b |
// 行内:**粗体**(支持 CJK 与全半角括号紧邻) *斜体* `行内代码` [链接](url)
// 自包含,无外部依赖,可单独编译做离屏测试。
// ============================================================

enum MD {

    // 代码块标记:LayoutManager 据此在整段后面画满宽圆角底
    static let codeBlockKey = NSAttributedString.Key("glintCodeBlock")
    // 追问气泡标记:LayoutManager 据此画暖色圆角底(区分用户追问与 AI 回答)
    static let userMsgKey = NSAttributedString.Key("glintUserMsg")
    // 引用/类比卡片标记:LayoutManager 据此画暖米色圆角卡片
    static let quoteBlockKey = NSAttributedString.Key("glintQuoteBlock")
    // 三级小标题左侧赤陶色竖线标记
    static let subHeadingBarKey = NSAttributedString.Key("glintSubHeadingBar")

    private static let boldOpenSentinel: Character = "\u{FFF9}"
    private static let boldCloseSentinel: Character = "\u{FFFA}"

    // MARK: 主入口

    static func render(_ src: String,
                       width: CGFloat,
                       baseFont: NSFont = .systemFont(ofSize: 14.5),
                       textColor: NSColor = ClaudeTheme.inkBody) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let lines = src.replacingOccurrences(of: "\r\n", with: "\n")
                       .replacingOccurrences(of: "\r", with: "\n")
                       .components(separatedBy: "\n")
        var i = 0
        var para: [String] = []
        var listIndents: [Int] = []   // 嵌套列表的缩进栈:把「前导空格数」动态映射成层级

        func flushPara() {
            guard !para.isEmpty else { return }
            let text = para.joined(separator: "\n")
            para.removeAll()
            let a = NSMutableAttributedString(attributedString:
                inlineAttributed(text, baseFont: baseFont, color: textColor))
            a.addAttribute(.paragraphStyle, value: bodyStyle(),
                           range: NSRange(location: 0, length: a.length))
            out.append(a)
            out.append(NSAttributedString(string: "\n"))
        }

        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)

            // 非列表的内容行会终结当前列表:清空缩进栈,下一个列表重新计层。
            // 空行不清(宽松列表:模型常在列表项之间留空行)。
            let itemParsed = listItem(line)
            if itemParsed == nil, !t.isEmpty { listIndents.removeAll() }

            // 代码块
            if t.hasPrefix("```") {
                flushPara()
                var code: [String] = []
                i += 1
                while i < lines.count,
                      !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                if i < lines.count { i += 1 } // 跳过结尾 ```
                out.append(codeBlock(code.joined(separator: "\n"), baseFont: baseFont))
                continue
            }
            // 空行
            if t.isEmpty { flushPara(); i += 1; continue }
            // 分隔线
            if isHR(t) {
                flushPara(); out.append(horizontalRule(width: width)); i += 1; continue
            }
            // 标题
            if let (level, content) = heading(t) {
                flushPara()
                out.append(headingAttr(content, level: level, baseFont: baseFont, color: textColor))
                i += 1; continue
            }
            // 表格(GFM):本行含 | 且下一行是 |---|---| 分隔行
            if t.contains("|"), i + 1 < lines.count, isTableDelimiter(lines[i + 1]) {
                flushPara()
                let header = splitTableRow(line)
                let aligns = tableAligns(lines[i + 1], columns: header.count)
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let rt = lines[i].trimmingCharacters(in: .whitespaces)
                    if rt.isEmpty || !rt.contains("|") { break }
                    rows.append(splitTableRow(lines[i]))
                    i += 1
                }
                out.append(tableAttr(header: header, aligns: aligns, rows: rows, baseFont: baseFont, color: textColor))
                continue
            }
            // 引用(连续多行 > 合并为同一个引用卡片块)
            if t.hasPrefix(">") {
                flushPara()
                var qLines: [String] = []
                while i < lines.count {
                    let qt = lines[i].trimmingCharacters(in: .whitespaces)
                    guard qt.hasPrefix(">") else { break }
                    let stripped = String(qt.drop(while: { $0 == ">" || $0 == " " }))
                    if !stripped.isEmpty { qLines.append(stripped) }
                    i += 1
                }
                if !qLines.isEmpty {
                    out.append(quoteAttr(qLines.joined(separator: "\u{2028}"), baseFont: baseFont, color: textColor))
                }
                continue
            }
            // 列表项:层级由缩进栈决定——比上一项缩得更深就进一层,变浅就弹栈回退。
            // 不做「除以固定空格数」的猜测,兼容 2/3/4 空格与 tab 的各种缩进风格
            // (模型常用 4 空格,旧算法「÷2」会把一层嵌套算成两层,缩进大得离谱)。
            if let item = itemParsed {
                flushPara()
                while let last = listIndents.last, item.leading < last { listIndents.removeLast() }
                if listIndents.isEmpty || item.leading > listIndents.last! { listIndents.append(item.leading) }
                out.append(listAttr(item, level: listIndents.count - 1, baseFont: baseFont, color: textColor))
                i += 1; continue
            }
            // 普通段落(连续非空行合并为一段)
            para.append(t); i += 1
        }
        flushPara()

        // 去掉结尾多余换行
        while out.length > 0, (out.string as NSString).hasSuffix("\n") {
            out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1))
        }
        // 若结尾是带圆角背景卡片的引用块(padY=9)或代码块(padY=8),补一行不带卡片标记的底部留白行,
        // 使 NSLayoutManager.usedRect 的下界完整包住卡片下内边距与底边框,防止滚动到底部时被裁切。
        if out.length > 0 {
            let lastIdx = out.length - 1
            let hasQuote = (out.attribute(quoteBlockKey, at: lastIdx, effectiveRange: nil) as? Bool) == true
            let hasCode  = (out.attribute(codeBlockKey,  at: lastIdx, effectiveRange: nil) as? Bool) == true
            if hasQuote || hasCode {
                let sp = NSMutableParagraphStyle()
                sp.paragraphSpacingBefore = 4
                sp.lineSpacing = 0
                sp.paragraphSpacing = 0
                out.append(NSAttributedString(string: "\n ", attributes: [
                    .font: NSFont.systemFont(ofSize: 10),
                    .paragraphStyle: sp
                ]))
            }
        }
        return out
    }

    // MARK: 行内(CJK 括号友好粗体预处理 + Apple inline markdown)

    // 将非行内代码段中的 **...** 替换为哨兵字符,规避 CommonMark 对中文紧邻全/半角括号如
    // `**推理期计算扩展 (Inference-Time Scaling)**来弥补` 无法识别右翼分隔符的缺陷,同时保留 `**code**` 原样。
    private static func preprocessCJKBold(_ s: String) -> String {
        var result = ""
        var i = s.startIndex
        var inCode = false

        while i < s.endIndex {
            let ch = s[i]
            if ch == "`" {
                inCode.toggle()
                result.append(ch)
                i = s.index(after: i)
                continue
            }
            if !inCode, s[i...].hasPrefix("**") {
                let contentStart = s.index(i, offsetBy: 2)
                if contentStart < s.endIndex,
                   let closeRange = s.range(of: "**", range: contentStart..<s.endIndex) {
                    let inner = s[contentStart..<closeRange.lowerBound]
                    if !inner.isEmpty, !inner.contains("\n"), !inner.contains("`") {
                        result.append(boldOpenSentinel)
                        result.append(contentsOf: inner)
                        result.append(boldCloseSentinel)
                        i = closeRange.upperBound
                        continue
                    }
                }
            }
            result.append(ch)
            i = s.index(after: i)
        }
        return result
    }

    static func inlineAttributed(_ s: String, baseFont: NSFont, color: NSColor) -> NSAttributedString {
        let prepared = preprocessCJKBold(s)
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let parsed: NSAttributedString
        if let p = try? NSAttributedString(markdown: prepared, options: opts) {
            parsed = p
        } else {
            parsed = NSAttributedString(string: prepared, attributes: [.font: baseFont, .foregroundColor: color])
        }
        let m = NSMutableAttributedString(attributedString: parsed)
        var full = NSRange(location: 0, length: m.length)

        // 1) 字体统一到 baseFont 字号,保留粗/斜 traits
        m.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            let traits = (value as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            if traits.contains(.bold) {
                m.addAttribute(.font, value: ClaudeTheme.boldFont(from: baseFont), range: range)
            } else if traits.contains(.italic) {
                let d = baseFont.fontDescriptor.withSymbolicTraits(.italic)
                m.addAttribute(.font, value: NSFont(descriptor: d, size: baseFont.pointSize) ?? baseFont, range: range)
            } else {
                m.addAttribute(.font, value: baseFont, range: range)
            }
        }
        m.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            if value == nil { m.addAttribute(.font, value: baseFont, range: range) }
        }
        // 2) 统一前景色
        m.addAttribute(.foregroundColor, value: color, range: full)

        // 2.5) 还原哨兵包裹的 CJK 粗体片段并赋予粗体 + 深炭黑强调色
        let openStr = String(boldOpenSentinel)
        let closeStr = String(boldCloseSentinel)
        while true {
            let ns = m.string as NSString
            let openRange = ns.range(of: openStr)
            guard openRange.location != NSNotFound else { break }
            let searchStart = openRange.location + openRange.length
            guard searchStart <= ns.length else {
                m.deleteCharacters(in: openRange)
                break
            }
            let closeRange = ns.range(of: closeStr, options: [], range: NSRange(location: searchStart, length: ns.length - searchStart))
            guard closeRange.location != NSNotFound else {
                m.deleteCharacters(in: openRange)
                break
            }
            m.deleteCharacters(in: closeRange)
            m.deleteCharacters(in: openRange)
            let boldRange = NSRange(location: openRange.location, length: closeRange.location - searchStart)
            if boldRange.length > 0 {
                m.addAttribute(.font, value: ClaudeTheme.boldFont(from: baseFont), range: boldRange)
                m.addAttribute(.foregroundColor, value: ClaudeTheme.inkStrong, range: boldRange)
            }
        }

        full = NSRange(location: 0, length: m.length)
        // 3) 行内代码:等宽 + 暖米灰底
        m.enumerateAttribute(.inlinePresentationIntent, in: full, options: []) { value, range, _ in
            guard let raw = (value as? NSNumber)?.uintValue ?? (value as? UInt) else { return }
            let intent = InlinePresentationIntent(rawValue: raw)
            if intent.contains(.code) {
                let mono = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1.0, weight: .regular)
                m.addAttribute(.font, value: mono, range: range)
                m.addAttribute(.backgroundColor, value: ClaudeTheme.pillHoverBg, range: range)
                m.addAttribute(.foregroundColor, value: ClaudeTheme.inkStrong, range: range)
            }
        }
        // 4) 链接:赤陶色 + 下划线
        m.enumerateAttribute(.link, in: full, options: []) { value, range, _ in
            if value != nil {
                m.addAttribute(.foregroundColor, value: ClaudeTheme.terracotta, range: range)
                m.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
        return m
    }

    // MARK: 段落样式(行高 ~1.7, 段间距 13pt)

    static func bodyStyle() -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 6.5
        p.paragraphSpacing = 13
        return p
    }

    // MARK: 标题(一/二级采用衬线体拉开气质层级,三级左侧配赤陶色竖条)

    private static func heading(_ s: String) -> (Int, String)? {
        var n = 0
        var idx = s.startIndex
        while idx < s.endIndex, s[idx] == "#", n < 6 { n += 1; idx = s.index(after: idx) }
        guard n > 0, idx < s.endIndex, s[idx] == " " else { return nil }
        var content = String(s[s.index(after: idx)...])
        // 去掉 ATX 闭合井号:"## 标题 ##" → "标题"
        content = content.trimmingCharacters(in: .whitespaces)
        while content.hasSuffix("#") { content.removeLast() }
        content = content.trimmingCharacters(in: .whitespaces)
        return (n, content)
    }

    private static func headingAttr(_ content: String, level: Int, baseFont: NSFont, color: NSColor) -> NSAttributedString {
        let size: CGFloat
        let before: CGFloat, after: CGFloat
        switch level {
        case 1: size = 22;   before = 14; after = 10
        case 2: size = 20;   before = 16; after = 9
        case 3: size = 15.5; before = 14; after = 6
        default: size = 14.5; before = 10; after = 4
        }
        let f = ClaudeTheme.serifHeadingFont(size: size)
        let m = NSMutableAttributedString(attributedString: inlineAttributed(content, baseFont: f, color: ClaudeTheme.inkStrong))
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = before
        p.paragraphSpacing = after
        p.lineSpacing = 4
        if level >= 3 {
            p.firstLineHeadIndent = 11
            p.headIndent = 11
            m.addAttribute(subHeadingBarKey, value: true, range: NSRange(location: 0, length: m.length))
        }
        m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length))
        m.append(NSAttributedString(string: "\n"))
        return m
    }

    // MARK: 列表(赤陶色 #D97757 微缩圆点)

    private struct Item { let leading: Int; let marker: String; let text: String }

    private static func listItem(_ line: String) -> Item? {
        // 前导空白宽度:空格 1、tab 按 4 算(层级由 render 的缩进栈决定,这里只报宽度)
        var leading = 0
        var start = line.startIndex
        while start < line.endIndex {
            if line[start] == " " { leading += 1 }
            else if line[start] == "\t" { leading += 4 }
            else { break }
            start = line.index(after: start)
        }
        let s = String(line[start...])
        // 无序(含任务列表 [ ] / [x])
        if let first = s.first, "-*+".contains(first) {
            let rest = s.dropFirst()
            if rest.first == " " {
                var text = String(rest.drop(while: { $0 == " " }))
                var marker = "•"
                if text.hasPrefix("[ ] ") { marker = "☐"; text = String(text.dropFirst(4)) }
                else if text.lowercased().hasPrefix("[x] ") { marker = "☑"; text = String(text.dropFirst(4)) }
                return Item(leading: leading, marker: marker, text: text)
            }
        }
        // 有序 1. / 1)(保留原始标点风格)
        var idx = s.startIndex
        var digits = ""
        while idx < s.endIndex, s[idx].isNumber { digits.append(s[idx]); idx = s.index(after: idx) }
        if !digits.isEmpty, idx < s.endIndex, s[idx] == "." || s[idx] == ")" {
            let punct = String(s[idx])
            let after = s.index(after: idx)
            if after < s.endIndex, s[after] == " " {
                return Item(leading: leading, marker: digits + punct, text: String(s[after...].drop(while: { $0 == " " })))
            }
        }
        return nil
    }

    private static func listAttr(_ item: Item, level: Int, baseFont: NSFont, color: NSColor) -> NSAttributedString {
        let indent = 18 + CGFloat(level) * 18
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 6
        p.paragraphSpacing = 7
        p.firstLineHeadIndent = max(0, indent - 16)
        p.headIndent = indent
        p.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
        let bulletColor = item.marker == "•" ? ClaudeTheme.terracotta : ClaudeTheme.inkMuted
        let bulletFont = item.marker == "•" ? NSFont.systemFont(ofSize: baseFont.pointSize + 2, weight: .bold) : baseFont
        let m = NSMutableAttributedString(string: item.marker + "\t",
                                          attributes: [.font: bulletFont, .foregroundColor: bulletColor, .paragraphStyle: p])
        let body = NSMutableAttributedString(attributedString: inlineAttributed(item.text, baseFont: baseFont, color: color))
        body.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: body.length))
        m.append(body)
        m.append(NSAttributedString(string: "\n"))
        return m
    }

    // MARK: 表格(GFM → NSTextTable)

    // 判定是否为表格分隔行,如 |---|:--:|--:|(每格只含 - : 且至少一个 -)
    private static func isTableDelimiter(_ line: String) -> Bool {
        guard line.contains("-"), line.contains("|") else { return false }
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            return !c.isEmpty && c.contains("-") && c.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    // 拆一行表格为单元格:去掉首尾 |,按 | 分(不处理转义 \| —— 罕见,够用)
    private static func splitTableRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // 从分隔行解析每列对齐(:--- 左 / :--: 中 / ---: 右)
    private static func tableAligns(_ line: String, columns: Int) -> [NSTextAlignment] {
        var a: [NSTextAlignment] = splitTableRow(line).map { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            let l = c.hasPrefix(":"), r = c.hasSuffix(":")
            return (l && r) ? .center : (r ? .right : .left)
        }
        while a.count < columns { a.append(.left) }
        return a
    }

    private static func tableAttr(header: [String], aligns: [NSTextAlignment], rows: [[String]],
                                  baseFont: NSFont, color: NSColor) -> NSAttributedString {
        let cols = max(1, header.count)
        let table = NSTextTable()
        table.numberOfColumns = cols
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.hidesEmptyCells = false

        func cell(_ text: String, row: Int, col: Int, isHeader: Bool) -> NSAttributedString {
            let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: col, columnSpan: 1)
            block.setBorderColor(NSColor.separatorColor.withAlphaComponent(0.55))
            block.setWidth(1, type: .absoluteValueType, for: .border)
            block.setWidth(7, type: .absoluteValueType, for: .padding)
            if isHeader { block.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.12) }
            let p = NSMutableParagraphStyle()
            p.textBlocks = [block]
            p.alignment = col < aligns.count ? aligns[col] : .left
            p.lineSpacing = 2
            let f = isHeader ? NSFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold) : baseFont
            let m = NSMutableAttributedString(attributedString: inlineAttributed(text, baseFont: f, color: color))
            if m.length == 0 { m.append(NSAttributedString(string: " ", attributes: [.font: f, .foregroundColor: color])) }
            m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length))
            m.append(NSAttributedString(string: "\n"))
            return m
        }

        let out = NSMutableAttributedString()
        for c in 0..<cols { out.append(cell(c < header.count ? header[c] : "", row: 0, col: c, isHeader: true)) }
        for (ri, rowCells) in rows.enumerated() {
            for c in 0..<cols { out.append(cell(c < rowCells.count ? rowCells[c] : "", row: ri + 1, col: c, isHeader: false)) }
        }
        // 关闭表格段 + 与下文留白(不带 textBlocks 的普通换行)
        let tail = NSMutableAttributedString(string: "\n")
        let tp = NSMutableParagraphStyle(); tp.paragraphSpacingBefore = 4; tp.paragraphSpacing = 9
        tail.addAttribute(.paragraphStyle, value: tp, range: NSRange(location: 0, length: tail.length))
        out.append(tail)
        return out
    }

    // MARK: 引用(Claude 风格暖底圆角卡片 + 赤陶色点缀)

    private static func quoteAttr(_ s: String, baseFont: NSFont, color: NSColor) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 6
        p.paragraphSpacingBefore = 14
        p.paragraphSpacing = 14
        p.firstLineHeadIndent = 14
        p.headIndent = 14
        p.tailIndent = -14
        let icon = NSMutableAttributedString(string: "✦  ",
            attributes: [.font: NSFont.systemFont(ofSize: baseFont.pointSize - 1, weight: .semibold),
                         .foregroundColor: ClaudeTheme.terracotta,
                         .paragraphStyle: p,
                         quoteBlockKey: true])
        let body = NSMutableAttributedString(attributedString:
            inlineAttributed(s, baseFont: baseFont, color: ClaudeTheme.inkBody))
        body.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: body.length))
        body.addAttribute(quoteBlockKey, value: true, range: NSRange(location: 0, length: body.length))
        icon.append(body)
        icon.append(NSAttributedString(string: "\n"))
        return icon
    }

    // MARK: 代码块

    private static func codeBlock(_ code: String, baseFont: NSFont) -> NSAttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular)
        let p = NSMutableParagraphStyle()
        p.firstLineHeadIndent = 12      // 内部左右留白(底块满宽,文字缩进)
        p.headIndent = 12
        p.tailIndent = -12
        p.lineSpacing = 4
        p.paragraphSpacingBefore = 18   // 与上文(标题/正文)拉开距离
        p.paragraphSpacing = 18         // 与下文拉开距离
        // 把每行的 \n 换成行分隔符 U+2028,使整块代码是「同一段落」——行间只走 lineSpacing,
        // 不再叠加段落间距(消除缝隙);满宽圆角底交给 CodeBlockLayoutManager 画(不再用碎的 .backgroundColor)。
        let oneParagraph = code.replacingOccurrences(of: "\n", with: "\u{2028}")
        let m = NSMutableAttributedString(string: oneParagraph, attributes: [
            .font: mono,
            .foregroundColor: ClaudeTheme.inkStrong,
            .paragraphStyle: p,
            codeBlockKey: true
        ])
        m.append(NSAttributedString(string: "\n"))   // 结束段落(不带 codeBlockKey)
        return m
    }

    // MARK: 分隔线

    private static func isHR(_ s: String) -> Bool {
        let body = s.filter { $0 != " " }
        guard body.count >= 3 else { return false }
        let set = Set(body)
        return set == ["-"] || set == ["*"] || set == ["_"]
    }

    static func horizontalRule(width: CGFloat) -> NSAttributedString {
        let cell = HRCell(width: width - 24)
        let att = NSTextAttachment()
        att.attachmentCell = cell
        let m = NSMutableAttributedString(attributedString: NSAttributedString(attachment: att))
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = 8
        p.paragraphSpacing = 10
        m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length))
        m.append(NSAttributedString(string: "\n"))
        return m
    }
}

// 在标记段落(代码块 / 引用卡片 / 追问气泡 / 三级标题赤陶竖条)后面画背景装饰
final class CodeBlockLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let ts = textStorage {
            let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            drawBlocks(MD.codeBlockKey, in: charRange, origin: origin, ts: ts,
                       fill: ClaudeTheme.codeBg,
                       stroke: ClaudeTheme.codeBorder,
                       radius: 8, padY: 8)
            drawBlocks(MD.quoteBlockKey, in: charRange, origin: origin, ts: ts,
                       fill: ClaudeTheme.calloutBg,
                       stroke: ClaudeTheme.calloutBorder,
                       radius: 10, padY: 9)
            drawBlocks(MD.userMsgKey, in: charRange, origin: origin, ts: ts,
                       fill: ClaudeTheme.terracottaSoft,
                       stroke: ClaudeTheme.terracotta.withAlphaComponent(0.28),
                       radius: 9, padY: 7)
            drawSubHeadingBars(in: charRange, origin: origin, ts: ts)
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawBlocks(_ key: NSAttributedString.Key, in charRange: NSRange, origin: NSPoint,
                            ts: NSTextStorage, fill: NSColor, stroke: NSColor, radius: CGFloat, padY: CGFloat) {
        ts.enumerateAttribute(key, in: charRange, options: []) { value, range, _ in
            guard (value as? Bool) == true else { return }
            let gr = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard let container = self.textContainer(forGlyphAt: gr.location, effectiveRange: nil) else { return }
            var block = CGRect.null
            self.enumerateLineFragments(forGlyphRange: gr) { _, usedRect, _, _, _ in
                block = block.isNull ? usedRect : block.union(usedRect)
            }
            guard !block.isNull else { return }
            let w = container.size.width
            var r = CGRect(x: 2, y: block.minY, width: max(10, w - 4), height: block.height)
            r = r.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: 0, dy: -padY)
            let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
            fill.setFill(); path.fill()
            stroke.setStroke(); path.lineWidth = 1; path.stroke()
        }
    }

    private func drawSubHeadingBars(in charRange: NSRange, origin: NSPoint, ts: NSTextStorage) {
        ts.enumerateAttribute(MD.subHeadingBarKey, in: charRange, options: []) { value, range, _ in
            guard (value as? Bool) == true else { return }
            let gr = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var block = CGRect.null
            self.enumerateLineFragments(forGlyphRange: gr) { _, usedRect, _, _, _ in
                block = block.isNull ? usedRect : block.union(usedRect)
            }
            guard !block.isNull else { return }
            let barH = max(14, block.height - 4)
            let barY = origin.y + block.minY + (block.height - barH) / 2
            let barRect = CGRect(x: origin.x + 1, y: barY, width: 3.2, height: barH)
            let path = NSBezierPath(roundedRect: barRect, xRadius: 1.6, yRadius: 1.6)
            ClaudeTheme.terracotta.setFill()
            path.fill()
        }
    }
}

// 画一条满宽暖色细线的附件 cell(给 markdown 的 --- 用)
final class HRCell: NSTextAttachmentCell {
    private let w: CGFloat
    init(width: CGFloat) { self.w = max(10, width); super.init() }
    required init(coder: NSCoder) { fatalError() }
    override func cellSize() -> NSSize { NSSize(width: w, height: 9) }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let y = cellFrame.midY.rounded() + 0.5
        let path = NSBezierPath()
        path.move(to: NSPoint(x: cellFrame.minX, y: y))
        path.line(to: NSPoint(x: cellFrame.minX + w, y: y))
        path.lineWidth = 1
        ClaudeTheme.windowBorder.setStroke()
        path.stroke()
    }
}
