import SwiftUI
import AppKit

public final class EarlgreyAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
public struct MongoEarlgreyApp: App {
    @NSApplicationDelegateAdaptor(EarlgreyAppDelegate.self) private var appDelegate
    @StateObject private var workspace = WorkspaceViewModel()

    public init() {}

    public var body: some Scene {
        WindowGroup("Mongo Earlgrey") {
            MainWindowView(workspace: workspace)
                .preferredColorScheme(.dark)
                .frame(minWidth: 980, idealWidth: 1280, minHeight: 640, idealHeight: 800)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save Document") {
                    if let tab = workspace.activeTab, tab.isInspectorVisible, !tab.isSavingDocument {
                        Task {
                            await workspace.saveEditorDocument(in: tab)
                        }
                    }
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(workspace.activeTab == nil)

                Divider()

                Button("Close Active Tab") {
                    if let id = workspace.selectedTabId {
                        workspace.closeTab(id)
                    } else {
                        NSApp.keyWindow?.performClose(nil)
                    }
                }
                .keyboardShortcut("w", modifiers: [.command])
            }

            CommandGroup(after: .textEditing) {
                Divider()

                Button("Find in Document…") {
                    workspace.activeTab?.openFindInEditor()
                }
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(workspace.activeTab == nil)

                Button("Find Next") {
                    workspace.activeTab?.jumpToNextFindMatch()
                }
                .keyboardShortcut("g", modifiers: [.command])
                .disabled(workspace.activeTab == nil)

                Button("Find Previous") {
                    workspace.activeTab?.jumpToPreviousFindMatch()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(workspace.activeTab == nil)
            }

            CommandMenu("Connection") {
                Button("New Connection…") {
                    workspace.startCreatingNewConnection()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Connection Manager…") {
                    workspace.openConnectionManager(for: workspace.activeConnection)
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Refresh Databases & Collections") {
                    Task {
                        await workspace.refreshDatabases()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(workspace.activeConnection == nil)

                Divider()

                Button("Disconnect") {
                    Task {
                        await workspace.disconnect()
                    }
                }
                .disabled(workspace.activeConnection == nil)
            }

            CommandMenu("Query") {
                Button("Run Query") {
                    if let tab = workspace.activeTab {
                        tab.pageSkip = 0
                        Task {
                            await workspace.runQuery(for: tab)
                        }
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(workspace.activeTab == nil)

                Button("Reset Query to Default") {
                    if let tab = workspace.activeTab {
                        tab.queryText = "db.getCollection(\"\(tab.collection)\").find({})"
                        tab.pageSkip = 0
                        Task {
                            await workspace.runQuery(for: tab)
                        }
                    }
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
                .disabled(workspace.activeTab == nil)

                Divider()

                Button("New Document…") {
                    if let tab = workspace.activeTab,
                       workspace.confirmDiscardUnsavedChangesIfNeeded(in: tab) {
                        tab.startNewDocument()
                    }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(workspace.activeTab == nil)
            }
        }
    }
}
