import AppKit

/// An opaque, layer-backed surface keeps the form's backing contents when its
/// parent application is inactive. The controller owns the complete view tree.
private final class FieldEditorSurface: NSView {
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

@MainActor
final class SQLFieldEditorController: NSWindowController, NSWindowDelegate {
    private let nameField = NSTextField()
    private let typePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let onSubmit: (String, SQLValueType) throws -> Void
    private var isDismissing = false

    init(onSubmit: @escaping (String, SQLValueType) throws -> Void) {
        self.onSubmit = onSubmit
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 286), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "添加时间字段"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = true
        panel.backgroundColor = .windowBackgroundColor
        panel.isExcludedFromWindowsMenu = true
        super.init(window: panel)
        panel.delegate = self
        buildForm(in: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationBecameActive), name: NSApplication.didBecomeActiveNotification, object: NSApp)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildForm(in panel: NSWindow) {
        let surface = FieldEditorSurface(frame: NSRect(x: 0, y: 0, width: 460, height: 286))
        surface.wantsLayer = true
        panel.contentView = surface

        let title = NSTextField(labelWithString: "添加时间字段")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let description = NSTextField(wrappingLabelWithString: "例如 paid_at 或 orders.created_at。字段及类型会保存在本机。")
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor

        let nameLabel = NSTextField(labelWithString: "字段名")
        let typeLabel = NSTextField(labelWithString: "类型")
        nameField.placeholderString = "paid_at"
        nameField.setAccessibilityLabel("新时间字段名称")
        nameField.setAccessibilityIdentifier("new-sql-field-name")
        typePopup.addItems(withTitles: SQLValueType.allCases.map(\.title))
        typePopup.selectItem(at: SQLValueType.allCases.firstIndex(of: .datetime)!)
        typePopup.setAccessibilityLabel("新时间字段类型")
        typePopup.setAccessibilityIdentifier("new-sql-field-type")
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 3
        errorLabel.setAccessibilityIdentifier("new-sql-field-error")

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelEditing))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let add = NSButton(title: "添加", target: self, action: #selector(addField))
        add.bezelStyle = .rounded
        add.keyEquivalent = "\r"
        panel.defaultButtonCell = add.cell as? NSButtonCell

        for view in [title, description, nameLabel, nameField, typeLabel, typePopup, errorLabel, cancel, add] {
            view.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            title.topAnchor.constraint(equalTo: surface.topAnchor, constant: 22),
            description.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            description.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -24),
            description.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: nameField.centerYAnchor),
            nameField.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 88),
            nameField.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -24),
            nameField.topAnchor.constraint(equalTo: description.bottomAnchor, constant: 18),
            nameField.heightAnchor.constraint(equalToConstant: 24),
            typeLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            typeLabel.centerYAnchor.constraint(equalTo: typePopup.centerYAnchor),
            typePopup.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            typePopup.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 12),
            typePopup.widthAnchor.constraint(equalToConstant: 160),
            errorLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: description.trailingAnchor),
            errorLabel.topAnchor.constraint(equalTo: typePopup.bottomAnchor, constant: 8),
            errorLabel.bottomAnchor.constraint(lessThanOrEqualTo: add.topAnchor, constant: -8),
            add.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -24),
            add.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -18),
            add.widthAnchor.constraint(equalToConstant: 76),
            cancel.trailingAnchor.constraint(equalTo: add.leadingAnchor, constant: -10),
            cancel.centerYAnchor.constraint(equalTo: add.centerYAnchor),
            cancel.widthAnchor.constraint(equalToConstant: 76)
        ])
        panel.initialFirstResponder = nameField
    }

    func refreshDisplay() {
        guard let window, let content = window.contentView else { return }
        content.needsLayout = true
        content.layoutSubtreeIfNeeded()
        content.setNeedsDisplay(content.bounds)
        window.displayIfNeeded()
    }

    @objc private func applicationBecameActive(_ notification: Notification) { refreshDisplay() }
    func windowDidBecomeKey(_ notification: Notification) { refreshDisplay() }
    func windowDidChangeOcclusionState(_ notification: Notification) {
        if window?.occlusionState.contains(.visible) == true { refreshDisplay() }
    }

    @objc private func addField(_ sender: Any?) {
        guard !isDismissing else { return }
        do {
            try onSubmit(nameField.stringValue, SQLValueType.allCases[typePopup.indexOfSelectedItem])
            dismiss(response: .OK)
        } catch {
            errorLabel.stringValue = error.localizedDescription
            window?.makeFirstResponder(nameField)
            refreshDisplay()
        }
    }

    @objc private func cancelEditing(_ sender: Any?) { dismiss(response: .cancel) }

    private func dismiss(response: NSApplication.ModalResponse) {
        guard !isDismissing, let panel = window else { return }
        isDismissing = true
        if let parent = panel.sheetParent { parent.endSheet(panel, returnCode: response) }
        else { panel.orderOut(nil) }
    }
}
