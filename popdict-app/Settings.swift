import AppKit
import ApplicationServices

// ============================================================
// 偏好设置窗口:模仿 macOS 原生工具栏图标样式 Tab 栏,分为三个标签页:
//   0. 基础:「在开机时启动」(LaunchAtLogin)、快捷键说明与当前服务商概览
//   1. 权限:辅助功能、屏幕录制权限状态检查与系统设置跳转
//   2. 服务商:Vertex AI / Gemini / DeepSeek / MiMo(前置彩色品牌 Logo)及自定义服务商配置
// ============================================================

enum BrandIcons {
    static let kIcon_deepseek = "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"
    static let kIcon_gemini = "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"
    static let kIcon_vertexai = "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"
    static let kIcon_xiaomi = "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"

    private static var cache: [String: NSImage] = [:]

    private static func decodePNG(_ b64: String) -> NSImage? {
        guard let data = Data(base64Encoded: b64),
              let img = NSImage(data: data) else { return nil }
        img.size = NSSize(width: 16, height: 16)
        img.isTemplate = false
        return img
    }

    static func icon(for providerName: String) -> NSImage? {
        let key = providerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let cached = cache[key] { return cached }

        let img: NSImage?
        switch key {
        case "deepseek":
            img = decodePNG(kIcon_deepseek)
        case "gemini":
            img = decodePNG(kIcon_gemini)
        case "vertex ai", "vertexai", "vertex":
            img = decodePNG(kIcon_vertexai)
        case "mimo", "xiaomi":
            img = decodePNG(kIcon_xiaomi)
        default:
            if let sym = NSImage(systemSymbolName: "server.rack", accessibilityDescription: providerName) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                let configured = sym.withSymbolConfiguration(cfg) ?? sym
                configured.size = NSSize(width: 16, height: 16)
                img = configured
            } else {
                img = nil
            }
        }
        if let img = img { cache[key] = img }
        return img
    }
}

// MARK: - 顶部图标式 Tab 按钮(模仿图 2 偏好设置样式)
final class PrefTabButton: NSControl {
    let tabIndex: Int
    private let symbolName: String
    private let titleText: String
    private var hovering = false { didSet { needsDisplay = true } }
    private var trackingRef: NSTrackingArea?

    var isSelected: Bool = false {
        didSet { needsDisplay = true }
    }

    init(index: Int, symbol: String, title: String, target: AnyObject?, action: Selector?) {
        self.tabIndex = index
        self.symbolName = symbol
        self.titleText = title
        super.init(frame: NSRect(x: 0, y: 0, width: 74, height: 58))
        self.target = target
        self.action = action
        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 74),
            heightAnchor.constraint(equalToConstant: 58),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingRef = t
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let cardRect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: cardRect, xRadius: 10, yRadius: 10)

        if isSelected {
            if isDark {
                NSColor(white: 1.0, alpha: 0.14).setFill()
                path.fill()
                NSColor(white: 1.0, alpha: 0.22).setStroke()
                path.lineWidth = 1
                path.stroke()
            } else {
                let topCol = NSColor(white: 1.0, alpha: 0.95)
                let botCol = NSColor(white: 0.93, alpha: 0.88)
                if let grad = NSGradient(starting: topCol, ending: botCol) {
                    grad.draw(in: path, angle: -90)
                } else {
                    topCol.setFill()
                    path.fill()
                }
                NSColor(white: 0.0, alpha: 0.13).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        } else if hovering {
            NSColor.labelColor.withAlphaComponent(0.05).setFill()
            path.fill()
        }

        let activeColor = NSColor.controlAccentColor
        let idleColor = NSColor.secondaryLabelColor
        let fgColor = isSelected ? activeColor : idleColor

        if let baseImg = NSImage(systemSymbolName: symbolName, accessibilityDescription: titleText) {
            let symCfg = NSImage.SymbolConfiguration(pointSize: 20, weight: isSelected ? .medium : .regular)
                .applying(.init(hierarchicalColor: fgColor))
            let img = baseImg.withSymbolConfiguration(symCfg) ?? baseImg
            let iw = img.size.width, ih = img.size.height
            let ix = (bounds.width - iw) / 2
            let iy = bounds.height - ih - 10
            img.draw(in: NSRect(x: ix, y: iy, width: iw, height: ih), from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        let font = NSFont.systemFont(ofSize: 12, weight: isSelected ? .medium : .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fgColor
        ]
        let str = NSAttributedString(string: titleText, attributes: attrs)
        let sz = str.size()
        let tx = (bounds.width - sz.width) / 2
        let ty: CGFloat = 7
        str.draw(at: NSPoint(x: tx, y: ty))
    }
}

final class SettingsController: NSObject {
    private var window: NSWindow?
    private var tabButtons: [PrefTabButton] = []
    private var tabViews: [NSView] = []
    private let contentContainer = NSView()
    private var currentTabIndex = 0

    // Tab 0: 基础控件
    private let launchAtLoginCheck = NSButton(checkboxWithTitle: "在开机时启动", target: nil, action: nil)
    private let basicActiveIconView = NSImageView()
    private let basicActiveLabel = NSTextField(labelWithString: "")

    // Tab 1: 权限控件
    private let axStatusLabel = NSTextField(labelWithString: "")
    private let scrStatusLabel = NSTextField(labelWithString: "")

    // Tab 2: 服务商控件
    private let providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let nameField = NSTextField()
    private let baseField = NSTextField()
    private let keyField = NSSecureTextField()
    private let modelField = NSTextField()
    private let visionCheck = NSButton(checkboxWithTitle: "支持看图(截图解释需要)", target: nil, action: nil)
    private let activeButton = NSButton(title: "设为当前使用", target: nil, action: nil)
    private let deleteButton = NSButton(title: "删除此服务商", target: nil, action: nil)

    // Tab 3: 语言与 Prompt 控件
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let translatePromptTextView = NSTextView()
    private let explainPromptTextView = NSTextView()
    private let resetPromptsButton = NSButton(title: "恢复默认 Prompt", target: nil, action: nil)

    private var nameRow: NSStackView?
    private var formatRow: NSStackView?
    private var baseRow: NSStackView?
    private var deleteRow: NSStackView?

    private var working: [Provider] = []
    private var workingLanguage: String = AppConfig.defaultLanguage
    private var workingTranslatePrompt: String = AppConfig.defaultTranslatePrompt
    private var workingExplainPrompt: String = AppConfig.defaultExplainPrompt
    private var activeIndex = 0
    private var selected = 0
    private let newItemTag = 9999
    private let restorePresetBaseTag = 9000

    func show(tab: Int? = nil) {
        if window == nil { build() }
        working = AppConfig.shared.providers
        if working.isEmpty { working = AppConfig.presets() }
        workingLanguage = AppConfig.shared.language
        workingTranslatePrompt = AppConfig.shared.translatePrompt
        workingExplainPrompt = AppConfig.shared.explainPrompt
        activeIndex = working.firstIndex { $0.name == AppConfig.shared.activeName } ?? 0
        selected = activeIndex
        launchAtLoginCheck.state = LaunchAtLogin.isEnabled() ? .on : .off
        rebuildPopup()
        loadForm()
        loadLanguageForm()
        refreshPermissions()
        selectTab(tab ?? currentTabIndex)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }

    func selectTab(_ index: Int) {
        guard index >= 0, index < tabViews.count else { return }
        flushForm()
        flushLanguageForm()
        currentTabIndex = index
        for (i, btn) in tabButtons.enumerated() {
            btn.isSelected = (i == index)
        }
        for (i, v) in tabViews.enumerated() {
            v.isHidden = (i != index)
        }
        refreshPermissions()
    }

    var windowObject: NSWindow? { window }

    private func build() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "偏好设置"
        win.isReleasedWhenClosed = false

        let b0 = PrefTabButton(index: 0, symbol: "gearshape", title: "基础", target: self, action: #selector(onTabClicked(_:)))
        let b1 = PrefTabButton(index: 1, symbol: "checkmark.shield", title: "权限", target: self, action: #selector(onTabClicked(_:)))
        let b2 = PrefTabButton(index: 2, symbol: "cpu", title: "服务商", target: self, action: #selector(onTabClicked(_:)))
        let b3 = PrefTabButton(index: 3, symbol: "globe", title: "语言", target: self, action: #selector(onTabClicked(_:)))
        tabButtons = [b0, b1, b2, b3]

        let tabBar = NSStackView(views: tabButtons)
        tabBar.orientation = .horizontal
        tabBar.spacing = 14
        tabBar.alignment = .centerY
        tabBar.translatesAutoresizingMaskIntoConstraints = false

        let topSep = NSBox()
        topSep.boxType = .separator
        topSep.alphaValue = 0.45
        topSep.translatesAutoresizingMaskIntoConstraints = false

        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        let vBasic = buildBasicTab()
        let vPerm = buildPermissionsTab()
        let vProv = buildProvidersTab()
        let vLang = buildLanguageTab()
        tabViews = [vBasic, vPerm, vProv, vLang]

        for v in tabViews {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(v)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                v.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
                v.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            ])
        }

        let cv = NSView()
        cv.addSubview(tabBar)
        cv.addSubview(topSep)
        cv.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12),
            tabBar.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            topSep.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 10),
            topSep.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 24),
            topSep.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -24),
            contentContainer.topAnchor.constraint(equalTo: topSep.bottomAnchor, constant: 6),
            contentContainer.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])

        win.contentView = cv
        window = win
    }

    @objc private func onTabClicked(_ sender: PrefTabButton) {
        selectTab(sender.tabIndex)
    }

    // MARK: - Tab 0: 基础
    private func buildBasicTab() -> NSView {
        launchAtLoginCheck.target = self
        launchAtLoginCheck.action = #selector(onLaunchAtLoginToggled)
        launchAtLoginCheck.font = .systemFont(ofSize: 13)

        let launchRow = prefRow(label: "启动", content: launchAtLoginCheck)

        let hkTitle = NSTextField(labelWithString: "⌃⌥E（Control + Option + E）")
        hkTitle.font = .systemFont(ofSize: 13)
        let hkHint = NSTextField(labelWithString: "框选屏幕任意区域后交由多模态模型看图讲解")
        hkHint.font = .systemFont(ofSize: 11)
        hkHint.textColor = .secondaryLabelColor
        let hkStack = NSStackView(views: [hkTitle, hkHint])
        hkStack.orientation = .vertical
        hkStack.alignment = .leading
        hkStack.spacing = 3
        let hkRow = prefRow(label: "截图解释", content: hkStack, alignTop: true)

        basicActiveIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            basicActiveIconView.widthAnchor.constraint(equalToConstant: 16),
            basicActiveIconView.heightAnchor.constraint(equalToConstant: 16),
        ])
        basicActiveLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let switchBtn = NSButton(title: "配置服务商…", target: self, action: #selector(onGoToProvidersTab))
        switchBtn.bezelStyle = .rounded
        switchBtn.controlSize = .small
        let curStack = NSStackView(views: [basicActiveIconView, basicActiveLabel, switchBtn])
        curStack.orientation = .horizontal
        curStack.spacing = 8
        curStack.alignment = .centerY
        let curRow = prefRow(label: "当前服务商", content: curStack)

        let vGap = NSView()
        vGap.translatesAutoresizingMaskIntoConstraints = false
        vGap.setContentHuggingPriority(.defaultLow, for: .vertical)

        let stack = NSStackView(views: [launchRow, hkRow, curRow, vGap])
        stack.orientation = .vertical
        stack.spacing = 22
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 48, bottom: 24, right: 48)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }

    @objc private func onLaunchAtLoginToggled() {
        let want = (launchAtLoginCheck.state == .on)
        if !LaunchAtLogin.setEnabled(want) {
            launchAtLoginCheck.state = LaunchAtLogin.isEnabled() ? .on : .off
            alert("无法修改开机启动配置，请检查 ~/Library/LaunchAgents 目录权限。")
        }
    }

    // MARK: - Tab 1: 权限
    private func buildPermissionsTab() -> NSView {
        axStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        scrStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let axBtn = NSButton(title: "打开系统设置…", target: self, action: #selector(onOpenAX))
        axBtn.bezelStyle = .rounded
        axBtn.controlSize = .small
        let axTop = NSStackView(views: [axStatusLabel, axBtn])
        axTop.orientation = .horizontal
        axTop.spacing = 10
        axTop.alignment = .centerY
        let axDesc = NSTextField(wrappingLabelWithString: "用于全局监听鼠标划词并直接读取选中文本(无此权限将无法弹出「翻译 / 解释」气泡)。")
        axDesc.font = .systemFont(ofSize: 11)
        axDesc.textColor = .secondaryLabelColor
        axDesc.preferredMaxLayoutWidth = 310
        let axCol = NSStackView(views: [axTop, axDesc])
        axCol.orientation = .vertical
        axCol.alignment = .leading
        axCol.spacing = 4
        let axRow = prefRow(label: "辅助功能", content: axCol, alignTop: true)

        let scrBtn = NSButton(title: "打开系统设置…", target: self, action: #selector(onOpenScreenRecording))
        scrBtn.bezelStyle = .rounded
        scrBtn.controlSize = .small
        let scrTop = NSStackView(views: [scrStatusLabel, scrBtn])
        scrTop.orientation = .horizontal
        scrTop.spacing = 10
        scrTop.alignment = .centerY
        let scrDesc = NSTextField(wrappingLabelWithString: "用于 ⌃⌥E 框选屏幕区域后截取画面交由多模态模型讲解。首次开启后通常需重新打开 Glint 生效。")
        scrDesc.font = .systemFont(ofSize: 11)
        scrDesc.textColor = .secondaryLabelColor
        scrDesc.preferredMaxLayoutWidth = 310
        let scrCol = NSStackView(views: [scrTop, scrDesc])
        scrCol.orientation = .vertical
        scrCol.alignment = .leading
        scrCol.spacing = 4
        let scrRow = prefRow(label: "屏幕录制", content: scrCol, alignTop: true)

        let recheckBtn = NSButton(title: "重新检查权限", target: self, action: #selector(onRecheckPermissions))
        recheckBtn.bezelStyle = .rounded
        let recheckRow = prefRow(label: "状态检测", content: recheckBtn)

        let vGap = NSView()
        vGap.translatesAutoresizingMaskIntoConstraints = false
        vGap.setContentHuggingPriority(.defaultLow, for: .vertical)

        let stack = NSStackView(views: [axRow, scrRow, recheckRow, vGap])
        stack.orientation = .vertical
        stack.spacing = 20
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 48, bottom: 24, right: 36)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }

    // MARK: - Tab 2: 服务商
    private func buildProvidersTab() -> NSView {
        providerPopup.target = self; providerPopup.action = #selector(popupChanged)
        providerPopup.translatesAutoresizingMaskIntoConstraints = false
        providerPopup.widthAnchor.constraint(equalToConstant: 210).isActive = true
        activeButton.target = self; activeButton.action = #selector(setActive); activeButton.bezelStyle = .rounded
        deleteButton.target = self; deleteButton.action = #selector(deleteCurrent); deleteButton.bezelStyle = .rounded; deleteButton.controlSize = .small

        let topRow = fieldRow("服务商", NSStackView(views: [providerPopup, activeButton]))

        formatPopup.target = self; formatPopup.action = #selector(formatChanged)
        formatPopup.translatesAutoresizingMaskIntoConstraints = false
        formatPopup.widthAnchor.constraint(equalToConstant: 320).isActive = true
        let fmtMenu = NSMenu()
        for fmt in APIFormat.customSelectableCases {
            let item = NSMenuItem(title: fmt.displayName, action: nil, keyEquivalent: "")
            item.representedObject = fmt.rawValue
            fmtMenu.addItem(item)
        }
        formatPopup.menu = fmtMenu

        for f in [nameField, baseField, keyField, modelField] {
            f.font = .systemFont(ofSize: 12); f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 320).isActive = true
        }
        baseField.placeholderString = APIFormat.openai.defaultBaseURL
        modelField.placeholderString = APIFormat.openai.defaultModelPlaceholder

        let nRow = fieldRow("名字", nameField)
        let fRow = fieldRow("接口格式", formatPopup)
        let bRow = fieldRow("Base URL", baseField)
        nameRow = nRow
        formatRow = fRow
        baseRow = bRow

        let form = NSStackView(views: [
            topRow,
            nRow, fRow, bRow,
            fieldRow("API Key", keyField), fieldRow("模型", modelField), indentRow(visionCheck),
        ])
        form.orientation = .vertical; form.spacing = 10; form.alignment = .leading

        let dRow = NSStackView(views: [hSpacer(), deleteButton]); dRow.orientation = .horizontal
        deleteRow = dRow

        let vGap = NSView(); vGap.translatesAutoresizingMaskIntoConstraints = false
        vGap.setContentHuggingPriority(.defaultLow, for: .vertical)

        let sep = NSBox(); sep.boxType = .separator; sep.alphaValue = 0.45; sep.translatesAutoresizingMaskIntoConstraints = false
        let saveBtn = NSButton(title: "保存", target: self, action: #selector(save))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        let closeBtn = NSButton(title: "关闭", target: self, action: #selector(closeWin))
        closeBtn.bezelStyle = .rounded
        let bottom = NSStackView(views: [hSpacer(), closeBtn, saveBtn])
        bottom.orientation = .horizontal
        bottom.spacing = 8

        let stack = NSStackView(views: [form, dRow, vGap, sep, bottom])
        stack.orientation = .vertical; stack.spacing = 10; stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 28, bottom: 14, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            dRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56),
            sep.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56),
            bottom.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56),
        ])
        return container
    }

    // MARK: - Tab 3: 语言与自定义 Prompt
    private func buildLanguageTab() -> NSView {
        languagePopup.target = self
        languagePopup.action = #selector(onLanguagePopupChanged)
        languagePopup.translatesAutoresizingMaskIntoConstraints = false
        languagePopup.widthAnchor.constraint(equalToConstant: 230).isActive = true

        let langMenu = NSMenu()
        for lang in AppConfig.supportedLanguages {
            let item = NSMenuItem(title: lang.displayName, action: nil, keyEquivalent: "")
            item.representedObject = lang.code
            langMenu.addItem(item)
        }
        languagePopup.menu = langMenu

        resetPromptsButton.target = self
        resetPromptsButton.action = #selector(onResetPrompts)
        resetPromptsButton.bezelStyle = .rounded
        resetPromptsButton.controlSize = .small

        let langTopBar = NSStackView(views: [languagePopup, resetPromptsButton])
        langTopBar.orientation = .horizontal
        langTopBar.spacing = 10
        langTopBar.alignment = .centerY

        let langHint = NSTextField(wrappingLabelWithString: "替换下方 Prompt 中的 <languages> 占位符（若删掉占位符，则语言选择对该 Prompt 不生效）。")
        langHint.font = .systemFont(ofSize: 11)
        langHint.textColor = .secondaryLabelColor
        langHint.preferredMaxLayoutWidth = 365

        let langCol = NSStackView(views: [langTopBar, langHint])
        langCol.orientation = .vertical
        langCol.alignment = .leading
        langCol.spacing = 4
        let langRow = fieldRowTop("目标语言", langCol)

        let transScroll = makePromptEditorScrollView(textView: translatePromptTextView, height: 68)
        let transRow = fieldRowTop("翻译 Prompt", transScroll)

        let explainScroll = makePromptEditorScrollView(textView: explainPromptTextView, height: 148)
        let explainRow = fieldRowTop("解释 Prompt", explainScroll)

        let vGap = NSView()
        vGap.translatesAutoresizingMaskIntoConstraints = false
        vGap.setContentHuggingPriority(.defaultLow, for: .vertical)

        let sep = NSBox()
        sep.boxType = .separator
        sep.alphaValue = 0.45
        sep.translatesAutoresizingMaskIntoConstraints = false

        let saveBtn = NSButton(title: "保存", target: self, action: #selector(save))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        let closeBtn = NSButton(title: "关闭", target: self, action: #selector(closeWin))
        closeBtn.bezelStyle = .rounded
        let bottom = NSStackView(views: [hSpacer(), closeBtn, saveBtn])
        bottom.orientation = .horizontal
        bottom.spacing = 8

        let stack = NSStackView(views: [langRow, transRow, explainRow, vGap, sep, bottom])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 28, bottom: 14, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sep.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56),
            bottom.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56),
        ])
        return container
    }

    private func makePromptEditorScrollView(textView: NSTextView, height: CGFloat) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalToConstant: 365),
            scroll.heightAnchor.constraint(equalToConstant: height),
        ])

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 350, height: CGFloat.greatestFiniteMagnitude)

        scroll.documentView = textView
        return scroll
    }

    private func fieldRowTop(_ t: String, _ field: NSView) -> NSStackView {
        let l = NSTextField(labelWithString: t)
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabelColor
        l.alignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 78).isActive = true
        let r = NSStackView(views: [l, field])
        r.orientation = .horizontal
        r.spacing = 10
        r.alignment = .top
        return r
    }

    // MARK: - 权限与概览状态刷新
    func refreshPermissions() {
        let axOK = AXIsProcessTrusted()
        axStatusLabel.stringValue = axOK ? "✓ 已授权" : "⚠️ 未授权"
        axStatusLabel.textColor = axOK ? .systemGreen : .systemOrange

        let scrOK = RegionCapture.hasScreenRecordingPermission()
        scrStatusLabel.stringValue = scrOK ? "✓ 已授权" : "⚠️ 未授权"
        scrStatusLabel.textColor = scrOK ? .systemGreen : .systemOrange

        let act: Provider? = (activeIndex >= 0 && activeIndex < working.count) ? working[activeIndex] : AppConfig.shared.active
        if let act = act {
            basicActiveIconView.image = BrandIcons.icon(for: act.name)
            let keyStatus = act.apiKey.isEmpty ? "未填 Key" : act.model
            basicActiveLabel.stringValue = "\(act.name)（\(keyStatus)）"
        } else {
            basicActiveIconView.image = nil
            basicActiveLabel.stringValue = "未选择"
        }
    }

    @objc private func onOpenAX() {
        gAppDelegate?.openAXSettings()
    }

    @objc private func onOpenScreenRecording() {
        gAppDelegate?.openScreenRecordingSettings()
    }

    @objc private func onRecheckPermissions() {
        gAppDelegate?.recheck()
        refreshPermissions()
    }

    @objc private func onGoToProvidersTab() {
        selectTab(2)
    }

    // MARK: - 布局辅助
    private func prefRow(label: String, content: NSView, alignTop: Bool = false) -> NSStackView {
        let l = NSTextField(labelWithString: label)
        l.font = .systemFont(ofSize: 13)
        l.textColor = .secondaryLabelColor
        l.alignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 82).isActive = true
        let r = NSStackView(views: [l, content])
        r.orientation = .horizontal
        r.spacing = 14
        r.alignment = alignTop ? .firstBaseline : .centerY
        return r
    }

    private func hSpacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func fieldRow(_ t: String, _ field: NSView) -> NSStackView {
        let l = NSTextField(labelWithString: t)
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabelColor
        l.alignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let r = NSStackView(views: [l, field])
        r.orientation = .horizontal
        r.spacing = 10
        r.alignment = .centerY
        return r
    }

    private func indentRow(_ v: NSView) -> NSStackView {
        let pad = NSView()
        pad.translatesAutoresizingMaskIntoConstraints = false
        pad.widthAnchor.constraint(equalToConstant: 82).isActive = true
        let r = NSStackView(views: [pad, v])
        r.orientation = .horizontal
        r.spacing = 0
        r.alignment = .centerY
        return r
    }

    private func rebuildPopup() {
        let menu = NSMenu()
        for (i, p) in working.enumerated() {
            let baseName = p.name.isEmpty ? "(未命名)" : p.name
            let title = (i == activeIndex) ? "\(baseName)（当前）" : baseName
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = i
            item.setExplicitIcon(BrandIcons.icon(for: p.name))
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let existingNames = Set(working.map { $0.name.lowercased() })
        for (idx, preset) in AppConfig.presets().enumerated() where !existingNames.contains(preset.name.lowercased()) {
            let restoreItem = NSMenuItem(title: "+ 添加官方预设: \(preset.name)", action: nil, keyEquivalent: "")
            restoreItem.tag = restorePresetBaseTag + idx
            restoreItem.setExplicitIcon(BrandIcons.icon(for: preset.name))
            menu.addItem(restoreItem)
        }
        let add = NSMenuItem(title: "+ 新增自定义服务商…", action: nil, keyEquivalent: "")
        add.tag = newItemTag
        if let plusImg = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: "新增") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            let configured = plusImg.withSymbolConfiguration(cfg) ?? plusImg
            configured.size = NSSize(width: 16, height: 16)
            add.setExplicitIcon(configured)
        }
        menu.addItem(add)
        providerPopup.menu = menu
        providerPopup.selectItem(at: max(0, min(selected, working.count - 1)))
    }

    private func selectedFormat() -> APIFormat {
        if let raw = formatPopup.selectedItem?.representedObject as? String,
           let fmt = APIFormat(rawValue: raw) {
            return fmt
        }
        return .openai
    }

    private func loadForm() {
        guard selected >= 0, selected < working.count else { return }
        let p = working[selected]
        let isPreset = AppConfig.isOfficialPreset(p.name)

        // 官方预设平台隐藏名字、接口格式、Base URL 与删除按钮
        nameRow?.isHidden = isPreset
        formatRow?.isHidden = isPreset
        baseRow?.isHidden = isPreset
        deleteRow?.isHidden = isPreset

        nameField.stringValue = p.name
        if let idx = APIFormat.customSelectableCases.firstIndex(of: p.format) {
            formatPopup.selectItem(at: idx)
        } else {
            formatPopup.selectItem(at: 0)
        }
        baseField.placeholderString = p.format.defaultBaseURL
        modelField.placeholderString = p.format.defaultModelPlaceholder
        baseField.stringValue = p.baseURL
        keyField.stringValue = p.apiKey
        modelField.stringValue = p.model
        visionCheck.state = p.vision ? .on : .off
        deleteButton.isEnabled = !isPreset && working.count > 1
        updateActiveButton()
    }

    private func flushForm() {
        guard selected >= 0, selected < working.count else { return }
        let current = working[selected]
        if let preset = AppConfig.officialPreset(named: current.name) {
            let mdl = modelField.stringValue.trimmingCharacters(in: .whitespaces)
            working[selected] = Provider(
                name: preset.name,
                format: preset.format,
                baseURL: preset.baseURL,
                apiKey: keyField.stringValue.trimmingCharacters(in: .whitespaces),
                model: mdl.isEmpty ? preset.model : mdl,
                vision: visionCheck.state == .on)
        } else {
            working[selected] = Provider(
                name: nameField.stringValue.trimmingCharacters(in: .whitespaces),
                format: selectedFormat(),
                baseURL: baseField.stringValue.trimmingCharacters(in: .whitespaces),
                apiKey: keyField.stringValue.trimmingCharacters(in: .whitespaces),
                model: modelField.stringValue.trimmingCharacters(in: .whitespaces),
                vision: visionCheck.state == .on)
        }
    }

    private func updateActiveButton() {
        if selected == activeIndex { activeButton.title = "✓ 当前使用中"; activeButton.isEnabled = false }
        else { activeButton.title = "设为当前使用"; activeButton.isEnabled = true }
    }

    @objc private func formatChanged() {
        let fmt = selectedFormat()
        baseField.placeholderString = fmt.defaultBaseURL
        modelField.placeholderString = fmt.defaultModelPlaceholder
        let curBase = baseField.stringValue.trimmingCharacters(in: .whitespaces)
        let defaultBases = Set(APIFormat.allCases.map { $0.defaultBaseURL } + ["https://", ""])
        if defaultBases.contains(curBase) {
            baseField.stringValue = fmt.defaultBaseURL
        }
        flushForm()
    }

    @objc private func popupChanged() {
        let tag = providerPopup.selectedItem?.tag ?? 0
        flushForm()
        let presets = AppConfig.presets()
        if tag == newItemTag {
            working.append(Provider(name: "新服务商", format: .openai, baseURL: APIFormat.openai.defaultBaseURL, apiKey: "", model: "", vision: false))
            selected = working.count - 1
        } else if tag >= restorePresetBaseTag && tag < restorePresetBaseTag + presets.count {
            let preset = presets[tag - restorePresetBaseTag]
            working.append(preset)
            selected = working.count - 1
        } else {
            selected = tag
        }
        rebuildPopup()
        loadForm()
    }

    @objc private func setActive() {
        flushForm()
        activeIndex = selected
        rebuildPopup()
        updateActiveButton()
        refreshPermissions()
    }

    @objc private func deleteCurrent() {
        guard working.count > 1, !AppConfig.isOfficialPreset(working[selected].name) else { return }
        flushForm()
        working.remove(at: selected)
        if activeIndex == selected { activeIndex = 0 }
        else if activeIndex > selected { activeIndex -= 1 }
        selected = min(selected, working.count - 1)
        rebuildPopup()
        loadForm()
        refreshPermissions()
    }

    private func loadLanguageForm() {
        if let idx = AppConfig.supportedLanguages.firstIndex(where: { $0.code == workingLanguage }) {
            languagePopup.selectItem(at: idx)
        } else {
            languagePopup.selectItem(at: 0)
        }
        translatePromptTextView.string = workingTranslatePrompt
        explainPromptTextView.string = workingExplainPrompt
    }

    private func flushLanguageForm() {
        if let code = languagePopup.selectedItem?.representedObject as? String, !code.isEmpty {
            workingLanguage = code
        }
        let tStr = translatePromptTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tStr.isEmpty {
            workingTranslatePrompt = translatePromptTextView.string
        }
        let eStr = explainPromptTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !eStr.isEmpty {
            workingExplainPrompt = explainPromptTextView.string
        }
    }

    @objc private func onLanguagePopupChanged() {
        flushLanguageForm()
    }

    @objc private func onResetPrompts() {
        workingTranslatePrompt = AppConfig.defaultTranslatePrompt
        workingExplainPrompt = AppConfig.defaultExplainPrompt
        translatePromptTextView.string = workingTranslatePrompt
        explainPromptTextView.string = workingExplainPrompt
    }

    @objc private func save() {
        flushForm()
        flushLanguageForm()
        if working.contains(where: { $0.name.isEmpty }) { alert("每个服务商都要有名字"); return }
        if Set(working.map { $0.name }).count != working.count { alert("服务商名字不能重复"); return }
        let activeName = working[max(0, min(activeIndex, working.count - 1))].name
        if !AppConfig.shared.setProviders(working, active: activeName) {
            alert("保存失败:无法写入配置文件(~/.config/glint)。请检查磁盘空间或目录权限。"); return
        }
        if !AppConfig.shared.setLanguageAndPrompts(
            language: workingLanguage,
            translatePrompt: workingTranslatePrompt,
            explainPrompt: workingExplainPrompt
        ) {
            alert("保存语言与 Prompt 配置失败:无法写入配置文件(~/.config/glint)。"); return
        }
        gAppDelegate?.refreshMenu()
        window?.close()
    }

    private func alert(_ msg: String) { let a = NSAlert(); a.messageText = msg; a.addButton(withTitle: "好的"); a.runModal() }
    @objc private func closeWin() { window?.close() }
}
