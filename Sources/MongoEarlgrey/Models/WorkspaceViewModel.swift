import Foundation
import SwiftUI
import AppKit

public struct TableColumnDescriptor: Identifiable, Hashable {
    public var id: String { path }
    public let path: String          // e.g. "_id", "name", "address", "address.city"
    public let leafName: String      // e.g. "city"
    public let parentPrefix: String? // e.g. "address."
    public let dominantType: String  // e.g. "ObjectId", "String", "Number", "Boolean", "Date", "Object", "Array"
    public let isExpandableObject: Bool
    public let subFieldCount: Int
    public let isExpanded: Bool
    public let parentPath: String?
}

@MainActor
public final class CollectionTabState: Identifiable, ObservableObject {
    public let id: UUID = UUID()
    public let connectionId: UUID
    public let database: String
    public let collection: String

    @Published public var queryText: String
    public var lastExecutedQueryText: String = ""
    @Published public var queryHistory: [String] = []
    @Published public var isQueryBarExpanded: Bool = false
    @Published public var documents: [BSONDocument] = [] {
        didSet { rebuildTableColumns() }
    }
    @Published public var totalCount: Int?
    @Published public var executionTimeMs: Double = 0
    @Published public var statusText: String = "Ready"
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?

    @Published public var pageLimit: Int = 50
    @Published public var pageSkip: Int = 0

    // Nested column & inline row expansion state
    @Published public var expandedColumnPaths: Set<String> = [] {
        didSet { rebuildTableColumns() }
    }
    @Published public var expandedRowIndices: Set<Int> = []
    @Published public var columnWidths: [String: CGFloat] = [:]
    @Published public private(set) var tableColumns: [TableColumnDescriptor] = []
    @Published public var sortColumnPath: String?
    @Published public var sortAscending: Bool = true

    // Selection & Document Editing
    @Published public var selectedRowIndex: Int?
    @Published public var isInspectorVisible: Bool = false
    public var editorText: String = ""
    @Published public var editorRevision: Int = 0
    @Published public var hasUnsavedEditorChanges: Bool = false
    @Published public var editorLineCount: Int = 0
    @Published public var editorByteSize: Int = 0
    @Published public var editorError: String?
    @Published public var isSavingDocument: Bool = false
    @Published public var saveSuccessBanner: String?
    @Published public var lastSaveConfirmationText: String?
    @Published public var isCreatingNewDocument: Bool = false
    @Published public var editorFocusTrigger: Int = 0

    // Document Editor In-File Search
    @Published public var isEditorFindVisible: Bool = false
    @Published public var editorFindText: String = ""
    @Published public var editorFindCaseSensitive: Bool = false
    @Published public var editorFindMatchIndex: Int = 0 // 1-based, or 0 if none
    @Published public var editorFindMatchCount: Int = 0
    @Published public var editorFindTriggerJump: Int = 0 // increments on Next/Previous to signal editor
    @Published public var editorFindFocusTrigger: Int = 0 // increments to focus Find box and select text

    private var queryHistoryStorageKey: String {
        "earlgrey.queryHistory.\(connectionId.uuidString).\(database).\(collection)"
    }

    public init(connectionId: UUID, database: String, collection: String) {
        self.connectionId = connectionId
        self.database = database
        self.collection = collection
        self.queryText = "db.getCollection(\"\(collection)\").find({})"
        self.queryHistory = UserDefaults.standard.stringArray(forKey: "earlgrey.queryHistory.\(connectionId.uuidString).\(database).\(collection)") ?? []
    }

    public func recordQueryHistory(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queryHistory.removeAll { $0 == trimmed }
        queryHistory.insert(trimmed, at: 0)
        if queryHistory.count > 15 {
            queryHistory = Array(queryHistory.prefix(15))
        }
        UserDefaults.standard.set(queryHistory, forKey: queryHistoryStorageKey)
    }

    public func setExternalEditorText(_ newText: String, markDirty: Bool = false) {
        editorText = newText
        editorRevision &+= 1
        hasUnsavedEditorChanges = markDirty
        updateEditorMetrics(for: newText)
        if isEditorFindVisible {
            recomputeFindMatches(jumpToFirstIfNeeded: false)
        }
    }

    public func markEditorDirty() {
        if !hasUnsavedEditorChanges {
            hasUnsavedEditorChanges = true
        }
        saveSuccessBanner = nil
        editorError = nil
    }

    public func updateEditorMetrics(for text: String) {
        let byteLen = text.utf8.count
        var lines = text.isEmpty ? 0 : 1
        for byte in text.utf8 where byte == 0x0A {
            lines += 1
        }
        if editorByteSize != byteLen {
            editorByteSize = byteLen
        }
        if editorLineCount != lines {
            editorLineCount = lines
        }
    }

    public var formattedEditorSize: String {
        if editorByteSize < 1024 {
            return "\(editorByteSize) B"
        } else if editorByteSize < 1024 * 1024 {
            return String(format: "%.1f KB", Double(editorByteSize) / 1024.0)
        } else {
            return String(format: "%.2f MB", Double(editorByteSize) / (1024.0 * 1024.0))
        }
    }

    public func openFindInEditor() {
        guard isInspectorVisible, selectedDocument != nil || isCreatingNewDocument else { return }
        isEditorFindVisible = true
        editorFindFocusTrigger &+= 1
        if !editorFindText.isEmpty {
            recomputeFindMatches(jumpToFirstIfNeeded: true)
        }
    }

    public func closeFindAndFocusEditor() {
        isEditorFindVisible = false
        editorFocusTrigger &+= 1
    }

    public func recomputeFindMatches(jumpToFirstIfNeeded: Bool) {
        let count = Self.countOccurrences(
            of: editorFindText,
            in: editorText,
            caseSensitive: editorFindCaseSensitive
        )
        editorFindMatchCount = count
        if count > 0 {
            if editorFindMatchIndex <= 0 || editorFindMatchIndex > count {
                editorFindMatchIndex = 1
            }
            if jumpToFirstIfNeeded {
                editorFindTriggerJump &+= 1
            }
        } else {
            editorFindMatchIndex = 0
        }
    }

    public func jumpToNextFindMatch() {
        guard isInspectorVisible, isEditorFindVisible, editorFindMatchCount > 0 else { return }
        if editorFindMatchIndex >= editorFindMatchCount {
            editorFindMatchIndex = 1
        } else {
            editorFindMatchIndex += 1
        }
        editorFindTriggerJump &+= 1
    }

    public func jumpToPreviousFindMatch() {
        guard isInspectorVisible, isEditorFindVisible, editorFindMatchCount > 0 else { return }
        if editorFindMatchIndex <= 1 {
            editorFindMatchIndex = editorFindMatchCount
        } else {
            editorFindMatchIndex -= 1
        }
        editorFindTriggerJump &+= 1
    }

    public static func countOccurrences(of query: String, in content: String, caseSensitive: Bool) -> Int {
        guard !query.isEmpty, !content.isEmpty else { return 0 }
        let nsContent = content as NSString
        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var count = 0
        var range = NSRange(location: 0, length: nsContent.length)
        while range.location < nsContent.length {
            range.length = nsContent.length - range.location
            let found = nsContent.range(of: query, options: options, range: range)
            if found.location != NSNotFound {
                count += 1
                range.location = found.location + max(1, found.length)
            } else {
                break
            }
        }
        return count
    }

    public var selectedDocument: BSONDocument? {
        guard let idx = selectedRowIndex, idx >= 0, idx < documents.count else {
            return nil
        }
        return documents[idx]
    }

    public func selectRow(_ index: Int?, openEditor: Bool = false) {
        selectedRowIndex = index
        editorError = nil
        saveSuccessBanner = nil
        isCreatingNewDocument = false

        if let idx = index, idx >= 0, idx < documents.count {
            if openEditor {
                isInspectorVisible = true
            }
            if isInspectorVisible {
                setExternalEditorText(BSONShellFormatter.format(documents[idx]))
            }
        } else {
            setExternalEditorText("")
        }
    }

    public func startNewDocument() {
        selectedRowIndex = nil
        isCreatingNewDocument = true
        isInspectorVisible = true
        editorError = nil
        saveSuccessBanner = nil
        let newDoc: BSONDocument = [
            "_id": .objectId(BSONObjectId.generate()),
            "createdAt": .dateTime(Date())
        ]
        setExternalEditorText(BSONShellFormatter.format(newDoc), markDirty: true)
    }

    public func toggleRowExpansion(_ rowIndex: Int) {
        if expandedRowIndices.contains(rowIndex) {
            expandedRowIndices.remove(rowIndex)
        } else {
            expandedRowIndices.insert(rowIndex)
        }
    }

    public func toggleSort(forColumn path: String) {
        let selectedDocId = selectedDocument?["_id"]
        expandedRowIndices.removeAll()

        if sortColumnPath == path {
            sortAscending.toggle()
        } else {
            sortColumnPath = path
            sortAscending = true
        }
        let asc = sortAscending
        documents.sort { a, b in
            let va = a.value(atPath: path) ?? .null
            let vb = b.value(atPath: path) ?? .null
            if let da = va.doubleValue, let db = vb.doubleValue {
                return asc ? (da < db) : (da > db)
            }
            let sa = va.displayCellText
            let sb = vb.displayCellText
            return asc
                ? (sa.localizedStandardCompare(sb) == .orderedAscending)
                : (sa.localizedStandardCompare(sb) == .orderedDescending)
        }

        if let targetId = selectedDocId {
            selectedRowIndex = documents.firstIndex(where: { $0["_id"] == targetId })
        }
    }

    public func toggleColumnExpansion(_ path: String) {
        if expandedColumnPaths.contains(path) {
            // Remove path and any child paths
            expandedColumnPaths = expandedColumnPaths.filter {
                $0 != path && !$0.hasPrefix(path + ".")
            }
        } else {
            expandedColumnPaths.insert(path)
        }
    }

    public func expandAllTopLevelObjects() {
        for doc in documents {
            for el in doc.elements {
                if case .document(let sub) = el.value, !sub.isEmpty {
                    expandedColumnPaths.insert(el.key)
                }
            }
        }
    }

    public func collapseAllColumns() {
        expandedColumnPaths.removeAll()
    }

    public func autoFitColumnWidth(for path: String) {
        var maxChars = path.count + 4
        for doc in documents.prefix(100) {
            if let val = doc.value(atPath: path) {
                switch val {
                case .objectId(let oid):
                    maxChars = max(maxChars, oid.hexString.count + 6)
                case .document(let sub):
                    maxChars = max(maxChars, min(36, sub.keys.joined(separator: ", ").count + 10))
                default:
                    maxChars = max(maxChars, min(55, val.displayCellText.count))
                }
            }
        }
        columnWidths[path] = max(110, min(600, CGFloat(maxChars) * 7.8 + 32))
    }

    /// Recompute spreadsheet columns in document key order, expanding any nested object columns in `expandedColumnPaths`.
    private func rebuildTableColumns() {
        var topLevelKeys: [String] = []
        var seenTopLevel = Set<String>()

        // Always put _id first if present
        for doc in documents {
            if doc["_id"] != nil && !seenTopLevel.contains("_id") {
                seenTopLevel.insert("_id")
                topLevelKeys.append("_id")
                break
            }
        }

        for doc in documents {
            for el in doc.elements {
                if !seenTopLevel.contains(el.key) {
                    seenTopLevel.insert(el.key)
                    topLevelKeys.append(el.key)
                }
            }
        }

        var result: [TableColumnDescriptor] = []
        for key in topLevelKeys {
            appendColumnDescriptors(forPath: key, parentPath: nil, into: &result)
        }
        self.tableColumns = result
    }

    private func appendColumnDescriptors(
        forPath path: String,
        parentPath: String?,
        into result: inout [TableColumnDescriptor]
    ) {
        var hasNonEmptySubdoc = false
        var subKeys: [String] = []
        var seenSubKeys = Set<String>()
        var detectedType: String = "String"

        for doc in documents {
            if let val = doc.value(atPath: path), val != .null && val != .undefined {
                detectedType = val.typeLabel
                if case .document(let subDoc) = val, !subDoc.isEmpty {
                    hasNonEmptySubdoc = true
                    for el in subDoc.elements {
                        if !seenSubKeys.contains(el.key) {
                            seenSubKeys.insert(el.key)
                            subKeys.append(el.key)
                        }
                    }
                }
            }
        }

        let isExpanded = expandedColumnPaths.contains(path)
        let parts = path.split(separator: ".").map(String.init)
        let leaf = parts.last ?? path
        let prefix = parts.count > 1 ? parts.dropLast().joined(separator: ".") + "." : nil

        result.append(
            TableColumnDescriptor(
                path: path,
                leafName: leaf,
                parentPrefix: prefix,
                dominantType: hasNonEmptySubdoc ? "Object" : detectedType,
                isExpandableObject: hasNonEmptySubdoc,
                subFieldCount: subKeys.count,
                isExpanded: isExpanded,
                parentPath: parentPath
            )
        )

        if hasNonEmptySubdoc && isExpanded {
            for subKey in subKeys {
                let childPath = "\(path).\(subKey)"
                appendColumnDescriptors(forPath: childPath, parentPath: path, into: &result)
            }
        }
    }
}

@MainActor
public final class WorkspaceViewModel: ObservableObject {
    @Published public var savedConnections: [ConnectionConfig] = []
    @Published public var activeConnection: ConnectionConfig?
    @Published public var serverStatusBanner: String = "Disconnected"
    @Published public var isConnecting: Bool = false
    @Published public var connectingConnectionId: UUID?
    @Published public var isRefreshingDatabases: Bool = false
    @Published public var connectionError: String?

    @Published public var databases: [DatabaseSummary] = []
    @Published public var expandedDatabases: Set<String> = []
    @Published public var sidebarSearchText: String = ""
    @Published public var selectedSidebarCollectionId: String?

    @Published public var openTabs: [CollectionTabState] = []
    @Published public var selectedTabId: UUID?

    @Published public var isConnectionManagerPresented: Bool = false
    @Published public var isEditingNewDraft: Bool = false
    @Published public var editingConnection: ConnectionConfig?

    public enum ConnectionTestStatus: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    @Published public var selectedManagerConnectionId: UUID?
    @Published public var draftConnection: ConnectionConfig = ConnectionConfig()
    @Published public var draftPortText: String = "27017"
    @Published public var connectionTestStatus: ConnectionTestStatus = .idle
    @Published public var showPasswordInManager: Bool = false

    private var activeClient: MongoClient?

    public init() {
        let loaded = ConnectionStore.shared.loadConnections()
        self.savedConnections = loaded
        if let first = loaded.first {
            self.selectedManagerConnectionId = first.id
            self.draftConnection = first
            self.draftPortText = String(first.port)
        }
    }

    public func openConnectionManager(for connection: ConnectionConfig? = nil) {
        if let conn = connection ?? activeConnection ?? savedConnections.first {
            selectManagerConnection(conn)
        } else {
            startCreatingNewConnection()
            return
        }
        isConnectionManagerPresented = true
    }

    public func selectManagerConnection(_ conn: ConnectionConfig) {
        isEditingNewDraft = false
        showPasswordInManager = false
        selectedManagerConnectionId = conn.id
        draftConnection = conn
        draftPortText = String(conn.port)
        connectionTestStatus = .idle
    }

    public func startCreatingNewConnection() {
        let newConn = ConnectionConfig(
            name: "New MongoDB Connection",
            colorName: "blue",
            useURI: true,
            uriString: "mongodb://127.0.0.1:27017",
            host: "127.0.0.1",
            port: 27017,
            isDemoMode: false
        )
        // Hold as an unsaved draft until the user explicitly clicks Save / Save & Connect
        isEditingNewDraft = true
        showPasswordInManager = false
        selectedManagerConnectionId = nil
        draftConnection = newConn
        draftPortText = String(newConn.port)
        connectionTestStatus = .idle
        isConnectionManagerPresented = true
    }

    public func cancelConnectionManager() {
        isEditingNewDraft = false
        showPasswordInManager = false
        connectionTestStatus = .idle
        if let fallback = activeConnection ?? savedConnections.first {
            selectManagerConnection(fallback)
        }
        isConnectionManagerPresented = false
    }

    public func runDraftConnectionTest() {
        connectionTestStatus = .testing
        let configToTest = draftConnection
        Task {
            let start = CFAbsoluteTimeGetCurrent()
            let client = MongoClient(config: configToTest)
            do {
                let info = try await client.connect()
                await client.disconnect()
                let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                connectionTestStatus = .success("\(info) • \(ms) ms")
            } catch {
                await client.disconnect()
                connectionTestStatus = .failure(error.localizedDescription)
            }
        }
    }

    public var activeTab: CollectionTabState? {
        guard let id = selectedTabId else { return openTabs.first }
        return openTabs.first(where: { $0.id == id })
    }

    public var filteredDatabases: [DatabaseSummary] {
        let query = sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return databases }

        return databases.compactMap { db in
            if db.name.lowercased().contains(query) {
                return db
            }
            let matchingCols = db.collections.filter { $0.name.lowercased().contains(query) }
            if !matchingCols.isEmpty {
                return DatabaseSummary(name: db.name, sizeOnDisk: db.sizeOnDisk, empty: db.empty, collections: matchingCols)
            }
            return nil
        }
    }

    // MARK: - Connection Persistence
    @discardableResult
    public func saveConnection(_ config: ConnectionConfig, preserveExistingFavorites: Bool = true) -> ConnectionConfig {
        var resolved = config
        let trimmedName = resolved.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            resolved.name = resolved.isDemoMode ? "Earlgrey Sandbox" : "Untitled Connection"
        } else {
            resolved.name = trimmedName
        }

        if let idx = savedConnections.firstIndex(where: { $0.id == resolved.id }) {
            if preserveExistingFavorites {
                resolved.favoriteCollections = savedConnections[idx].favoriteCollections
            }
            savedConnections[idx] = resolved
        } else {
            savedConnections.append(resolved)
        }

        if activeConnection?.id == resolved.id {
            activeConnection?.name = resolved.name
            activeConnection?.colorName = resolved.colorName
        }

        isEditingNewDraft = false
        selectedManagerConnectionId = resolved.id
        ConnectionStore.shared.saveConnections(savedConnections)
        return resolved
    }

    public func toggleFavorite(database: String, collection: String) {
        guard var active = activeConnection else { return }
        let id = "\(database).\(collection)"
        if let idx = active.favoriteCollections.firstIndex(of: id) {
            active.favoriteCollections.remove(at: idx)
        } else {
            active.favoriteCollections.append(id)
        }
        self.activeConnection = active
        saveConnection(active, preserveExistingFavorites: false)
    }

    public func isFavorite(database: String, collection: String) -> Bool {
        guard let active = activeConnection else { return false }
        let id = "\(database).\(collection)"
        return active.favoriteCollections.contains(id)
    }

    public func duplicateConnection(_ config: ConnectionConfig) {
        var copy = config
        copy.id = UUID()
        copy.name = "\(config.name) Copy"
        copy.hasStoredKeychainPassword = false
        savedConnections.append(copy)
        ConnectionStore.shared.saveConnections(savedConnections)
        selectManagerConnection(copy)
    }

    // MARK: - Connect & Load Databases
    public func connect(to config: ConnectionConfig) async {
        isConnecting = true
        connectingConnectionId = config.id
        connectionError = nil

        let isSwitchingConnection = (activeConnection?.id != config.id)

        if let existing = activeClient {
            await existing.disconnect()
            activeClient = nil
        }

        if isSwitchingConnection {
            // Clear stale tabs and schema from the previous connection immediately
            openTabs = []
            selectedTabId = nil
            databases = []
            expandedDatabases = []
            sidebarSearchText = ""
            selectedSidebarCollectionId = nil
            activeConnection = nil
        }

        var updatedConfig = config
        updatedConfig.lastConnectedAt = Date()
        updatedConfig = saveConnection(updatedConfig, preserveExistingFavorites: true)

        let client = MongoClient(config: updatedConfig)
        do {
            let banner = try await client.connect()
            let dbs = try await client.listDatabasesWithCollections()

            self.activeClient = client
            self.activeConnection = updatedConfig
            self.serverStatusBanner = banner
            self.databases = dbs
            // Auto-expand non-system databases
            let nonSystem = dbs.map(\.name).filter { !["admin", "local", "config"].contains($0) }
            if !nonSystem.isEmpty {
                self.expandedDatabases = Set(nonSystem)
            } else if let first = dbs.first {
                self.expandedDatabases = [first.name]
            }
            self.isConnecting = false
            self.connectingConnectionId = nil
            self.isConnectionManagerPresented = false
        } catch {
            self.isConnecting = false
            self.connectingConnectionId = nil
            self.connectionError = error.localizedDescription
        }
    }

    public func refreshDatabases() async {
        guard let client = activeClient else { return }
        isRefreshingDatabases = true
        defer { isRefreshingDatabases = false }
        do {
            let dbs = try await client.listDatabasesWithCollections()
            self.databases = dbs
        } catch {
            self.connectionError = error.localizedDescription
        }
    }

    public func disconnect() async {
        if let client = activeClient {
            await client.disconnect()
        }
        activeClient = nil
        activeConnection = nil
        databases = []
        expandedDatabases = []
        sidebarSearchText = ""
        selectedSidebarCollectionId = nil
        openTabs = []
        selectedTabId = nil
        serverStatusBanner = "Disconnected"
    }

    // MARK: - Open Collection Tab (Double-Click Handler)
    public func openCollectionTab(database: String, collection: String, forceNewTab: Bool = false) {
        guard let connId = activeConnection?.id else { return }

        if !forceNewTab,
           let existing = openTabs.first(where: {
               $0.connectionId == connId && $0.database == database && $0.collection == collection
           }) {
            selectedTabId = existing.id
            return
        }

        let newTab = CollectionTabState(connectionId: connId, database: database, collection: collection)
        openTabs.append(newTab)
        selectedTabId = newTab.id

        Task {
            await runQuery(for: newTab)
        }
    }

    public func duplicateTab(_ tab: CollectionTabState) {
        guard let connId = activeConnection?.id else { return }
        let newTab = CollectionTabState(connectionId: connId, database: tab.database, collection: tab.collection)
        newTab.queryText = tab.queryText
        newTab.pageLimit = tab.pageLimit
        openTabs.append(newTab)
        selectedTabId = newTab.id
        Task {
            await runQuery(for: newTab)
        }
    }

    public func closeTab(_ tabId: UUID, force: Bool = false) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabId }) else { return }
        let tab = openTabs[idx]
        if !force && !confirmDiscardUnsavedChangesIfNeeded(in: tab) {
            return
        }
        let wasSelected = (selectedTabId == tabId)
        openTabs.remove(at: idx)
        if wasSelected {
            if idx < openTabs.count {
                selectedTabId = openTabs[idx].id
            } else {
                selectedTabId = openTabs.last?.id
            }
        }
    }

    public func closeOtherTabs(except tabId: UUID) {
        let others = openTabs.filter { $0.id != tabId }
        for other in others where !confirmDiscardUnsavedChangesIfNeeded(in: other) {
            return
        }
        openTabs.removeAll { $0.id != tabId }
        selectedTabId = tabId
    }

    public func confirmDiscardUnsavedChangesIfNeeded(in tab: CollectionTabState) -> Bool {
        guard tab.hasUnsavedEditorChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Unsaved Document Changes"
        alert.informativeText = "You have unsaved edits in \(tab.database).\(tab.collection). Do you want to discard them?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Run Query in Tab
    public func runQuery(for tab: CollectionTabState) async {
        guard let client = activeClient else {
            tab.errorMessage = "Not connected to any MongoDB instance."
            return
        }

        // Automatically reset pageSkip if query text changed since the previous execution
        if !tab.lastExecutedQueryText.isEmpty && tab.queryText != tab.lastExecutedQueryText {
            tab.pageSkip = 0
        }
        let executedQuery = tab.queryText

        tab.isLoading = true
        tab.errorMessage = nil
        tab.expandedRowIndices.removeAll()

        do {
            let parsed = try ShellQueryParser.parseQuery(executedQuery, defaultCollection: tab.collection)
            let result = try await client.executeQuery(
                database: tab.database,
                defaultCollection: tab.collection,
                parsedQuery: parsed,
                fallbackLimit: tab.pageLimit,
                fallbackSkip: tab.pageSkip
            )

            tab.lastExecutedQueryText = executedQuery
            tab.recordQueryHistory(executedQuery)

            tab.documents = result.documents
            tab.totalCount = result.totalCount
            tab.executionTimeMs = result.executionTimeMs
            tab.statusText = result.statusText
            tab.isLoading = false

            // Keep selected row valid if possible
            if let sel = tab.selectedRowIndex {
                if sel < result.documents.count {
                    if !tab.hasUnsavedEditorChanges {
                        tab.selectRow(sel, openEditor: tab.isInspectorVisible)
                    }
                } else if !tab.hasUnsavedEditorChanges {
                    tab.selectRow(nil)
                }
            }
        } catch {
            tab.isLoading = false
            tab.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Save Edited / New Document
    public func saveEditorDocument(in tab: CollectionTabState) async {
        guard let client = activeClient else { return }
        tab.editorError = nil
        tab.saveSuccessBanner = nil
        tab.isSavingDocument = true

        do {
            let parsedDoc = try ShellQueryParser.parseDocument(tab.editorText)

            if tab.isCreatingNewDocument {
                try await client.insertDocument(
                    database: tab.database,
                    collection: tab.collection,
                    document: parsedDoc
                )
                tab.isCreatingNewDocument = false
                tab.hasUnsavedEditorChanges = false
                tab.isSavingDocument = false
                tab.isEditorFindVisible = false
                tab.isInspectorVisible = false
                await runQuery(for: tab)
                let msg = "Inserted document ✓"
                tab.lastSaveConfirmationText = msg
                scheduleClearConfirmation(msg, in: tab)
            } else {
                guard let selectedDoc = tab.selectedDocument,
                      let originalId = selectedDoc["_id"] else {
                    throw MongoDriverError.commandFailed(
                        code: nil,
                        message: "Cannot save document without an _id field."
                    )
                }

                try await client.replaceDocument(
                    database: tab.database,
                    collection: tab.collection,
                    originalId: originalId,
                    replacement: parsedDoc
                )

                // Update in-place immediately for snappy UX
                if let idx = tab.selectedRowIndex, idx < tab.documents.count {
                    var updated = parsedDoc
                    if updated["_id"] == nil {
                        var elems = [BSONElement(key: "_id", value: originalId)]
                        elems.append(contentsOf: updated.elements)
                        updated = BSONDocument(elements: elems)
                    }
                    tab.documents[idx] = updated
                    tab.setExternalEditorText(BSONShellFormatter.format(updated))
                }
                tab.hasUnsavedEditorChanges = false
                tab.isSavingDocument = false
                tab.isEditorFindVisible = false
                tab.isInspectorVisible = false
                let msg = "Document saved ✓"
                tab.lastSaveConfirmationText = msg
                scheduleClearConfirmation(msg, in: tab)
            }
        } catch {
            tab.isSavingDocument = false
            tab.editorError = error.localizedDescription
        }
    }

    private func scheduleClearConfirmation(_ expected: String, in tab: CollectionTabState) {
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if tab.lastSaveConfirmationText == expected {
                tab.lastSaveConfirmationText = nil
            }
        }
    }
}
