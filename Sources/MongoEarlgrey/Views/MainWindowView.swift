import SwiftUI
import AppKit

@MainActor
private final class MainWindowUIState: ObservableObject {
    @Published var isFavoritesExpanded: Bool = true
}

@MainActor
private final class HoverState: ObservableObject {
    @Published var isHovered: Bool = false
}

private struct SidebarRowHoverModifier: ViewModifier {
    let isSelected: Bool
    @StateObject private var hoverState = HoverState()

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.16)
                            : (hoverState.isHovered ? Color.primary.opacity(0.06) : Color.clear)
                    )
            )
            .onHover { hovering in
                hoverState.isHovered = hovering
            }
    }
}

public struct MainWindowView: View {
    @ObservedObject public var workspace: WorkspaceViewModel
    @StateObject private var uiState = MainWindowUIState()

    public init(workspace: WorkspaceViewModel) {
        self.workspace = workspace
    }

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 235, ideal: 265, max: 360)
        } detail: {
            detailContent
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Menu {
                    Section("Saved Connections") {
                        ForEach(workspace.savedConnections) { conn in
                            Button {
                                Task {
                                    await workspace.connect(to: conn)
                                }
                            } label: {
                                HStack {
                                    Text(conn.name)
                                    if workspace.activeConnection?.id == conn.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    Button("Connection Manager… (⌘K)") {
                        workspace.openConnectionManager(for: workspace.activeConnection)
                    }

                    Button("New Connection… (⌘N)") {
                        workspace.startCreatingNewConnection()
                    }

                    if workspace.activeConnection != nil {
                        Divider()
                        Button("Disconnect") {
                            Task {
                                await workspace.disconnect()
                            }
                        }
                    }
                } label: {
                    let isCrimsonTag = (workspace.activeConnection?.colorName.lowercased() == "rose")
                    HStack(spacing: 6) {
                        if let active = workspace.activeConnection {
                            Circle()
                                .fill(EarlgreyTheme.connectionColor(active.colorName))
                                .frame(width: 8, height: 8)
                            Text(active.name)
                                .font(.system(size: 12.5, weight: .semibold))
                            if isCrimsonTag {
                                Text("LIVE")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.red.opacity(0.16))
                                    .foregroundStyle(.red)
                                    .clipShape(Capsule())
                            }
                        } else {
                            Image(systemName: "network")
                            Text("Connection Setup")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isCrimsonTag ? Color.red.opacity(0.08) : Color.clear)
                    )
                }
                .menuStyle(.borderlessButton)
                .help("Switch Connection or Open Connection Manager (⌘K)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    workspace.startCreatingNewConnection()
                } label: {
                    Label("New Connection", systemImage: "plus.circle")
                }
                .help("Create a New MongoDB Connection (⌘N)")

                if workspace.activeConnection != nil {
                    Button {
                        Task {
                            await workspace.refreshDatabases()
                        }
                    } label: {
                        if workspace.isRefreshingDatabases {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(workspace.isRefreshingDatabases)
                    .help("Refresh Databases & Collections (⌘R)")
                }

                Button {
                    if workspace.isConnectionManagerPresented && (workspace.activeConnection != nil || !workspace.isEditingNewDraft) {
                        workspace.cancelConnectionManager()
                    } else {
                        workspace.openConnectionManager(for: workspace.activeConnection)
                    }
                } label: {
                    Label(
                        workspace.isConnectionManagerPresented ? "Back" : "Connections",
                        systemImage: "server.rack"
                    )
                }
                .help("Manage Saved Connections (⌘K)")
            }
        }
    }

    // MARK: - Left Sidebar (Databases & Collections)
    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if workspace.activeConnection != nil {
                // Search / Filter Collections Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    NativeTextField("Filter collections…", text: $workspace.sidebarSearchText)
                        .frame(height: 24)
                    if !workspace.sidebarSearchText.isEmpty {
                        Button {
                            workspace.sidebarSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Divider()
            }

            if workspace.activeConnection == nil {
                // Quick Saved Connections List in Sidebar when disconnected
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("QUICK CONNECT")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            workspace.startCreatingNewConnection()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.borderless)
                        .help("New Connection")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(workspace.savedConnections) { conn in
                                let isSelected = (workspace.selectedManagerConnectionId == conn.id)
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(EarlgreyTheme.connectionColor(conn.colorName))
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(conn.name)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(conn.displayAddress)
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .modifier(SidebarRowHoverModifier(isSelected: isSelected))
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    workspace.selectManagerConnection(conn)
                                    Task {
                                        await workspace.connect(to: conn)
                                    }
                                }
                                .onTapGesture(count: 1) {
                                    workspace.selectManagerConnection(conn)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
            } else {
                // Connected Database & Collection Tree (with pinned Favorites section)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        pinnedFavoritesSidebarSection

                        ForEach(workspace.filteredDatabases) { db in
                            databaseSectionView(db)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                }

                Divider()

                // Connection Footer Status
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text(workspace.serverStatusBanner)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if workspace.isRefreshingDatabases {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Button {
                        Task {
                            await workspace.disconnect()
                        }
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Disconnect")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var pinnedFavoritesSidebarSection: some View {
        let favIds = Set(workspace.activeConnection?.favoriteCollections ?? [])
        let query = workspace.sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let favCols = workspace.databases
            .flatMap(\.collections)
            .filter { col in
                guard favIds.contains("\(col.database).\(col.name)") else { return false }
                if query.isEmpty { return true }
                return col.name.lowercased().contains(query) || col.database.lowercased().contains(query)
            }

        if !favCols.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Image(systemName: uiState.isFavoritesExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Image(systemName: "star.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.yellow)
                    Text("FAVORITES")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(favCols.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        uiState.isFavoritesExpanded.toggle()
                    }
                }

                if uiState.isFavoritesExpanded {
                    ForEach(favCols) { col in
                        collectionSidebarRow(col, showDatabasePrefix: true, indent: 20)
                    }
                }

                Divider()
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
            }
        }
    }

    private func databaseSectionView(_ db: DatabaseSummary) -> some View {
        let isExpanded = workspace.expandedDatabases.contains(db.name) || !workspace.sidebarSearchText.isEmpty

        return VStack(alignment: .leading, spacing: 1) {
            // Database Header Row
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Image(systemName: "cylinder.split.1x2.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.accentColor)

                Text(db.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Text("\(db.collections.count)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.12)) {
                    if workspace.expandedDatabases.contains(db.name) {
                        workspace.expandedDatabases.remove(db.name)
                    } else {
                        workspace.expandedDatabases.insert(db.name)
                    }
                }
            }

            // Collections inside Database
            if isExpanded {
                ForEach(db.collections) { col in
                    collectionSidebarRow(col, showDatabasePrefix: false, indent: 26)
                }
            }
        }
    }

    private func collectionSidebarRow(
        _ col: CollectionSummary,
        showDatabasePrefix: Bool = false,
        indent: CGFloat = 26
    ) -> some View {
        let isSelected = (workspace.selectedSidebarCollectionId == col.id) ||
            (workspace.activeTab?.database == col.database && workspace.activeTab?.collection == col.name)
        let isFav = workspace.isFavorite(database: col.database, collection: col.name)
        let isView = (col.type.lowercased() == "view")

        return HStack(spacing: 7) {
            Image(systemName: isView ? "eye" : "tablecells")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

            if showDatabasePrefix {
                Text("\(col.database).\(col.name)")
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.88))
                    .lineLimit(1)
            } else {
                Text(col.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.88))
                    .lineLimit(1)
            }

            Spacer()

            // Favorite Star Button
            Button {
                workspace.toggleFavorite(database: col.database, collection: col.name)
            } label: {
                Image(systemName: isFav ? "star.fill" : "star")
                    .font(.system(size: 10.5))
                    .foregroundStyle(isFav ? Color.yellow : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help(isFav ? "Remove from Favorites" : "Add to Favorites")
        }
        .padding(.leading, indent)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .modifier(SidebarRowHoverModifier(isSelected: isSelected))
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                workspace.selectedSidebarCollectionId = col.id
                workspace.isConnectionManagerPresented = false
                workspace.openCollectionTab(database: col.database, collection: col.name)
            }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                workspace.selectedSidebarCollectionId = col.id
            }
        )
        .contextMenu {
            Button("Open Collection") {
                workspace.isConnectionManagerPresented = false
                workspace.openCollectionTab(database: col.database, collection: col.name)
            }
            Button("Open in New Query Tab") {
                workspace.isConnectionManagerPresented = false
                workspace.openCollectionTab(database: col.database, collection: col.name, forceNewTab: true)
            }
            Button(isFav ? "Remove from Favorites" : "Add to Favorites") {
                workspace.toggleFavorite(database: col.database, collection: col.name)
            }
            Divider()
            Button("Copy Collection Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(col.name, forType: .string)
            }
        }
        .help("Double-click to open \(col.database).\(col.name)")
    }

    // MARK: - Right Detail Area (Quick Connect Welcome OR Connection Manager OR Tabs)
    @ViewBuilder
    private var detailContent: some View {
        if workspace.isConnectionManagerPresented {
            ConnectionManagerView(workspace: workspace)
        } else if workspace.activeConnection == nil {
            quickConnectWelcomeView
        } else if workspace.openTabs.isEmpty {
            connectedNoTabsView
        } else {
            VStack(spacing: 0) {
                tabBarView

                Divider()

                if let activeTab = workspace.activeTab {
                    CollectionTabView(tab: activeTab, workspace: workspace)
                        .id(activeTab.id)
                }
            }
        }
    }

    private var quickConnectWelcomeView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(Color.accentColor)

                Text("Mongo Earlgrey")
                    .font(.system(size: 26, weight: .bold))

                Text("Fast, native macOS MongoDB client. Select a saved connection to connect, or set up a new one.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let err = workspace.connectionError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button {
                        workspace.connectionError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss error")
                }
                .padding(10)
                .frame(maxWidth: 540)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("QUICK CONNECT")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        workspace.startCreatingNewConnection()
                    } label: {
                        Label("New", systemImage: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(workspace.savedConnections) { conn in
                            quickConnectCard(conn)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .frame(width: 540)

            HStack(spacing: 12) {
                Button {
                    workspace.openConnectionManager(for: workspace.savedConnections.first)
                } label: {
                    Label("Manage Connections…", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .buttonStyle(.bordered)

                Button {
                    workspace.startCreatingNewConnection()
                } label: {
                    Label("New Connection…", systemImage: "plus.circle")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func quickConnectCard(_ conn: ConnectionConfig) -> some View {
        let resolved = try? conn.resolveEndpoint()
        let usesTLS = conn.isDemoMode ? false : (resolved?.useTLS ?? conn.useTLS)
        let usesAuth = conn.isDemoMode ? false : ((resolved?.username?.isEmpty == false) || conn.authEnabled)
        let isThisConnecting = (workspace.isConnecting && workspace.connectingConnectionId == conn.id)

        return HStack(spacing: 12) {
            Circle()
                .fill(EarlgreyTheme.connectionColor(conn.colorName))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(conn.name)
                        .font(.system(size: 13.5, weight: .semibold))

                    if conn.isDemoMode {
                        badgePill("Sample", color: .orange)
                    }
                    if usesTLS {
                        badgePill("TLS", icon: "lock.shield.fill", color: .green)
                    }
                    if usesAuth {
                        badgePill("Auth", icon: "key.fill", color: .blue)
                    }
                }

                HStack(spacing: 8) {
                    Text(conn.displayAddress)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let last = conn.lastConnectedAt {
                        Text("• Used \(last.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Button("Edit") {
                workspace.selectManagerConnection(conn)
                workspace.isConnectionManagerPresented = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                Task {
                    await workspace.connect(to: conn)
                }
            } label: {
                HStack(spacing: 4) {
                    if isThisConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                    }
                    Text("Connect")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(workspace.isConnecting)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard !workspace.isConnecting else { return }
            Task {
                await workspace.connect(to: conn)
            }
        }
    }

    private func badgePill(_ text: String, icon: String? = nil, color: Color) -> some View {
        HStack(spacing: 3) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 9.5, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(color.opacity(0.14))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private var tabBarView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(workspace.openTabs) { tab in
                    let isSelected = (workspace.selectedTabId == tab.id)
                    HStack(spacing: 7) {
                        if tab.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "tablecells")
                                .font(.system(size: 11))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        }

                        Text(tab.collection)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))

                        Text(tab.database)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)

                        if tab.hasUnsavedEditorChanges {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                                .help("Unsaved document changes")
                        }

                        Button {
                            workspace.closeTab(tab.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(3)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color(nsColor: .textBackgroundColor) : Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isSelected ? Color.primary.opacity(0.14) : Color.clear, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        workspace.selectedTabId = tab.id
                    }
                    .contextMenu {
                        Button("Duplicate Tab") {
                            workspace.duplicateTab(tab)
                        }
                        Divider()
                        Button("Close Tab") {
                            workspace.closeTab(tab.id)
                        }
                        if workspace.openTabs.count > 1 {
                            Button("Close Other Tabs") {
                                workspace.closeOtherTabs(except: tab.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var connectedNoTabsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)

            Text("Double-click any collection in the sidebar to open it")
                .font(.system(size: 15, weight: .semibold))

            Text("Opens with db.getCollection(\"...\").find({}) ready to filter, inspect, and edit.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

            // 1. Starred Favorites Section (if any)
            let allCols = workspace.databases.flatMap(\.collections)
            let favIds = Set(workspace.activeConnection?.favoriteCollections ?? [])
            let favCols = allCols.filter { favIds.contains("\($0.database).\($0.name)") }

            if !favCols.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.yellow)
                        Text("FAVORITE COLLECTIONS")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(favCols) { col in
                                HStack(spacing: 4) {
                                    Button {
                                        workspace.openCollectionTab(database: col.database, collection: col.name)
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: col.type.lowercased() == "view" ? "eye" : "tablecells")
                                                .font(.system(size: 11))
                                            Text("\(col.database).\(col.name)")
                                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        workspace.toggleFavorite(database: col.database, collection: col.name)
                                    } label: {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.yellow)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove from Favorites")
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Color.yellow.opacity(0.12))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(Color.yellow.opacity(0.35), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }

            // 2. Available Collections Quick Launch
            let nonFavCols = allCols.filter { !favIds.contains("\($0.database).\($0.name)") }.prefix(8)
            if !nonFavCols.isEmpty {
                VStack(spacing: 8) {
                    Text("AVAILABLE COLLECTIONS")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, favCols.isEmpty ? 8 : 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(nonFavCols)) { col in
                                HStack(spacing: 4) {
                                    Button {
                                        workspace.openCollectionTab(database: col.database, collection: col.name)
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: col.type.lowercased() == "view" ? "eye" : "tablecells")
                                                .font(.system(size: 11))
                                            Text("\(col.database).\(col.name)")
                                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        workspace.toggleFavorite(database: col.database, collection: col.name)
                                    } label: {
                                        Image(systemName: "star")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Add to Favorites")
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Color.primary.opacity(0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
