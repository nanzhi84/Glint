# ADR-0001: 划词浮窗统一定位至鼠标光标右下角

- **状态 (Status)**：Accepted
- **日期 (Date)**：2026-10-26

## 1. 背景与上下文 (Context)

在先前的浮窗定位设计中，[popdict-app/Geometry.swift](../../popdict-app/Geometry.swift) 与 [popdict-app/main.swift](../../popdict-app/main.swift) 采用了双分支混合定位策略：
1. **AX 选区矩形分支（`rectBesideSelection`）**：当 macOS Accessibility（`kAXBoundsForRange` / `AXBoundsForTextMarkerRange` / `AXFrame`）返回的选区矩形通过粗略可信度校验（`plausibleSelectionBounds`）时，将气泡放在整个选区外接矩形右上角（`x = sel.maxX + 12, maxY = sel.maxY`），右侧空间不足时则翻转到选区最左侧（`x = sel.minX - 12 - w`）。
2. **释放点兜底分支（`rectNearPoint`）**：当 AX 未返回矩形（如终端、Claude Code 等走 `Cmd+C` 路径）或矩形被判不可信时，将气泡放在鼠标释放点**正上方水平居中**（`x = pt.x - w/2, y = pt.y + 12`）。

通过 [experiments/cursor-placement/run_experiment.swift](../../experiments/cursor-placement/run_experiment.swift) 对 `~/.config/popdict/popdict.log` 真实日志及 7 类典型划词场景的实验分析，发现旧方案在全部 7 类场景中均偏离光标右下角：
- **多行划词垂直远漂**：在 PDF.js 或网页中选中多行段落时，AX 返回整段的外接矩形 `sel`，其顶边 `sel.maxY` 位于第一行顶部，而用户释放鼠标时光标位于最后一行末尾，导致浮窗弹在距离光标 350px–590px 之外的段落首行右上角。
- **WebKit/Chrome 块级容器宽度虚高**：选中列表项前缀（如 `"2. "`，拖拽仅 74px）时，`AXBoundsForTextMarkerRange` 常返回整行块级容器宽度（`maxX = 1422`），浮窗向右远跳 572px。
- **靠右段落触发左跳远端**：当段落右缘靠近屏幕右侧时，`rectBesideSelection` 将浮窗翻转到 `sel.minX - 12 - w`（整段最左侧），距光标达 713px。
- **反向划词首尾倒置**：从右向左或从下向上拖选时，光标停在左端/上端，而 `sel.maxX` 仍在右端。
- **无 AX 场景遮挡选区与光标**：`rectNearPoint` 将气泡放在光标正上方居中，点击「翻译 / 解释」后浮窗以气泡左上角为锚点向下展开 `460×380` 面板，直接覆盖光标与刚选中的文字。
- **双屏交界处跨屏跳变**：旧版 `screenFor` / `clampToScreen` 以展开后未夹紧矩形的中心点 `(rect.midX, rect.midY)` 查找屏幕；当用户在左侧外接屏（`x: -2560..0`）靠右区域划词并展开 460px 浮窗时，`midX > 0` 落入右侧主屏，导致浮窗跨显示器跳变。

## 2. 决策方案 (Decision)

1. **统一锚定于鼠标释放光标右下角（`rectAtCursorBottomRight`）**：
   - 废弃基于 AX 选区外接矩形的 `rectBesideSelection`、`plausibleSelectionBounds` 与 `boundsForSelection` IPC 查询，取词路径仅查询 `kAXSelectedTextAttribute`（失败回退剪贴板 `Cmd+C`）。
   - 所有划词气泡统一以鼠标释放时刻的光标位置 `pt`（AppKit 坐标）为基准，将浮窗**左上角 `(rect.minX, rect.maxY)`** 精确锚定在光标右下角：
     - `minX = pt.x + 8`（光标右侧 8pt）
     - `maxY = pt.y - 8`（光标下方 8pt，即 `origin.y = pt.y - 8 - h`）
   - 若靠近当前屏幕 `visibleFrame` 右缘或下缘，在所属屏幕可视区内按 `kScreenEdgeGap = 6` 夹紧，绝不向段落远端翻转。
2. **以光标/锚点确定所属屏幕**：
   - 初始气泡以光标点 `pt` 确定所在 `NSScreen`；后续切换为「翻译 / 解释」大面板或流式自动长高时，固定以面板左上角锚点 `topLeft` 所在屏幕进行 `clampRectToVisible` 夹紧，消除双屏交界处的跨屏跳变。

## 3. 影响与后果 (Consequences)

- **正面收益**：
  - 无论在 Chrome、PDF.js、Safari、原生应用还是终端中，无论单行、跨 15 行段落、正向或反向拖选，浮窗 100% 精确落在光标右下角（距光标热点仅 `~11.3pt`），移动鼠标极短距离即可点击「🌐 翻译」或「💡 解释」。
  - 浮窗从光标右下角继续向右、向下生长，全程不遮挡光标左侧与上方的已选中文本。
  - 省去每次划词时最多 5 次冗余的 AX 参数化范围边界 IPC 调用，降低取词延迟与日志噪音。
- **边界约束**：
  - 当光标贴近屏幕最底部（距离 Dock 栏或屏幕底边不足浮窗高度）或最右端时，浮窗将贴齐当前屏幕可视区边缘（保留 `6pt` 间距）。
