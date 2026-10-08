import AppKit
import ChecksumCore

@MainActor
final class FloatingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class SlimProgressView: NSView {
    private let fill = CALayer()
    var doubleValue: Double = 0 { didSet { needsLayout = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        fill.backgroundColor = NSColor.controlAccentColor.cgColor
        layer?.addSublayer(fill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        updateBorder()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { true }

    private func updateBorder() {
        layer?.borderColor = (highlighted ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.backgroundColor = (highlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.12)
            : NSColor.controlBackgroundColor).cgColor
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
    private let preview = NSTextField(labelWithString: "or click + to choose")
    private let details = NSPopover()
    private let result = NSTextView()
    private let progress = SlimProgressView()
    private let copyButton = NSButton(title: "Copy checksum", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
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
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
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

        let choose = iconButton("plus", label: "Choose files", action: #selector(chooseFiles))
        filename.stringValue = "Drop files here"
        filename.font = .systemFont(ofSize: 12, weight: .medium)
        filename.lineBreakMode = .byTruncatingMiddle
        preview.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        preview.textColor = .secondaryLabelColor
        preview.lineBreakMode = .byTruncatingMiddle
        preview.isSelectable = true
        let text = NSStackView(views: [filename, preview])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        filename.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        filename.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
        preview.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true

        algorithmMenu.addItems(withTitles: Algorithm.allCases.map(\.rawValue))
        algorithmMenu.selectItem(withTitle: UserDefaults.standard.string(forKey: "algorithm") ?? Algorithm.sha256.rawValue)
        algorithmMenu.controlSize = .small
        algorithmMenu.font = .systemFont(ofSize: 11)
        algorithmMenu.target = self
        algorithmMenu.action = #selector(changeAlgorithm)
        algorithmMenu.widthAnchor.constraint(equalToConstant: 91).isActive = true
        updateNote()

        configureIcon(copyButton, symbol: "doc.on.doc", label: "Copy checksum", action: #selector(copyChecksum))
        copyButton.isEnabled = false
        configureIcon(cancelButton, symbol: "stop.fill", label: "Cancel hashing", action: #selector(cancelHash))
        cancelButton.isEnabled = false
        cancelButton.isHidden = true
        let more = iconButton("chevron.down", label: "Show full checksums", action: #selector(showDetails(_:)))
        let close = iconButton("xmark", label: "Close window", action: #selector(closeWindow))

        let row = NSStackView(views: [choose, text, algorithmMenu, copyButton, cancelButton, more, close])
        row.spacing = 9
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(row)
        progress.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(progress)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -2),
            text.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            progress.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            progress.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            progress.heightAnchor.constraint(equalToConstant: 3)
        ])

        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 180))
        let scroll = NSScrollView(frame: NSRect(x: 12, y: 12, width: 416, height: 156))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        result.isEditable = false
        result.isSelectable = true
        result.drawsBackground = false
        result.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
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
        details.contentSize = NSSize(width: 440, height: 180)
    }

    private func configureIcon(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.title = ""
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func iconButton(_ symbol: String, label: String, action: Selector) -> NSButton {
        let button = NSButton()
        configureIcon(button, symbol: symbol, label: label, action: action)
        return button
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
                            self.preview.stringValue = "\(Int(self.progress.doubleValue * 100))% · \(file.lastPathComponent)"
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
                self.preview.toolTip = output
                self.copyValue = clipboard
                self.copyButton.isHidden = false
                self.cancelButton.isHidden = true
                self.copyButton.isEnabled = !clipboard.isEmpty
                self.cancelButton.isEnabled = false
                self.progress.doubleValue = 1
                self.worker = nil
            }
        }
    }

    @objc private func cancelHash() {
        worker?.cancel()
        worker = nil
        runID = UUID()
        cancelButton.isEnabled = false
        preview.stringValue = "Cancelled · drop a file to try again"
        result.string = "Calculation cancelled."
        copyButton.isHidden = false
        cancelButton.isHidden = true
    }

    @objc private func copyChecksum() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyValue, forType: .string)
        preview.stringValue = "Copied to clipboard"
    }

    func applicationWillTerminate(_ notification: Notification) { worker?.cancel() }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
