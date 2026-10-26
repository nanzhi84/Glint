import AppKit

// ============================================================
// BrandLogo: popdict 品牌视觉资产模块 (Claude 暖纸书卷 + 赤陶星芒 ✦ 风格)
// - appIconImage(size:) : 渲染 macOS 圆角矩形应用图标 (用于 NSApp.applicationIconImage 与 .icns 打包)
// - menuBarIcon(size:)  : 渲染菜单栏 18×18 自适应明暗 Template 矢量图标 (划词气泡 + 四角星芒 ✦)
// - pngData(pixelSize:) : 离屏渲染指定像素尺寸的标准 PNG 数据
// ============================================================

enum BrandLogo {

    // 品牌核心色板 (与 ClaudeTheme 保持严格一致)
    private static let paperTop       = NSColor(srgbRed: 250/255, green: 249/255, blue: 245/255, alpha: 1.0) // #FAF9F5
    private static let paperMid       = NSColor(srgbRed: 246/255, green: 243/255, blue: 236/255, alpha: 1.0) // #F6F3EC
    private static let paperBot       = NSColor(srgbRed: 237/255, green: 231/255, blue: 218/255, alpha: 1.0) // #EDE7DA
    private static let squircleBorder = NSColor(srgbRed: 226/255, green: 221/255, blue: 208/255, alpha: 1.0) // #E2DDD0
    private static let backCardFill   = NSColor(srgbRed: 235/255, green: 230/255, blue: 218/255, alpha: 1.0) // #EBE6DA
    private static let backCardStroke = NSColor(srgbRed: 221/255, green: 214/255, blue: 198/255, alpha: 1.0) // #DDD6C6
    private static let backCardLine   = NSColor(srgbRed: 213/255, green: 206/255, blue: 192/255, alpha: 1.0) // #D5CEC0
    private static let inkStrong      = NSColor(srgbRed: 20/255,  green: 20/255,  blue: 19/255,  alpha: 1.0) // #141413
    private static let inkBody        = NSColor(srgbRed: 45/255,  green: 45/255,  blue: 42/255,  alpha: 0.78)
    private static let inkMuted       = NSColor(srgbRed: 115/255, green: 114/255, blue: 108/255, alpha: 0.55)
    private static let terracotta     = NSColor(srgbRed: 217/255, green: 119/255, blue: 87/255,  alpha: 1.0) // #D97757
    private static let terracottaTop  = NSColor(srgbRed: 229/255, green: 133/255, blue: 101/255, alpha: 1.0) // #E58565
    private static let terracottaBot  = NSColor(srgbRed: 196/255, green: 96/255,  blue: 64/255,  alpha: 1.0) // #C46040

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

            // 从顶部中间偏左开始逆时针/顺时针绘制气泡
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

    // MARK: - 2. macOS 彩色应用图标 (Claude 暖纸 + 赤陶星芒 ✦)

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

    // MARK: - 内部矢量绘制实现 (基于 512×512 归一化坐标系, Y 向上为正转为顶左 flipped 坐标)

    private static func drawAppIcon(in cg: CGContext, size: NSSize) {
        cg.saveGState()
        // 统一变换为 512×512 且左上角为原点 (Y 向下增大, 与 SVG 完全对齐)
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
        NSColor(white: 1.0, alpha: 0.8).setStroke()
        innerHi.lineWidth = 2
        innerHi.stroke()

        // 2. 背景微倾书页层 (rotate -6 deg around (256, 248))
        cg.saveGState()
        cg.translateBy(x: 256, y: 248)
        cg.rotate(by: -6.0 * .pi / 180.0)
        cg.translateBy(x: -256, y: -248)

        let backRect = NSRect(x: 122, y: 114, width: 268, height: 246)
        let backPath = NSBezierPath(roundedRect: backRect, xRadius: 38, yRadius: 38)
        backCardFill.setFill()
        backPath.fill()
        backCardStroke.setStroke()
        backPath.lineWidth = 2.5
        backPath.stroke()

        let backLine1 = NSBezierPath()
        backLine1.move(to: NSPoint(x: 158, y: 162))
        backLine1.line(to: NSPoint(x: 264, y: 162))
        backLine1.lineWidth = 6
        backLine1.lineCapStyle = .round
        backCardLine.setStroke()
        backLine1.stroke()

        let backLine2 = NSBezierPath()
        backLine2.move(to: NSPoint(x: 158, y: 188))
        backLine2.line(to: NSPoint(x: 232, y: 188))
        backLine2.lineWidth = 6
        backLine2.lineCapStyle = .round
        backLine2.stroke()
        cg.restoreGState()

        // 3. 左下角划词选区胶囊 + I-Beam 选词光标
        let selPill = NSBezierPath(roundedRect: NSRect(x: 96, y: 382, width: 116, height: 28), xRadius: 9, yRadius: 9)
        terracotta.withAlphaComponent(0.16).setFill()
        selPill.fill()

        let selTextLine = NSBezierPath()
        selTextLine.move(to: NSPoint(x: 112, y: 396))
        selTextLine.line(to: NSPoint(x: 186, y: 396))
        selTextLine.lineWidth = 5.5
        selTextLine.lineCapStyle = .round
        terracotta.withAlphaComponent(0.65).setStroke()
        selTextLine.stroke()

        terracotta.setStroke()
        let ibeamStem = NSBezierPath()
        ibeamStem.move(to: NSPoint(x: 204, y: 376))
        ibeamStem.line(to: NSPoint(x: 204, y: 416))
        ibeamStem.lineWidth = 4.5
        ibeamStem.lineCapStyle = .round
        ibeamStem.stroke()

        for capY: CGFloat in [376, 416] {
            let cap = NSBezierPath()
            cap.move(to: NSPoint(x: 195, y: capY))
            cap.line(to: NSPoint(x: 213, y: capY))
            cap.lineWidth = 4
            cap.lineCapStyle = .round
            cap.stroke()
        }

        // 4. 主体划词弹出卡片 (带左下角指向选区的气泡尾尖)
        let cardPath = popupBubbleCardPath()
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 20,
                     color: NSColor(srgbRed: 20/255, green: 20/255, blue: 19/255, alpha: 0.11).cgColor)
        NSColor.white.setFill()
        cardPath.fill()
        cg.restoreGState()

        if let cardGrad = NSGradient(colors: [NSColor.white, paperTop, paperMid],
                                     atLocations: [0.0, 0.5, 1.0],
                                     colorSpace: .sRGB) {
            cardGrad.draw(in: cardPath, angle: 65)
        }
        squircleBorder.setStroke()
        cardPath.lineWidth = 3
        cardPath.lineJoinStyle = .round
        cardPath.stroke()

        // 5. 卡片内左侧赤陶色书卷竖条
        let accentBar = NSBezierPath(roundedRect: NSRect(x: 142, y: 146, width: 8, height: 168), xRadius: 4, yRadius: 4)
        terracotta.setFill()
        accentBar.fill()

        // 6. 经典衬线字母 "P" (#141413, 平顶左直右圆弧碗部, 无接缝缺口)
        inkStrong.setFill()
        NSBezierPath(roundedRect: NSRect(x: 172, y: 150, width: 46, height: 11), xRadius: 3, yRadius: 3).fill()
        NSBezierPath(roundedRect: NSRect(x: 172, y: 263, width: 52, height: 11), xRadius: 3, yRadius: 3).fill()
        NSBezierPath(roundedRect: NSRect(x: 186, y: 150, width: 22, height: 124), xRadius: 2, yRadius: 2).fill()

        let pBowlOuter = NSBezierPath()
        pBowlOuter.move(to: NSPoint(x: 196, y: 150))
        pBowlOuter.line(to: NSPoint(x: 238, y: 150))
        pBowlOuter.appendArc(withCenter: NSPoint(x: 238, y: 189), radius: 39, startAngle: 270, endAngle: 90, clockwise: false)
        pBowlOuter.line(to: NSPoint(x: 196, y: 228))
        pBowlOuter.close()
        pBowlOuter.fill()

        // 内部镂空还原暖纸卡片底色
        let pBowlInner = NSBezierPath()
        pBowlInner.move(to: NSPoint(x: 208, y: 164))
        pBowlInner.line(to: NSPoint(x: 235, y: 164))
        pBowlInner.appendArc(withCenter: NSPoint(x: 235, y: 189), radius: 25, startAngle: 270, endAngle: 90, clockwise: false)
        pBowlInner.line(to: NSPoint(x: 208, y: 214))
        pBowlInner.close()
        paperTop.setFill()
        pBowlInner.fill()

        // 7. 底部释义排版横线与右下角经纬地球徽标
        inkBody.setFill()
        NSBezierPath(roundedRect: NSRect(x: 174, y: 294, width: 136, height: 9), xRadius: 4.5, yRadius: 4.5).fill()
        inkMuted.setFill()
        NSBezierPath(roundedRect: NSRect(x: 174, y: 314, width: 92, height: 8), xRadius: 4, yRadius: 4).fill()

        inkMuted.setStroke()
        let globeCircle = NSBezierPath(ovalIn: NSRect(x: 335, y: 289, width: 30, height: 30))
        globeCircle.lineWidth = 2.6
        globeCircle.stroke()
        let globeMeridian = NSBezierPath(ovalIn: NSRect(x: 342.8, y: 289, width: 14.4, height: 30))
        globeMeridian.lineWidth = 2.4
        globeMeridian.stroke()
        let globeEq = NSBezierPath()
        globeEq.move(to: NSPoint(x: 336, y: 304))
        globeEq.line(to: NSPoint(x: 364, y: 304))
        globeEq.lineWidth = 2.4
        globeEq.stroke()

        // 8. 右上角赤陶色四角星芒 ✦
        let aura = NSBezierPath(ovalIn: NSRect(x: 302, y: 126, width: 84, height: 84))
        terracotta.withAlphaComponent(0.12).setFill()
        aura.fill()

        let mainStar = fourPointStarPath(center: NSPoint(x: 344, y: 156), radius: 38, waist: 10)
        if let starGrad = NSGradient(colors: [terracottaTop, terracotta, terracottaBot],
                                     atLocations: [0.0, 0.5, 1.0],
                                     colorSpace: .sRGB) {
            starGrad.draw(in: mainStar, angle: 60)
        } else {
            terracotta.setFill()
            mainStar.fill()
        }

        let subStar = fourPointStarPath(center: NSPoint(x: 384, y: 200), radius: 18, waist: 5)
        terracotta.setFill()
        subStar.fill()

        cg.restoreGState()
    }

    private static func popupBubbleCardPath() -> NSBezierPath {
        let p = NSBezierPath()
        let left: CGFloat = 112
        let top: CGFloat = 108
        let right: CGFloat = 404
        let bottom: CGFloat = 352
        let r: CGFloat = 40

        p.move(to: NSPoint(x: left + r, y: top))
        p.line(to: NSPoint(x: right - r, y: top))
        p.appendArc(withCenter: NSPoint(x: right - r, y: top + r), radius: r, startAngle: 270, endAngle: 0, clockwise: false)
        p.line(to: NSPoint(x: right, y: bottom - r))
        p.appendArc(withCenter: NSPoint(x: right - r, y: bottom - r), radius: r, startAngle: 0, endAngle: 90, clockwise: false)
        p.line(to: NSPoint(x: 222, y: bottom))
        p.line(to: NSPoint(x: 176, y: 388))
        p.line(to: NSPoint(x: 182, y: bottom))
        p.line(to: NSPoint(x: left + r, y: bottom))
        p.appendArc(withCenter: NSPoint(x: left + r, y: bottom - r), radius: r, startAngle: 90, endAngle: 180, clockwise: false)
        p.line(to: NSPoint(x: left, y: top + r))
        p.appendArc(withCenter: NSPoint(x: left + r, y: top + r), radius: r, startAngle: 180, endAngle: 270, clockwise: false)
        p.close()
        return p
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
