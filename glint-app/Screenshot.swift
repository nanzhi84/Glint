import AppKit
import CoreGraphics

// ============================================================
// 框选截图组件:全屏遮罩拖选 → 截「遮罩下方」真实画面 → PNG/base64 编码
// 给 Glint 的「截图解释」用:截到的图发给多模态大模型看图讲解。
// ============================================================

// 可成为 key 的无边框遮罩窗口(为了能收到 Esc 键,并禁止 AppKit 按 visibleFrame 裁切或挪动全屏遮罩)
private final class CaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

// 全屏遮罩:拖动框选,选区外压暗、选区内透明,显示像素尺寸;Esc 取消,松手确认。
private final class SelectionView: NSView {
    var onBeginSelection: (() -> Void)?
    var onFinish: ((NSRect?) -> Void)?   // 选区(本视图坐标);nil = 取消
    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var finished = false

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    func clearSelection() {
        startPoint = nil
        currentRect = .zero
        needsDisplay = true
    }

    private func finish(_ rect: NSRect?) {
        if finished { return }
        finished = true
        onFinish?(rect)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        onBeginSelection?()
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let s = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(x: min(s.x, p.x), y: min(s.y, p.y),
                             width: abs(p.x - s.x), height: abs(p.y - s.y))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        let r = currentRect
        if r.width > 8 && r.height > 8 { finish(r) } else { finish(nil) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finish(nil) }   // Esc
    }

    override func draw(_ dirtyRect: NSRect) {
        // 先把整块清成透明(消除上一帧残留)
        NSColor.clear.setFill()
        bounds.fill(using: .copy)

        let dim = NSColor.black.withAlphaComponent(0.35)
        dim.setFill()
        let sel = currentRect
        if sel.width < 1 || sel.height < 1 {
            bounds.fill()
            return
        }
        // 选区外四块压暗,选区内保持透明
        let b = bounds
        NSRect(x: b.minX, y: sel.maxY, width: b.width, height: b.maxY - sel.maxY).fill()       // 上
        NSRect(x: b.minX, y: b.minY, width: b.width, height: sel.minY - b.minY).fill()         // 下
        NSRect(x: b.minX, y: sel.minY, width: sel.minX - b.minX, height: sel.height).fill()    // 左
        NSRect(x: sel.maxX, y: sel.minY, width: b.maxX - sel.maxX, height: sel.height).fill()  // 右

        // 边框
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: sel); path.lineWidth = 1.5; path.stroke()

        // 尺寸标签(像素;按当前遮罩所在屏幕的缩放估算,默认 1 适配非 Retina / 外接普通屏)
        let scale = window?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let label = "\(Int(sel.width * scale)) × \(Int(sel.height * scale))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white]
        let size = (label as NSString).size(withAttributes: attrs)
        let lx = sel.minX
        var ly = sel.maxY + 4
        if ly + size.height + 4 > b.maxY { ly = sel.minY - size.height - 6 }
        let bg = NSRect(x: lx - 4, y: ly - 2, width: size.width + 8, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 3, yRadius: 3).fill()
        (label as NSString).draw(at: NSPoint(x: lx, y: ly), withAttributes: attrs)
    }
}

final class RegionCapture {
    private var windows: [CaptureWindow] = []
    private var keyMonitor: Any?
    private var completed = false
    private var cursorPushed = false

    func activeWindowFrames() -> [NSRect] {
        windows.map { $0.frame }
    }

    private func cleanup() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
        for win in windows {
            win.orderOut(nil)
        }
        windows.removeAll()
    }

    private func finishCapture(on win: CaptureWindow?, localRect: NSRect?, completion: @escaping (NSImage?) -> Void) {
        guard !completed else { return }
        completed = true
        guard let win = win, let localRect = localRect else {
            cleanup()
            completion(nil)
            return
        }
        // 本屏幕遮罩窗口内局部坐标 → 全局 Quartz 坐标(主屏左上原点)
        let quartz = captureQuartzRect(
            localRect: localRect,
            screenFrame: win.frame,
            primaryScreenHeight: primaryScreenHeight()
        )
        // 截当前屏幕遮罩窗口「下方」的真实画面(压暗层不会进图);此刻窗口仍在屏上
        let winID = CGWindowID(win.windowNumber)
        let cg = CGWindowListCreateImage(quartz, .optionOnScreenBelowWindow, winID,
                                         [.bestResolution, .boundsIgnoreFraming])
        cleanup()
        guard let cg = cg, cg.width > 0, cg.height > 0 else {
            completion(nil)
            return
        }
        let img = NSImage(cgImage: cg, size: NSSize(width: quartz.width, height: quartz.height))
        completion(img)
    }

    // 为每块连接的显示器分别创建独立全屏遮罩窗口(规避 macOS「显示器具有单独的空间」对单窗口跨屏的裁切与 visibleFrame 收缩)
    func capture(completion: @escaping (NSImage?) -> Void) {
        cleanup()
        completed = false
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            completion(nil)
            return
        }

        NSCursor.crosshair.push()
        cursorPushed = true

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.finishCapture(on: nil, localRect: nil, completion: completion)
                return nil
            }
            return event
        }

        var views: [SelectionView] = []
        let mouseLoc = NSEvent.mouseLocation
        var initialKeyWin: CaptureWindow?

        for screen in screens {
            let sf = screen.frame
            let win = CaptureWindow(contentRect: sf, styleMask: .borderless,
                                    backing: .buffered, defer: false)
            win.setFrame(sf, display: false)
            win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            win.backgroundColor = .clear
            win.isOpaque = false
            win.hasShadow = false
            win.ignoresMouseEvents = false
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = SelectionView(frame: NSRect(origin: .zero, size: sf.size))
            view.autoresizingMask = [.width, .height]
            win.contentView = view
            windows.append(win)
            views.append(view)

            if sf.contains(mouseLoc) {
                initialKeyWin = win
            }

            view.onBeginSelection = { [weak view] in
                for v in views where v !== view {
                    v.clearSelection()
                }
            }
            view.onFinish = { [weak self, weak win] localRect in
                self?.finishCapture(on: win, localRect: localRect, completion: completion)
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        let keyWin = initialKeyWin ?? windows.first
        for win in windows where win !== keyWin {
            win.orderFrontRegardless()
        }
        if let keyWin = keyWin {
            keyWin.makeKeyAndOrderFront(nil)
            if let v = keyWin.contentView {
                keyWin.makeFirstResponder(v)
            }
        }
    }

    // NSImage → 缩放(最长边 ≤ 2048)→ PNG → base64 data URL
    static func encodeToDataURL(_ image: NSImage) -> String? {
        guard var cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let maxSide = 2048
        let w = cg.width, h = cg.height
        if max(w, h) > maxSide {
            let scale = CGFloat(maxSide) / CGFloat(max(w, h))
            let nw = max(1, Int(CGFloat(w) * scale)), nh = max(1, Int(CGFloat(h) * scale))
            if let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.interpolationQuality = .high
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
                if let scaled = ctx.makeImage() { cg = scaled }
            }
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + data.base64EncodedString()
    }

    // 屏幕录制权限(与「辅助功能」彼此独立)
    static func hasScreenRecordingPermission() -> Bool { CGPreflightScreenCaptureAccess() }
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool { CGRequestScreenCaptureAccess() }
}
