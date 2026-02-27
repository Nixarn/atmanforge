import SwiftUI
#if os(macOS)
import AppKit
import ImageIO
#endif

// MARK: - Cached metadata per library image

struct LibraryImageEntry: Identifiable {
    let id: String            // filename as unique id
    let imagePath: String     // relative: generations/<file>.png
    let thumbPath: String     // relative: .thumbnails/<file>.png
    let fileName: String
    let fileSize: UInt64
    let pixelWidth: Int
    let pixelHeight: Int
    let meta: ImageMeta?
    // Keep job reference for selection / actions
    let job: GenerationJob?
    let imageIndex: Int
    let fileDate: Date

    var prompt: String { meta?.prompt ?? job?.prompt ?? "" }
    var model: AIModel { meta?.model ?? job?.model ?? .gemini25 }
    var createdAt: Date { meta?.createdAt ?? job?.createdAt ?? fileDate }

    var resolutionString: String {
        guard pixelWidth > 0 && pixelHeight > 0 else { return "—" }
        return "\(pixelWidth)×\(pixelHeight)"
    }

    var fileSizeString: String {
        guard fileSize > 0 else { return "—" }
        let mb = Double(fileSize) / (1024 * 1024)
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        }
        let kb = Double(fileSize) / 1024
        return String(format: "%.0f KB", kb)
    }
}

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    var thumbnailMaxSize: CGFloat = 96
    private var projectRoot: URL? {
        appState.projectManager.projectsRootURL
    }

    // MARK: - Build entries from disk + .meta files

    private var allEntries: [LibraryImageEntry] {
        guard let root = projectRoot else { return [] }
        let generationsDir = root.appendingPathComponent("generations")
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(atPath: generationsDir.path) else { return [] }
        let pngFiles = files.filter { $0.hasSuffix(".png") }.sorted()

        // Build a lookup from image path → (job, index) for selection support
        var jobLookup: [String: (GenerationJob, Int)] = [:]
        for job in appState.generationJobs where job.status == .completed {
            for (index, path) in job.savedImagePaths.enumerated() {
                jobLookup[path] = (job, index)
            }
        }

        let entries: [LibraryImageEntry] = pngFiles.compactMap { fileName in
            let relativePath = "generations/\(fileName)"
            let fileURL = generationsDir.appendingPathComponent(fileName)

            // Read metadata from .meta file (cached)
            let meta = appState.projectManager.cachedMeta(forGenerationFile: fileName, inFolder: root)

            // File size
            let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
            let fileSize = attrs?[.size] as? UInt64 ?? 0

            // Pixel dimensions via CGImageSource (lightweight, no full decode)
            var pw = 0
            var ph = 0
            if let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                pw = props[kCGImagePropertyPixelWidth] as? Int ?? 0
                ph = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            }

            let thumbPath = ".thumbnails/\(fileName)"

            // Find matching job for selection
            let match = jobLookup[relativePath]

            let fileDate = attrs?[.modificationDate] as? Date ?? Date()

            return LibraryImageEntry(
                id: fileName,
                imagePath: relativePath,
                thumbPath: thumbPath,
                fileName: fileName,
                fileSize: fileSize,
                pixelWidth: pw,
                pixelHeight: ph,
                meta: meta,
                job: match?.0,
                imageIndex: match?.1 ?? 0,
                fileDate: fileDate
            )
        }

        return sortedEntries(entries)
    }

    private func sortedEntries(_ entries: [LibraryImageEntry]) -> [LibraryImageEntry] {
        let ascending = appState.librarySortAscending

        let sorted: [LibraryImageEntry]
        switch appState.librarySortOrder {
        case .dateAdded:
            sorted = entries.sorted {
                ascending
                    ? $0.createdAt < $1.createdAt
                    : $0.createdAt > $1.createdAt
            }
        case .name:
            sorted = entries.sorted {
                let cmp = $0.fileName.localizedStandardCompare($1.fileName)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        case .model:
            sorted = entries.sorted {
                let cmp = $0.model.displayName.localizedStandardCompare($1.model.displayName)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        case .resolution:
            sorted = entries.sorted {
                let areaA = $0.pixelWidth * $0.pixelHeight
                let areaB = $1.pixelWidth * $1.pixelHeight
                return ascending ? areaA < areaB : areaA > areaB
            }
        case .size:
            sorted = entries.sorted {
                ascending ? $0.fileSize < $1.fileSize : $0.fileSize > $1.fileSize
            }
        }
        return sorted
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if !allEntries.isEmpty {
                if appState.libraryViewMode == .grid {
                    gridHeaderBar
                } else {
                    listColumnHeader
                }
                Divider()
            }

            Group {
                if allEntries.isEmpty {
                    emptyState
                } else if appState.libraryViewMode == .grid {
                    imageGrid
                } else {
                    imageList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        .quickLookKeyHandler(appState: appState)
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
    }

    // MARK: - Grid Header Bar

    private var gridHeaderBar: some View {
        HStack {
            gridSortMenu
            Spacer()
            viewModeToggle
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var gridSortMenu: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                    Button {
                        if appState.librarySortOrder == order {
                            appState.librarySortAscending.toggle()
                        } else {
                            appState.librarySortOrder = order
                            appState.librarySortAscending = (order == .name || order == .model)
                        }
                    } label: {
                        HStack {
                            Text(order.label)
                            if appState.librarySortOrder == order {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text("Sort: \(appState.librarySortOrder.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                appState.librarySortAscending.toggle()
            } label: {
                Image(systemName: appState.librarySortAscending ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var viewModeToggle: some View {
        HStack(spacing: 2) {
            Button {
                appState.libraryViewMode = .grid
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.caption)
                    .foregroundStyle(appState.libraryViewMode == .grid ? .primary : .secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                appState.libraryViewMode = .list
            } label: {
                Image(systemName: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(appState.libraryViewMode == .list ? .primary : .secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - List Column Header

    private var listColumnHeader: some View {
        HStack(spacing: 0) {
            // Thumbnail spacer (48 + 10 spacing)
            Color.clear.frame(width: 58, height: 1)

            columnHeaderButton(.name, minWidth: 80)
            plainColumnHeader("Prompt", minWidth: 100)
            columnHeaderButton(.model, minWidth: 70)
            columnHeaderButton(.resolution, minWidth: 70)
            columnHeaderButton(.size, minWidth: 56)
            columnHeaderButton(.dateAdded, minWidth: 70)

            // View mode toggle on the right
            Spacer().frame(width: 4)
            viewModeToggle
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func columnHeaderButton(_ order: LibrarySortOrder, minWidth: CGFloat) -> some View {
        let isActive = appState.librarySortOrder == order

        return Button {
            if isActive {
                appState.librarySortAscending.toggle()
            } else {
                appState.librarySortOrder = order
                // Text fields default ascending, numeric/date fields default descending
                switch order {
                case .name, .model:
                    appState.librarySortAscending = true
                case .resolution, .size, .dateAdded:
                    appState.librarySortAscending = false
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(order.label)
                    .font(.caption2)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)

                if isActive {
                    Image(systemName: appState.librarySortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minWidth: minWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func plainColumnHeader(_ title: String, minWidth: CGFloat) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minWidth: minWidth)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No images yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Generated images will appear here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Selection Handling

    private func handleTap(entry: LibraryImageEntry, commandDown: Bool, shiftDown: Bool, entries: [LibraryImageEntry]) {
        if commandDown {
            appState.toggleLibraryImageSelection(entry.id, entry: entry)
        } else if shiftDown {
            appState.selectLibraryImageRange(to: entry.id, entries: entries)
        } else {
            appState.selectLibraryImage(entry.id, entry: entry)
        }
    }

    private func isEntrySelected(_ entry: LibraryImageEntry) -> Bool {
        appState.selectedLibraryImageIDs.contains(entry.id)
    }

    // MARK: - Grid View

    private var imageGrid: some View {
        let entries = allEntries
        return ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: thumbnailMaxSize), spacing: 8)],
                spacing: 8
            ) {
                ForEach(entries) { entry in
                    if let root = projectRoot {
                        let savedURL = root.appendingPathComponent(entry.imagePath)
                        let isSelected = isEntrySelected(entry)
                        let aspectRatio = entry.meta?.aspectRatio ?? entry.job?.aspectRatio ?? .r1_1

                        gridThumbnail(
                            entry: entry,
                            url: root.appendingPathComponent(entry.thumbPath),
                            aspectRatio: aspectRatio,
                            isSelected: isSelected,
                            savedImageURL: savedURL,
                            entries: entries
                        )
                    }
                }
            }
            .padding(12)
        }
    }

    private func gridThumbnail(entry: LibraryImageEntry, url: URL, aspectRatio: AspectRatio, isSelected: Bool, savedImageURL: URL?, entries: [LibraryImageEntry]) -> some View {
        let maxDim = thumbnailMaxSize
        let (w, h) = aspectRatio.ratio
        let thumbWidth: CGFloat
        let thumbHeight: CGFloat
        if w >= h {
            thumbWidth = maxDim
            thumbHeight = maxDim * CGFloat(h) / CGFloat(w)
        } else {
            thumbHeight = maxDim
            thumbWidth = maxDim * CGFloat(w) / CGFloat(h)
        }

        let selectedCount = appState.selectedLibraryImageIDs.count
        let isMulti = selectedCount > 1 && appState.selectedLibraryImageIDs.contains(entry.id)

        // Build list of selected image URLs for multi-select "Add to Reference"
        let multiURLs: [URL]?
        if isMulti, let root = projectRoot {
            multiURLs = appState.selectedLibraryImageIDs.map { fileName in
                root.appendingPathComponent("generations/\(fileName)")
            }
        } else {
            multiURLs = nil
        }

        return ThumbnailHoverView(
            url: url,
            width: thumbWidth,
            height: thumbHeight,
            isSelected: isSelected,
            savedImageURL: savedImageURL,
            onTap: { cmd, shift in
                handleTap(entry: entry, commandDown: cmd, shiftDown: shift, entries: entries)
            },
            onPreview: {
                #if os(macOS)
                if let savedImageURL { QuickLookController.shared.preview(url: savedImageURL) }
                #endif
            },
            extraContextMenu: {
                AnyView(gridContextMenuExtra(entry: entry, selectedCount: selectedCount))
            },
            multiSelectedImageURLs: multiURLs
        )
    }

    @ViewBuilder
    private func gridContextMenuExtra(entry: LibraryImageEntry, selectedCount: Int) -> some View {
        Divider()
        if selectedCount > 1 && appState.selectedLibraryImageIDs.contains(entry.id) {
            Button(role: .destructive) {
                appState.requestDeleteLibraryImages(appState.selectedLibraryImageIDs)
            } label: {
                Label("Remove \(selectedCount) Images", systemImage: "trash")
            }
        } else {
            Button(role: .destructive) {
                appState.requestDeleteLibraryImages([entry.id])
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    // MARK: - List View

    private var imageList: some View {
        let entries = allEntries
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    if let root = projectRoot {
                        let savedURL = root.appendingPathComponent(entry.imagePath)
                        let isSelected = isEntrySelected(entry)

                        listRow(entry: entry, root: root, isSelected: isSelected, savedImageURL: savedURL, entries: entries)
                    }
                }
            }
        }
    }

    private func listRow(entry: LibraryImageEntry, root: URL, isSelected: Bool, savedImageURL: URL?, entries: [LibraryImageEntry]) -> some View {
        let thumbURL = root.appendingPathComponent(entry.thumbPath)

        return HStack(spacing: 0) {
            listThumbnail(url: thumbURL, savedImageURL: savedImageURL)
                .padding(.trailing, 10)

            Text(entry.fileName)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minWidth: 80)

            Text(entry.prompt)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minWidth: 100)

            Text(entry.model.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minWidth: 70)

            Text(entry.resolutionString)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minWidth: 70)

            Text(entry.fileSizeString)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minWidth: 56)

            Text(dateLabel(for: entry.createdAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minWidth: 70)

            // Spacer matching view mode toggle width
            Color.clear.frame(width: 54, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            #if os(macOS)
            let flags = NSEvent.modifierFlags
            let cmd = flags.contains(.command)
            let shift = flags.contains(.shift)
            #else
            let cmd = false
            let shift = false
            #endif
            handleTap(entry: entry, commandDown: cmd, shiftDown: shift, entries: entries)
        }
        .contextMenu {
            listContextMenu(entry: entry, savedImageURL: savedImageURL)
        }
    }

    private func updateHoveredPreviewURL(isHovered: Bool, previewURL: URL?) {
        guard let previewURL else { return }
        if isHovered {
            appState.hoveredPreviewURL = previewURL
            #if os(macOS)
            QuickLookController.shared.updateIfVisible(url: previewURL)
            #endif
        } else if appState.hoveredPreviewURL == previewURL {
            appState.hoveredPreviewURL = nil
        }
    }

    private func listThumbnail(url: URL, savedImageURL: URL?) -> some View {
        Group {
            #if os(macOS)
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .onHover { isHovered in
                        updateHoveredPreviewURL(isHovered: isHovered, previewURL: savedImageURL)
                    }
            } else {
                placeholderThumb
            }
            #else
            if let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                placeholderThumb
            }
            #endif
        }
    }

    private var placeholderThumb: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 48, height: 48)
    }

    private func dateLabel(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func listContextMenu(entry: LibraryImageEntry, savedImageURL: URL?) -> some View {
        if let fileURL = savedImageURL {
            let selectedCount = appState.selectedLibraryImageIDs.count
            let isMulti = selectedCount > 1 && appState.selectedLibraryImageIDs.contains(entry.id)

            #if os(macOS)
            Button {
                QuickLookController.shared.preview(url: fileURL)
            } label: {
                Label("Preview", systemImage: "eye")
            }
            #endif

            Button {
                #if os(macOS)
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                #endif
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }

            #if os(macOS)
            Button {
                appState.exportSelectedImages()
            } label: {
                Label(isMulti ? "Export \(selectedCount) Images" : "Export", systemImage: "square.and.arrow.up")
            }
            #endif

            Divider()

            if isMulti, let root = projectRoot {
                Button {
                    var allData: [Data] = []
                    for fileName in appState.selectedLibraryImageIDs {
                        let url = root.appendingPathComponent("generations/\(fileName)")
                        if let data = try? Data(contentsOf: url) {
                            allData.append(data)
                        }
                    }
                    appState.addReferenceImages(allData)
                } label: {
                    Label("Add \(selectedCount) to Reference", systemImage: "photo.on.rectangle.angled")
                }
            } else {
                Button {
                    if let data = try? Data(contentsOf: fileURL) {
                        appState.addReferenceImages([data])
                    }
                } label: {
                    Label("Add to Reference", systemImage: "photo.on.rectangle.angled")
                }

                Button {
                    appState.prompt = ""
                    appState.referenceImages.removeAll()
                    if let data = try? Data(contentsOf: fileURL) {
                        appState.addReferenceImages([data])
                    }
                    appState.commitUndoCheckpoint()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }

            Divider()

            if isMulti {
                Button(role: .destructive) {
                    appState.requestDeleteLibraryImages(appState.selectedLibraryImageIDs)
                } label: {
                    Label("Remove \(selectedCount) Images", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    appState.requestDeleteLibraryImages([entry.id])
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}
