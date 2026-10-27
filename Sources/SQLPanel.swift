import AppKit

final class SQLPanel: NSView {
    let fieldPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let typePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let zonePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let stylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let addButton = NSButton(title: "+", target: nil, action: nil)
    let removeButton = NSButton(title: "−", target: nil, action: nil)
    let copyButton = NSButton(title: "复制 SQL", target: nil, action: nil)
    let preview = NSTextView(frame: NSRect(x: 0, y: 0, width: 820, height: 72))
    let hint = NSTextField(labelWithString: "")
    let zoneLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "MySQL")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        zoneLabel.font = .systemFont(ofSize: 11)
        zoneLabel.textColor = .secondaryLabelColor
        copyButton.bezelStyle = .rounded
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.imagePosition = .imageLeading
        copyButton.isEnabled = false
        copyButton.setAccessibilityIdentifier("sql-copy")
        let heading = NSStackView(views: [title, zoneLabel, NSView(), copyButton])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 10

        fieldPopup.setAccessibilityLabel("SQL 时间字段")
        fieldPopup.setAccessibilityIdentifier("sql-field")
        fieldPopup.widthAnchor.constraint(equalToConstant: 190).isActive = true
        typePopup.addItems(withTitles: SQLValueType.allCases.map(\.title))
        typePopup.widthAnchor.constraint(equalToConstant: 104).isActive = true
        typePopup.setAccessibilityLabel("SQL 变量类型")
        typePopup.setAccessibilityIdentifier("sql-type")
        zonePopup.addItems(withTitles: ["转换结果", "UTC", "GMT+8"])
        zonePopup.widthAnchor.constraint(equalToConstant: 118).isActive = true
        zonePopup.setAccessibilityLabel("SQL 使用的时区")
        zonePopup.setAccessibilityIdentifier("sql-zone")
        for button in [addButton, removeButton] {
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 16, weight: .regular)
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        }
        addButton.setAccessibilityLabel("添加时间字段")
        addButton.toolTip = "添加自定义时间字段"
        removeButton.setAccessibilityLabel("移除自定义时间字段")
        removeButton.toolTip = "移除选中的自定义字段；默认字段保留"

        func label(_ text: String) -> NSTextField {
            let view = NSTextField(labelWithString: text)
            view.font = .systemFont(ofSize: 12)
            view.textColor = .secondaryLabelColor
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
            return view
        }
        let fields = NSStackView(views: [label("字段"), fieldPopup, addButton, removeButton, label("类型"), typePopup, NSView(), label("取值"), zonePopup])
        fields.orientation = .horizontal
        fields.alignment = .centerY
        fields.spacing = 8

        stylePopup.addItems(withTitles: SQLSnippetStyle.allCases.filter { $0 != .assignment }.map { $0 == .equal ? "等于 / 多条 IN" : $0.title })
        stylePopup.widthAnchor.constraint(equalToConstant: 246).isActive = true
        stylePopup.setAccessibilityLabel("SQL 语句模板")
        stylePopup.setAccessibilityIdentifier("sql-style")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        let styles = NSStackView(views: [label("模板"), stylePopup, hint, NSView()])
        styles.orientation = .horizontal
        styles.alignment = .centerY
        styles.spacing = 8

        preview.isEditable = false
        preview.isSelectable = true
        preview.isRichText = false
        preview.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        preview.drawsBackground = false
        preview.textContainerInset = NSSize(width: 10, height: 8)
        preview.isVerticallyResizable = true
        preview.isHorizontallyResizable = false
        preview.autoresizingMask = .width
        preview.textContainer?.widthTracksTextView = true
        preview.setAccessibilityLabel("MySQL 语句预览")
        preview.setAccessibilityIdentifier("sql-preview")
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = preview

        let content = NSStackView(views: [heading, fields, styles, scroll])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            heightAnchor.constraint(equalToConstant: 218),
            heading.heightAnchor.constraint(equalToConstant: 28),
            fields.heightAnchor.constraint(equalToConstant: 28),
            styles.heightAnchor.constraint(equalToConstant: 28),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 70)
        ])
        for view in [heading, fields, styles, scroll] {
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        shape.fill()
        NSColor.separatorColor.setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }
}
