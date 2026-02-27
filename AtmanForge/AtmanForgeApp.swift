import SwiftUI
import UserNotifications

@main
struct AtmanForgeApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    appState.unseenCompletionCount = 0
                    NSApplication.shared.dockTile.badgeLabel = ""
                }
        }
        .commands {
            ProjectCommands(appState: appState)
            CommandGroup(replacing: .appInfo) {
                Button("About AtmanForge") {
                    let credits = NSMutableAttributedString()
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center

                    credits.append(NSAttributedString(
                        string: "MIT License \u{00A9} Turbo Lynx Oy\n",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 11),
                            .foregroundColor: NSColor.labelColor,
                            .paragraphStyle: style
                        ]
                    ))
                    credits.append(NSAttributedString(
                        string: "@nixarn",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 11),
                            .link: URL(string: "https://x.com/nixarn")!,
                            .paragraphStyle: style
                        ]
                    ))

                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .credits: credits
                    ])
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appState.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { appState.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!appState.canUndo)
                Button("Redo") { appState.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!appState.canRedo)
            }
        }

    }
}

struct ProjectCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandMenu("Project") {
            Button("New Project...") {
                appState.showNewProjectAlert = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open Project...") {
                openProjectFolder()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("New Canvas...") {
                appState.showNewCanvasAlert = true
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(!appState.hasProjectsRoot || appState.selectedProjectID == nil)

            Divider()

            #if os(macOS)
            Button("Export Image...") {
                appState.exportSelectedImages()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(appState.selectedImageJob == nil && appState.selectedLibraryImageIDs.isEmpty)
            #endif

            Divider()

            Button("Close Project") {
                appState.closeProject()
            }
            .disabled(!appState.hasProjectsRoot)
        }
    }

    private func openProjectFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Open Projects Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            appState.openProject(url: url)
        }
        #endif
    }
}
