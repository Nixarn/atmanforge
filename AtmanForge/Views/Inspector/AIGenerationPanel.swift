import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
#if os(macOS)
import AppKit
#endif

struct AIGenerationPanel: View {
    @Environment(AppState.self) private var appState
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isDropTargeted = false
    @State private var promptDebounceTask: Task<Void, Never>?
    @State private var sketchingReferenceIndex: Int?

    private var model: ModelDefinition? { appState.selectedModel }
    private var maxRefImages: Int { model?.maxReferenceImages ?? 0 }

    var body: some View {
        @Bindable var appState = appState

        VStack(alignment: .leading, spacing: 12) {
            if !appState.hasAPIKey {
                APIKeyBanner(appState: appState)
            }

            Text("Model")
                .font(.headline)

            VStack(spacing: 6) {
                ForEach(appState.visibleGenerationModels, id: \.id) { model in
                    let isSelected = appState.selectedModelID == model.id
                    Button {
                        appState.selectedModelID = model.id
                        appState.onModelChanged()
                    } label: {
                        HStack {
                            Text(model.displayName)
                                .fontWeight(isSelected ? .semibold : .regular)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                        .contentShape(Rectangle())
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                }
            }

            Divider()

            // Reference Images
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Reference Images")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3))
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                        )
                        .frame(minHeight: appState.referenceImages.isEmpty ? 100 : nil)

                    if appState.referenceImages.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text("Drop images here")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(72), spacing: 8), count: 3), spacing: 8) {
                            ForEach(Array(appState.referenceImages.enumerated()), id: \.element.id) { index, reference in
                                ZStack(alignment: .topTrailing) {
                                    ReferenceImageThumbnail(imageData: reference.data)
                                        .aspectRatio(1, contentMode: .fill)
                                        .frame(width: 72, height: 72)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 6))

                                    Button {
                                        appState.removeReferenceImage(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 4, y: -4)
                                }
                                .contextMenu {
                                    #if os(macOS)
                                    Button {
                                        sketchingReferenceIndex = index
                                    } label: {
                                        Label("Sketch", systemImage: "pencil.tip.crop.circle")
                                    }
                                    Button {
                                        pasteFromClipboard()
                                    } label: {
                                        Label("Paste", systemImage: "doc.on.clipboard")
                                    }
                                    #endif
                                }
                            }
                        }
                        .padding(8)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                .contextMenu {
                    #if os(macOS)
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    #endif
                }
                .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers)
                }

                HStack {
                    #if os(macOS)
                    Button {
                        browseForImages()
                    } label: {
                        Label("Browse", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.referenceImages.count >= maxRefImages)
                    #else
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: max(maxRefImages - appState.referenceImages.count, 1),
                        matching: .images
                    ) {
                        Label("Browse", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                    .disabled(appState.referenceImages.count >= maxRefImages)
                    .onChange(of: selectedPhotos) { _, newItems in
                        let epoch = appState.referenceImagesEpoch
                        Task {
                            var newImages: [Data] = []
                            for item in newItems {
                                if let data = try? await item.loadTransferable(type: Data.self) {
                                    newImages.append(data)
                                }
                            }
                            appState.addReferenceImages(newImages, epoch: epoch)
                            selectedPhotos = []
                        }
                    }
                    #endif


                    Spacer()

                    if !appState.referenceImages.isEmpty {
                        Button {
                            appState.clearReferenceImages()
                            appState.commitUndoCheckpoint()
                        } label: {
                            Text("Clear")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }

                    Text("\(appState.referenceImages.count)/\(maxRefImages) max")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $appState.prompt)
                    .font(.body)
                    .frame(minHeight: 60, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Text("Aspect Ratio")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Aspect Ratio", selection: $appState.selectedAspectRatio) {
                    ForEach(model?.aspectRatios ?? [], id: \.self) { ratio in
                        Text(ratio.displayName).tag(ratio)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            if let model, model.supportsResolution {
                HStack {
                    Text("Resolution")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Resolution", selection: $appState.selectedResolution) {
                        ForEach(model.resolutions, id: \.self) { res in
                            Text(res.displayName).tag(res)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            if let model, model.maxImages > 1 {
                HStack {
                    Text("Images")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(appState.imageCount)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { Double(appState.imageCount) },
                            set: { appState.imageCount = Int($0) }
                        ),
                        in: 1...Double(model.maxImages),
                        step: 1
                    )
                    .frame(width: 100)
                }
            }

            if let specs = model?.parameters, !specs.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(specs) { spec in
                        parameterControl(spec)
                    }
                }
            }

            Button {
                appState.generateImage()
            } label: {
                HStack {
                    if appState.runningJobCount > 0 {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(appState.runningJobCount > 0 ? "Generate (\(appState.runningJobCount) running)" : "Generate")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appState.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let error = appState.errorMessage {
                HStack(alignment: .top, spacing: 4) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                    Button {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(error, forType: .string)
                        #else
                        UIPasteboard.general.string = error
                        #endif
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy error message")
                }
            }
        }
        #if os(macOS)
        .sheet(isPresented: Binding(
            get: { sketchingReferenceIndex != nil },
            set: { if !$0 { sketchingReferenceIndex = nil } }
        )) {
            if let index = sketchingReferenceIndex,
               appState.referenceImages.indices.contains(index) {
                SketchEditorView(
                    imageData: appState.referenceImages[index].data,
                    onSave: { newData in
                        appState.replaceReferenceImage(at: index, with: newData)
                        sketchingReferenceIndex = nil
                    },
                    onCancel: {
                        sketchingReferenceIndex = nil
                    }
                )
            }
        }
        #endif
        .onChange(of: appState.prompt) {
            promptDebounceTask?.cancel()
            promptDebounceTask = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                appState.commitUndoCheckpoint()
            }
        }
        .onChange(of: appState.selectedModelID) {
            appState.onModelChanged()
            appState.commitUndoCheckpoint()
        }
        .onChange(of: appState.selectedAspectRatio) {
            appState.commitUndoCheckpoint()
        }
        .onChange(of: appState.selectedResolution) {
            appState.commitUndoCheckpoint()
        }
        .onChange(of: appState.imageCount) {
            appState.commitUndoCheckpoint()
        }
        .onChange(of: appState.parameterValues) {
            appState.commitUndoCheckpoint()
        }
        .onChange(of: appState.referenceImages) {
            appState.commitUndoCheckpoint()
        }
    }

    // MARK: - Generic Parameter Controls

    @ViewBuilder
    private func parameterControl(_ spec: ParameterSpec) -> some View {
        @Bindable var appState = appState

        switch spec.control {
        case .picker:
            HStack {
                Text(spec.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker(spec.label, selection: stringBinding(for: spec)) {
                    ForEach(spec.options ?? [], id: \.self) { option in
                        Text(option.capitalized).tag(option)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

        case .slider:
            VStack(alignment: .leading, spacing: 6) {
                Text(spec.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(doubleBinding(for: spec).wrappedValue, format: .number.precision(.fractionLength(2)))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .leading)
                    Slider(
                        value: doubleBinding(for: spec),
                        in: (spec.min ?? 0)...(spec.max ?? 1),
                        step: spec.step ?? 0.05
                    )
                    .frame(maxWidth: .infinity)
                }
            }

        case .toggle:
            Toggle(spec.label, isOn: boolBinding(for: spec))
                .font(.subheadline)
        }
    }

    private func stringBinding(for spec: ParameterSpec) -> Binding<String> {
        let fallback = spec.defaultValue.stringValue ?? ""
        return Binding(
            get: { appState.parameterValues[spec.key]?.stringValue ?? fallback },
            set: { appState.parameterValues[spec.key] = .string($0) }
        )
    }

    private func doubleBinding(for spec: ParameterSpec) -> Binding<Double> {
        let fallback = spec.defaultValue.doubleValue ?? (spec.min ?? 0)
        return Binding(
            get: { appState.parameterValues[spec.key]?.doubleValue ?? fallback },
            set: { appState.parameterValues[spec.key] = .double($0) }
        )
    }

    private func boolBinding(for spec: ParameterSpec) -> Binding<Bool> {
        let fallback = spec.defaultValue.boolValue ?? false
        return Binding(
            get: { appState.parameterValues[spec.key]?.boolValue ?? fallback },
            set: { appState.parameterValues[spec.key] = .bool($0) }
        )
    }

    #if os(macOS)
    private func browseForImages() {
        let remaining = maxRefImages - appState.referenceImages.count
        guard remaining > 0 else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = remaining > 1
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.title = "Choose Reference Images"

        guard panel.runModal() == .OK else { return }

        var images: [Data] = []
        for url in panel.urls.prefix(remaining) {
            if let data = try? Data(contentsOf: url) {
                images.append(data)
            }
        }
        if !images.isEmpty {
            appState.addReferenceImages(images)
        }
    }

    private func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
              !images.isEmpty else { return }

        var imageDataArray: [Data] = []
        for image in images {
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                imageDataArray.append(pngData)
            }
        }

        if !imageDataArray.isEmpty {
            appState.addReferenceImages(imageDataArray)
        }
    }
    #endif

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let remaining = maxRefImages - appState.referenceImages.count
        guard remaining > 0 else { return false }

        // These loads finish on their own schedule. Stamp the current epoch so a
        // Clear pressed while they're in flight discards them instead of having
        // them reappear in the emptied list.
        let epoch = appState.referenceImagesEpoch

        let providersToProcess = Array(providers.prefix(remaining))
        for provider in providersToProcess {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          let imageData = try? Data(contentsOf: url) else { return }
                    DispatchQueue.main.async {
                        appState.addReferenceImages([imageData], epoch: epoch)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    DispatchQueue.main.async {
                        appState.addReferenceImages([data], epoch: epoch)
                    }
                }
            }
        }
        return true
    }
}

private struct APIKeyBanner: View {
    let appState: AppState

    var body: some View {
        Button {
            appState.showSettings = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "key")
                    .font(.caption)
                Text("API key not set")
                    .font(.caption)
                Spacer()
                Text("Settings")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.yellow.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

/// Displays a downsampled thumbnail of reference image data.
/// Isolated from AppState so its body is not re-evaluated on every state change (e.g., typing).
private struct ReferenceImageThumbnail: View {
    let imageData: Data

    var body: some View {
        if let source = CGImageSourceCreateWithData(imageData as CFData, nil),
           let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceThumbnailMaxPixelSize: 256,
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceCreateThumbnailWithTransform: true,
           ] as CFDictionary) {
            Image(decorative: thumbnail, scale: 1.0)
                .resizable()
                .scaledToFill()
        }
    }
}
