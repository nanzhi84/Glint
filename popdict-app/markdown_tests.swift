import AppKit

// Markdown.swift 列表渲染的单测(不进 App 打包;跑法:
//   swiftc -o /tmp/popdict_md_test Markdown.swift markdown_tests.swift -framework AppKit && /tmp/popdict_md_test)

@main
struct MDTests {
    static var failures = 0
    static func expect(_ cond: Bool, _ name: String) {
        if cond { print("  ok  \(name)") } else { failures += 1; print("FAIL  \(name)") }
    }

    // 渲染后找到包含 needle 的那一行,取其段落样式的 headIndent(即该列表项的缩进层级体现)
    static func headIndent(of needle: String, in src: String) -> CGFloat? {
        let a = MD.render(src, width: 400)
        let s = a.string as NSString
        let r = s.range(of: needle)
        guard r.location != NSNotFound else { return nil }
        guard let p = a.attribute(.paragraphStyle, at: r.location, effectiveRange: nil) as? NSParagraphStyle else { return nil }
        return p.headIndent
    }

    static func main() {
        let lv0: CGFloat = 18, lv1: CGFloat = 36, lv2: CGFloat = 54

        // 顶层列表项 → 一级缩进
        expect(headIndent(of: "苹果", in: "- 苹果\n- 香蕉") == lv0, "顶层无序项 → 18")

        // 模型最常见:有序项下嵌 4 空格的无序项 → 应是二级(36),不是三级(54)
        expect(headIndent(of: "子项甲", in: "1. 标题一\n    - 子项甲\n2. 标题二") == lv1, "4 空格嵌套 → 36")

        // 2 空格与 3 空格的嵌套同样算二级
        expect(headIndent(of: "子项乙", in: "- 父项\n  - 子项乙") == lv1, "2 空格嵌套 → 36")
        expect(headIndent(of: "子项丙", in: "1. 父项\n   - 子项丙") == lv1, "3 空格嵌套 → 36")

        // tab 缩进也算二级
        expect(headIndent(of: "子项丁", in: "- 父项\n\t- 子项丁") == lv1, "tab 嵌套 → 36")

        // 三层嵌套(0/4/8 空格)→ 逐级 18/36/54
        let deep = "- 一层\n    - 二层\n        - 三层"
        expect(headIndent(of: "一层", in: deep) == lv0 &&
               headIndent(of: "二层", in: deep) == lv1 &&
               headIndent(of: "三层", in: deep) == lv2, "0/4/8 空格 → 18/36/54")

        // 回退:嵌套后回到顶层,层级要弹回
        expect(headIndent(of: "又回顶层", in: "1. 父项\n    - 子项\n2. 又回顶层") == lv0, "回退到顶层 → 18")

        // 段落打断后新列表重新计层:即使首项自带缩进也算顶层
        expect(headIndent(of: "新列表", in: "- 老列表\n\n中间一段话\n\n   - 新列表") == lv0, "段落打断后重新计层 → 18")

        // 空行不打断同一列表的层级关系(宽松列表)
        expect(headIndent(of: "隔行子项", in: "- 父项\n\n    - 隔行子项") == lv1, "空行不打断嵌套 → 36")

        // 有序号的嵌套项与无序一致
        expect(headIndent(of: "编号子项", in: "1. 父项\n    1. 编号子项") == lv1, "嵌套有序项 → 36")

        // 1. CJK 与括号紧邻粗体解析契约
        let cjkBoldSrc = "研究方向：**多镜头（多视角）联合生成**中，如何用**推理期计算扩展 (Inference-Time Scaling)**来弥补“开环生成”的不稳定性。"
        let rendered = MD.render(cjkBoldSrc, width: 400)
        expect(!rendered.string.contains("**"), "CJK 与括号紧邻粗体不得残留 **")

        let boldRange = (rendered.string as NSString).range(of: "推理期计算扩展 (Inference-Time Scaling)")
        var isBold = false
        if boldRange.location != NSNotFound,
           let font = rendered.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont {
            let fontName = font.fontName
            isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                || fontName.contains("Bold")
                || fontName.contains("Semibold")
                || fontName.contains("Heavy")
        }
        expect(isBold, "括号紧邻 CJK 的粗体片段应具有 Bold 字重特征")

        let inlineCodeSrc = "测试行内代码 `**not_bold**` 不被剥离"
        let inlineCodeRendered = MD.render(inlineCodeSrc, width: 400)
        expect(inlineCodeRendered.string.contains("**not_bold**"), "行内代码 `**not_bold**` 内部星号应原样保留")

        // 2. 排版行高与段间距契约 (MD.bodyStyle())
        let bodyStyle = MD.bodyStyle()
        expect(bodyStyle.paragraphSpacing >= 12 && bodyStyle.lineSpacing >= 6, "MD.bodyStyle() 段间距 >= 12 且行高 >= 6")

        // 3. 列表项赤陶色圆点契约 (#D97757)
        let bulletRendered = MD.render("- 传统做法：加去噪步数", width: 400)
        var isTerracotta = false
        if bulletRendered.length > 0,
           let color = bulletRendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
           let srgb = color.usingColorSpace(.sRGB) {
            isTerracotta = srgb.redComponent > 0.75
                && srgb.greenComponent > 0.40
                && srgb.greenComponent < 0.55
                && srgb.blueComponent < 0.45
        }
        expect(isTerracotta, "列表圆点首字符应为 #D97757 赤陶色")

        // 4. 结尾引用卡片不被 usedRect 下界截断契约
        let bottomQuoteSrc = "### 第三层\n- 列表项\n\n> 一句话类比：先别急着把水管开大（调 batch 窗口），先查清楚为什么水在漏（ZIP 重复回读）——漏点堵上，比加压有用得多。"
        let bottomQuoteAttr = MD.render(bottomQuoteSrc, width: 452)
        let ts = NSTextStorage(attributedString: bottomQuoteAttr)
        let lm = CodeBlockLayoutManager()
        let tc = NSTextContainer(size: NSSize(width: 452, height: CGFloat.greatestFiniteMagnitude))
        tc.lineFragmentPadding = 0
        lm.addTextContainer(tc)
        ts.addLayoutManager(lm)
        lm.ensureLayout(for: tc)
        let usedMaxY = lm.usedRect(for: tc).maxY
        var cardMaxY: CGFloat = 0
        ts.enumerateAttribute(MD.quoteBlockKey, in: NSRange(location: 0, length: ts.length), options: []) { value, range, _ in
            guard (value as? Bool) == true else { return }
            let gr = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var block = CGRect.null
            lm.enumerateLineFragments(forGlyphRange: gr) { _, usedRect, _, _, _ in
                block = block.isNull ? usedRect : block.union(usedRect)
            }
            if !block.isNull {
                cardMaxY = max(cardMaxY, block.maxY + 9.0)
            }
        }
        expect(cardMaxY > 0 && usedMaxY >= cardMaxY + 2.0, "结尾引用卡片底部不得超出 usedRect 下界(防止滚到底部时被截断)")

        // 5. 连续多行 > 引用合并为单个引用卡片块契约
        let multiQuoteRendered = MD.render("> 第一行引用\n> 第二行引用", width: 400)
        var quoteRangeCount = 0
        multiQuoteRendered.enumerateAttribute(MD.quoteBlockKey, in: NSRange(location: 0, length: multiQuoteRendered.length), options: []) { value, _, _ in
            if (value as? Bool) == true {
                quoteRangeCount += 1
            }
        }
        expect(quoteRangeCount == 1, "连续多行 > 引用应合并为单个引用卡片块")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
        exit(failures == 0 ? 0 : 1)
    }
}
