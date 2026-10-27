import AppKit

// ============================================================
// 浮窗定位的纯几何逻辑(不碰 NSScreen/NSEvent,便于单测:见 geometry_tests.swift)
// ============================================================

let kScreenEdgeGap: CGFloat = 6   // 浮窗与可视区边缘的最小间距
let kCursorOffsetX: CGFloat = 8   // 浮窗左缘相对光标向右偏移
let kCursorOffsetY: CGFloat = 8   // 浮窗上缘相对光标向下偏移

// 将任意浮窗矩形严格夹紧在屏幕可视区 visibleFrame 内(四边保留 kScreenEdgeGap 间距)。
func clampRectToVisible(_ rect: NSRect, visible vf: CGRect) -> NSRect {
    var r = rect
    r.origin.x = min(max(r.origin.x, vf.minX + kScreenEdgeGap), vf.maxX - r.width - kScreenEdgeGap)
    r.origin.y = min(max(r.origin.y, vf.minY + kScreenEdgeGap), vf.maxY - r.height - kScreenEdgeGap)
    return r
}

// 划词气泡定位(AppKit 左下原点坐标):
// 浮窗左上角 (minX, maxY) 精确落在鼠标光标 pt 的右下角 (pt.x + kCursorOffsetX, pt.y - kCursorOffsetY),
// 随后展开的翻译/解释浮窗保持该左上角锚点向右、向下生长,全程不遮挡光标左上方已选中的文本。
func rectAtCursorBottomRight(_ pt: NSPoint, visible vf: CGRect, w: CGFloat, h: CGFloat) -> NSRect {
    let x = pt.x + kCursorOffsetX
    let y = pt.y - kCursorOffsetY - h
    return clampRectToVisible(NSRect(x: x, y: y, width: w, height: h), visible: vf)
}

// 兼容入口:同 rectAtCursorBottomRight
func rectNearPoint(_ pt: NSPoint, visible vf: CGRect, w: CGFloat, h: CGFloat) -> NSRect {
    return rectAtCursorBottomRight(pt, visible: vf, w: w, h: h)
}

// 多屏框选截图坐标转换:
// 将某一显示器全屏遮罩窗口内的局部选区 localRect(左下原点,相对于该屏幕窗口 frame)
// 转换为 CGWindowListCreateImage 所需的全局 Quartz 坐标(以主屏左上角为原点,Y 轴向下)。
func captureQuartzRect(localRect: NSRect, screenFrame: NSRect, primaryScreenHeight: CGFloat) -> CGRect {
    let globalMinX = screenFrame.minX + localRect.minX
    let globalMaxY = screenFrame.minY + localRect.maxY
    return CGRect(
        x: globalMinX,
        y: primaryScreenHeight - globalMaxY,
        width: localRect.width,
        height: localRect.height
    )
}

