import AppKit

// Geometry.swift 的单测(不进 App 打包;跑法:
//   swiftc -o /tmp/popdict_geo_test Geometry.swift geometry_tests.swift -framework AppKit && /tmp/popdict_geo_test)

@main
struct GeoTests {
    static var failures = 0

    static func expect(_ cond: Bool, _ name: String) {
        if cond {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func approx(_ a: CGFloat, _ b: CGFloat, eps: CGFloat = 0.5) -> Bool {
        abs(a - b) < eps
    }

    static func insideSafeArea(_ r: NSRect, visible vf: CGRect, gap: CGFloat = 6) -> Bool {
        let safe = vf.insetBy(dx: gap, dy: gap)
        return r.minX >= safe.minX - 0.5
            && r.maxX <= safe.maxX + 0.5
            && r.minY >= safe.minY - 0.5
            && r.maxY <= safe.maxY + 0.5
    }

    static func main() {
        let vf = NSRect(x: 0, y: 0, width: 1800, height: 1100)
        let bubbleW: CGFloat = 152
        let bubbleH: CGFloat = 34

        // —— 1. 常量契约 ——
        expect(approx(kScreenEdgeGap, 6) && approx(kCursorOffsetX, 8) && approx(kCursorOffsetY, 8),
               "常量契约: kScreenEdgeGap=6, kCursorOffsetX=8, kCursorOffsetY=8")

        // —— 2. 常规位置(主屏内部): 浮窗左上角精确落在光标右下角 (pt.x + 8, pt.y - 8) ——
        let ptNormal = NSPoint(x: 900, y: 500)
        let rNormal = rectAtCursorBottomRight(ptNormal, visible: vf, w: bubbleW, h: bubbleH)
        expect(approx(rNormal.minX, 908)
                && approx(rNormal.maxY, 492)
                && approx(rNormal.origin.y, 492 - bubbleH)
                && approx(rNormal.width, bubbleW)
                && approx(rNormal.height, bubbleH)
                && rNormal.minX > ptNormal.x
                && rNormal.maxY < ptNormal.y,
               "常规位置: 左上角精确锚定在光标右下角 (pt.x+8, pt.y-8)")

        let rCompat = rectNearPoint(ptNormal, visible: vf, w: bubbleW, h: bubbleH)
        expect(approx(rCompat.minX, rNormal.minX)
                && approx(rCompat.minY, rNormal.minY)
                && approx(rCompat.width, rNormal.width)
                && approx(rCompat.height, rNormal.height),
               "兼容入口 rectNearPoint 与 rectAtCursorBottomRight 行为一致")

        // —— 3. 多行长段划词 / 反向划词释放点 ——
        let ptMultiLineEnd = NSPoint(x: 745, y: 435)
        let rMultiLine = rectAtCursorBottomRight(ptMultiLineEnd, visible: vf, w: bubbleW, h: bubbleH)
        expect(approx(rMultiLine.minX, 753) && approx(rMultiLine.maxY, 427) && insideSafeArea(rMultiLine, visible: vf),
               "多行长段划词释放点 (745, 435) → 精确锚定在 (753, 427)")

        let ptReverseEnd = NSPoint(x: 510, y: 627)
        let rReverse = rectAtCursorBottomRight(ptReverseEnd, visible: vf, w: bubbleW, h: bubbleH)
        expect(approx(rReverse.minX, 518) && approx(rReverse.maxY, 619) && insideSafeArea(rReverse, visible: vf),
               "反向拖选释放点 (510, 627) → 精确锚定在 (518, 619)")

        // —— 4. 屏幕右边界夹紧 ——
        let ptNearRight = NSPoint(x: 1720, y: 500)
        let rRight = rectAtCursorBottomRight(ptNearRight, visible: vf, w: bubbleW, h: bubbleH)
        expect(approx(rRight.maxX, vf.maxX - 6)
                && approx(rRight.minX, vf.maxX - 6 - bubbleW)
                && approx(rRight.maxY, 492)
                && insideSafeArea(rRight, visible: vf),
               "屏幕右边界夹紧: maxX 夹紧至 vf.maxX-6, maxY 保持 pt.y-8")

        // —— 5. 屏幕下边界夹紧(含 Dock 栏上方 vf.minY > 0) ——
        let vfWithDock = NSRect(x: 0, y: 70, width: 1800, height: 1005)
        let ptNearDock = NSPoint(x: 600, y: 95)
        let rBottom = rectAtCursorBottomRight(ptNearDock, visible: vfWithDock, w: bubbleW, h: bubbleH)
        expect(approx(rBottom.minY, vfWithDock.minY + 6)
                && approx(rBottom.minX, 608)
                && insideSafeArea(rBottom, visible: vfWithDock),
               "屏幕下边界夹紧(Dock 上方): minY 夹紧至 vf.minY+6, minX 保持 pt.x+8")

        // —— 6. 屏幕右下角极限位置 ——
        let ptBottomRight = NSPoint(x: 1795, y: 5)
        let rCornerBR = rectAtCursorBottomRight(ptBottomRight, visible: vf, w: bubbleW, h: bubbleH)
        expect(approx(rCornerBR.maxX, vf.maxX - 6)
                && approx(rCornerBR.minY, vf.minY + 6)
                && insideSafeArea(rCornerBR, visible: vf),
               "屏幕右下角极限位置: 同时触发右/下边界夹紧, 完整落在可视区内")

        // —— 7. 屏幕左边界与上边界极限位置 ——
        let ptLeftEdge = NSPoint(x: -5, y: 500)
        let rLeft = rectAtCursorBottomRight(ptLeftEdge, visible: vf, w: bubbleW, h: bubbleH)
        expect(approx(rLeft.minX, vf.minX + 6)
                && approx(rLeft.maxY, 492)
                && insideSafeArea(rLeft, visible: vf),
               "屏幕左边界极限位置: minX 夹紧至 vf.minX+6")

        let ptTopEdge = NSPoint(x: 900, y: 1105)
        let rTop = rectAtCursorBottomRight(ptTopEdge, visible: vf, w: bubbleW, h: bubbleH)
        expect(approx(rTop.minX, 908)
                && approx(rTop.maxY, vf.maxY - 6)
                && insideSafeArea(rTop, visible: vf),
               "屏幕上边界极限位置: maxY 夹紧至 vf.maxY-6")

        // —— 8. 多显示器负坐标屏幕(左侧外接屏) ——
        let vfLeftMonitor = CGRect(x: -2560, y: -116, width: 2560, height: 1440)
        let ptLeftMonCenter = NSPoint(x: -1200, y: 400)
        let rLeftMonCenter = rectAtCursorBottomRight(ptLeftMonCenter, visible: vfLeftMonitor, w: bubbleW, h: bubbleH)
        expect(approx(rLeftMonCenter.minX, -1192)
                && approx(rLeftMonCenter.maxY, 392)
                && insideSafeArea(rLeftMonCenter, visible: vfLeftMonitor),
               "左侧负坐标外接屏内部: 精确落在 (-1192, 392)")

        let ptLeftMonSeam = NSPoint(x: -50, y: 400)
        let rLeftMonSeam = rectAtCursorBottomRight(ptLeftMonSeam, visible: vfLeftMonitor, w: bubbleW, h: bubbleH)
        expect(approx(rLeftMonSeam.maxX, -6)
                && rLeftMonSeam.maxX <= -6
                && approx(rLeftMonSeam.maxY, 392)
                && insideSafeArea(rLeftMonSeam, visible: vfLeftMonitor),
               "左侧负坐标外接屏靠近交界处 (x=-50): 夹紧至 maxX=-6, 不跨屏跳入主屏")

        // —— 9. 展开态浮窗夹紧 (clampRectToVisible) ——
        let expandedInBounds = NSRect(x: 400, y: 300, width: 460, height: 380)
        let cInBounds = clampRectToVisible(expandedInBounds, visible: vf)
        expect(approx(cInBounds.minX, 400) && approx(cInBounds.minY, 300),
               "展开态浮窗未超界: clampRectToVisible 保持原位置不变")

        let expandedOverflowBR = NSRect(x: 1500, y: -120, width: 460, height: 380)
        let cOverflowBR = clampRectToVisible(expandedOverflowBR, visible: vf)
        expect(approx(cOverflowBR.maxX, vf.maxX - 6)
                && approx(cOverflowBR.minY, vf.minY + 6)
                && approx(cOverflowBR.width, 460)
                && approx(cOverflowBR.height, 380)
                && insideSafeArea(cOverflowBR, visible: vf),
               "展开态浮窗超出右下边界: clampRectToVisible 严格夹紧在 vf.insetBy(dx:6, dy:6) 内")

        let expandedOverflowTL = NSRect(x: -20, y: 800, width: 460, height: 380)
        let cOverflowTL = clampRectToVisible(expandedOverflowTL, visible: vf)
        expect(approx(cOverflowTL.minX, vf.minX + 6)
                && approx(cOverflowTL.maxY, vf.maxY - 6)
                && insideSafeArea(cOverflowTL, visible: vf),
               "展开态浮窗超出左上边界: clampRectToVisible 严格夹紧在 vf.insetBy(dx:6, dy:6) 内")

        // —— 10. 多屏框选截图坐标转换 (captureQuartzRect) ——
        let mainScreenFrame = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let qMain = captureQuartzRect(
            localRect: NSRect(x: 100, y: 200, width: 300, height: 400),
            screenFrame: mainScreenFrame,
            primaryScreenHeight: 1117
        )
        expect(approx(qMain.origin.x, 100)
                && approx(qMain.origin.y, 517)
                && approx(qMain.width, 300)
                && approx(qMain.height, 400),
               "主屏(Screen 0)框选坐标转换: localRect(100,200,300,400) → Quartz(100,517,300,400)")

        let subScreenFrame = NSRect(x: -2560, y: -116, width: 2560, height: 1440)
        let qSubMid = captureQuartzRect(
            localRect: NSRect(x: 500, y: 300, width: 600, height: 400),
            screenFrame: subScreenFrame,
            primaryScreenHeight: 1117
        )
        expect(approx(qSubMid.origin.x, -2060)
                && approx(qSubMid.origin.y, 533)
                && approx(qSubMid.width, 600)
                && approx(qSubMid.height, 400),
               "左侧负坐标不等高副屏(Screen 1)中部框选转换: localRect(500,300,600,400) → Quartz(-2060,533,600,400)")

        let qSubTop = captureQuartzRect(
            localRect: NSRect(x: 100, y: 1250, width: 200, height: 150),
            screenFrame: subScreenFrame,
            primaryScreenHeight: 1117
        )
        expect(approx(qSubTop.origin.x, -2460)
                && approx(qSubTop.origin.y, -167)
                && approx(qSubTop.width, 200)
                && approx(qSubTop.height, 150),
               "左侧不等高副屏高于主屏顶部区域框选转换: localRect(100,1250,200,150) → Quartz(-2460,-167,200,150)")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
        exit(failures == 0 ? 0 : 1)
    }
}
