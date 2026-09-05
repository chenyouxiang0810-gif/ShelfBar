import AppKit

@MainActor
final class SearchInputHost: NSObject, NSTextViewDelegate {
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private final class IMESearchTextView: NSTextView {
        var onInputChange: ((String) -> Void)?
        var doCommandHandler: ((Selector) -> Bool)?

        override func insertText(_ insertString: Any, replacementRange: NSRange) {
            super.insertText(insertString, replacementRange: replacementRange)
            onInputChange?(string)
        }

        override func setMarkedText(
            _ string: Any,
            selectedRange: NSRange,
            replacementRange: NSRange
        ) {
            super.setMarkedText(
                string,
                selectedRange: selectedRange,
                replacementRange: replacementRange
            )
            onInputChange?(self.string)
        }

        override func unmarkText() {
            super.unmarkText()
            onInputChange?(string)
        }

        override func doCommand(by selector: Selector) {
            if doCommandHandler?(selector) == true {
                return
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                window?.orderOut(nil)
                return
            }
            super.doCommand(by: selector)
        }
    }

    private var panel: NSPanel?
    private var searchView: IMESearchTextView?
    var onChange: ((String) -> Void)?
    var onCommand: ((Selector) -> Bool)?

    func begin(query: String) {
        if panel != nil {
            update(query: query)
            focus()
            return
        }

        let textView = IMESearchTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textView.string = query
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.drawsBackground = false
        textView.insertionPointColor = .clear
        textView.textColor = .clear
        textView.selectedTextAttributes = [.foregroundColor: NSColor.clear]
        textView.markedTextAttributes = [.foregroundColor: NSColor.clear]
        textView.onInputChange = { [weak self] value in
            self?.onChange?(value)
        }
        textView.doCommandHandler = { [weak self] selector in
            self?.onCommand?(selector) ?? false
        }

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let panel = KeyPanel(
            contentRect: NSRect(x: screenFrame.minX + 1, y: screenFrame.minY + 1, width: 2, height: 2),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = textView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 0.02
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.panel = panel
        self.searchView = textView

        panel.orderFrontRegardless()
        focus()
    }

    func update(query: String) {
        guard searchView?.string != query else { return }
        searchView?.string = query
    }

    func end() {
        panel?.orderOut(nil)
        panel = nil
        searchView = nil
    }

    func textDidChange(_ notification: Notification) {
        guard let view = notification.object as? NSTextView else { return }
        onChange?(view.string)
    }

    private func focus() {
        guard let panel, let searchView else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchView)
        searchView.setSelectedRange(NSRange(location: searchView.string.count, length: 0))
        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.panel,
                  let searchView = self?.searchView
            else { return }
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(searchView)
        }
    }
}
