import AppKit
import ChecksumCore

@MainActor
final class FloatingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Borderless controls retain a quiet resting state and a generous hit target.
@MainActor
final class BarButton: NSButton {
    private var tracking: NSTrackingArea?
    private var hovered = false
    var showsTile = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if showsTile || (isEnabled && (hovered || isHighlighted)) {
            let opacity = isHighlighted ? 0.10 : (hovered && isEnabled ? 0.07 : 0.035)
            NSColor.labelColor.withAlphaComponent(opacity).setFill()
            let radius: CGFloat = showsTile ? 10 : 6
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius).fill()
        }
        super.draw(dirtyRect)
    }
}

@MainActor
final class SlimProgressView: NSView {
    private let fill = CALayer()
    var doubleValue: Double = 0 {
        didSet {
            needsLayout = true
            setAccessibilityValue(Int(min(max(doubleValue, 0), 1) * 100))
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        fill.backgroundColor = NSColor.controlAccentColor.cgColor
        layer?.addSublayer(fill)
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel("Calculating checksum")
        setAccessibilityMinValue(0)
        setAccessibilityMaxValue(100)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        fill.backgroundColor = NSColor.controlAccentColor.cgColor
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * min(max(doubleValue, 0), 1), height: bounds.height)
        CATransaction.commit()
    }
}

@MainActor
final class DropView: NSView {
    var onDrop: (([URL]) -> Void)?
    private var highlighted = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        updateBorder()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }

    private func updateBorder() {
        layer?.borderColor = (highlighted ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.12)).cgColor
        layer?.backgroundColor = (highlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.12)
            : NSColor.windowBackgroundColor).cgColor
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        highlighted = true
        updateBorder()
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        highlighted = false
        updateBorder()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        highlighted = false
        updateBorder()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        highlighted = false
        updateBorder()
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let algorithmMenu = NSPopUpButton()
    private let filename = NSTextField(labelWithString: "No file selected")
    private let preview = NSTextField(labelWithString: "Choose with + or ⌘O")
    private let details = NSPopover()
    private let result = NSTextView()
    private let progress = SlimProgressView()
    private let copyButton = BarButton(title: "Copy checksum", target: nil, action: nil)
    private let cancelButton = BarButton(title: "Cancel", target: nil, action: nil)
    private let moreButton = BarButton()
    private let detailsTitle = NSTextField(labelWithString: "Checksums")
    private let detailsSubtitle = NSTextField(labelWithString: "")
    private var copyFeedback: Task<Void, Never>?
    private var worker: Task<Void, Never>?
    private var runID = UUID()
    private var selectedFiles: [URL] = []
    private var copyValue = ""

    private var algorithm: Algorithm {
        Algorithm(rawValue: algorithmMenu.titleOfSelectedItem ?? "") ?? .sha256
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenus()
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        start(filenames.map { URL(fileURLWithPath: $0) })
        window.makeKeyAndOrderFront(nil)
        sender.reply(toOpenOrPrint: .success)
    }

    private func buildMenus() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About FaySHA", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit FaySHA", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        let open = fileMenu.addItem(withTitle: "Choose Files…", action: #selector(chooseFiles), keyEquivalent: "o")
        open.target = self
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        let copy = editMenu.addItem(withTitle: "Copy", action: #selector(copySelectionOrChecksum(_:)), keyEquivalent: "c")
        copy.target = self
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func buildWindow() {
        window = FloatingWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 72),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "FaySHA"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        // A separate autosave key prevents the old large window size from returning.
        window.setFrameAutosaveName("FaySHABar")
        if !window.setFrameUsingName("FaySHABar") { window.center() }
        window.setContentSize(NSSize(width: 520, height: 72))
        window.delegate = self

        let root = DropView(frame: .zero)
        root.onDrop = { [weak self] in self?.start($0) }
        root.layer?.masksToBounds = true
        window.contentView = root

        let choose = BarButton()
        configureIcon(choose, symbol: "plus", label: "Choose files (⌘O)", action: #selector(chooseFiles), size: NSSize(width: 38, height: 40))
        choose.showsTile = true
        choose.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        filename.stringValue = "Drop files here"
        filename.font = .systemFont(ofSize: 12, weight: .medium)
        filename.lineBreakMode = .byTruncatingMiddle
        preview.font = .systemFont(ofSize: 11, weight: .regular)
        preview.textColor = .secondaryLabelColor
        preview.lineBreakMode = .byTruncatingMiddle
        preview.isSelectable = true
        filename.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        filename.maximumNumberOfLines = 1
        preview.maximumNumberOfLines = 1

        algorithmMenu.addItems(withTitles: Algorithm.allCases.map(\.rawValue))
        algorithmMenu.selectItem(withTitle: UserDefaults.standard.string(forKey: "algorithm") ?? Algorithm.sha256.rawValue)
        algorithmMenu.controlSize = .small
        algorithmMenu.font = .systemFont(ofSize: 10, weight: .medium)
        algorithmMenu.isBordered = false
        algorithmMenu.setAccessibilityLabel("Checksum algorithm")
        algorithmMenu.target = self
        algorithmMenu.action = #selector(changeAlgorithm)
        algorithmMenu.widthAnchor.constraint(equalToConstant: 82).isActive = true
        algorithmMenu.heightAnchor.constraint(equalToConstant: 18).isActive = true
        updateNote()

        configureIcon(copyButton, symbol: "doc.on.doc", label: "Copy checksum", action: #selector(copyChecksum))
        copyButton.isEnabled = false
        copyButton.isHidden = true
        configureIcon(cancelButton, symbol: "stop.fill", label: "Cancel hashing", action: #selector(cancelHash))
        cancelButton.isEnabled = false
        cancelButton.isHidden = true
        configureIcon(moreButton, symbol: "chevron.down", label: "Show full checksums", action: #selector(showDetails(_:)))
        moreButton.isEnabled = false
        moreButton.isHidden = true
        let close = BarButton()
        configureIcon(close, symbol: "xmark", label: "Close window (⌘Q)", action: #selector(closeWindow), size: NSSize(width: 24, height: 28))
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .regular))
        close.contentTintColor = .secondaryLabelColor

        // Copy and stop share one slot, so hashing never shifts the layout.
        let actionSlot = NSView()
        actionSlot.translatesAutoresizingMaskIntoConstraints = false
        actionSlot.widthAnchor.constraint(equalToConstant: 28).isActive = true
        actionSlot.heightAnchor.constraint(equalToConstant: 26).isActive = true
        for button in [copyButton, cancelButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            actionSlot.addSubview(button)
            button.centerXAnchor.constraint(equalTo: actionSlot.centerXAnchor).isActive = true
            button.centerYAnchor.constraint(equalTo: actionSlot.centerYAnchor).isActive = true
        }
        // Metadata lives above the result actions. Fixed anchors keep all states stable.
        for view in [choose, filename, preview, algorithmMenu, actionSlot, moreButton, close] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        progress.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(progress)
        progress.isHidden = true
        NSLayoutConstraint.activate([
            choose.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            choose.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            filename.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 64),
            filename.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -11),
            filename.trailingAnchor.constraint(equalTo: algorithmMenu.leadingAnchor, constant: -12),
            algorithmMenu.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -48),
            algorithmMenu.centerYAnchor.constraint(equalTo: filename.centerYAnchor),
            preview.leadingAnchor.constraint(equalTo: filename.leadingAnchor),
            preview.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: 11),
            preview.trailingAnchor.constraint(equalTo: actionSlot.leadingAnchor, constant: -10),
            actionSlot.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -2),
            actionSlot.centerYAnchor.constraint(equalTo: preview.centerYAnchor),
            moreButton.trailingAnchor.constraint(equalTo: algorithmMenu.trailingAnchor),
            moreButton.centerYAnchor.constraint(equalTo: preview.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            close.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            progress.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            progress.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            progress.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2)
        ])

        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 220))
        let scroll = NSScrollView(frame: NSRect(x: 16, y: 16, width: 408, height: 146))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        detailsTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        detailsSubtitle.font = .systemFont(ofSize: 11)
        detailsSubtitle.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [detailsTitle, detailsSubtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 4
        heading.frame = NSRect(x: 20, y: 178, width: 400, height: 30)
        heading.autoresizingMask = [.width, .minYMargin]
        controller.view.addSubview(heading)
        result.frame = NSRect(origin: .zero, size: scroll.contentSize)
        result.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        result.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        result.isEditable = false
        result.isSelectable = true
        result.drawsBackground = false
        result.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        result.textColor = .labelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        result.defaultParagraphStyle = paragraph
        result.setAccessibilityLabel("Full checksum results")
        result.textContainerInset = NSSize(width: 4, height: 4)
        result.isHorizontallyResizable = false
        result.isVerticallyResizable = true
        result.autoresizingMask = [.width]
        result.textContainer?.widthTracksTextView = true
        result.textContainer?.lineBreakMode = .byCharWrapping
        result.string = "Drop files onto the bar to calculate their checksums."
        scroll.documentView = result
        controller.view.addSubview(scroll)
        details.contentViewController = controller
        details.behavior = .transient
        details.contentSize = NSSize(width: 440, height: 220)
    }

    private func configureIcon(_ button: NSButton, symbol: String, label: String, action: Selector, size: NSSize = NSSize(width: 28, height: 26)) {
        button.title = ""
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.target = self
        button.action = action
        button.image = button.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        button.focusRingType = .exterior
        button.widthAnchor.constraint(equalToConstant: size.width).isActive = true
        button.heightAnchor.constraint(equalToConstant: size.height).isActive = true
    }

    private func updateNote() {
        algorithmMenu.toolTip = algorithm.isLegacy
            ? "Legacy checksum; unsuitable for security."
            : "Checksum algorithm"
    }

    @objc private func closeWindow() { window.close() }

    @objc private func showDetails(_ sender: NSButton) {
        if details.isShown { details.close() }
        else { details.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY) }
    }

    @objc private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK { self?.start(panel.urls) }
        }
    }

    @objc private func changeAlgorithm() {
        UserDefaults.standard.set(algorithm.rawValue, forKey: "algorithm")
        updateNote()
        if !selectedFiles.isEmpty { start(selectedFiles) }
    }

    private func start(_ files: [URL]) {
        guard !files.isEmpty else { return }
        worker?.cancel()
        selectedFiles = files
        resetCopyFeedback()
        details.close()
        preview.font = .systemFont(ofSize: 11)
        preview.textColor = .secondaryLabelColor
        detailsTitle.stringValue = files.count == 1 ? "Checksum" : "Checksums"
        detailsSubtitle.stringValue = "\(algorithm.rawValue) · \(files.count) \(files.count == 1 ? "file" : "files")"
        moreButton.isEnabled = false
        moreButton.isHidden = true
        runID = UUID()
        let id = runID
        let mode = algorithm
        filename.stringValue = files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"
        filename.toolTip = files.map(\.path).joined(separator: "\n")
        result.string = "Calculating…"
        preview.stringValue = "Calculating \(mode.rawValue)…"
        preview.toolTip = nil
        copyValue = ""
        copyButton.isEnabled = false
        copyButton.toolTip = files.count == 1 ? "Copy checksum" : "Copy checksums"
        copyButton.isHidden = true
        cancelButton.isHidden = false
        cancelButton.isEnabled = true
        progress.doubleValue = 0
        progress.isHidden = false

        worker = Task.detached { [weak self] in
            guard let self else { return }
            var lines: [String] = []
            var display: [String] = []
            var errors = 0
            for (index, file) in files.enumerated() {
                if Task.isCancelled { return }
                let access = file.startAccessingSecurityScopedResource()
                do {
                    let digest = try Checksum.hash(file: file, algorithm: mode) { fraction in
                        Task { @MainActor [weak self] in
                            guard let self, self.runID == id, self.cancelButton.isEnabled else { return }
                            self.progress.doubleValue = (Double(index) + fraction) / Double(files.count)
                            let percent = Int(self.progress.doubleValue * 100)
                            self.preview.stringValue = files.count == 1
                                ? "Calculating… \(percent)%"
                                : "\(percent)% · \(index + 1) of \(files.count) files"
                        }
                    }
                    lines.append(files.count == 1 ? digest : "\(digest)  \(file.lastPathComponent)")
                    display.append(files.count == 1 ? digest : "\(file.lastPathComponent)\n\(digest)")
                } catch is CancellationError {
                    if access { file.stopAccessingSecurityScopedResource() }
                    return
                } catch {
                    errors += 1
                    display.append("\(file.lastPathComponent)\n\(error.localizedDescription)")
                }
                if access { file.stopAccessingSecurityScopedResource() }
            }
            let clipboard = lines.joined(separator: "\n")
            let output = display.joined(separator: "\n\n")
            let errorCount = errors
            await MainActor.run { [weak self] in
                guard let self, self.runID == id else { return }
                self.result.string = output
                self.preview.stringValue = errorCount == 0
                    ? (files.count == 1 ? clipboard : "\(files.count) checksums ready")
                    : "\(errorCount) \(errorCount == 1 ? "error" : "errors") · click ⌄ for details"
                self.preview.font = errorCount == 0 && files.count == 1
                    ? .monospacedSystemFont(ofSize: 11, weight: .regular)
                    : .systemFont(ofSize: 11)
                self.preview.textColor = errorCount > 0 ? .systemOrange : .secondaryLabelColor
                self.preview.toolTip = output
                self.copyValue = clipboard
                self.copyButton.isHidden = clipboard.isEmpty
                self.moreButton.isHidden = false
                self.moreButton.isEnabled = true
                self.cancelButton.isHidden = true
                self.copyButton.isEnabled = !clipboard.isEmpty
                self.cancelButton.isEnabled = false
                self.progress.isHidden = true
                self.worker = nil
            }
        }
    }

    @objc private func cancelHash() {
        worker?.cancel()
        worker = nil
        runID = UUID()
        cancelButton.isEnabled = false
        progress.isHidden = true
        preview.stringValue = "Cancelled · choose or drop files to retry"
        result.string = "Calculation cancelled."
        copyButton.isHidden = true
        moreButton.isHidden = true
        moreButton.isEnabled = false
        cancelButton.isHidden = true
    }

    private func resetCopyFeedback() {
        copyFeedback?.cancel()
        copyFeedback = nil
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy checksum")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        copyButton.contentTintColor = .labelColor
        copyButton.setAccessibilityLabel(selectedFiles.count > 1 ? "Copy checksums" : "Copy checksum")
    }

    @objc private func copySelectionOrChecksum(_ sender: Any?) {
        let activeWindow = NSApp.keyWindow
        // File panels and other native windows retain their normal Copy behavior.
        if window.attachedSheet != nil ||
            (activeWindow !== window && activeWindow !== details.contentViewController?.view.window) {
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: sender)
            return
        }
        if let editor = activeWindow?.firstResponder as? NSTextView, editor.selectedRange().length > 0 {
            editor.copy(nil)
        } else {
            copyChecksum()
        }
    }

    @objc private func copyChecksum() {
        guard !copyValue.isEmpty else { return }
        resetCopyFeedback()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyValue, forType: .string)
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        copyButton.contentTintColor = .controlAccentColor
        copyButton.setAccessibilityLabel("Copied")
        NSAccessibility.post(element: copyButton, notification: .announcementRequested, userInfo: [
            .announcement: "Checksum copied", .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
        copyFeedback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.resetCopyFeedback()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        worker?.cancel()
        copyFeedback?.cancel()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
