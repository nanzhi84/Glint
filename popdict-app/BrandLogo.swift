import AppKit

// ============================================================
// BrandLogo: Glint 品牌视觉资产模块 (菜单栏同款灵光气泡 + 赤陶星芒 ✦ 彩色精修版)
// - appIconImage(size:) : 渲染 macOS 圆角矩形应用图标 (用于 NSApp.applicationIconImage 与 Glint.icns 打包)
// - menuBarIcon(size:)  : 渲染菜单栏 18×18 自适应明暗 Template 矢量图标 (划词气泡 + 四角星芒 ✦)
// - pngData(pixelSize:) : 离屏渲染指定像素尺寸的标准 PNG 数据
// ============================================================

enum BrandLogo {

    // 品牌核心色板 (与 ClaudeTheme 保持严格一致)
    private static let paperTop       = NSColor(srgbRed: 250/255, green: 249/255, blue: 245/255, alpha: 1.0) // #FAF9F5
    private static let paperMid       = NSColor(srgbRed: 245/255, green: 241/255, blue: 232/255, alpha: 1.0) // #F5F1E8
    private static let paperBot       = NSColor(srgbRed: 234/255, green: 226/255, blue: 210/255, alpha: 1.0) // #EAE2D2
    private static let squircleBorder = NSColor(srgbRed: 223/255, green: 216/255, blue: 200/255, alpha: 1.0) // #DFD8C8
    private static let inkStrong      = NSColor(srgbRed: 24/255,  green: 24/255,  blue: 22/255,  alpha: 1.0) // #181816
    private static let terracotta     = NSColor(srgbRed: 217/255, green: 119/255, blue: 87/255,  alpha: 1.0) // #D97757
    private static let terracottaTop  = NSColor(srgbRed: 238/255, green: 144/255, blue: 112/255, alpha: 1.0) // #EE9070
    private static let terracottaBot  = NSColor(srgbRed: 192/255, green: 90/255,  blue: 57/255,  alpha: 1.0) // #C05A39

    // MARK: - 1. 菜单栏专属矢量 Template 图标 (18×18pt)

    static func menuBarIcon(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        let img = NSImage(size: size, flipped: true) { rect in
            let w = rect.width
            let h = rect.height
            let s = min(w, h) / 18.0

            NSColor.black.setStroke()
            NSColor.black.setFill()

            // 1) 主体划词气泡外框(留出右上角给星芒 ✦ 呼吸空间,左下角带气泡尾尖)
            let bubble = NSBezierPath()
            let left: CGFloat   = 1.6 * s
            let top: CGFloat    = 2.6 * s
            let right: CGFloat  = 14.8 * s
            let bottom: CGFloat = 13.4 * s
            let r: CGFloat      = 3.0 * s

            bubble.move(to: NSPoint(x: 9.8 * s, y: top))
            bubble.line(to: NSPoint(x: left + r, y: top))
            bubble.appendArc(withCenter: NSPoint(x: left + r, y: top + r), radius: r, startAngle: 270, endAngle: 180, clockwise: true)
            bubble.line(to: NSPoint(x: left, y: bottom - r))
            bubble.appendArc(withCenter: NSPoint(x: left + r, y: bottom - r), radius: r, startAngle: 180, endAngle: 90, clockwise: true)
            // 左下角气泡尾尖
            bubble.line(to: NSPoint(x: 4.5 * s, y: bottom))
            bubble.line(to: NSPoint(x: 3.4 * s, y: 16.0 * s))
            bubble.line(to: NSPoint(x: 7.2 * s, y: bottom))
            bubble.line(to: NSPoint(x: right - r, y: bottom))
            bubble.appendArc(withCenter: NSPoint(x: right - r, y: bottom - r), radius: r, startAngle: 90, endAngle: 0, clockwise: true)
            bubble.line(to: NSPoint(x: right, y: 8.6 * s))
            bubble.lineWidth = 1.45 * s
            bubble.lineCapStyle = .round
            bubble.lineJoinStyle = .round
            bubble.stroke()

            // 2) 气泡内部左侧书卷竖线 + 双行释义横线
            let bar = NSBezierPath()
            bar.move(to: NSPoint(x: 4.4 * s, y: 5.5 * s))
            bar.line(to: NSPoint(x: 4.4 * s, y: 10.6 * s))
            bar.lineWidth = 1.55 * s
            bar.lineCapStyle = .round
            bar.stroke()

            let line1 = NSBezierPath()
            line1.move(to: NSPoint(x: 6.8 * s, y: 6.6 * s))
            line1.line(to: NSPoint(x: 9.8 * s, y: 6.6 * s))
            line1.lineWidth = 1.35 * s
            line1.lineCapStyle = .round
            line1.stroke()

            let line2 = NSBezierPath()
            line2.move(to: NSPoint(x: 6.8 * s, y: 9.7 * s))
            line2.line(to: NSPoint(x: 11.6 * s, y: 9.7 * s))
            line2.lineWidth = 1.35 * s
            line2.lineCapStyle = .round
            line2.stroke()

            // 3) 右上角标志性四角星芒 ✦
            let star = fourPointStarPath(center: NSPoint(x: 13.6 * s, y: 4.4 * s),
                                         radius: 3.3 * s,
                                         waist: 0.95 * s)
            star.fill()

            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: - 2. macOS 彩色应用图标 (菜单栏图标同款构图 + Claude 暖纸 & 赤陶上色版)

    static func appIconImage(size: NSSize = NSSize(width: 512, height: 512)) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawAppIcon(in: ctx, size: rect.size)
            return true
        }
        img.isTemplate = false
        return img
    }

    static func pngData(pixelSize: Int) -> Data? {
        guard pixelSize > 0 else { return nil }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = NSSize(width: pixelSize, height: pixelSize)
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            drawAppIcon(in: ctx.cgContext, size: NSSize(width: pixelSize, height: pixelSize))
            ctx.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - 内部矢量绘制实现 (基于 512×512 归一化坐标系, 左上角为原点, 与 SVG 完全对齐)

    private static func drawAppIcon(in cg: CGContext, size: NSSize) {
        cg.saveGState()
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: size.width / 512.0, y: -size.height / 512.0)

        // 1. 外层 macOS 暖纸 Squircle 底座 + 阴影
        let squircleRect = NSRect(x: 38, y: 38, width: 436, height: 436)
        let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: 98, yRadius: 98)

        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 22,
                     color: NSColor(srgbRed: 20/255, green: 20/255, blue: 19/255, alpha: 0.14).cgColor)
        paperTop.setFill()
        squirclePath.fill()
        cg.restoreGState()

        if let bgGrad = NSGradient(colors: [paperTop, paperMid, paperBot],
                                   atLocations: [0.0, 0.55, 1.0],
                                   colorSpace: .sRGB) {
            bgGrad.draw(in: squirclePath, angle: 65)
        }
        let borderPath = NSBezierPath(roundedRect: squircleRect.insetBy(dx: 2, dy: 2), xRadius: 96, yRadius: 96)
        squircleBorder.setStroke()
        borderPath.lineWidth = 4
        borderPath.stroke()

        let innerHi = NSBezierPath(roundedRect: squircleRect.insetBy(dx: 5, dy: 5), xRadius: 93, yRadius: 93)
        NSColor(white: 1.0, alpha: 0.88).setStroke()
        innerHi.lineWidth = 2
        innerHi.stroke()

        // 2. 右上角开口的圆角气泡主轮廓线 (#181816 深炭墨色, 与菜单栏图标完全同构)
        let left: CGFloat   = 108
        let top: CGFloat    = 136
        let right: CGFloat  = 368
        let bottom: CGFloat = 350
        let r: CGFloat      = 54

        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -6), blur: 12,
                     color: NSColor(srgbRed: 20/255, green: 20/255, blue: 19/255, alpha: 0.09).cgColor)

        let openBubble = NSBezierPath()
        openBubble.move(to: NSPoint(x: 264, y: top))
        openBubble.line(to: NSPoint(x: left + r, y: top))
        openBubble.appendArc(withCenter: NSPoint(x: left + r, y: top + r), radius: r, startAngle: 270, endAngle: 180, clockwise: true)
        openBubble.line(to: NSPoint(x: left, y: bottom - r))
        openBubble.appendArc(withCenter: NSPoint(x: left + r, y: bottom - r), radius: r, startAngle: 180, endAngle: 90, clockwise: true)
        openBubble.line(to: NSPoint(x: 168, y: bottom))
        openBubble.line(to: NSPoint(x: 150, y: 396))
        openBubble.line(to: NSPoint(x: 222, y: bottom))
        openBubble.line(to: NSPoint(x: right - r, y: bottom))
        openBubble.appendArc(withCenter: NSPoint(x: right - r, y: bottom - r), radius: r, startAngle: 90, endAngle: 0, clockwise: true)
        openBubble.line(to: NSPoint(x: right, y: 252))
        openBubble.lineWidth = 26
        openBubble.lineCapStyle = .round
        openBubble.lineJoinStyle = .round
        inkStrong.setStroke()
        openBubble.stroke()

        // 3. 气泡内部左侧赤陶色书卷竖条 (Anthropic Terracotta #D97757)
        let leftBar = NSBezierPath()
        leftBar.move(to: NSPoint(x: 166, y: 196))
        leftBar.line(to: NSPoint(x: 166, y: 292))
        leftBar.lineWidth = 26
        leftBar.lineCapStyle = .round
        terracotta.setStroke()
        leftBar.stroke()

        // 4. 气泡内部右侧双横线 (上短下长, #181816 深炭墨色)
        inkStrong.setStroke()
        let line1 = NSBezierPath()
        line1.move(to: NSPoint(x: 214, y: 216))
        line1.line(to: NSPoint(x: 274, y: 216))
        line1.lineWidth = 24
        line1.lineCapStyle = .round
        line1.stroke()

        let line2 = NSBezierPath()
        line2.move(to: NSPoint(x: 214, y: 272))
        line2.line(to: NSPoint(x: 310, y: 272))
        line2.lineWidth = 24
        line2.lineCapStyle = .round
        line2.stroke()

        // 5. 右上角标志性赤陶色四角星芒 ✦
        let star = fourPointStarPath(center: NSPoint(x: 346, y: 168), radius: 68, waist: 19)
        if let starGrad = NSGradient(colors: [terracottaTop, terracotta, terracottaBot],
                                     atLocations: [0.0, 0.5, 1.0],
                                     colorSpace: .sRGB) {
            starGrad.draw(in: star, angle: 55)
        } else {
            terracotta.setFill()
            star.fill()
        }

        cg.restoreGState()
        cg.restoreGState()
    }

    private static func fourPointStarPath(center c: NSPoint, radius R: CGFloat, waist w: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        let top    = NSPoint(x: c.x,     y: c.y - R)
        let right  = NSPoint(x: c.x + R, y: c.y)
        let bottom = NSPoint(x: c.x,     y: c.y + R)
        let left   = NSPoint(x: c.x - R, y: c.y)
        let tr     = NSPoint(x: c.x + w, y: c.y - w)
        let br     = NSPoint(x: c.x + w, y: c.y + w)
        let bl     = NSPoint(x: c.x - w, y: c.y + w)
        let tl     = NSPoint(x: c.x - w, y: c.y - w)

        p.move(to: top)
        p.curve(to: right,  controlPoint1: tr, controlPoint2: tr)
        p.curve(to: bottom, controlPoint1: br, controlPoint2: br)
        p.curve(to: left,   controlPoint1: bl, controlPoint2: bl)
        p.curve(to: top,    controlPoint1: tl, controlPoint2: tl)
        p.close()
        return p
    }

    // 生成标准 macOS .iconset 目录内所需的 10 张 PNG 图标
    static func writeIconset(to iconsetDir: URL) throws {
        try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
        let specs: [(String, Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]
        for (filename, px) in specs {
            if let data = pngData(pixelSize: px) {
                try data.write(to: iconsetDir.appendingPathComponent(filename))
            }
        }
    }
}
