import SwiftUI
import AppKit

/// A rock-solid AppKit NSTextField wrapper that guarantees click-to-focus, visible borders,
/// full Cmd+V / Cmd+C / Cmd+X / Cmd+A / Cmd+Z / Shift+Cmd+Z keyboard shortcut support,
/// and deterministic focus/Shift+Return/Escape handling on macOS.
public struct NativeTextField: NSViewRepresentable {
    public let placeholder: String
    @Binding public var text: String
    public var isMonospaced: Bool
    public var isSecure: Bool
    public var focusTrigger: Int
    public var onTextChange: ((String) -> Void)?
    public var onCommit: (() -> Void)?
    public var onPreviousCommit: (() -> Void)?
    public var onCancel: (() -> Void)?

    public init(
        _ placeholder: String,
        text: Binding<String>,
        isMonospaced: Bool = false,
        isSecure: Bool = false,
        focusTrigger: Int = 0,
        onTextChange: ((String) -> Void)? = nil,
        onCommit: (() -> Void)? = nil,
        onPreviousCommit: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.isMonospaced = isMonospaced
        self.isSecure = isSecure
        self.focusTrigger = focusTrigger
        self.onTextChange = onTextChange
        self.onCommit = onCommit
        self.onPreviousCommit = onPreviousCommit
        self.onCancel = onCancel
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField
        if isSecure {
            field = ShortcutAwareSecureTextField()
        } else {
            field = ShortcutAwareTextField()
        }

        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.stringValue = text
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.backgroundColor = NSColor.textBackgroundColor
        field.textColor = NSColor.labelColor
        field.focusRingType = .exterior
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false

        if isMonospaced {
            field.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        } else {
            field.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        }

        if focusTrigger > 0 {
            context.coordinator.lastFocusTrigger = focusTrigger
            requestFocusAndSelectAll(on: field, retryIfWindowMissing: true)
        }

        return field
    }

    public func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        if focusTrigger != context.coordinator.lastFocusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            requestFocusAndSelectAll(on: nsView, retryIfWindowMissing: true)
        }
    }

    private func requestFocusAndSelectAll(on field: NSTextField, retryIfWindowMissing: Bool) {
        DispatchQueue.main.async { [weak field] in
            guard let field = field else { return }
            if let win = field.window {
                win.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            } else if retryIfWindowMissing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak field] in
                    guard let field = field, let win = field.window else { return }
                    win.makeFirstResponder(field)
                    field.currentEditor()?.selectAll(nil)
                }
            }
        }
    }

    public final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeTextField
        var lastFocusTrigger: Int = 0

        init(_ parent: NativeTextField) {
            self.parent = parent
            self.lastFocusTrigger = parent.focusTrigger
        }

        public func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let newValue = field.stringValue
            if parent.text != newValue {
                parent.text = newValue
                parent.onTextChange?(newValue)
            }
        }

        public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let shiftHeld = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                if shiftHeld, let prev = parent.onPreviousCommit {
                    prev()
                } else {
                    parent.onCommit?()
                }
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)),
               let onCancel = parent.onCancel {
                onCancel()
                return true
            }
            return false
        }
    }
}

final class ShortcutAwareTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                if flags == [.command, .shift], chars == "z" {
                    if NSApp.sendAction(Selector(("redo:")), to: nil, from: self) { return true }
                }
                if flags == .command {
                    switch chars {
                    case "v":
                        if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
                    case "c":
                        if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
                    case "x":
                        if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
                    case "a":
                        if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
                    case "z":
                        if NSApp.sendAction(Selector(("undo:")), to: nil, from: self) { return true }
                    default:
                        break
                    }
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class ShortcutAwareSecureTextField: NSSecureTextField {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                case "v":
                    if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
                case "c":
                    if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
                case "x":
                    if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
                case "a":
                    if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
                default:
                    break
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
