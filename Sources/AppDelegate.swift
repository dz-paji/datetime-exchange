import AppKit

private final class ZonePanel: NSView {
    let zone: ConversionZone
    let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 350, height: 220))
    let roleLabel = NSTextField(labelWithString: "")
    let countLabel = NSTextField(labelWithString: "支持单条或多行")
    let copyButton = NSButton(title: "复制", target: nil, action: nil)
    let pasteButton = NSButton(title: "粘贴", target: nil, action: nil)
    var isSource = false { didSet { needsDisplay = true } }
    var hasError = false { didSet { needsDisplay = true } }

    init(zone: ConversionZone) {
        self.zone = zone
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: zone.title)
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let offset = NSTextField(labelWithString: zone == .utc ? "+00:00" : "+08:00")
        offset.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        offset.textColor = .secondaryLabelColor
        roleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        roleLabel.setContentHuggingPriority(.required, for: .horizontal)

        let heading = NSStackView(views: [title, offset, NSView(), roleLabel])
        heading.orientation = .horizontal
        heading.alignment = .firstBaseline
        heading.spacing = 10

        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.font = .monospacedSystemFont(ofSize: 17, weight: .regular)
        editor.textColor = .labelColor
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 17, height: 12)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.smartInsertDeleteEnabled = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = true
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = false
        editor.setAccessibilityLabel("\(zone.title) 时间")
        editor.setAccessibilityIdentifier("\(zone.rawValue)-editor")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 8
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: editor.font!, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = editor

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        copyButton.bezelStyle = .rounded
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.imagePosition = .imageLeading
        copyButton.setAccessibilityLabel("复制 \(zone.title) 时间")
        pasteButton.bezelStyle = .rounded
        pasteButton.setAccessibilityLabel("粘贴 \(zone.title) 时间")
        let footer = NSStackView(views: [countLabel, NSView(), pasteButton, copyButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        let separator = NSBox()
        separator.boxType = .separator

        for view in [heading, scroll, separator, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            heading.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            heading.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -6),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            separator.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            footer.heightAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: 12, yRadius: 12)
        NSColor.textBackgroundColor.setFill()
        shape.fill()
        (hasError ? NSColor.systemRed.withAlphaComponent(0.7) : isSource ? NSColor.systemGreen.withAlphaComponent(0.55) : NSColor.separatorColor).setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSMenuItemValidation {
    private var window: NSWindow!
    private var panels: [ConversionZone: ZonePanel] = [:]
    private var source: ConversionZone = .utc
    private var isUpdating = false
    private var batchHasErrors = false
    private var inputCount = 0
    private var statusItem: NSStatusItem!
    private var clockTimer: Timer?
    private var messageTimer: Timer?
    private let utcClock = NSTextField(labelWithString: "")
    private let gmt8Clock = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "关闭窗口后，可从菜单栏重新打开")
    private let pinButton = NSButton(checkboxWithTitle: "窗口置顶", target: nil, action: nil)
    private let defaultStatus = "关闭窗口后，可从菜单栏重新打开"
    private let sqlPanel = SQLPanel(frame: .zero)
    private let sqlFields = SQLFieldStore()
    private var generatedSQL = ""
    private let sqlStyles = SQLSnippetStyle.allCases.filter { $0 != .assignment }
    private var fieldEditor: SQLFieldEditorController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenus()
        buildWindow()
        buildStatusItem()
        refresh(from: .utc)
        tick()
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        clockTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        showWindow(nil)
        window.makeFirstResponder(panels[.utc]!.editor)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(nil)
        return true
    }

    private func buildMenus() {
        let main = NSMenu()
        let appRoot = NSMenuItem()
        let appMenu = NSMenu(title: "时间转换")
        appMenu.addItem(withTitle: "关于时间转换", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏时间转换", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出时间转换", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appRoot.submenu = appMenu
        main.addItem(appRoot)

        let editRoot = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editRoot.submenu = edit
        main.addItem(editRoot)

        let convertRoot = NSMenuItem(title: "转换", action: nil, keyEquivalent: "")
        let convert = NSMenu(title: "转换")
        convert.addItem(withTitle: "复制转换结果", action: #selector(copyResult), keyEquivalent: "\r").target = self
        let copySQLItem = convert.addItem(withTitle: "复制 MySQL 条件", action: #selector(copySQL), keyEquivalent: "\r")
        copySQLItem.keyEquivalentModifierMask = [.command, .shift]
        copySQLItem.target = self
        convert.addItem(withTitle: "填入当前时间", action: #selector(fillNow), keyEquivalent: "n").target = self
        let clear = convert.addItem(withTitle: "清空", action: #selector(clearAll), keyEquivalent: "k")
        clear.keyEquivalentModifierMask = [.command, .shift]
        clear.target = self
        convert.addItem(.separator())
        convert.addItem(withTitle: "输入 UTC 时间", action: #selector(focusUTC), keyEquivalent: "1").target = self
        convert.addItem(withTitle: "输入 GMT+8 时间", action: #selector(focusGMT8), keyEquivalent: "2").target = self
        convertRoot.submenu = convert
        main.addItem(convertRoot)

        let windowRoot = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "显示时间转换", action: #selector(showWindow), keyEquivalent: "0").target = self
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowRoot.submenu = windowMenu
        main.addItem(windowRoot)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "时间转换"
        window.titlebarAppearsTransparent = true
        window.contentMinSize = NSSize(width: 900, height: 790)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("TimeConverterWindow")

        let title = NSTextField(labelWithString: "时间转换")
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "UTC  ⇄  GMT+8   ·   固定相差 8 小时，自动处理跨日与跨年")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 6
        let symbol = NSImageView()
        symbol.image = NSImage(systemSymbolName: "clock.arrow.2.circlepath", accessibilityDescription: nil)
        symbol.contentTintColor = .systemGreen
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 31, weight: .regular)
        symbol.widthAnchor.constraint(equalToConstant: 38).isActive = true
        symbol.heightAnchor.constraint(equalToConstant: 38).isActive = true
        let heading = NSStackView(views: [symbol, titleStack, NSView()])
        heading.orientation = .horizontal
        heading.spacing = 14

        for clock in [utcClock, gmt8Clock] {
            clock.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            clock.textColor = .secondaryLabelColor
            clock.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let clocks = NSStackView(views: [utcClock, gmt8Clock, NSView()])
        clocks.orientation = .horizontal
        clocks.spacing = 24

        let hint = NSTextField(labelWithString: "可只输入日期，缺少的时、分、秒自动补零。每行一条。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        pinButton.font = .systemFont(ofSize: 11)
        let nowButton = NSButton(title: "当前时间", target: self, action: #selector(fillNow))
        nowButton.bezelStyle = .rounded
        nowButton.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
        nowButton.imagePosition = .imageLeading
        let clearButton = NSButton(title: "清空", target: self, action: #selector(clearAll))
        clearButton.bezelStyle = .rounded
        let toolbar = NSStackView(views: [hint, NSView(), pinButton, nowButton, clearButton])
        toolbar.orientation = .horizontal
        toolbar.spacing = 10

        for (index, zone) in ConversionZone.allCases.enumerated() {
            let panel = ZonePanel(zone: zone)
            panel.editor.delegate = self
            panel.copyButton.tag = index
            panel.pasteButton.tag = index
            panel.copyButton.target = self
            panel.copyButton.action = #selector(copySide)
            panel.pasteButton.target = self
            panel.pasteButton.action = #selector(pasteSide)
            panels[zone] = panel
        }
        let converter = NSStackView(views: [panels[.utc]!, panels[.gmt8]!])
        converter.orientation = .horizontal
        converter.distribution = .fillEqually
        converter.spacing = 14
        converter.setContentHuggingPriority(.defaultLow, for: .vertical)

        let formatLabel = NSTextField(labelWithString: "输出 YYYY-MM-DD HH:mm:ss   ·   日期 / 小时 / 时分均可输入   ·   空行保留")
        formatLabel.font = .systemFont(ofSize: 11)
        formatLabel.textColor = .secondaryLabelColor
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 2
        errorLabel.isHidden = true
        errorLabel.setAccessibilityIdentifier("conversion-errors")

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setAccessibilityIdentifier("conversion-status")
        let shortcutLabel = NSTextField(labelWithString: "⌘↩ 时间 · ⇧⌘↩ SQL")
        shortcutLabel.font = .systemFont(ofSize: 11)
        shortcutLabel.textColor = .secondaryLabelColor
        let exampleButton = NSButton(title: "跨日示例", target: self, action: #selector(fillExample))
        exampleButton.bezelStyle = .inline
        let bottom = NSStackView(views: [statusLabel, NSView(), shortcutLabel, exampleButton])
        bottom.orientation = .horizontal
        bottom.spacing = 15

        configureSQLControls()
        let stack = NSStackView(views: [heading, clocks, toolbar, converter, formatLabel, sqlPanel, errorLabel, bottom])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
        for view in [heading, clocks, toolbar, converter, formatLabel, sqlPanel, errorLabel, bottom] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "UTC ⇄ 8"
        statusItem.button?.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        statusItem.button?.toolTip = "时间转换 · 点击打开"
        let menu = NSMenu()
        menu.addItem(withTitle: "打开时间转换", action: #selector(showWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "填入当前时间", action: #selector(openWithNow), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出时间转换", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }

    private func refresh(from zone: ConversionZone) {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        source = zone
        let batch = TimeConversion.batch(panels[zone]!.editor.string, from: zone)
        let target = panels[zone.opposite]!
        target.editor.string = batch.output
        target.editor.undoManager?.removeAllActions()
        inputCount = batch.inputCount
        batchHasErrors = !batch.issues.isEmpty
        for side in ConversionZone.allCases {
            let panel = panels[side]!
            panel.isSource = side == zone
            panel.hasError = side == zone && batchHasErrors
            panel.roleLabel.stringValue = side == zone ? "输入" : "结果 / 也可输入"
            panel.roleLabel.textColor = side == zone ? .systemGreen : .secondaryLabelColor
            panel.copyButton.isEnabled = inputCount > 0 && !batchHasErrors
            if inputCount == 0 {
                panel.countLabel.stringValue = side == zone ? "支持单条或多行" : "等待输入"
            } else if side == zone {
                panel.countLabel.stringValue = "\(inputCount) 条时间" + (batchHasErrors ? " · \(batch.issues.count) 条错误" : "")
            } else {
                panel.countLabel.stringValue = "已转换 \(inputCount - batch.issues.count) 条" + (batchHasErrors ? " · 错误行留空" : "")
            }
        }
        errorLabel.isHidden = !batchHasErrors
        errorLabel.stringValue = batch.issues.prefix(3).map { "\(zone.title) 第 \($0.line) 行：\($0.message)" }.joined(separator: "\n")
        messageTimer?.invalidate()
        statusLabel.stringValue = batchHasErrors ? "请修正错误行后再复制" : defaultStatus
        statusLabel.textColor = batchHasErrors ? .systemRed : .secondaryLabelColor
        refreshSQL()
    }

    private func configureSQLControls() {
        sqlPanel.fieldPopup.target = self
        sqlPanel.fieldPopup.action = #selector(sqlFieldChanged)
        sqlPanel.typePopup.target = self
        sqlPanel.typePopup.action = #selector(sqlTypeChanged)
        sqlPanel.zonePopup.target = self
        sqlPanel.zonePopup.action = #selector(sqlZoneChanged)
        sqlPanel.stylePopup.target = self
        sqlPanel.stylePopup.action = #selector(sqlStyleChanged)
        sqlPanel.addButton.target = self
        sqlPanel.addButton.action = #selector(addSQLField)
        sqlPanel.removeButton.target = self
        sqlPanel.removeButton.action = #selector(removeSQLField)
        sqlPanel.copyButton.target = self
        sqlPanel.copyButton.action = #selector(copySQL)
        sqlPanel.typePopup.toolTip = "string：带引号的完整时间；datetime：CAST 为 DATETIME；date：先按所选时区转换，再只保留日期"
        if !sqlStyles.contains(sqlFields.style) { sqlFields.style = .greaterOrEqual }
        sqlPanel.stylePopup.selectItem(at: sqlStyles.firstIndex(of: sqlFields.style) ?? 1)
        sqlPanel.zonePopup.selectItem(at: sqlFields.zoneIndex)
        reloadSQLFields()
    }

    private func reloadSQLFields() {
        sqlPanel.fieldPopup.removeAllItems()
        sqlPanel.fieldPopup.addItems(withTitles: sqlFields.fields.map(\.name))
        sqlPanel.fieldPopup.selectItem(withTitle: sqlFields.selectedName)
        syncSQLFieldType()
    }

    private func syncSQLFieldType() {
        let field = sqlFields.fields.first(where: { $0.name == sqlFields.selectedName })!
        sqlPanel.typePopup.selectItem(at: SQLValueType.allCases.firstIndex(of: field.valueType) ?? 1)
        sqlPanel.removeButton.isEnabled = sqlFields.canRemove(field.name)
    }

    private var selectedSQLZone: ConversionZone {
        switch sqlFields.zoneIndex {
        case 1: return .utc
        case 2: return .gmt8
        default: return source.opposite
        }
    }

    private var selectedSQLStyle: SQLSnippetStyle {
        if sqlFields.hasChosenStyle { return sqlFields.style }
        if inputCount == 2 { return .range }
        return inputCount > 2 ? .equal : .greaterOrEqual
    }

    private func refreshSQL() {
        generatedSQL = ""
        sqlPanel.copyButton.isEnabled = false
        let zone = selectedSQLZone
        let style = selectedSQLStyle
        sqlPanel.stylePopup.selectItem(at: sqlStyles.firstIndex(of: style) ?? 1)
        sqlPanel.zoneLabel.stringValue = "\(zone.title) · 复制到 WHERE 后"
        switch style {
        case .equal:
            sqlPanel.hint.stringValue = "单条时间用 =，多条自动生成 IN (…)"
        case .between:
            sqlPanel.hint.stringValue = "输入两行：起始时间、结束时间；包含两端"
        case .range:
            sqlPanel.hint.stringValue = "输入两行：起始时间、结束时间；不包含结束"
        default:
            sqlPanel.hint.stringValue = "输入一条时间；多条可选 IN 或区间模板"
        }
        guard inputCount > 0 else {
            setSQLPreview("输入时间后，这里会自动生成 MySQL 筛选条件。", color: .secondaryLabelColor)
            return
        }
        guard !batchHasErrors else {
            setSQLPreview("请先修正时间输入中的错误，再生成 SQL。", color: .systemRed)
            return
        }
        guard let field = sqlFields.fields.first(where: { $0.name == sqlFields.selectedName }) else { return }
        do {
            generatedSQL = try SQLGeneration.generate(times: panels[zone]!.editor.string, field: field.name, valueType: field.valueType, style: style)
            setSQLPreview(generatedSQL, color: .labelColor)
            sqlPanel.copyButton.isEnabled = true
        } catch {
            setSQLPreview(error.localizedDescription, color: .systemRed)
        }
    }

    private func setSQLPreview(_ text: String, color: NSColor) {
        sqlPanel.preview.string = text
        sqlPanel.preview.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        sqlPanel.preview.textColor = color
    }

    @objc private func sqlFieldChanged(_ sender: NSPopUpButton) {
        guard let name = sender.titleOfSelectedItem else { return }
        sqlFields.selectedName = name
        syncSQLFieldType()
        refreshSQL()
    }

    @objc private func sqlTypeChanged(_ sender: NSPopUpButton) {
        guard SQLValueType.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        sqlFields.setType(SQLValueType.allCases[sender.indexOfSelectedItem], for: sqlFields.selectedName)
        refreshSQL()
    }

    @objc private func sqlZoneChanged(_ sender: NSPopUpButton) {
        sqlFields.zoneIndex = sender.indexOfSelectedItem
        refreshSQL()
    }

    @objc private func sqlStyleChanged(_ sender: NSPopUpButton) {
        guard sqlStyles.indices.contains(sender.indexOfSelectedItem) else { return }
        sqlFields.style = sqlStyles[sender.indexOfSelectedItem]
        refreshSQL()
    }

    @objc private func addSQLField(_ sender: Any?) {
        if let fieldEditor {
            fieldEditor.refreshDisplay()
            return
        }
        let editor = SQLFieldEditorController { [weak self] name, type in
            guard let self else { return }
            try self.sqlFields.add(name: name, type: type)
            self.reloadSQLFields()
            self.refreshSQL()
            self.showMessage("已添加字段 \(self.sqlFields.selectedName)")
        }
        fieldEditor = editor
        let panel = editor.window!
        window.beginSheet(panel) { [weak self, weak editor] _ in
            panel.orderOut(nil)
            if self?.fieldEditor === editor { self?.fieldEditor = nil }
        }
        editor.refreshDisplay()
    }

    @objc private func removeSQLField(_ sender: Any?) {
        let name = sqlFields.selectedName
        guard sqlFields.canRemove(name) else { return }
        sqlFields.remove(name)
        reloadSQLFields()
        refreshSQL()
        showMessage("已移除自定义字段 \(name)")
    }

    @objc private func copySQL(_ sender: Any?) {
        guard !generatedSQL.isEmpty else { NSSound.beep(); return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(generatedSQL, forType: .string) {
            showMessage("已复制 MySQL 条件 · \(selectedSQLZone.title)")
        } else {
            showMessage("复制失败，请在 SQL 预览中选中后按 ⌘C", error: true)
        }
    }

    func textDidChange(_ notification: Notification) {
        guard !isUpdating, let editor = notification.object as? NSTextView,
              let zone = ConversionZone.allCases.first(where: { panels[$0]?.editor === editor }) else { return }
        refresh(from: zone)
    }

    private func replaceInput(_ text: String, in zone: ConversionZone, select: Bool = false) {
        panels[zone]!.editor.string = text
        panels[zone]!.editor.undoManager?.removeAllActions()
        refresh(from: zone)
        window.makeFirstResponder(panels[zone]!.editor)
        if select { panels[zone]!.editor.selectAll(nil) }
    }

    private func copy(_ zone: ConversionZone) {
        guard inputCount > 0, !batchHasErrors else { NSSound.beep(); return }
        do {
            let normalized = try panels[zone]!.editor.string
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n")
                .map { line in line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : try TimeConversion.canonical(line) }
                .joined(separator: "\n")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(normalized, forType: .string) else {
                showMessage("复制失败，请选中结果后按 ⌘C", error: true)
                return
            }
            showMessage("已复制 \(zone.title) · \(inputCount) 条时间")
        } catch {
            showMessage(error.localizedDescription, error: true)
        }
    }

    private func showMessage(_ text: String, error: Bool = false) {
        messageTimer?.invalidate()
        statusLabel.stringValue = text
        statusLabel.textColor = error ? .systemRed : .systemGreen
        messageTimer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(resetMessage), userInfo: nil, repeats: false)
    }

    @objc private func resetMessage() {
        statusLabel.stringValue = batchHasErrors ? "请修正错误行后再复制" : defaultStatus
        statusLabel.textColor = batchHasErrors ? .systemRed : .secondaryLabelColor
    }

    @objc private func tick() {
        let now = Date()
        utcClock.stringValue = "当前 UTC   \(TimeConversion.current(in: .utc, at: now))"
        gmt8Clock.stringValue = "GMT+8   \(TimeConversion.current(in: .gmt8, at: now))"
    }

    @objc private func showWindow(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        fieldEditor?.refreshDisplay()
    }
    @objc private func fillNow(_ sender: Any?) { replaceInput(TimeConversion.current(in: source), in: source, select: true) }
    @objc private func openWithNow(_ sender: Any?) { showWindow(nil); fillNow(nil) }
    @objc private func clearAll(_ sender: Any?) { replaceInput("", in: source) }
    @objc private func fillExample(_ sender: Any?) { replaceInput("2026-10-25\n2026-10-25 20\n2026-10-25 20:30", in: .utc) }
    @objc private func copyResult(_ sender: Any?) { copy(source.opposite) }
    @objc private func copySide(_ sender: NSButton) { copy(ConversionZone.allCases[sender.tag]) }
    @objc private func pasteSide(_ sender: NSButton) {
        let zone = ConversionZone.allCases[sender.tag]
        guard let text = NSPasteboard.general.string(forType: .string) else {
            showMessage("剪贴板里没有文本", error: true)
            return
        }
        replaceInput(text, in: zone)
    }
    @objc private func togglePin(_ sender: NSButton) { window.level = sender.state == .on ? .floating : .normal }
    @objc private func focusUTC(_ sender: Any?) { focus(.utc) }
    @objc private func focusGMT8(_ sender: Any?) { focus(.gmt8) }
    private func focus(_ zone: ConversionZone) { showWindow(nil); window.makeFirstResponder(panels[zone]!.editor); panels[zone]!.editor.selectAll(nil) }
    @objc private func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "时间转换", .applicationVersion: "1.2.1", .credits: NSAttributedString(string: "UTC ↔ GMT+8\n本地离线换算 · MySQL 时间筛选条件")])
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(copyResult) { return inputCount > 0 && !batchHasErrors }
        if menuItem.action == #selector(copySQL) { return !generatedSQL.isEmpty }
        return true
    }
}
