import SwiftUI
import AppKit

public struct ConnectionManagerView: View {
    @ObservedObject public var workspace: WorkspaceViewModel

    public init(workspace: WorkspaceViewModel) {
        self.workspace = workspace
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left Column: Saved Connections List
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("SAVED CONNECTIONS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        workspace.startCreatingNewConnection()
                    } label: {
                        Label("New", systemImage: "plus")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Create a new MongoDB connection")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 4) {
                        if workspace.isEditingNewDraft {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(EarlgreyTheme.connectionColor(workspace.draftConnection.colorName))
                                    .frame(width: 9, height: 9)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workspace.draftConnection.name.isEmpty ? "New Connection" : workspace.draftConnection.name)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .lineLimit(1)
                                    Text("Unsaved draft…")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(.orange)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.accentColor.opacity(0.18))
                            )
                        }

                        ForEach(workspace.savedConnections) { conn in
                            connectionRow(conn)
                        }
                    }
                    .padding(8)
                }

                Divider()

                HStack {
                    Button {
                        workspace.startCreatingNewConnection()
                    } label: {
                        Label("Add New Connection", systemImage: "plus.circle.fill")
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .padding(12)
            }
            .frame(width: 260)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Right Column: Connection Setup & URI / Fields Editor
            VStack(alignment: .leading, spacing: 0) {
                // Top Header Bar
                HStack(spacing: 12) {
                    Circle()
                        .fill(EarlgreyTheme.connectionColor(workspace.draftConnection.colorName))
                        .frame(width: 12, height: 12)

                    Text(workspace.draftConnection.name.isEmpty ? "Untitled Connection" : workspace.draftConnection.name)
                        .font(.system(size: 17, weight: .semibold))

                    if workspace.isEditingNewDraft {
                        Text("UNSAVED DRAFT")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.16))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }

                    if workspace.draftConnection.isDemoMode {
                        Text("BUILT-IN SAMPLE DB")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Button(workspace.activeConnection != nil ? "Done" : "Back") {
                        workspace.cancelConnectionManager()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Return to previous screen")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // 1. Connection Name & Color Tag
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Connection Name")
                                    .font(.system(size: 12, weight: .semibold))
                                NativeTextField(
                                    "e.g. Production Atlas, Staging, Local Mongo",
                                    text: $workspace.draftConnection.name
                                )
                                .frame(height: 26)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Color Tag")
                                    .font(.system(size: 12, weight: .semibold))
                                HStack(spacing: 8) {
                                    ForEach(EarlgreyTheme.colorOptions, id: \.id) { item in
                                        Button {
                                            workspace.draftConnection.colorName = item.id
                                        } label: {
                                            ZStack {
                                                Circle()
                                                    .fill(EarlgreyTheme.connectionColor(item.id))
                                                    .frame(width: 22, height: 22)
                                                if workspace.draftConnection.colorName == item.id {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .help(item.label)
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }

                        if workspace.draftConnection.isDemoMode {
                            GroupBox {
                                HStack(spacing: 12) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Built-in Sample Database")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("This is an in-memory sample database. To connect to your own MongoDB instance, click '+ New' on the left or switch this connection to a standard MongoDB URI below.")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Use Custom MongoDB URI Instead") {
                                        workspace.draftConnection.isDemoMode = false
                                        workspace.draftConnection.uriString = "mongodb://127.0.0.1:27017"
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(8)
                            }
                        } else {
                            // 2. PRIMARY: MongoDB Connection String (URI) Box
                            let uriHasPassword = ConnectionConfig.extractPasswordFromURI(workspace.draftConnection.uriString) != nil

                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Label("MongoDB Connection String (URI)", systemImage: "link")
                                        .font(.system(size: 13, weight: .semibold))

                                    if uriHasPassword || !workspace.draftConnection.password.isEmpty {
                                        HStack(spacing: 3) {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 9))
                                            Text("Keychain")
                                                .font(.system(size: 9.5, weight: .semibold))
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.14))
                                        .foregroundStyle(.green)
                                        .clipShape(Capsule())
                                    }

                                    Spacer()

                                    if uriHasPassword {
                                        Button {
                                            workspace.showPasswordInManager.toggle()
                                        } label: {
                                            Label(
                                                workspace.showPasswordInManager ? "Hide Password" : "Reveal / Edit URI",
                                                systemImage: workspace.showPasswordInManager ? "eye.slash" : "eye"
                                            )
                                            .font(.system(size: 11, weight: .medium))
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    Button {
                                        if let pasted = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                                           !pasted.isEmpty {
                                            workspace.draftConnection.useURI = true
                                            workspace.draftConnection.uriString = pasted
                                            workspace.draftConnection.syncFieldsFromURI()
                                            workspace.draftPortText = String(workspace.draftConnection.port)
                                        }
                                    } label: {
                                        Label("Paste URI", systemImage: "doc.on.clipboard")
                                            .font(.system(size: 11.5, weight: .medium))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    if !workspace.draftConnection.uriString.isEmpty {
                                        Button("Clear") {
                                            workspace.draftConnection.uriString = ""
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }

                                if uriHasPassword && !workspace.showPasswordInManager && !workspace.isEditingNewDraft {
                                    HStack(spacing: 8) {
                                        Text(ConnectionConfig.maskedURI(workspace.draftConnection.uriString))
                                            .font(.system(size: 12.5, design: .monospaced))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                        Spacer()
                                        Button("Edit") {
                                            workspace.showPasswordInManager = true
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                    .padding(.horizontal, 8)
                                    .frame(height: 28)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                                    )
                                } else {
                                    NativeTextField(
                                        "mongodb://username:password@127.0.0.1:27017/mydb?authSource=admin  or  mongodb+srv://...",
                                        text: $workspace.draftConnection.uriString,
                                        isMonospaced: true,
                                        onTextChange: { _ in
                                            workspace.draftConnection.useURI = true
                                            workspace.draftConnection.syncFieldsFromURI()
                                            workspace.draftPortText = String(workspace.draftConnection.port)
                                        }
                                    )
                                    .frame(height: 28)
                                }

                                Text("Paste or type any mongodb:// or mongodb+srv:// URI above, or configure Host & Authentication fields below. Passwords are stored in the macOS Keychain.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.accentColor.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
                            )

                            // 3. Individual Host, Port, TLS & Authentication Fields (Auto-synced with URI)
                            VStack(alignment: .leading, spacing: 14) {
                                Text("HOST, TLS & AUTHENTICATION DETAILS")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Host / Server Address")
                                            .font(.system(size: 12, weight: .medium))
                                        NativeTextField(
                                            "127.0.0.1",
                                            text: $workspace.draftConnection.host,
                                            isMonospaced: true,
                                            onTextChange: { _ in
                                                workspace.draftConnection.syncURIFromFields()
                                            }
                                        )
                                        .frame(height: 26)
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Port")
                                            .font(.system(size: 12, weight: .medium))
                                        NativeTextField(
                                            "27017",
                                            text: $workspace.draftPortText,
                                            isMonospaced: true,
                                            onTextChange: { newPortStr in
                                                if let p = Int(newPortStr.trimmingCharacters(in: .whitespaces)),
                                                   p >= 1 && p <= 65535 {
                                                    workspace.draftConnection.port = p
                                                    workspace.draftConnection.syncURIFromFields()
                                                }
                                            }
                                        )
                                        .frame(width: 95, height: 26)
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Default Database (Optional)")
                                            .font(.system(size: 12, weight: .medium))
                                        NativeTextField(
                                            "admin or mydb",
                                            text: $workspace.draftConnection.defaultDatabase,
                                            isMonospaced: true,
                                            onTextChange: { _ in
                                                workspace.draftConnection.syncURIFromFields()
                                            }
                                        )
                                        .frame(width: 160, height: 26)
                                    }
                                }

                                Divider()

                                // Authentication & TLS / Direct Options
                                HStack(spacing: 18) {
                                    Toggle("Require Authentication", isOn: $workspace.draftConnection.authEnabled)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .onChange(of: workspace.draftConnection.authEnabled) { _, _ in
                                            workspace.draftConnection.syncURIFromFields()
                                        }

                                    Toggle("Use TLS / SSL", isOn: $workspace.draftConnection.useTLS)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .onChange(of: workspace.draftConnection.useTLS) { _, _ in
                                            workspace.draftConnection.syncURIFromFields()
                                        }

                                    Toggle("Direct Connection", isOn: $workspace.draftConnection.directConnection)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .help("Bypass replica-set primary redirection (essential for SSH tunnels or port-forwarding)")
                                        .onChange(of: workspace.draftConnection.directConnection) { _, _ in
                                            workspace.draftConnection.syncURIFromFields()
                                        }

                                    Spacer()
                                }

                                if workspace.draftConnection.useTLS {
                                    HStack(spacing: 8) {
                                        Toggle("Allow Self-Signed / Invalid TLS Certificates", isOn: $workspace.draftConnection.tlsAllowInvalidCertificates)
                                            .font(.system(size: 12))
                                            .onChange(of: workspace.draftConnection.tlsAllowInvalidCertificates) { _, _ in
                                                workspace.draftConnection.syncURIFromFields()
                                            }

                                        if workspace.draftConnection.tlsAllowInvalidCertificates {
                                            HStack(spacing: 4) {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .font(.system(size: 10))
                                                Text("TLS certificate verification disabled")
                                                    .font(.system(size: 11, weight: .medium))
                                            }
                                            .foregroundStyle(.orange)
                                        }
                                    }
                                }

                                if workspace.draftConnection.authEnabled {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Username")
                                                .font(.system(size: 11.5, weight: .medium))
                                                .foregroundStyle(.secondary)
                                            NativeTextField(
                                                "Username",
                                                text: $workspace.draftConnection.username,
                                                onTextChange: { _ in
                                                    workspace.draftConnection.syncURIFromFields()
                                                }
                                            )
                                            .frame(height: 26)
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text("Password")
                                                    .font(.system(size: 11.5, weight: .medium))
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                                Button(workspace.showPasswordInManager ? "Hide" : "Show") {
                                                    workspace.showPasswordInManager.toggle()
                                                }
                                                .buttonStyle(.plain)
                                                .font(.system(size: 10.5, weight: .medium))
                                                .foregroundStyle(Color.accentColor)
                                            }
                                            NativeTextField(
                                                "Password",
                                                text: $workspace.draftConnection.password,
                                                isSecure: !workspace.showPasswordInManager,
                                                onTextChange: { _ in
                                                    workspace.draftConnection.syncURIFromFields()
                                                }
                                            )
                                            .frame(height: 26)
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Auth Database")
                                                .font(.system(size: 11.5, weight: .medium))
                                                .foregroundStyle(.secondary)
                                            NativeTextField(
                                                "admin",
                                                text: $workspace.draftConnection.authDatabase,
                                                isMonospaced: true,
                                                onTextChange: { _ in
                                                    workspace.draftConnection.syncURIFromFields()
                                                }
                                            )
                                            .frame(width: 110, height: 26)
                                        }
                                    }
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.primary.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }

                        // Status / Test Result Banner
                        statusBannerView
                    }
                    .padding(24)
                }

                Divider()

                // Bottom Action Bar
                HStack(spacing: 12) {
                    Button {
                        workspace.runDraftConnectionTest()
                    } label: {
                        Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(.bordered)
                    .disabled(workspace.connectionTestStatus == .testing || workspace.isConnecting)

                    Button {
                        let saved = workspace.saveConnection(workspace.draftConnection, preserveExistingFavorites: true)
                        workspace.draftConnection = saved
                        workspace.connectionTestStatus = .success("Connection saved securely.")
                    } label: {
                        Label("Save Connection", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(workspace.isConnecting)

                    Spacer()

                    Button("Cancel") {
                        workspace.cancelConnectionManager()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        let saved = workspace.saveConnection(workspace.draftConnection, preserveExistingFavorites: true)
                        workspace.draftConnection = saved
                        Task {
                            await workspace.connect(to: saved)
                            if let err = workspace.connectionError {
                                workspace.connectionTestStatus = .failure(err)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if workspace.isConnecting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "bolt.fill")
                            }
                            Text("Save & Connect")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(workspace.isConnecting || workspace.connectionTestStatus == .testing)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var statusBannerView: some View {
        switch workspace.connectionTestStatus {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Testing connection to MongoDB server…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .success(let msg):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(msg)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .failure(let err):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(err)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func connectionRow(_ conn: ConnectionConfig) -> some View {
        let isSelected = (!workspace.isEditingNewDraft && workspace.selectedManagerConnectionId == conn.id)
        return HStack(spacing: 10) {
            Circle()
                .fill(EarlgreyTheme.connectionColor(conn.colorName))
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(conn.name)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Text(conn.displayAddress)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
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
        .contextMenu {
            Button("Connect") {
                Task {
                    await workspace.connect(to: conn)
                }
            }
            Button("Duplicate") {
                workspace.duplicateConnection(conn)
            }
        }
    }
}
