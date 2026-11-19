import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct CollectionTabView: View {
    @ObservedObject public var tab: CollectionTabState
    @ObservedObject public var workspace: WorkspaceViewModel

    public init(tab: CollectionTabState, workspace: WorkspaceViewModel) {
        self.tab = tab
        self.workspace = workspace
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Query Toolbar
            queryToolbar

            if tab.isLoading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .frame(height: 2)
            } else {
                Divider()
            }

            // Optional Query Error Banner
            if let err = tab.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        tab.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.12))

                Divider()
            }

            // 2. Main Split Content: Spreadsheet Table + Document Editor
            HSplitView {
                SpreadsheetTableView(tab: tab, workspace: workspace)
                    .frame(minWidth: 180, maxWidth: .infinity, maxHeight: .infinity)

                if tab.isInspectorVisible {
                    DocumentInspectorPane(tab: tab, workspace: workspace)
                        .frame(minWidth: 320, idealWidth: 860, maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            // 3. Bottom Status & Pagination Bar
            bottomStatusBar
        }
    }

    // MARK: - Top Query Bar
    private var queryToolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Breadcrumb badge
                HStack(spacing: 5) {
                    Image(systemName: "cylinder.split.1x2.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(tab.database)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("/")
                        .foregroundStyle(.quaternary)
                    Text(tab.collection)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                // Export current results as JSON
                if !tab.documents.isEmpty {
                    Button {
                        exportDocumentsToJSON()
                    } label: {
                        Label("Export JSON", systemImage: "square.and.arrow.up")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Export displayed documents to a JSON file")
                }

                // Expand / Collapse Nested Object Columns
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if tab.expandedColumnPaths.isEmpty {
                            tab.expandAllTopLevelObjects()
                        } else {
                            tab.collapseAllColumns()
                        }
                    }
                } label: {
                    Label(
                        tab.expandedColumnPaths.isEmpty ? "Expand Nested Fields" : "Collapse Nested Fields",
                        systemImage: tab.expandedColumnPaths.isEmpty ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
                    )
                    .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Expand or collapse nested Object fields into table columns")

                // New Document Button
                Button {
                    if workspace.confirmDiscardUnsavedChangesIfNeeded(in: tab) {
                        tab.startNewDocument()
                    }
                } label: {
                    Label("New Document", systemImage: "plus")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Toggle Document Editor Drawer
                Button {
                    if tab.isInspectorVisible {
                        if workspace.confirmDiscardUnsavedChangesIfNeeded(in: tab) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                tab.hasUnsavedEditorChanges = false
                                tab.isInspectorVisible = false
                            }
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if let idx = tab.selectedRowIndex {
                                tab.selectRow(idx, openEditor: true)
                            } else if !tab.documents.isEmpty {
                                tab.selectRow(0, openEditor: true)
                            } else {
                                tab.isInspectorVisible = true
                            }
                        }
                    }
                } label: {
                    Label(
                        tab.isInspectorVisible ? "Hide Editor" : "View / Edit Doc",
                        systemImage: "sidebar.trailing"
                    )
                    .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Query Input Row
            HStack(alignment: .top, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.leading, 8)
                        .padding(.top, 9)

                    MongoCodeEditor(
                        text: $tab.queryText,
                        isSingleLineQueryBar: !tab.isQueryBarExpanded,
                        fontSize: 12.5,
                        onCommit: {
                            tab.pageSkip = 0
                            Task { await workspace.runQuery(for: tab) }
                        }
                    )
                    .frame(height: tab.isQueryBarExpanded ? 92 : 30)

                    HStack(spacing: 4) {
                        if !tab.queryHistory.isEmpty {
                            Menu {
                                Section("Recent Queries") {
                                    ForEach(Array(tab.queryHistory.enumerated()), id: \.offset) { _, histQuery in
                                        Button {
                                            tab.queryText = histQuery
                                            tab.pageSkip = 0
                                            Task { await workspace.runQuery(for: tab) }
                                        } label: {
                                            Text(histQuery)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 22, height: 22)
                            .help("Query History")
                        }

                        if tab.queryText != "db.getCollection(\"\(tab.collection)\").find({})" {
                            Button {
                                tab.queryText = "db.getCollection(\"\(tab.collection)\").find({})"
                                tab.pageSkip = 0
                                Task { await workspace.runQuery(for: tab) }
                            } label: {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reset to default query")
                        }

                        Button {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                tab.isQueryBarExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: tab.isQueryBarExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help(tab.isQueryBarExpanded ? "Collapse query bar" : "Expand multi-line query editor")
                    }
                    .padding(.trailing, 6)
                    .padding(.top, 4)
                }
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )

                Button {
                    tab.pageSkip = 0
                    Task {
                        await workspace.runQuery(for: tab)
                    }
                } label: {
                    HStack(spacing: 5) {
                        if tab.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                        }
                        Text("Run")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                }
                .buttonStyle(.borderedProminent)
                .help("Run Query (Return or ⌘Return)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Bottom Status Bar
    private var bottomStatusBar: some View {
        let isNextDisabled: Bool = {
            if let total = tab.totalCount {
                return (tab.pageSkip + tab.documents.count) >= total
            }
            return tab.documents.count < tab.pageLimit
        }()

        return HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tab.isLoading ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                Text(tab.statusText)
                    .font(.system(size: 11.5, weight: .medium))
            }

            if tab.executionTimeMs > 0 {
                Text(String(format: "• %.1f ms", tab.executionTimeMs))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if !tab.expandedColumnPaths.isEmpty {
                Text("• \(tab.expandedColumnPaths.count) nested \(tab.expandedColumnPaths.count == 1 ? "column" : "columns") expanded")
                    .font(.system(size: 11))
                    .foregroundStyle(.purple)
            }

            if let savedBanner = tab.lastSaveConfirmationText {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text(savedBanner)
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .foregroundStyle(.green)
                .clipShape(Capsule())
            }

            Spacer()

            Text("Double-click any row to view & edit document")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Divider()
                .frame(height: 14)

            // Pagination Controls
            HStack(spacing: 6) {
                Text("Limit:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: $tab.pageLimit) {
                    Text("25").tag(25)
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text("250").tag(250)
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 65)
                .onChange(of: tab.pageLimit) { _, _ in
                    tab.pageSkip = 0
                    Task { await workspace.runQuery(for: tab) }
                }

                Button {
                    tab.pageSkip = max(0, tab.pageSkip - tab.pageLimit)
                    Task { await workspace.runQuery(for: tab) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(tab.pageSkip == 0 || tab.isLoading)

                Text("Skip \(tab.pageSkip)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 52)

                Button {
                    tab.pageSkip += tab.pageLimit
                    Task { await workspace.runQuery(for: tab) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isNextDisabled || tab.isLoading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func exportDocumentsToJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(tab.database)_\(tab.collection).json"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let formattedDocs = tab.documents.map { BSONShellFormatter.format($0, indent: 2) }
        let payload = "[\n" + formattedDocs.joined(separator: ",\n") + "\n]\n"
        do {
            try payload.write(to: url, atomically: true, encoding: .utf8)
            tab.lastSaveConfirmationText = "Exported \(tab.documents.count) docs ✓"
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if tab.lastSaveConfirmationText == "Exported \(tab.documents.count) docs ✓" {
                    tab.lastSaveConfirmationText = nil
                }
            }
        } catch {
            tab.errorMessage = "Failed to export JSON: \(error.localizedDescription)"
        }
    }
}

@MainActor
private final class InspectorUIState: ObservableObject {
    @Published var copiedDocumentBriefly: Bool = false
    @Published var copiedIdBriefly: Bool = false
    var findDebounceWorkItem: DispatchWorkItem?
}

// MARK: - Document Viewer & Editor Inspector Pane
public struct DocumentInspectorPane: View {
    @ObservedObject public var tab: CollectionTabState
    @ObservedObject public var workspace: WorkspaceViewModel
    @StateObject private var inspectorUI = InspectorUIState()

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Inspector Header
            HStack(spacing: 8) {
                Image(systemName: tab.isCreatingNewDocument ? "doc.badge.plus" : "curlybraces.square.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tab.isCreatingNewDocument ? "New Document" : "Document Editor")
                            .font(.system(size: 12.5, weight: .semibold))

                        if tab.hasUnsavedEditorChanges {
                            Text("Modified")
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.18))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }

                    if let doc = tab.selectedDocument, let idVal = doc["_id"] {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(idVal.displayCellText, forType: .string)
                            inspectorUI.copiedIdBriefly = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                inspectorUI.copiedIdBriefly = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(inspectorUI.copiedIdBriefly ? "Copied _id ✓" : idVal.displayCellText)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(inspectorUI.copiedIdBriefly ? Color.green : Color.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Click to copy _id")
                    } else if tab.isCreatingNewDocument {
                        Text("Insert into \(tab.database).\(tab.collection)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    formatCurrentEditorJSON()
                } label: {
                    Text("Format")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Format BSON / Shell JSON")

                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        tab.openFindInEditor()
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut("f", modifiers: .command)
                .help("Find in Document (⌘F)")

                if !tab.isCreatingNewDocument, let doc = tab.selectedDocument {
                    Button {
                        if workspace.confirmDiscardUnsavedChangesIfNeeded(in: tab) {
                            tab.setExternalEditorText(BSONShellFormatter.format(doc))
                            tab.editorError = nil
                            tab.saveSuccessBanner = nil
                        }
                    } label: {
                        Text("Revert")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!tab.hasUnsavedEditorChanges)
                    .help("Discard unsaved edits")
                }

                Button {
                    if workspace.confirmDiscardUnsavedChangesIfNeeded(in: tab) {
                        tab.hasUnsavedEditorChanges = false
                        tab.isEditorFindVisible = false
                        tab.isInspectorVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close Document Editor")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if tab.selectedDocument != nil || tab.isCreatingNewDocument {
                // Find Search Bar in Document Editor
                if tab.isEditorFindVisible {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        NativeTextField(
                            "Find in document…",
                            text: $tab.editorFindText,
                            isMonospaced: true,
                            focusTrigger: tab.editorFindFocusTrigger,
                            onTextChange: { _ in
                                scheduleFindUpdate()
                            },
                            onCommit: {
                                tab.jumpToNextFindMatch()
                            },
                            onPreviousCommit: {
                                tab.jumpToPreviousFindMatch()
                            },
                            onCancel: {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    tab.closeFindAndFocusEditor()
                                }
                            }
                        )
                        .frame(minWidth: 130, idealWidth: 180, maxWidth: 250)
                        .frame(height: 24)

                        // Case Sensitive Toggle
                        Button {
                            tab.editorFindCaseSensitive.toggle()
                            tab.recomputeFindMatches(jumpToFirstIfNeeded: true)
                        } label: {
                            Text("Aa")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(tab.editorFindCaseSensitive ? Color.accentColor : Color.primary.opacity(0.08))
                                .foregroundStyle(tab.editorFindCaseSensitive ? Color.white : Color.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .help("Toggle Match Case")

                        if !tab.editorFindText.isEmpty {
                            if tab.editorFindMatchCount > 0 {
                                Text("\(tab.editorFindMatchIndex) of \(tab.editorFindMatchCount)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                            } else {
                                Text("0 matches")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            // Previous Match Button
                            Button {
                                tab.jumpToPreviousFindMatch()
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(tab.editorFindMatchCount == 0)
                            .help("Previous match (⇧⌘G or Shift+Return)")

                            // Next Match Button
                            Button {
                                tab.jumpToNextFindMatch()
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(tab.editorFindMatchCount == 0)
                            .help("Next match (⌘G or Return)")

                            Button {
                                tab.editorFindText = ""
                                tab.editorFindMatchIndex = 0
                                tab.editorFindMatchCount = 0
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        Button("Done") {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                tab.closeFindAndFocusEditor()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .windowBackgroundColor))

                    Divider()
                }

                // Code Editor Body
                MongoCodeEditor(
                    text: $tab.editorText,
                    isSingleLineQueryBar: false,
                    isDocumentEditor: true,
                    fontSize: 12.5,
                    externalRevision: tab.editorRevision,
                    searchTerm: tab.isEditorFindVisible ? tab.editorFindText : "",
                    caseSensitive: tab.editorFindCaseSensitive,
                    currentMatchIndex: tab.isEditorFindVisible ? tab.editorFindMatchIndex : 0,
                    jumpTrigger: tab.editorFindTriggerJump,
                    focusEditorTrigger: tab.editorFocusTrigger,
                    onCommit: {
                        Task {
                            await workspace.saveEditorDocument(in: tab)
                        }
                    },
                    onToggleFind: {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            tab.openFindInEditor()
                        }
                    },
                    onFindNext: {
                        tab.jumpToNextFindMatch()
                    },
                    onFindPrevious: {
                        tab.jumpToPreviousFindMatch()
                    },
                    onDirtyChange: {
                        tab.markEditorDirty()
                    }
                )
                .background(Color(nsColor: .textBackgroundColor))

                if let err = tab.editorError {
                    Divider()
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.12))
                }

                if let banner = tab.saveSuccessBanner {
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(banner)
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.green.opacity(0.12))
                }

                Divider()

                // Inspector Footer with Save Button & Document Metrics
                HStack(spacing: 10) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(tab.editorText, forType: .string)
                        inspectorUI.copiedDocumentBriefly = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            inspectorUI.copiedDocumentBriefly = false
                        }
                    } label: {
                        Label(
                            inspectorUI.copiedDocumentBriefly ? "Copied ✓" : "Copy",
                            systemImage: inspectorUI.copiedDocumentBriefly ? "checkmark" : "doc.on.doc"
                        )
                        .font(.system(size: 11.5))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text("\(tab.editorLineCount) lines • \(tab.formattedEditorSize)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Button {
                        Task {
                            await workspace.saveEditorDocument(in: tab)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if tab.isSavingDocument {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                            }
                            Text(tab.isCreatingNewDocument ? "Insert Document" : "Save Document (⌘S)")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(tab.isSavingDocument)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No Document Selected")
                        .font(.system(size: 13, weight: .medium))
                    Text("Click or double-click any row in the table to view and edit its BSON document.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    private func formatCurrentEditorJSON() {
        do {
            let parsed = try ShellQueryParser.parseDocument(tab.editorText)
            tab.setExternalEditorText(BSONShellFormatter.format(parsed), markDirty: true)
            tab.editorError = nil
        } catch {
            tab.editorError = error.localizedDescription
        }
    }

    private func scheduleFindUpdate() {
        inspectorUI.findDebounceWorkItem?.cancel()
        if tab.editorByteSize <= 20_000 {
            tab.recomputeFindMatches(jumpToFirstIfNeeded: true)
            return
        }
        let work = DispatchWorkItem { [weak tab] in
            tab?.recomputeFindMatches(jumpToFirstIfNeeded: true)
        }
        inspectorUI.findDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
    }
}
