import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var replicateKey: String = ""
    @State private var savedKey: String = ""
    @State private var rootFolderPath: String = ""
    @State private var showSaveConfirmation = false
    @State private var showRevertConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            Form {
                Section("API Keys") {
                    SecureField("Replicate API Key", text: $replicateKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: replicateKey) {
                            showSaveConfirmation = false
                        }

                    if replicateKey != savedKey {
                        Button("Save API Key") {
                            do {
                                try KeychainManager.save(key: "replicate_api_key", value: replicateKey)
                                savedKey = replicateKey
                                showSaveConfirmation = true
                                appState.refreshAPIKeyStatus()
                            } catch {
                                appState.statusMessage = "Failed to save API key: \(error.localizedDescription)"
                            }
                        }
                        .disabled(replicateKey.isEmpty)
                    }

                    if showSaveConfirmation {
                        Text("API key saved.")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }

                Section("Generation") {
                    HStack {
                        Text("Parallel request delay")
                        Spacer()
                        Text("\(Int(appState.parallelRequestDelay))s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 30, alignment: .trailing)
                        Stepper("", value: Binding(
                            get: { appState.parallelRequestDelay },
                            set: { appState.parallelRequestDelay = $0 }
                        ), in: 0...30, step: 1)
                        .labelsHidden()
                    }
                    Text("Delay between API calls when generating multiple images with models that don't support batch requests (Gemini).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Thumbnails") {
                    Picker("Max size", selection: Binding(
                        get: { appState.thumbnailMaxPixelSize },
                        set: { newValue in
                            appState.thumbnailMaxPixelSize = newValue
                            appState.migrateThumbnailsIfNeeded()
                        }
                    )) {
                        Text("64 px").tag(64)
                        Text("128 px").tag(128)
                        Text("256 px").tag(256)
                    }
                    Text("Changing this will regenerate all existing thumbnails.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Models") {
                    ForEach(ModelRegistry.shared.generationModels, id: \.id) { model in
                        Toggle(model.displayName, isOn: Binding(
                            get: { !appState.hiddenModels.contains(model.id) },
                            set: { visible in
                                if visible {
                                    appState.hiddenModels.remove(model.id)
                                } else {
                                    appState.hiddenModels.insert(model.id)
                                    if appState.selectedModelID == model.id,
                                       let first = appState.visibleGenerationModels.first {
                                        appState.selectedModelID = first.id
                                        appState.onModelChanged()
                                    }
                                }
                            }
                        ))
                    }
                }

                Section("Custom Models File") {
                    Text(ModelRegistry.shared.hasUserOverride
                         ? "Using your custom Models.json. Entries with matching ids override bundled models; new ids are appended."
                         : "Using bundled models. Click Edit to start a custom Models.json from a copy of the bundled file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let err = ModelRegistry.shared.loadError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 8) {
                        Button("Edit File") {
                            do {
                                try ModelRegistry.shared.openUserFileForEditing()
                            } catch {
                                appState.showToast("Could not open Models.json: \(error.localizedDescription)",
                                                   icon: "xmark.circle", style: .error)
                            }
                        }
                        if ModelRegistry.shared.hasUserOverride {
                            Button("Reveal in Finder") {
                                ModelRegistry.shared.revealUserFileInFinder()
                            }
                        }
                        Button("Reload") {
                            ModelRegistry.shared.reload()
                        }
                        Spacer()
                        if ModelRegistry.shared.hasUserOverride {
                            Button("Revert to Bundled…", role: .destructive) {
                                showRevertConfirmation = true
                            }
                        }
                    }
                }

                Section("Projects Folder") {
                    HStack {
                        Text(rootFolderPath.isEmpty ? "Not set" : rootFolderPath)
                            .foregroundStyle(rootFolderPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.head)

                        Spacer()

                        Button("Choose...") {
                            pickFolder()
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 620, height: 600)
        .onAppear {
            let loaded = KeychainManager.load(key: "replicate_api_key") ?? ""
            replicateKey = loaded
            savedKey = loaded
            rootFolderPath = appState.projectManager.projectsRootURL?.path ?? ""
        }
        .confirmationDialog(
            "Revert to bundled models?",
            isPresented: $showRevertConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Custom File", role: .destructive) {
                do {
                    try ModelRegistry.shared.revertToBundled()
                } catch {
                    appState.showToast("Could not revert: \(error.localizedDescription)",
                                       icon: "xmark.circle", style: .error)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your custom Models.json will be deleted.")
        }
    }

    private func pickFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Choose Projects Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            appState.setProjectsRoot(url)
            rootFolderPath = url.path
        }
        #endif
    }
}
