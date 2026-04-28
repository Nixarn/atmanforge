import SwiftUI
#if os(macOS)
import AppKit
#endif

struct HorizontalClipShape: Shape {
    var clipFromX: CGFloat

    var animatableData: CGFloat {
        get { clipFromX }
        set { clipFromX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: clipFromX, y: 0, width: rect.width - clipFromX, height: rect.height))
    }
}

struct ComparisonOverlayView<MenuContent: View>: View {
    let referenceURL: URL
    let generatedURL: URL
    var initialPosition: CGFloat = 0.0
    let contextMenuActions: () -> MenuContent

    @State private var position: CGFloat = 0.0
    @State private var refImage: NSImage?
    @State private var genImage: NSImage?

    var body: some View {
        GeometryReader { geo in
            let dividerX = geo.size.width * position

            if let ref = refImage, let gen = genImage {
                ZStack(alignment: .leading) {
                    Image(nsImage: ref)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                    Image(nsImage: gen)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .clipShape(HorizontalClipShape(clipFromX: dividerX))

                    // Divider line + handle
                    ZStack {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: geo.size.height)
                            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 0)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 32, height: 32)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.black.opacity(0.15), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 0)
                            .overlay {
                                Image(systemName: "arrow.left.and.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.gray)
                            }
                    }
                    .position(x: dividerX, y: geo.size.height / 2)
                    .allowsHitTesting(false)
                }
                .drawingGroup()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            position = min(max(value.location.x / geo.size.width, 0), 1)
                        }
                )
                .contextMenu {
                    contextMenuActions()
                }
            }
        }
        .aspectRatio(contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            position = initialPosition
            loadImages()
        }
        .onChange(of: referenceURL) { loadImages() }
        .onChange(of: generatedURL) { loadImages() }
    }

    private func loadImages() {
        refImage = NSImage(contentsOf: referenceURL)
        genImage = NSImage(contentsOf: generatedURL)
    }
}

struct ImageInspectorView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedReferenceIndex: Int = 0
    @State private var comparisonActive: Bool = false
    @State private var comparisonViewID: UUID = UUID()
    @State private var showRequestDetails: Bool = false

    private var job: GenerationJob? {
        appState.selectedImageJob
    }

    private var imageIndex: Int {
        appState.selectedImageIndex
    }

    private var projectRoot: URL? {
        appState.projectManager.projectsRootURL
    }

    private var isMultiSelection: Bool {
        appState.selectedLibraryImageIDs.count > 1
    }

    var body: some View {
        Group {
            if isMultiSelection {
                multiSelectionView
            } else if let job = job {
                VStack(spacing: 0) {
                    header
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            comparisonImageView(job)
                            referenceImageThumbnails(job)
                            metadataSection(job)
                            if showRequestDetails, let params = job.requestParamsJSON, !params.isEmpty {
                                ScrollView(.vertical) {
                                    Text(params)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 120)
                                .padding(8)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            Spacer()
                            actionButtons(job)
                        }
                        .padding(16)
                    }
                    .scrollIndicators(.never)
                }
                .frame(width: 320)
                #if os(macOS)
                .background(Color(nsColor: .windowBackgroundColor))
                #else
                .background(Color(uiColor: .systemBackground))
                #endif
                .onChange(of: appState.selectedImageJob?.id) { _, _ in
                    selectedReferenceIndex = 0
                    comparisonActive = false
                    comparisonViewID = UUID()
                }
                .onChange(of: appState.selectedImageIndex) { _, _ in
                    selectedReferenceIndex = 0
                    comparisonActive = false
                    comparisonViewID = UUID()
                }
            }
        }
        #if os(macOS)
        .quickLookKeyHandler(appState: appState)
        #endif
    }

    // MARK: - Multi-Selection View

    private var multiSelectionView: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    multiSelectionSummary
                    multiSelectionActions
                }
                .padding(16)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 320)
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
    }

    private var multiSelectionSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("\(appState.selectedLibraryImageIDs.count) Images Selected")
                    .font(.headline)
            }

            if let root = projectRoot {
                let totalSize = computeTotalFileSize(root: root)
                if totalSize > 0 {
                    metadataRow("Total Size", value: formatBytes(totalSize))
                }
            }
        }
    }

    private func computeTotalFileSize(root: URL) -> UInt64 {
        let fm = FileManager.default
        var total: UInt64 = 0
        for fileName in appState.selectedLibraryImageIDs {
            let fileURL = root.appendingPathComponent("generations/\(fileName)")
            if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? UInt64 {
                total += size
            }
        }
        return total
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        }
        let kb = Double(bytes) / 1024
        return String(format: "%.0f KB", kb)
    }

    private var multiSelectionActions: some View {
        VStack(spacing: 8) {
            Divider()
            #if os(macOS)
            Button {
                appState.exportSelectedImages()
            } label: {
                Label("Export Selected", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            #endif
            Button(role: .destructive) {
                appState.requestDeleteLibraryImages(appState.selectedLibraryImageIDs)
            } label: {
                Label("Remove Selected", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Text("Inspector")
                    .font(.headline)
                if let params = appState.selectedImageJob?.requestParamsJSON, !params.isEmpty {
                    Button {
                        showRequestDetails.toggle()
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help(showRequestDetails ? "Hide request" : "Show request")
                }
            }
            Spacer()
            Button {
                appState.clearImageSelection()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func comparisonImageView(_ job: GenerationJob) -> some View {
        if job.referenceImagePaths.isEmpty || job.model?.kind == .backgroundRemoval {
            fullImage(job)
        } else {
            comparisonSlider(job)
        }
    }

    @ViewBuilder
    private func comparisonSlider(_ job: GenerationJob) -> some View {
        if imageIndex < job.savedImagePaths.count, let root = projectRoot {
            let generatedURL = root.appendingPathComponent(job.savedImagePaths[imageIndex])
            let safeRefIndex = min(selectedReferenceIndex, job.referenceImagePaths.count - 1)
            let referenceURL = root.appendingPathComponent(job.referenceImagePaths[max(0, safeRefIndex)])

            ComparisonOverlayView(
                referenceURL: referenceURL,
                generatedURL: generatedURL,
                initialPosition: comparisonActive ? 0.5 : 0.0,
                contextMenuActions: { imageContextMenu(imageURL: generatedURL) }
            )
            .id(comparisonViewID)
            .onHover { isHovered in
                updateHoveredPreviewURL(isHovered: isHovered, previewURL: generatedURL)
            }
        }
    }

    @ViewBuilder
    private func referenceImageThumbnails(_ job: GenerationJob) -> some View {
        if !job.referenceImagePaths.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Reference Images")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        comparisonActive = true
                        comparisonViewID = UUID()
                    } label: {
                        Text("Compare")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(job.referenceImagePaths.enumerated()), id: \.offset) { index, path in
                            if let root = projectRoot {
                                let url = root.appendingPathComponent(path)
                                referenceThumbnail(url: url, isSelected: index == selectedReferenceIndex)
                                    .onTapGesture {
                                        selectedReferenceIndex = index
                                    }
                            }
                        }
                    }
                }
            }
        }
    }

    private func updateHoveredPreviewURL(isHovered: Bool, previewURL: URL) {
        if isHovered {
            appState.hoveredPreviewURL = previewURL
            #if os(macOS)
            QuickLookController.shared.updateIfVisible(url: previewURL)
            #endif
        } else if appState.hoveredPreviewURL == previewURL {
            appState.hoveredPreviewURL = nil
        }
    }

    @ViewBuilder
    private func referenceThumbnail(url: URL, isSelected: Bool) -> some View {
        #if os(macOS)
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .onHover { isHovered in
                    updateHoveredPreviewURL(isHovered: isHovered, previewURL: url)
                }
        }
        #else
        if let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        #endif
    }

    @ViewBuilder
    private func fullImage(_ job: GenerationJob) -> some View {
        if imageIndex < job.savedImagePaths.count, let root = projectRoot {
            let imageURL = root.appendingPathComponent(job.savedImagePaths[imageIndex])
            #if os(macOS)
            if let nsImage = NSImage(contentsOf: imageURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(checkerboard)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onDrag {
                        NSItemProvider(contentsOf: imageURL) ?? NSItemProvider()
                    }
                    .contextMenu {
                        imageContextMenu(imageURL: imageURL)
                    }
                    .onHover { isHovered in
                        updateHoveredPreviewURL(isHovered: isHovered, previewURL: imageURL)
                    }
            }
            #else
            if let data = try? Data(contentsOf: imageURL), let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(checkerboard)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onDrag {
                        NSItemProvider(contentsOf: imageURL) ?? NSItemProvider()
                    }
                    .contextMenu {
                        imageContextMenu(imageURL: imageURL)
                    }
            }
            #endif
        }
    }

    private var checkerboard: some View {
        Image(decorative: Self.checkerboardTile, scale: 1.0)
            .resizable(resizingMode: .tile)
    }

    private static let checkerboardTile: CGImage = {
        let sq = 8
        let size = sq * 2
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Light squares
        ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: sq, height: sq))
        ctx.fill(CGRect(x: sq, y: sq, width: sq, height: sq))
        // Dark squares
        ctx.setFillColor(CGColor(gray: 0.75, alpha: 1))
        ctx.fill(CGRect(x: sq, y: 0, width: sq, height: sq))
        ctx.fill(CGRect(x: 0, y: sq, width: sq, height: sq))
        return ctx.makeImage()!
    }()

    @ViewBuilder
    private func imageContextMenu(imageURL: URL) -> some View {
        #if os(macOS)
        Button {
            QuickLookController.shared.preview(url: imageURL)
        } label: {
            Label("Preview", systemImage: "eye")
        }

        Button {
            NSWorkspace.shared.activateFileViewerSelecting([imageURL])
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }

        Button {
            appState.exportSelectedImages()
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }

        Divider()
        #endif

        Button {
            if let data = try? Data(contentsOf: imageURL) {
                appState.addReferenceImages([data])
            }
        } label: {
            Label("Add to Reference", systemImage: "photo.on.rectangle.angled")
        }

        Button {
            appState.prompt = ""
            appState.referenceImages.removeAll()
            if let data = try? Data(contentsOf: imageURL) {
                appState.addReferenceImages([data])
            }
            appState.commitUndoCheckpoint()
        } label: {
            Label("Edit", systemImage: "pencil")
        }
    }

    private func metadataSection(_ job: GenerationJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details")
                .font(.subheadline)
                .fontWeight(.semibold)

            metadataRow("Model", value: job.displayName)
            metadataRow("Aspect Ratio", value: job.aspectRatio.displayName)

            if imageIndex < job.savedImagePaths.count, let root = projectRoot {
                let imageURL = root.appendingPathComponent(job.savedImagePaths[imageIndex])
                if let dimensions = imageSize(url: imageURL) {
                    metadataRow("Resolution", value: "\(dimensions.width) × \(dimensions.height)")
                }
                if let size = fileSize(url: imageURL) {
                    metadataRow("File Size", value: size)
                }
            }

            metadataRow("Created", value: formattedDate(job.createdAt))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(job.prompt, forType: .string)
                        #else
                        UIPasteboard.general.string = job.prompt
                        #endif
                        appState.showToast("Prompt copied", icon: "doc.on.doc")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy prompt")
                }
                Text(job.prompt)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    private func actionButtons(_ job: GenerationJob) -> some View {
        VStack(spacing: 8) {
            Divider()

            VStack(spacing: 6) {
                Button {
                    guard imageIndex < job.savedImagePaths.count, let root = projectRoot else { return }
                    let imageURL = root.appendingPathComponent(job.savedImagePaths[imageIndex])
                    guard let data = try? Data(contentsOf: imageURL) else { return }
                    appState.prompt = ""
                    appState.referenceImages.removeAll()
                    appState.addReferenceImages([data])
                    appState.commitUndoCheckpoint()
                } label: {
                    Label("Edit Image", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button {
                    appState.removeBackground(job: job, imageIndex: imageIndex)
                } label: {
                    HStack {
                        if appState.isRemovingBackground {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Label("Remove Background", systemImage: "person.and.background.dotted")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(appState.isRemovingBackground || job.model?.kind == .backgroundRemoval)

                Button {
                    appState.loadSettings(from: job)
                } label: {
                    Label("Retry", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    appState.loadSettingsCompatible(from: job)
                } label: {
                    Label("Reuse Parameters", systemImage: "doc.text.image")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                #if os(macOS)
                Button {
                    appState.exportSelectedImages()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    guard imageIndex < job.savedImagePaths.count, let root = projectRoot else { return }
                    let imageURL = root.appendingPathComponent(job.savedImagePaths[imageIndex])
                    NSWorkspace.shared.activateFileViewerSelecting([imageURL])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                #endif
            }
        }
    }

    private func imageSize(url: URL) -> (width: Int, height: Int)? {
        #if os(macOS)
        guard let image = NSImage(contentsOf: url),
              let rep = image.representations.first else { return nil }
        return (rep.pixelsWide, rep.pixelsHigh)
        #else
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        return (Int(image.size.width * image.scale), Int(image.size.height * image.scale))
        #endif
    }

    private func fileSize(url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? Int64 else { return nil }
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

