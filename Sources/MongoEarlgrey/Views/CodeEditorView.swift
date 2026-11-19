import SwiftUI
import AppKit

public struct MongoCodeEditor: NSViewRepresentable {
    @Binding public var text: String
    public var isSingleLineQueryBar: Bool
    public var isDocumentEditor: Bool
    public var fontSize: CGFloat
    public var externalRevision: Int
    public var searchTerm: String
    public var caseSensitive: Bool
    public var currentMatchIndex: Int // 1-based index to scroll to
    public var jumpTrigger: Int       // increment to trigger scroll/selection jump
    public var focusEditorTrigger: Int
    public var onCommit: (() -> Void)?
    public var onToggleFind: (() -> Void)?
    public var onFindNext: (() -> Void)?
    public var onFindPrevious: (() -> Void)?
    public var onDirtyChange: (() -> Void)?

    public init(
        text: Binding<String>,
        isSingleLineQueryBar: Bool = false,
        isDocumentEditor: Bool = false,
        fontSize: CGFloat = 13,
        externalRevision: Int = 0,
        searchTerm: String = "",
        caseSensitive: Bool = false,
        currentMatchIndex: Int = 0,
        jumpTrigger: Int = 0,
        focusEditorTrigger: Int = 0,
        onCommit: (() -> Void)? = nil,
        onToggleFind: (() -> Void)? = nil,
        onFindNext: (() -> Void)? = nil,
        onFindPrevious: (() -> Void)? = nil,
        onDirtyChange: (() -> Void)? = nil
    ) {
        self._text = text
        self.isSingleLineQueryBar = isSingleLineQueryBar
        self.isDocumentEditor = isDocumentEditor
        self.fontSize = fontSize
        self.externalRevision = externalRevision
        self.searchTerm = searchTerm
        self.caseSensitive = caseSensitive
        self.currentMatchIndex = currentMatchIndex
        self.jumpTrigger = jumpTrigger
        self.focusEditorTrigger = focusEditorTrigger
        self.onCommit = onCommit
        self.onToggleFind = onToggleFind
        self.onFindNext = onFindNext
        self.onFindPrevious = onFindPrevious
        self.onDirtyChange = onDirtyChange
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = !isSingleLineQueryBar
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = CommandAwareTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false

        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.font = baseFont
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.typingAttributes = [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor
        ]

        // Only lay out lines visible in the viewport so large documents remain responsive
        textView.layoutManager?.allowsNonContiguousLayout = true

        // Disable macOS smart substitutions that corrupt JSON/JS code
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false

        textView.textContainerInset = isSingleLineQueryBar
            ? NSSize(width: 4, height: 6)
            : NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        textView.isSingleLineQueryBar = isSingleLineQueryBar
        textView.isDocumentEditor = isDocumentEditor
        wireCallbacks(on: textView, context: context)

        textView.string = text
        context.coordinator.lastTextLength = (text as NSString).length
        context.coordinator.lastExternalRevision = externalRevision
        context.coordinator.lastSearchTerm = searchTerm
        context.coordinator.lastCaseSensitive = caseSensitive
        context.coordinator.lastMatchIndex = currentMatchIndex
        context.coordinator.lastFocusEditorTrigger = focusEditorTrigger
        context.coordinator.applyHighlighting(to: textView, in: nil)
        context.coordinator.applySearchHighlighting(to: textView)

        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? CommandAwareTextView else { return }
        if scrollView.hasVerticalScroller != !isSingleLineQueryBar {
            scrollView.hasVerticalScroller = !isSingleLineQueryBar
        }
        textView.isSingleLineQueryBar = isSingleLineQueryBar
        textView.isDocumentEditor = isDocumentEditor
        wireCallbacks(on: textView, context: context)

        // For large document editors, skip O(N) full-string equality checks on unrelated SwiftUI updates;
        // external replacements always bump `externalRevision`.
        let revisionChanged = (externalRevision != context.coordinator.lastExternalRevision)
        let shouldReloadText: Bool
        if isDocumentEditor {
            shouldReloadText = revisionChanged
        } else {
            shouldReloadText = revisionChanged || (textView.string != text)
        }

        if shouldReloadText {
            context.coordinator.lastExternalRevision = externalRevision
            context.coordinator.invalidateSearchCache()
            let selectedRanges = textView.selectedRanges
            textView.string = text
            context.coordinator.lastTextLength = (text as NSString).length
            context.coordinator.applyHighlighting(to: textView, in: nil)
            context.coordinator.applySearchHighlighting(to: textView)
            context.coordinator.lastSearchTerm = searchTerm
            context.coordinator.lastCaseSensitive = caseSensitive
            context.coordinator.lastMatchIndex = currentMatchIndex

            let maxLen = (text as NSString).length
            let validRanges = selectedRanges.compactMap { val -> NSValue? in
                let r = val.rangeValue
                guard r.location <= maxLen else { return nil }
                return NSValue(range: NSRange(location: r.location, length: min(r.length, maxLen - r.location)))
            }
            if !validRanges.isEmpty {
                textView.selectedRanges = validRanges
            }
        } else if searchTerm != context.coordinator.lastSearchTerm
                    || caseSensitive != context.coordinator.lastCaseSensitive
                    || currentMatchIndex != context.coordinator.lastMatchIndex {
            if searchTerm != context.coordinator.lastSearchTerm || caseSensitive != context.coordinator.lastCaseSensitive {
                context.coordinator.invalidateSearchCache()
            }
            context.coordinator.lastSearchTerm = searchTerm
            context.coordinator.lastCaseSensitive = caseSensitive
            context.coordinator.lastMatchIndex = currentMatchIndex
            context.coordinator.applySearchHighlighting(to: textView)
        }

        if jumpTrigger != context.coordinator.lastJumpTrigger {
            context.coordinator.lastJumpTrigger = jumpTrigger
            context.coordinator.jumpToMatch(index: currentMatchIndex, in: textView)
        }

        if focusEditorTrigger != context.coordinator.lastFocusEditorTrigger {
            context.coordinator.lastFocusEditorTrigger = focusEditorTrigger
            DispatchQueue.main.async { [weak textView] in
                guard let textView = textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    private func wireCallbacks(on textView: CommandAwareTextView, context: Context) {
        textView.onExecuteShortcut = {
            context.coordinator.parent.onCommit?()
        }
        textView.onFindShortcut = {
            context.coordinator.parent.onToggleFind?()
        }
        textView.onFindNextShortcut = {
            context.coordinator.parent.onFindNext?()
        }
        textView.onFindPreviousShortcut = {
            context.coordinator.parent.onFindPrevious?()
        }
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MongoCodeEditor
        var lastJumpTrigger: Int = 0
        var lastFocusEditorTrigger: Int = 0
        var lastExternalRevision: Int = 0
        var lastSearchTerm: String = ""
        var lastCaseSensitive: Bool = false
        var lastMatchIndex: Int = 0
        var lastTextLength: Int = 0
        private var isUpdating = false
        private var highlightGeneration: Int = 0

        // Cached Find match ranges to avoid rescanning large documents
        private var cachedMatches: [NSRange] = []
        private var cachedMatchQuery: String = ""
        private var cachedMatchCaseSensitive: Bool = false
        private var cachedMatchValid: Bool = false

        // Pre-compiled static regexes for zero-allocation syntax highlighting
        private static let numberBoolRegex = try! NSRegularExpression(
            pattern: #"\b(true|false|null|undefined|-?\d+(\.\d+)?)\b"#
        )
        private static let mongoKeywordsRegex = try! NSRegularExpression(
            pattern: #"\b(db|getCollection|find|findOne|sort|limit|skip|projection|project|count|countDocuments|aggregate|ObjectId|ISODate|UUID|NumberLong|Long|NumberInt|Int32|Double|NumberDecimal|Decimal128|BinData|Timestamp|MinKey|MaxKey|new|RegExp)\b"#
        )
        private static let mongoOperatorsRegex = try! NSRegularExpression(
            pattern: #"\$[a-zA-Z0-9_]+"#
        )
        private static let stringLiteralRegex = try! NSRegularExpression(
            pattern: #""([^"\\]|\\.)*"|'([^'\\]|\\.)*'"#
        )
        private static let objectKeyRegex = try! NSRegularExpression(
            pattern: #""([^"\\]|\\.)*"\s*(?=:)"#
        )

        init(_ parent: MongoCodeEditor) {
            self.parent = parent
            self.lastJumpTrigger = parent.jumpTrigger
            self.lastFocusEditorTrigger = parent.focusEditorTrigger
            self.lastExternalRevision = parent.externalRevision
            self.lastSearchTerm = parent.searchTerm
            self.lastCaseSensitive = parent.caseSensitive
            self.lastMatchIndex = parent.currentMatchIndex
        }

        func invalidateSearchCache() {
            cachedMatchValid = false
            cachedMatches.removeAll(keepingCapacity: true)
        }

        public func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            let currentString = textView.string
            parent.text = currentString
            parent.onDirtyChange?()
            invalidateSearchCache()

            let nsString = currentString as NSString
            let newLength = nsString.length
            let sel = textView.selectedRange()
            let delta = max(0, newLength - lastTextLength)
            lastTextLength = newLength

            if newLength > 0 {
                // Only re-highlight the modified line/paragraph range during keystrokes for O(line) speed
                let startLoc = max(0, min(sel.location - delta, newLength - 1))
                let endLoc = min(newLength, NSMaxRange(sel))
                let affectedRange = NSRange(location: startLoc, length: max(0, endLoc - startLoc))
                let lineRange = nsString.paragraphRange(for: affectedRange)
                applyHighlighting(to: textView, in: lineRange)
            }
            isUpdating = false
        }

        private func ensureMatchCache(in string: String) -> [NSRange] {
            if cachedMatchValid && cachedMatchQuery == parent.searchTerm && cachedMatchCaseSensitive == parent.caseSensitive {
                return cachedMatches
            }
            cachedMatches.removeAll(keepingCapacity: true)
            cachedMatchQuery = parent.searchTerm
            cachedMatchCaseSensitive = parent.caseSensitive
            cachedMatchValid = true

            guard !parent.searchTerm.isEmpty else { return cachedMatches }
            let nsString = string as NSString
            let options: NSString.CompareOptions = parent.caseSensitive ? [] : [.caseInsensitive]
            var searchRange = NSRange(location: 0, length: nsString.length)
            while searchRange.location < nsString.length {
                searchRange.length = nsString.length - searchRange.location
                let foundRange = nsString.range(of: parent.searchTerm, options: options, range: searchRange)
                if foundRange.location != NSNotFound {
                    cachedMatches.append(foundRange)
                    searchRange.location = foundRange.location + max(1, foundRange.length)
                } else {
                    break
                }
            }
            return cachedMatches
        }

        func jumpToMatch(index: Int, in textView: NSTextView) {
            guard !parent.searchTerm.isEmpty, index > 0 else { return }
            let matches = ensureMatchCache(in: textView.string)
            guard index <= matches.count else { return }
            let foundRange = matches[index - 1]
            textView.setSelectedRange(foundRange)
            textView.scrollRangeToVisible(foundRange)
            textView.showFindIndicator(for: foundRange)
        }

        func applyHighlighting(to textView: NSTextView, in targetRange: NSRange?) {
            guard let storage = textView.textStorage else { return }
            let fullString = textView.string
            let nsString = fullString as NSString
            let totalLength = nsString.length
            guard totalLength > 0 else { return }

            let chunkSize = 150_000

            if let targetRange = targetRange {
                let activeRange = NSIntersectionRange(targetRange, NSRange(location: 0, length: totalLength))
                guard activeRange.length > 0 else { return }
                highlightRange(activeRange, in: fullString, storage: storage)
                return
            }

            highlightGeneration &+= 1
            let gen = highlightGeneration

            if totalLength <= chunkSize {
                highlightRange(NSRange(location: 0, length: totalLength), in: fullString, storage: storage)
                return
            }

            // Highlight the first chunk immediately, then progressively color remaining chunks without blocking UI
            let firstEnd = alignedChunkEnd(from: 0, chunkSize: chunkSize, in: nsString)
            highlightRange(NSRange(location: 0, length: firstEnd), in: fullString, storage: storage)

            if firstEnd < totalLength {
                scheduleRemainingChunks(from: firstEnd, chunkSize: chunkSize, generation: gen, in: textView)
            }
        }

        private func alignedChunkEnd(from start: Int, chunkSize: Int, in nsString: NSString) -> Int {
            let rawEnd = min(nsString.length, start + chunkSize)
            if rawEnd >= nsString.length { return nsString.length }
            let paraRange = nsString.paragraphRange(for: NSRange(location: rawEnd, length: 0))
            return min(nsString.length, NSMaxRange(paraRange))
        }

        private func scheduleRemainingChunks(from start: Int, chunkSize: Int, generation: Int, in textView: NSTextView) {
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self = self,
                      let textView = textView,
                      generation == self.highlightGeneration,
                      let storage = textView.textStorage else { return }

                let fullString = textView.string
                let nsString = fullString as NSString
                let totalLength = nsString.length
                guard start < totalLength else { return }

                let end = self.alignedChunkEnd(from: start, chunkSize: chunkSize, in: nsString)
                let range = NSRange(location: start, length: end - start)
                if range.length > 0 {
                    self.highlightRange(range, in: fullString, storage: storage)
                }

                if end < totalLength {
                    self.scheduleRemainingChunks(from: end, chunkSize: chunkSize, generation: generation, in: textView)
                }
            }
        }

        private func highlightRange(_ activeRange: NSRange, in fullString: String, storage: NSTextStorage) {
            let baseFont = NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
            let boldFont = NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .medium)

            storage.beginEditing()
            // Preserve any active search background highlight attributes by updating only font and foregroundColor
            storage.addAttributes([
                .font: baseFont,
                .foregroundColor: NSColor.labelColor
            ], range: activeRange)

            highlightRegex(Self.numberBoolRegex, color: NSColor.systemBlue, font: baseFont, in: fullString, range: activeRange, storage: storage)
            highlightRegex(Self.mongoKeywordsRegex, color: NSColor.systemPurple, font: boldFont, in: fullString, range: activeRange, storage: storage)
            highlightRegex(Self.mongoOperatorsRegex, color: NSColor.systemOrange, font: boldFont, in: fullString, range: activeRange, storage: storage)
            highlightRegex(Self.stringLiteralRegex, color: NSColor.systemGreen, font: baseFont, in: fullString, range: activeRange, storage: storage)
            highlightRegex(Self.objectKeyRegex, color: NSColor.systemTeal, font: boldFont, in: fullString, range: activeRange, storage: storage)

            storage.endEditing()
        }

        func applySearchHighlighting(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let nsString = textView.string as NSString
            let fullRange = NSRange(location: 0, length: nsString.length)
            guard fullRange.length > 0 else { return }

            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: fullRange)

            if !parent.searchTerm.isEmpty {
                let matches = ensureMatchCache(in: textView.string)
                let highlightCap = 2_000
                let passiveColor = NSColor.systemYellow.withAlphaComponent(0.38)
                for matchRange in matches.prefix(highlightCap) {
                    storage.addAttribute(.backgroundColor, value: passiveColor, range: matchRange)
                }

                // Always highlight the active match even when match count exceeds the passive highlight cap
                if parent.currentMatchIndex > 0 && parent.currentMatchIndex <= matches.count {
                    let activeRange = matches[parent.currentMatchIndex - 1]
                    storage.addAttribute(
                        .backgroundColor,
                        value: NSColor.systemOrange.withAlphaComponent(0.70),
                        range: activeRange
                    )
                }
            }
            storage.endEditing()
        }

        private func highlightRegex(
            _ regex: NSRegularExpression,
            color: NSColor,
            font: NSFont,
            in text: String,
            range: NSRange,
            storage: NSTextStorage
        ) {
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let matchRange = match?.range else { return }
                storage.addAttributes([
                    .foregroundColor: color,
                    .font: font
                ], range: matchRange)
            }
        }
    }
}

final class CommandAwareTextView: NSTextView {
    var isSingleLineQueryBar: Bool = false
    var isDocumentEditor: Bool = false
    var onExecuteShortcut: (() -> Void)?
    var onFindShortcut: (() -> Void)?
    var onFindNextShortcut: (() -> Void)?
    var onFindPreviousShortcut: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        super.mouseDown(with: event)
    }

    override func performFindPanelAction(_ sender: Any?) {
        if let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSControl)?.tag,
           let action = NSFindPanelAction(rawValue: UInt(tag)) {
            switch action {
            case .showFindPanel:
                if let onFindShortcut = onFindShortcut {
                    onFindShortcut()
                    return
                }
            case .next:
                if let onFindNextShortcut = onFindNextShortcut {
                    onFindNextShortcut()
                    return
                }
            case .previous:
                if let onFindPreviousShortcut = onFindPreviousShortcut {
                    onFindPreviousShortcut()
                    return
                }
            default:
                break
            }
        }
        super.performFindPanelAction(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                if flags == [.command, .shift] {
                    switch chars {
                    case "z":
                        undoManager?.redo()
                        return true
                    case "g":
                        if onFindPreviousShortcut != nil {
                            onFindPreviousShortcut?()
                            return true
                        }
                    default:
                        break
                    }
                }
                if flags == .command {
                    switch chars {
                    case "v":
                        paste(nil)
                        return true
                    case "c":
                        copy(nil)
                        return true
                    case "x":
                        cut(nil)
                        return true
                    case "a":
                        selectAll(nil)
                        return true
                    case "z":
                        undoManager?.undo()
                        return true
                    case "f":
                        if onFindShortcut != nil {
                            onFindShortcut?()
                            return true
                        }
                    case "g":
                        if onFindNextShortcut != nil {
                            onFindNextShortcut?()
                            return true
                        }
                    case "s":
                        if isDocumentEditor, onExecuteShortcut != nil {
                            onExecuteShortcut?()
                            return true
                        }
                    default:
                        break
                    }
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = (event.keyCode == 36 || event.keyCode == 76)
        let isTab = (event.keyCode == 48)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd+Return always triggers commit/run
        if isReturn && flags.contains(.command) {
            onExecuteShortcut?()
            return
        }

        // In single-line query bar mode, plain Return also runs the query (Shift+Return inserts newline)
        if isSingleLineQueryBar && isReturn && !flags.contains(.shift) {
            onExecuteShortcut?()
            return
        }

        // In multi-line document editor, Tab inserts 2 soft spaces and Return preserves indentation
        if !isSingleLineQueryBar && flags.isSubset(of: [.shift]) {
            if isTab && !flags.contains(.shift) {
                insertText("  ", replacementRange: selectedRange())
                return
            }
            if isReturn {
                insertNewlineWithAutoIndent()
                return
            }
        }

        super.keyDown(with: event)
    }

    private func insertNewlineWithAutoIndent() {
        let nsStr = string as NSString
        let sel = selectedRange()
        let lineRange = nsStr.lineRange(for: NSRange(location: min(sel.location, nsStr.length), length: 0))
        let lineText = nsStr.substring(with: lineRange)

        var leadingSpaces = ""
        for ch in lineText {
            if ch == " " || ch == "\t" {
                leadingSpaces.append(ch)
            } else {
                break
            }
        }

        // Prefix text up to cursor on the current line to decide whether opening brace/bracket increases indent
        let prefixEnd = max(lineRange.location, min(sel.location, nsStr.length))
        let prefixRange = NSRange(location: lineRange.location, length: prefixEnd - lineRange.location)
        let prefixTrimmed = nsStr.substring(with: prefixRange).trimmingCharacters(in: .whitespacesAndNewlines)
        if prefixTrimmed.hasSuffix("{") || prefixTrimmed.hasSuffix("[") {
            leadingSpaces += "  "
        }

        insertText("\n" + leadingSpaces, replacementRange: sel)
    }
}
