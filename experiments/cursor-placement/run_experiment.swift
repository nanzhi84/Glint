import AppKit
import CoreGraphics
import Foundation

// ============================================================
// Experiment: Cursor Bottom-Right Placement vs Legacy Placement
// 1. 解析 ~/.config/glint/glint.log 真实划词日志统计 AX 异常与偏移
// 2. 验证本机双屏 (Retina 主屏 + 左侧外接屏) 坐标转换与 NSPanel minSize 行为
// 3. 对比 Legacy (rectBesideSelection / rectNearPoint) 与 CursorBottomRight 落点误差
// ============================================================

let kEdgeGap: CGFloat = 6

// --- 1. 旧版算法 (Baseline) ---
func legacyPlausibleSelectionBounds(_ r: CGRect, down: CGPoint, up: CGPoint) -> Bool {
    let drag = CGRect(x: min(down.x, up.x), y: min(down.y, up.y),
                      width: abs(down.x - up.x), height: abs(down.y - up.y))
    guard r.intersects(drag.insetBy(dx: -80, dy: -80)) else { return false }
    return r.height <= drag.height + 160
}

func legacyRectBesideSelection(_ selAK: CGRect, visible vf: CGRect, w: CGFloat, h: CGFloat) -> NSRect {
    let gap: CGFloat = 12
    var x = selAK.maxX + gap
    if x + w > vf.maxX - kEdgeGap {
        let leftX = selAK.minX - gap - w
        x = leftX >= vf.minX + kEdgeGap ? leftX : vf.maxX - w - kEdgeGap
    }
    x = max(x, vf.minX + kEdgeGap)
    var y = selAK.maxY - h
    y = min(y, vf.maxY - h - kEdgeGap)
    y = max(y, vf.minY + kEdgeGap)
    return NSRect(x: x, y: y, width: w, height: h)
}

func legacyRectNearPoint(_ pt: NSPoint, visible vf: CGRect, w: CGFloat, h: CGFloat) -> NSRect {
    let gap: CGFloat = 12
    var x = pt.x - w / 2
    x = min(max(x, vf.minX + kEdgeGap), vf.maxX - w - kEdgeGap)
    var y = pt.y + gap
    if y + h > vf.maxY - kEdgeGap { y = pt.y - gap - h }
    y = min(max(y, vf.minY + kEdgeGap), vf.maxY - h - kEdgeGap)
    return NSRect(x: x, y: y, width: w, height: h)
}

// --- 2. 新版算法: 精确锚定在光标右下角 (Cursor Bottom-Right) ---
// AppKit 坐标 (左下原点):
// 光标点为 pt。浮窗左上角 (minX, maxY) 精确落在光标右下角:
//   理想左上角: minX = pt.x + offsetX, maxY = pt.y - offsetY (即 origin.y = pt.y - offsetY - h)
// 若超出屏幕可视区右缘或下缘，夹紧进 visibleFrame (优先翻转到光标上方或贴齐右缘)。
func rectAtCursorBottomRight(
    _ pt: NSPoint,
    visible vf: CGRect,
    w: CGFloat,
    h: CGFloat,
    offsetX: CGFloat = 8,
    offsetY: CGFloat = 8
) -> NSRect {
    var x = pt.x + offsetX
    x = min(max(x, vf.minX + kEdgeGap), vf.maxX - w - kEdgeGap)

    var y = pt.y - offsetY - h
    y = min(max(y, vf.minY + kEdgeGap), vf.maxY - h - kEdgeGap)
    return NSRect(x: x, y: y, width: w, height: h)
}

// --- 3. 真实场景仿真测试集 ---
struct Scenario {
    let name: String
    let downQuartz: CGPoint
    let upQuartz: CGPoint
    let axBoundsQuartz: CGRect?   // AX 返回的矩形 (Quartz 左上原点)
    let visibleAK: CGRect         // 所在屏幕 visibleFrame (AppKit 左下原点)
    let primaryH: CGFloat
}

let vfMain = CGRect(x: 0, y: 90, width: 1728, height: 994)
let primaryH: CGFloat = 1117
let btnW: CGFloat = 149
let btnH: CGFloat = 32

let scenarios: [Scenario] = [
    // 场景 1: PDF.js 双栏论文 15 行整段划词 (取自 glint.log 15:09:23 真实坐标)
    Scenario(
        name: "PDF.js 15行整段正向划词 (log 15:09:23)",
        downQuartz: CGPoint(x: 420, y: 360),
        upQuartz: CGPoint(x: 745, y: 682),
        axBoundsQuartz: CGRect(x: 418, y: 356, width: 431, height: 334),
        visibleAK: vfMain,
        primaryH: primaryH
    ),
    // 场景 2: 网页列表项前缀短划词 "2. "，AX 却返回整行宽 1422 (取自 glint.log 15:00:02)
    Scenario(
        name: "网页列表项短划词 '2. ' (log 15:00:02)",
        downQuartz: CGPoint(x: 780, y: 690),
        upQuartz: CGPoint(x: 854, y: 690),
        axBoundsQuartz: CGRect(x: 780, y: 681, width: 642, height: 24),
        visibleAK: vfMain,
        primaryH: primaryH
    ),
    // 场景 3: 网页 7 行长段划词 (取自 glint.log 15:01:57 PDF.js 介绍段落)
    Scenario(
        name: "网页 7行段落划词 (log 15:01:57)",
        downQuartz: CGPoint(x: 520, y: 345),
        upQuartz: CGPoint(x: 830, y: 510),
        axBoundsQuartz: CGRect(x: 520, y: 339, width: 870, height: 180),
        visibleAK: vfMain,
        primaryH: primaryH
    ),
    // 场景 4: 从右往左 / 从下往上反向划词
    Scenario(
        name: "反向划词 (从右下往左上拖选)",
        downQuartz: CGPoint(x: 920, y: 580),
        upQuartz: CGPoint(x: 510, y: 490),
        axBoundsQuartz: CGRect(x: 510, y: 482, width: 410, height: 106),
        visibleAK: vfMain,
        primaryH: primaryH
    ),
    // 场景 5: 终端 / Claude Code 无 AX bounds (取自 glint.log 15:03:15 Cmd+C 路径)
    Scenario(
        name: "终端/Claude Code 无 AX 划词 (log 15:03:15)",
        downQuartz: CGPoint(x: 300, y: 600),
        upQuartz: CGPoint(x: 950, y: 640),
        axBoundsQuartz: nil,
        visibleAK: vfMain,
        primaryH: primaryH
    ),
    // 场景 6: 网页右侧栏划词 (sel.maxX 靠近屏幕右缘 1620，触发旧版左跳 bug)
    Scenario(
        name: "靠右缘段落划词 (旧版左跳远端 bug)",
        downQuartz: CGPoint(x: 980, y: 400),
        upQuartz: CGPoint(x: 1520, y: 460),
        axBoundsQuartz: CGRect(x: 980, y: 390, width: 640, height: 80),
        visibleAK: vfMain,
        primaryH: primaryH
    ),
    // 场景 7: 单行正向划词
    Scenario(
        name: "普通单行正向划词",
        downQuartz: CGPoint(x: 400, y: 500),
        upQuartz: CGPoint(x: 650, y: 500),
        axBoundsQuartz: CGRect(x: 400, y: 490, width: 250, height: 22),
        visibleAK: vfMain,
        primaryH: primaryH
    )
]

print("=== Experiment 1: 真实场景落点对比 (目标: 浮窗左上角落在光标右下角 pt + (8, -8)) ===")
for s in scenarios {
    let upAK = NSPoint(x: s.upQuartz.x, y: s.primaryH - s.upQuartz.y)
    let targetTopLeft = NSPoint(x: upAK.x + 8, y: upAK.y - 8)

    // Legacy 计算
    let legacyRect: NSRect
    if let b = s.axBoundsQuartz, legacyPlausibleSelectionBounds(b, down: s.downQuartz, up: s.upQuartz) {
        let selAK = CGRect(x: b.minX, y: s.primaryH - b.maxY, width: b.width, height: b.height)
        legacyRect = legacyRectBesideSelection(selAK, visible: s.visibleAK, w: btnW, h: btnH)
    } else {
        legacyRect = legacyRectNearPoint(upAK, visible: s.visibleAK, w: btnW, h: btnH)
    }
    let legacyTopLeft = NSPoint(x: legacyRect.minX, y: legacyRect.maxY)
    let legacyErr = hypot(legacyTopLeft.x - targetTopLeft.x, legacyTopLeft.y - targetTopLeft.y)
    let legacyInBottomRight = (legacyRect.minX >= upAK.x) && (legacyRect.maxY <= upAK.y)

    // New 计算
    let newRect = rectAtCursorBottomRight(upAK, visible: s.visibleAK, w: btnW, h: btnH)
    let newTopLeft = NSPoint(x: newRect.minX, y: newRect.maxY)
    let newErr = hypot(newTopLeft.x - targetTopLeft.x, newTopLeft.y - targetTopLeft.y)
    let newInBottomRight = (newRect.minX >= upAK.x) && (newRect.maxY <= upAK.y)

    print(String(format: "• %@\n    光标(AK)=(%.0f, %.0f) 期望左上角=(%.0f, %.0f)\n    Legacy 左上角=(%.0f, %.0f) 偏差=%.1fpx 位于光标右下=%@\n    New    左上角=(%.0f, %.0f) 偏差=%.1fpx 位于光标右下=%@",
                 s.name,
                 upAK.x, upAK.y, targetTopLeft.x, targetTopLeft.y,
                 legacyTopLeft.x, legacyTopLeft.y, legacyErr, legacyInBottomRight ? "YES" : "NO ❌",
                 newTopLeft.x, newTopLeft.y, newErr, newInBottomRight ? "YES ✅" : "NO"))
}

// --- 4. 验证 NSPanel minSize 对小尺寸按钮气泡的影响 ---
print("\n=== Experiment 2: NSPanel minSize vs 按钮气泡尺寸验证 ===")
let testRect = NSRect(x: 500, y: 500, width: 149, height: 32)
let p = NSPanel(contentRect: testRect, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
p.minSize = NSSize(width: 300, height: 180)
print("init frame with minSize(300,180): \(p.frame)")
p.setFrame(NSRect(x: 520, y: 480, width: 149, height: 32), display: false)
print("after setFrame(149,32) with minSize(300,180): \(p.frame)")

// --- 5. 双屏边界跳屏 Bug 复现与修复验证 ---
print("\n=== Experiment 3: 双屏交界处 (screen[1] x=-2560..0 与 screen[0] x=0..1728) 跳屏验证 ===")
let screen0Frame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
let screen0Visible = CGRect(x: 0, y: 90, width: 1728, height: 994)
let screen1Frame = CGRect(x: -2560, y: -116, width: 2560, height: 1440)
let screen1Visible = CGRect(x: -2560, y: -116, width: 2560, height: 1440)
let mockScreens = [(name: "screen[0]", frame: screen0Frame, visible: screen0Visible),
                   (name: "screen[1]", frame: screen1Frame, visible: screen1Visible)]

// 旧版按 rect.midX/midY 找屏幕: 当用户在 screen[1] 右侧 (x = -120, y = 500) 点开解释浮窗 (w = 460)
let anchorOnScreen1 = NSPoint(x: -120, y: 500)
let expandedRect = NSRect(x: anchorOnScreen1.x, y: anchorOnScreen1.y - 180, width: 460, height: 180)
let legacyPickedScreen = mockScreens.first(where: { $0.frame.contains(NSPoint(x: expandedRect.midX, y: expandedRect.midY)) })?.name ?? "fallback"
let fixedPickedScreen = mockScreens.first(where: { $0.frame.contains(anchorOnScreen1) })?.name ?? "fallback"
print("用户在 screen[1] 右侧 (x=-120) 展开 460px 浮窗:")
print("  expandedRect.midX = \(expandedRect.midX)")
print("  Legacy screenFor(expandedRect) 选中屏幕: \(legacyPickedScreen) (错误跳到主屏 ❌)")
print("  Fixed  screenFor(point: anchor) 选中屏幕: \(fixedPickedScreen) (保持在当前屏 ✅)")

// --- 6. 解析 ~/.config/glint/glint.log 统计真实划词情况 ---
let logPath = ("~/.config/glint/glint.log" as NSString).expandingTildeInPath
if let data = try? Data(contentsOf: URL(fileURLWithPath: logPath)),
   let content = String(data: data.suffix(250_000), encoding: .utf8) {
    let lines = content.components(separatedBy: "\n")
    var axCount = 0
    var nilBoundsCount = 0
    var implausibleCount = 0
    var m1ZeroErrCount = 0
    var m3UsedCount = 0
    for l in lines {
        if l.contains("m1 bounds-for-range err=0") { m1ZeroErrCount += 1 }
        if l.contains("m3 element-frame used") { m3UsedCount += 1 }
        if l.contains("bounds implausible") { implausibleCount += 1 }
        if l.contains("AX=") && l.contains("bounds=nil") { nilBoundsCount += 1 }
        else if l.contains("AX=") && l.contains("bounds=") { axCount += 1 }
    }
    print("\n=== Experiment 4: ~/.config/glint/glint.log 尾部 250KB 真实划词统计 ===")
    print("  AX 返回非空 bounds 次数: \(axCount) (其中 m1 返回空矩形回退 m2/m3: \(m1ZeroErrCount) 次, 落入 m3 整元素 frame: \(m3UsedCount) 次, 被判 implausible: \(implausibleCount) 次)")
    print("  AX 返回 bounds=nil (走 Cmd+C / 终端等): \(nilBoundsCount) 次")
}
