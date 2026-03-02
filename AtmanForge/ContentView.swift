import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.hasProjectsRoot {
                mainLayout
            } else {
                WelcomeView()
            }
        }
        .overlay(alignment: .top) {
            ToastOverlay()
        }
        .overlay {
            if let progress = appState.thumbnailMigrationProgress {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        Text("Resizing thumbnails...")
                            .font(.headline)
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .transition(.opacity)
            }
        }
        #if os(macOS)
        .quickLookKeyHandler(appState: appState)
        #endif
        .navigationTitle(appState.projectName)
        .sheet(isPresented: Binding(
            get: { appState.showSettings },
            set: { appState.showSettings = $0 }
        )) {
            SettingsView()
        }
    }

    private var mainLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                GenerationSidebar()

                Divider()

                CenterPanelView()
                    .frame(minWidth: 480)

                if appState.selectedImageJob != nil || appState.selectedLibraryImageIDs.count > 1 {
                    Divider()
                    ImageInspectorView()
                }
            }
        }
        .task {
            appState.loadProjects()
        }
        .alert("Remove Images?", isPresented: deleteConfirmationBinding) {
            Button("Remove", role: .destructive) {
                appState.confirmDeleteLibraryImages()
            }
            Button("Remove (Don't Ask Again)", role: .destructive) {
                appState.projectPreferences.skipDeleteConfirmation = true
                appState.saveProjectPreferences()
                appState.confirmDeleteLibraryImages()
            }
            Button("Cancel", role: .cancel) {
                appState.pendingDeleteIDs.removeAll()
            }
        } message: {
            Text("This will permanently delete \(appState.pendingDeleteIDs.count) image\(appState.pendingDeleteIDs.count == 1 ? "" : "s") from disk.")
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { appState.showDeleteConfirmation },
            set: { appState.showDeleteConfirmation = $0 }
        )
    }

}
