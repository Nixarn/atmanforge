import SwiftUI
import UserNotifications

enum CenterTab: String, CaseIterable {
    case activity
    case library
}

enum LibrarySortOrder: String, CaseIterable {
    case name, model, resolution, size, dateAdded

    var label: String {
        switch self {
        case .name: return "Name"
        case .model: return "Model"
        case .resolution: return "Resolution"
        case .size: return "Size"
        case .dateAdded: return "Date Added"
        }
    }
}

enum LibraryViewMode: String, CaseIterable {
    case grid, list
}

/// A reference image plus a stable identity. The grid used to key thumbnails by
/// array index, which made removing one animate as though the *last* had gone.
struct ReferenceImage: Identifiable, Equatable {
    let id: UUID
    let data: Data

    init(data: Data) {
        self.id = UUID()
        self.data = data
    }
}

struct GenerationParamsSnapshot: Equatable {
    let prompt: String
    let selectedModelID: String
    let selectedResolution: ImageResolution
    let selectedAspectRatio: AspectRatio
    let imageCount: Int
    let referenceImages: [ReferenceImage]
    let parameterValues: [String: ParameterValue]
}

@MainActor
@Observable
class AppState {
    // MARK: - Data
    var projects: [Project] = []

    // MARK: - Selection
    var selectedProjectID: String?
    var selectedCanvasID: String?

    // MARK: - UI State
    var isGenerating = false
    var statusMessage = "Ready"
    var selectedCenterTab: CenterTab = .activity
    var activityThumbnailSize: CGFloat = 64
    var libraryThumbnailSize: CGFloat = 96
    var selectedTool: CanvasTool = .select
    var canvasZoom: CGFloat = 1.0
    var canvasOffset: CGSize = .zero
    var imageVersion = 0
    var showSettings = false
    var errorMessage: String?
    var projectSizeText: String = ""
    var hoveredPreviewURL: URL?
    var librarySortOrder: LibrarySortOrder = .dateAdded
    var librarySortAscending: Bool = false
    var libraryViewMode: LibraryViewMode = .grid

    // MARK: - Image Inspector
    var selectedImageJob: GenerationJob?
    var selectedImageIndex: Int = 0
    var isRemovingBackground = false
    var toasts: [AppToast] = []
    var unseenCompletionCount = 0

    // MARK: - Library Multi-Selection
    var selectedLibraryImageIDs: Set<String> = []
    var showDeleteConfirmation = false
    var pendingDeleteIDs: Set<String> = []
    var projectPreferences = ProjectPreferences()

    // MARK: - App Settings
    var hasAPIKey: Bool = false

    var parallelRequestDelay: TimeInterval {
        get { UserDefaults.standard.object(forKey: "parallelRequestDelay") as? TimeInterval ?? 5.0 }
        set { UserDefaults.standard.set(newValue, forKey: "parallelRequestDelay") }
    }

    var thumbnailMaxPixelSize: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: "thumbnailMaxPixelSize")
            return stored > 0 ? stored : 128
        }
        set { UserDefaults.standard.set(newValue, forKey: "thumbnailMaxPixelSize") }
    }

    var thumbnailMigrationProgress: Double?

    var hiddenModels: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hiddenModels") ?? []) {
        didSet { UserDefaults.standard.set(Array(hiddenModels), forKey: "hiddenModels") }
    }

    var visibleGenerationModels: [ModelDefinition] {
        ModelRegistry.shared.generationModels.filter { !hiddenModels.contains($0.id) }
    }

    var selectedModel: ModelDefinition? {
        ModelRegistry.shared.model(id: selectedModelID)
    }

    // MARK: - AI Generation
    var prompt = ""
    var selectedModelID: String = "gemini-2.5"
    var selectedResolution: ImageResolution = .r2k
    var selectedAspectRatio: AspectRatio = .r1_1
    var imageCount: Int = 1
    var referenceImages: [ReferenceImage] = []
    var parameterValues: [String: ParameterValue] = [:]

    // MARK: - Undo/Redo
    var undoStack: [GenerationParamsSnapshot] = []
    var redoStack: [GenerationParamsSnapshot] = []
    var lastCommittedSnapshot: GenerationParamsSnapshot?
    var isRestoringSnapshot = false

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Jobs
    var generationJobs: [GenerationJob] = []
    var activeJobID: UUID?

    // MARK: - Services
    let projectManager = ProjectManager.shared

    // MARK: - Computed

    var hasProjectsRoot: Bool

    init() {
        hasProjectsRoot = ProjectManager.shared.projectsRootURL != nil

        // Until the user touches Settings -> Models, follow the registry's
        // defaults. Setting this in init doesn't fire didSet, so nothing is
        // written to UserDefaults; the first manual toggle writes the key and
        // from then on the user's choice wins.
        if UserDefaults.standard.object(forKey: "hiddenModels") == nil {
            hiddenModels = ModelRegistry.shared.defaultHiddenModelIDs
        }
        if !visibleGenerationModels.contains(where: { $0.id == selectedModelID }),
           let first = visibleGenerationModels.first {
            selectedModelID = first.id
        }
        onModelChanged()

        lastCommittedSnapshot = currentSnapshot()
        refreshAPIKeyStatus()
    }

    func refreshAPIKeyStatus() {
        let key = KeychainManager.load(key: "replicate_api_key")
        hasAPIKey = key != nil && !key!.isEmpty
    }

    var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    var selectedCanvas: Canvas? {
        guard let projectID = selectedProjectID,
              let canvasID = selectedCanvasID,
              let project = projects.first(where: { $0.id == projectID }) else {
            return nil
        }
        return project.canvases.first { $0.id == canvasID }
    }

    var projectName: String {
        projectManager.projectsRootURL?.lastPathComponent ?? "AtmanForge"
    }

    var runningJobCount: Int {
        generationJobs.filter { $0.status == .running || $0.status == .pending }.count
    }

    // MARK: - Model Changed

    func onModelChanged() {
        guard let model = selectedModel else { return }

        if imageCount > model.maxImages {
            imageCount = model.maxImages
        }
        if referenceImages.count > model.maxReferenceImages {
            referenceImages = Array(referenceImages.prefix(model.maxReferenceImages))
        }
        if !model.aspectRatios.contains(selectedAspectRatio) {
            selectedAspectRatio = model.aspectRatios.first ?? .r1_1
        }
        if !model.resolutions.isEmpty,
           !model.resolutions.contains(selectedResolution),
           let lowest = model.resolutions.first {
            selectedResolution = lowest
        }
        for spec in model.parameters where parameterValues[spec.key] == nil {
            parameterValues[spec.key] = spec.defaultValue
        }
    }

    // MARK: - Undo/Redo

    func currentSnapshot() -> GenerationParamsSnapshot {
        GenerationParamsSnapshot(
            prompt: prompt,
            selectedModelID: selectedModelID,
            selectedResolution: selectedResolution,
            selectedAspectRatio: selectedAspectRatio,
            imageCount: imageCount,
            referenceImages: referenceImages,
            parameterValues: parameterValues
        )
    }

    func commitUndoCheckpoint() {
        guard !isRestoringSnapshot else { return }
        let current = currentSnapshot()
        guard let last = lastCommittedSnapshot, last != current else { return }
        undoStack.append(last)
        if undoStack.count > 30 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        lastCommittedSnapshot = current
    }

    func undo() {
        commitUndoCheckpoint()
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        restore(snapshot)
    }

    private func restore(_ snapshot: GenerationParamsSnapshot) {
        isRestoringSnapshot = true
        prompt = snapshot.prompt
        selectedModelID = snapshot.selectedModelID
        selectedResolution = snapshot.selectedResolution
        selectedAspectRatio = snapshot.selectedAspectRatio
        imageCount = snapshot.imageCount
        referenceImages = snapshot.referenceImages
        parameterValues = snapshot.parameterValues
        lastCommittedSnapshot = snapshot
        isRestoringSnapshot = false
    }

    /// Incremented whenever the reference list is emptied. Drops load their
    /// images asynchronously, so a load that started before a clear must not
    /// repopulate the list after it.
    private(set) var referenceImagesEpoch = 0

    /// Empties the reference list and invalidates any drop still in flight.
    /// Callers that want this to be undoable follow it with `commitUndoCheckpoint()`.
    func clearReferenceImages() {
        referenceImages.removeAll()
        referenceImagesEpoch &+= 1
    }

    /// - Parameter epoch: the value of `referenceImagesEpoch` when the work that
    ///   produced `images` began. Pass it from anything asynchronous; if the list
    ///   was cleared in the meantime the images are stale and get dropped.
    func addReferenceImages(_ images: [Data], epoch: Int? = nil) {
        if let epoch, epoch != referenceImagesEpoch { return }
        let remaining = (selectedModel?.maxReferenceImages ?? 0) - referenceImages.count
        guard remaining > 0 else { return }
        for imageData in images.prefix(remaining) {
            if let normalized = Self.normalizeImageData(imageData) {
                referenceImages.append(ReferenceImage(data: normalized))
            }
        }
        commitUndoCheckpoint()
    }

    func removeReferenceImage(at index: Int) {
        guard referenceImages.indices.contains(index) else { return }
        referenceImages.remove(at: index)
        commitUndoCheckpoint()
    }

    func replaceReferenceImage(at index: Int, with data: Data) {
        guard referenceImages.indices.contains(index) else { return }
        referenceImages[index] = ReferenceImage(data: data)
        commitUndoCheckpoint()
    }

    /// Normalize image data for API consumption.
    /// JPEG and PNG are returned as-is (universally supported by AI APIs).
    /// Other formats (HEIC, TIFF, etc.) are converted to PNG.
    private static func normalizeImageData(_ data: Data) -> Data? {
        guard data.count >= 4 else { return nil }
        let header = [UInt8](data.prefix(4))

        // JPEG: starts with FF D8
        if header[0] == 0xFF && header[1] == 0xD8 {
            return data
        }
        // PNG: starts with 89 50 4E 47
        if header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47 {
            return data
        }

        // Convert other formats (HEIC, TIFF, WebP, etc.) to PNG
        #if os(macOS)
        guard let image = NSImage(data: data),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
        #else
        guard let image = UIImage(data: data),
              let pngData = image.pngData() else {
            return nil
        }
        return pngData
        #endif
    }

    /// Downscale an image so its longest edge fits within `maxSize`.
    /// Returns `nil` if the image already fits (no downscaling needed).
    private static func downscaleForBackgroundRemoval(_ data: Data, maxSize: Int = 1024) -> (downscaled: Data, originalWidth: Int, originalHeight: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let origW = cgImage.width
        let origH = cgImage.height
        guard max(origW, origH) > maxSize else { return nil }

        let scale = CGFloat(maxSize) / CGFloat(max(origW, origH))
        let newW = Int(CGFloat(origW) * scale)
        let newH = Int(CGFloat(origH) * scale)

        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: newW, height: newH,
                                 bitsPerComponent: 8, bytesPerRow: 0,
                                 space: colorSpace,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let downscaledCG = ctx.makeImage() else { return nil }

        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData as CFMutableData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, downscaledCG, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (downscaled: mutableData as Data, originalWidth: origW, originalHeight: origH)
    }

    /// Extract the alpha channel from `resultData` as a grayscale mask,
    /// upscale to original dimensions, and composite onto the original full-res image.
    private static func extractAndApplyMask(resultData: Data, originalData: Data, originalWidth: Int, originalHeight: Int) -> Data? {
        // Decode the API result to get its alpha channel
        guard let resultSource = CGImageSourceCreateWithData(resultData as CFData, nil),
              let resultCG = CGImageSourceCreateImageAtIndex(resultSource, 0, nil) else {
            return nil
        }
        let rw = resultCG.width
        let rh = resultCG.height

        // Render API result into RGBA context to read alpha
        guard let rgbaCtx = CGContext(data: nil, width: rw, height: rh,
                                      bitsPerComponent: 8, bytesPerRow: rw * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        rgbaCtx.draw(resultCG, in: CGRect(x: 0, y: 0, width: rw, height: rh))
        guard let rgbaData = rgbaCtx.data else { return nil }

        // Extract alpha bytes into a grayscale buffer
        let pixelCount = rw * rh
        let alphaBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
        defer { alphaBytes.deallocate() }
        let src = rgbaData.bindMemory(to: UInt8.self, capacity: pixelCount * 4)
        for i in 0..<pixelCount {
            alphaBytes[i] = src[i * 4 + 3] // alpha is the 4th byte in RGBA
        }

        // Create a small grayscale mask image
        guard let graySpace = CGColorSpace(name: CGColorSpace.linearGray),
              let maskCtx = CGContext(data: alphaBytes, width: rw, height: rh,
                                     bitsPerComponent: 8, bytesPerRow: rw,
                                     space: graySpace,
                                     bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let smallMask = maskCtx.makeImage() else {
            return nil
        }

        // Upscale the grayscale mask to original dimensions with bicubic interpolation
        guard let upscaleCtx = CGContext(data: nil, width: originalWidth, height: originalHeight,
                                         bitsPerComponent: 8, bytesPerRow: originalWidth,
                                         space: graySpace,
                                         bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        upscaleCtx.interpolationQuality = .high
        upscaleCtx.draw(smallMask, in: CGRect(x: 0, y: 0, width: originalWidth, height: originalHeight))
        guard let fullMask = upscaleCtx.makeImage() else { return nil }

        // Decode original full-res image
        guard let origSource = CGImageSourceCreateWithData(originalData as CFData, nil),
              let origCG = CGImageSourceCreateImageAtIndex(origSource, 0, nil) else {
            return nil
        }

        // Composite: clip original through the upscaled mask
        guard let origColorSpace = origCG.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let compCtx = CGContext(data: nil, width: originalWidth, height: originalHeight,
                                     bitsPerComponent: 8, bytesPerRow: 0,
                                     space: origColorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        let fullRect = CGRect(x: 0, y: 0, width: originalWidth, height: originalHeight)
        compCtx.clip(to: fullRect, mask: fullMask)
        compCtx.draw(origCG, in: fullRect)
        guard let compositedCG = compCtx.makeImage() else { return nil }

        // Encode as PNG
        let pngData = NSMutableData()
        guard let pngDest = CGImageDestinationCreateWithData(pngData as CFMutableData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(pngDest, compositedCG, nil)
        guard CGImageDestinationFinalize(pngDest) else { return nil }
        return pngData as Data
    }

    // MARK: - Image Inspector

    func selectImage(job: GenerationJob, index: Int) {
        selectedImageJob = job
        selectedImageIndex = index
    }

    func clearImageSelection() {
        selectedImageJob = nil
        selectedImageIndex = 0
        selectedLibraryImageIDs.removeAll()
    }

    #if os(macOS)
    func exportSelectedImages() {
        guard let root = projectManager.projectsRootURL else { return }

        // Collect image paths to export
        var imageURLs: [URL] = []

        if selectedLibraryImageIDs.count > 1 {
            // Multi-selection from library
            for fileName in selectedLibraryImageIDs {
                let url = root.appendingPathComponent("generations/\(fileName)")
                if FileManager.default.fileExists(atPath: url.path) {
                    imageURLs.append(url)
                }
            }
        } else if let job = selectedImageJob, selectedImageIndex < job.savedImagePaths.count {
            // Single selection from inspector
            let url = root.appendingPathComponent(job.savedImagePaths[selectedImageIndex])
            if FileManager.default.fileExists(atPath: url.path) {
                imageURLs.append(url)
            }
        }

        guard !imageURLs.isEmpty else { return }

        if imageURLs.count == 1 {
            // Single image: use save panel
            let sourceURL = imageURLs[0]
            let panel = NSSavePanel()
            panel.title = "Export Image"
            panel.nameFieldStringValue = sourceURL.lastPathComponent
            panel.allowedContentTypes = [.png]

            guard panel.runModal() == .OK, let destURL = panel.url else { return }
            do {
                let data = try Data(contentsOf: sourceURL)
                try data.write(to: destURL)
                statusMessage = "Exported to \(destURL.lastPathComponent)"
                showToast("Image exported", icon: "checkmark.circle", style: .success)
            } catch {
                statusMessage = "Export failed: \(error.localizedDescription)"
                showToast("Export failed", icon: "xmark.circle", style: .error)
            }
        } else {
            // Multiple images: pick a folder
            let panel = NSOpenPanel()
            panel.title = "Export \(imageURLs.count) Images"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true

            guard panel.runModal() == .OK, let destFolder = panel.url else { return }
            var exported = 0
            for sourceURL in imageURLs {
                let destURL = destFolder.appendingPathComponent(sourceURL.lastPathComponent)
                do {
                    let data = try Data(contentsOf: sourceURL)
                    try data.write(to: destURL)
                    exported += 1
                } catch {
                    // Continue exporting remaining images
                }
            }
            statusMessage = "Exported \(exported) image\(exported == 1 ? "" : "s")"
            showToast("Exported \(exported) image\(exported == 1 ? "" : "s")", icon: "checkmark.circle", style: .success)
        }
    }
    #endif

    // MARK: - Library Multi-Selection

    /// Single click: clear set, select one, update inspector
    func selectLibraryImage(_ id: String, entry: LibraryImageEntry) {
        selectedLibraryImageIDs = [id]
        if let job = entry.job {
            selectedImageJob = job
            selectedImageIndex = entry.imageIndex
        } else {
            selectedImageJob = nil
            selectedImageIndex = 0
        }
    }

    /// Cmd+click: toggle item in selection set
    func toggleLibraryImageSelection(_ id: String, entry: LibraryImageEntry) {
        if selectedLibraryImageIDs.contains(id) {
            selectedLibraryImageIDs.remove(id)
        } else {
            selectedLibraryImageIDs.insert(id)
        }
        // If exactly one remains, sync inspector
        if selectedLibraryImageIDs.count == 1, let remaining = selectedLibraryImageIDs.first {
            // The caller should provide the entry for the remaining item if possible,
            // but for now we keep current inspector state or clear if the deselected was the inspected one
            if id == remaining {
                // We just added this one
                if let job = entry.job {
                    selectedImageJob = job
                    selectedImageIndex = entry.imageIndex
                }
            }
        }
        if selectedLibraryImageIDs.isEmpty {
            selectedImageJob = nil
            selectedImageIndex = 0
        }
    }

    /// Shift+click: select range from last selected to target
    func selectLibraryImageRange(to id: String, entries: [LibraryImageEntry]) {
        guard let targetIndex = entries.firstIndex(where: { $0.id == id }) else { return }

        // Find the anchor: the first entry in the current ordered list that's already selected
        var anchorIndex = targetIndex
        for (i, entry) in entries.enumerated() {
            if selectedLibraryImageIDs.contains(entry.id) {
                anchorIndex = i
                break
            }
        }

        let rangeStart = min(anchorIndex, targetIndex)
        let rangeEnd = max(anchorIndex, targetIndex)

        for i in rangeStart...rangeEnd {
            selectedLibraryImageIDs.insert(entries[i].id)
        }

        // If only one selected, sync inspector
        if selectedLibraryImageIDs.count == 1, let entry = entries.first(where: { selectedLibraryImageIDs.contains($0.id) }) {
            if let job = entry.job {
                selectedImageJob = job
                selectedImageIndex = entry.imageIndex
            }
        }
    }

    /// Request deletion: check preferences, show confirmation or delete immediately
    func requestDeleteLibraryImages(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        if projectPreferences.skipDeleteConfirmation {
            pendingDeleteIDs = ids
            confirmDeleteLibraryImages()
        } else {
            pendingDeleteIDs = ids
            showDeleteConfirmation = true
        }
    }

    /// Execute deletion of pending images
    func confirmDeleteLibraryImages() {
        guard let root = projectManager.projectsRootURL, !pendingDeleteIDs.isEmpty else { return }
        let ids = pendingDeleteIDs
        pendingDeleteIDs.removeAll()

        // Delete files from disk
        projectManager.deleteGenerationImages(fileNames: ids, from: root)

        // Remove deleted paths from jobs, then remove jobs with no images left
        var jobsToRemove: [UUID] = []
        for job in generationJobs {
            var indicesToRemove: [Int] = []
            for (index, path) in job.savedImagePaths.enumerated() {
                let fileName = (path as NSString).lastPathComponent
                if ids.contains(fileName) {
                    indicesToRemove.append(index)
                }
            }
            for index in indicesToRemove.reversed() {
                job.savedImagePaths.remove(at: index)
                if index < job.thumbnailPaths.count {
                    job.thumbnailPaths.remove(at: index)
                }
            }
            if job.savedImagePaths.isEmpty && job.status == .completed {
                jobsToRemove.append(job.id)
            }
        }
        generationJobs.removeAll { jobsToRemove.contains($0.id) }

        // Clear selection for deleted items
        selectedLibraryImageIDs.subtract(ids)
        if selectedLibraryImageIDs.isEmpty || selectedImageJob.map({ jobsToRemove.contains($0.id) }) == true {
            selectedImageJob = nil
            selectedImageIndex = 0
        }

        // Persist and update
        saveActivity()
        imageVersion += 1
        let count = ids.count
        showToast("\(count) image\(count == 1 ? "" : "s") removed", icon: "trash", style: .info)
    }

    // MARK: - Toasts

    func showToast(_ message: String, icon: String = "checkmark", style: AppToast.ToastStyle = .info) {
        let toast = AppToast(message: message, icon: icon, style: style)
        withAnimation { toasts.append(toast) }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { toasts.removeAll { $0.id == toast.id } }
        }
    }

    func notifyJobCompleted(title: String, message: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)

        if !NSApplication.shared.isActive {
            unseenCompletionCount += 1
            NSApplication.shared.dockTile.badgeLabel = "\(unseenCompletionCount)"
        }
    }

    // MARK: - Reuse Settings

    func loadSettings(from job: GenerationJob) {
        hiddenModels.remove(job.modelID)
        selectedModelID = job.modelID
        onModelChanged()
        prompt = job.prompt
        selectedAspectRatio = job.aspectRatio
        if let res = job.resolution {
            selectedResolution = res
        }
        imageCount = job.imageCount
        for (key, value) in job.parameters {
            parameterValues[key] = value
        }
        if let root = projectManager.projectsRootURL, !job.referenceImagePaths.isEmpty {
            clearReferenceImages()
            for path in job.referenceImagePaths {
                let url = root.appendingPathComponent(path)
                if let data = try? Data(contentsOf: url) {
                    referenceImages.append(ReferenceImage(data: data))
                }
            }
        }
        commitUndoCheckpoint()
    }

    func retryJob(_ job: GenerationJob) {
        guard let model = job.model else {
            errorMessage = "Unknown model: \(job.modelID)"
            return
        }

        var retryReferenceImages: [Data] = []
        if let root = projectManager.projectsRootURL {
            for path in job.referenceImagePaths {
                let url = root.appendingPathComponent(path)
                if let data = try? Data(contentsOf: url) {
                    retryReferenceImages.append(data)
                }
            }
        }

        runGeneration(
            prompt: job.prompt,
            model: model,
            aspectRatio: job.aspectRatio,
            resolution: job.resolution,
            imageCount: job.imageCount,
            referenceImages: retryReferenceImages,
            parameters: job.parameters
        )
    }

    func loadSettingsCompatible(from job: GenerationJob) {
        loadSettings(from: job)
    }

    // MARK: - Project Operations

    func loadProjects() {
        projectManager.startAccessing()
        do {
            projects = try projectManager.loadProjects()
            if selectedProjectID == nil, let first = projects.first {
                selectedProjectID = first.id
            }
        } catch {
            statusMessage = "Failed to load projects: \(error.localizedDescription)"
        }
        loadActivity()
        loadProjectPreferences()
        updateProjectSize()
    }

    func loadProjectPreferences() {
        guard let root = projectManager.projectsRootURL else { return }
        projectPreferences = projectManager.loadPreferences(from: root)
    }

    func saveProjectPreferences() {
        guard let root = projectManager.projectsRootURL else { return }
        projectManager.savePreferences(projectPreferences, to: root)
    }

    func createProject(name: String) {
        do {
            let project = try projectManager.createProject(name: name)
            projects.insert(project, at: 0)
            selectedProjectID = project.id
            selectedCanvasID = nil
            statusMessage = "Created project: \(name)"
        } catch {
            statusMessage = "Failed to create project: \(error.localizedDescription)"
        }
    }

    func deleteProject(_ project: Project) {
        do {
            try projectManager.deleteProject(project)
            projects.removeAll { $0.id == project.id }
            if selectedProjectID == project.id {
                selectedProjectID = nil
                selectedCanvasID = nil
            }
            statusMessage = "Deleted project: \(project.name)"
        } catch {
            statusMessage = "Failed to delete project: \(error.localizedDescription)"
        }
    }

    func renameProject(_ project: Project, to newName: String) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        do {
            try projectManager.renameProject(&projects[index], to: newName)
        } catch {
            statusMessage = "Failed to rename project: \(error.localizedDescription)"
        }
    }

    // MARK: - Canvas Operations

    func createCanvas(inProjectID projectID: String, name: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        do {
            let canvas = try projectManager.createCanvas(
                inProject: &projects[index],
                name: name,
                width: selectedResolution.dimensions(for: selectedAspectRatio).width,
                height: selectedResolution.dimensions(for: selectedAspectRatio).height
            )
            selectedCanvasID = canvas.id
            statusMessage = "Created canvas: \(name)"
        } catch {
            statusMessage = "Failed to create canvas: \(error.localizedDescription)"
        }
    }

    func deleteCanvas(_ canvas: Canvas, fromProjectID projectID: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        do {
            try projectManager.deleteCanvas(canvas, fromProject: &projects[index])
            if selectedCanvasID == canvas.id {
                selectedCanvasID = nil
            }
            statusMessage = "Deleted canvas: \(canvas.name)"
        } catch {
            statusMessage = "Failed to delete canvas: \(error.localizedDescription)"
        }
    }

    // MARK: - AI Generation

    func generateImage() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            errorMessage = "Enter a prompt first."
            statusMessage = "Enter a prompt first."
            return
        }
        guard let model = selectedModel else {
            errorMessage = "Unknown model: \(selectedModelID)"
            statusMessage = "Unknown model."
            return
        }

        var requestParams: [String: ParameterValue] = [:]
        for spec in model.parameters {
            requestParams[spec.key] = parameterValues[spec.key] ?? spec.defaultValue
        }

        runGeneration(
            prompt: trimmedPrompt,
            model: model,
            aspectRatio: selectedAspectRatio,
            resolution: model.supportsResolution ? selectedResolution : nil,
            imageCount: imageCount,
            referenceImages: referenceImages.map(\.data),
            parameters: requestParams
        )
    }

    private func runGeneration(
        prompt: String,
        model: ModelDefinition,
        aspectRatio: AspectRatio,
        resolution: ImageResolution?,
        imageCount: Int,
        referenceImages: [Data],
        parameters: [String: ParameterValue]
    ) {
        guard let projectRoot = projectManager.projectsRootURL else {
            errorMessage = "No project folder open."
            statusMessage = "No project folder open."
            return
        }

        guard let apiKey = KeychainManager.load(key: "replicate_api_key"), !apiKey.isEmpty else {
            errorMessage = "No Replicate API key configured. Add it in Settings."
            statusMessage = "API key missing."
            return
        }

        let job = GenerationJob(
            modelID: model.id,
            prompt: prompt,
            projectID: projectRoot.lastPathComponent,
            aspectRatio: aspectRatio,
            resolution: resolution,
            imageCount: imageCount,
            parameters: parameters
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            generationJobs.insert(job, at: 0)
        }
        activeJobID = job.id

        var referenceHashes: [String] = []
        if !referenceImages.isEmpty {
            let result = projectManager.saveReferenceImages(referenceImages, toFolder: projectRoot)
            job.referenceImagePaths = result.paths
            referenceHashes = result.hashes
        }

        errorMessage = nil
        statusMessage = "Generating with \(model.displayName)..."
        job.startedAt = Date()
        job.status = .running

        let request = GenerationRequest(
            prompt: prompt,
            model: model,
            aspectRatio: aspectRatio,
            resolution: resolution,
            imageCount: imageCount,
            referenceImages: referenceImages,
            parameters: parameters
        )

        let provider = ReplicateProvider(apiKey: apiKey)

        Task {
            do {
                let result = try await provider.generateImage(request: request, parallelDelay: parallelRequestDelay) { [weak self] cancelURL, paramsJSON in
                    Task { @MainActor in
                        guard let self else { return }
                        if job.startedAt == nil {
                            job.startedAt = Date()
                        }
                        job.cancelURLs.append(cancelURL)
                        if let paramsJSON { job.requestParamsJSON = paramsJSON }
                    }
                }

                guard !result.imageDataArray.isEmpty else {
                    let msg = result.partialErrors.first ?? "No image output received from the API."
                    throw ReplicateError.generationFailed(msg)
                }

                let meta = ImageMeta(
                    prompt: prompt,
                    modelID: model.id,
                    aspectRatio: aspectRatio,
                    resolution: resolution,
                    imageCount: imageCount,
                    parameters: parameters,
                    referenceHashes: referenceHashes,
                    createdAt: Date()
                )
                let saved = try projectManager.saveGeneratedImages(result.imageDataArray, toFolder: projectRoot, meta: meta, thumbnailMaxSize: CGFloat(thumbnailMaxPixelSize))

                job.resultImageData = result.imageDataArray
                job.savedImagePaths = saved.imagePaths
                job.thumbnailPaths = saved.thumbnailPaths
                job.completedAt = Date()
                job.status = .completed
                imageVersion += 1

                // Handle partial failures: create a separate failed job for the errors
                if !result.partialErrors.isEmpty {
                    let successCount = result.imageDataArray.count
                    let totalCount = successCount + result.partialErrors.count
                    let failedJob = GenerationJob(
                        modelID: model.id,
                        prompt: prompt,
                        projectID: projectRoot.lastPathComponent,
                        aspectRatio: aspectRatio,
                        resolution: resolution,
                        imageCount: imageCount,
                        parameters: parameters
                    )
                    failedJob.startedAt = job.startedAt
                    failedJob.completedAt = Date()
                    failedJob.status = .failed
                    failedJob.requestParamsJSON = job.requestParamsJSON
                    let errorSummary = result.partialErrors.first ?? "Unknown error"
                    failedJob.errorMessage = "Failed (\(result.partialErrors.count)/\(totalCount)): \(errorSummary)"
                    if let jobIndex = generationJobs.firstIndex(where: { $0.id == job.id }) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            generationJobs.insert(failedJob, at: jobIndex + 1)
                        }
                    }
                    statusMessage = "Saved \(saved.imagePaths.count) image\(saved.imagePaths.count == 1 ? "" : "s") (\(result.partialErrors.count) failed)"
                    showToast("Partially completed", icon: "exclamationmark.triangle", style: .success)
                } else {
                    statusMessage = "Saved \(saved.imagePaths.count) image\(saved.imagePaths.count == 1 ? "" : "s")"
                    showToast("Image generated", icon: "checkmark.circle", style: .success)
                }
                notifyJobCompleted(title: "Image Generated", message: statusMessage)
                saveActivity()
            } catch {
                if job.status != .cancelled {
                    job.completedAt = Date()
                    job.status = .failed
                    job.errorMessage = error.localizedDescription
                    errorMessage = error.localizedDescription
                    statusMessage = "Generation failed."
                    showToast("Generation failed", icon: "xmark.circle", style: .error)
                    notifyJobCompleted(title: "Generation Failed", message: error.localizedDescription)
                }
                saveActivity()
            }
        }
    }

    func cancelJob(_ job: GenerationJob) {
        guard job.status == .running || job.status == .pending else { return }

        let cancelURLs = job.cancelURLs
        job.completedAt = Date()
        job.status = .cancelled
        statusMessage = "Cancelled"
        saveActivity()

        guard let apiKey = KeychainManager.load(key: "replicate_api_key"), !apiKey.isEmpty else { return }
        let provider = ReplicateProvider(apiKey: apiKey)

        Task.detached {
            for url in cancelURLs {
                try? await provider.cancelPrediction(url: url)
            }
        }
    }

    func removeBackground(job: GenerationJob, imageIndex: Int) {
        guard let projectRoot = projectManager.projectsRootURL else { return }
        guard imageIndex < job.savedImagePaths.count else { return }
        guard let apiKey = KeychainManager.load(key: "replicate_api_key"), !apiKey.isEmpty else {
            errorMessage = "No Replicate API key configured. Add it in Settings."
            return
        }
        guard let bgModel = ModelRegistry.shared.backgroundRemovalModel else {
            errorMessage = "No background removal model defined."
            return
        }

        let imagePath = job.savedImagePaths[imageIndex]
        let imageURL = projectRoot.appendingPathComponent(imagePath)
        guard let imageData = try? Data(contentsOf: imageURL) else {
            errorMessage = "Could not read image file."
            return
        }

        let refResult = projectManager.saveReferenceImages([imageData], toFolder: projectRoot)

        let bgJob = GenerationJob(
            modelID: bgModel.id,
            prompt: "",
            projectID: projectRoot.lastPathComponent,
            aspectRatio: job.aspectRatio,
            resolution: nil,
            imageCount: 1,
            parameters: [:]
        )
        bgJob.referenceImagePaths = refResult.paths
        bgJob.startedAt = Date()
        bgJob.status = .running
        generationJobs.insert(bgJob, at: 0)
        activeJobID = bgJob.id

        isRemovingBackground = true
        statusMessage = "Removing background..."

        let provider = ReplicateProvider(apiKey: apiKey)

        Task {
            do {
                let downscaleInfo = Self.downscaleForBackgroundRemoval(imageData)
                let apiInput = downscaleInfo?.downscaled ?? imageData

                let resultData = try await provider.removeBackground(imageData: apiInput, model: bgModel)

                let finalData: Data
                if let info = downscaleInfo,
                   let composited = Self.extractAndApplyMask(
                       resultData: resultData,
                       originalData: imageData,
                       originalWidth: info.originalWidth,
                       originalHeight: info.originalHeight
                   ) {
                    finalData = composited
                } else {
                    finalData = resultData
                }

                let meta = ImageMeta(
                    prompt: bgJob.prompt,
                    modelID: bgModel.id,
                    aspectRatio: bgJob.aspectRatio,
                    resolution: nil,
                    imageCount: 1,
                    parameters: [:],
                    referenceHashes: refResult.hashes,
                    createdAt: Date()
                )
                let saved = try projectManager.saveGeneratedImages([finalData], toFolder: projectRoot, meta: meta, thumbnailMaxSize: CGFloat(thumbnailMaxPixelSize))

                bgJob.resultImageData = [finalData]
                bgJob.savedImagePaths = saved.imagePaths
                bgJob.thumbnailPaths = saved.thumbnailPaths
                bgJob.completedAt = Date()
                bgJob.status = .completed

                selectImage(job: bgJob, index: 0)
                imageVersion += 1
                statusMessage = "Background removed"
                isRemovingBackground = false
                showToast("Background removed", icon: "checkmark.circle", style: .success)
                notifyJobCompleted(title: "Background Removed", message: "Background removed successfully")
                saveActivity()
            } catch {
                bgJob.completedAt = Date()
                bgJob.status = .failed
                bgJob.errorMessage = error.localizedDescription
                errorMessage = error.localizedDescription
                statusMessage = "Background removal failed."
                isRemovingBackground = false
                showToast("Background removal failed", icon: "xmark.circle", style: .error)
                notifyJobCompleted(title: "Background Removal Failed", message: error.localizedDescription)
                saveActivity()
            }
        }
    }

    func removeJob(_ job: GenerationJob) {
        generationJobs.removeAll { $0.id == job.id }
        if selectedImageJob?.id == job.id {
            clearImageSelection()
        }
        saveActivity()
    }

    // MARK: - Project Size

    func updateProjectSize() {
        guard let root = projectManager.projectsRootURL else {
            projectSizeText = ""
            return
        }
        let bytes = projectManager.projectSize(at: root)
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1000 {
            let gb = mb / 1024
            projectSizeText = String(format: "%.1f GB", gb)
        } else {
            projectSizeText = String(format: "%.1f MB", mb)
        }
    }

    // MARK: - Zoom

    func zoomIn() {
        canvasZoom = min(canvasZoom * 1.25, 10.0)
    }

    func zoomOut() {
        canvasZoom = max(canvasZoom / 1.25, 0.1)
    }

    func zoomToFit() {
        canvasZoom = 1.0
        canvasOffset = .zero
    }

    // MARK: - Root Folder

    func setProjectsRoot(_ url: URL) {
        projectManager.setProjectsRoot(url)
        hasProjectsRoot = true
        addToRecentProjects(url)
        loadProjects()
    }

    // MARK: - Recent Projects

    var recentProjects: [(name: String, url: URL)] {
        guard let bookmarks = UserDefaults.standard.array(forKey: "recentProjectBookmarks") as? [Data] else {
            return []
        }
        var results: [(name: String, url: URL)] = []
        for data in bookmarks {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                results.append((name: url.lastPathComponent, url: url))
            }
        }
        return results
    }

    func addToRecentProjects(_ url: URL) {
        var bookmarks = UserDefaults.standard.array(forKey: "recentProjectBookmarks") as? [Data] ?? []

        // Remove existing entry for same path
        bookmarks.removeAll { data in
            var isStale = false
            if let existing = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                return existing.path == url.path
            }
            return false
        }

        // Add new bookmark at front
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmarks.insert(bookmark, at: 0)
        }

        // Keep max 10
        if bookmarks.count > 10 {
            bookmarks = Array(bookmarks.prefix(10))
        }

        UserDefaults.standard.set(bookmarks, forKey: "recentProjectBookmarks")
    }

    func loadActivity() {
        guard let root = projectManager.projectsRootURL else { return }
        let loaded = projectManager.loadActivity(from: root)
        // Merge: keep any in-flight jobs, prepend loaded history
        let inFlight = generationJobs.filter { $0.status == .pending || $0.status == .running }
        generationJobs = inFlight + loaded

        let lastMigrated = UserDefaults.standard.integer(forKey: "thumbnailLastMigratedSize")
        if lastMigrated != thumbnailMaxPixelSize {
            migrateThumbnailsIfNeeded()
        }
    }

    func migrateThumbnailsIfNeeded() {
        guard let root = projectManager.projectsRootURL else { return }
        let maxSize = CGFloat(thumbnailMaxPixelSize)
        let currentSetting = thumbnailMaxPixelSize
        Task.detached { [projectManager] in
            var didShowProgress = false
            let count = projectManager.migrateThumbnails(in: root, maxSize: maxSize) { progress in
                Task { @MainActor [weak self] in
                    didShowProgress = true
                    self?.thumbnailMigrationProgress = progress
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if count > 0 {
                    ThumbnailCache.shared.clearAll()
                    self.imageVersion += 1
                }
                if didShowProgress || self.thumbnailMigrationProgress != nil {
                    self.thumbnailMigrationProgress = nil
                }
                UserDefaults.standard.set(currentSetting, forKey: "thumbnailLastMigratedSize")
            }
        }
    }

    func saveActivity() {
        guard let root = projectManager.projectsRootURL else { return }
        projectManager.saveActivity(generationJobs, to: root)
        updateProjectSize()
    }

    func closeProject() {
        hasProjectsRoot = false
        selectedProjectID = nil
        selectedCanvasID = nil
        projects = []
        projectManager.stopAccessing()
    }

    func openProject(url: URL) {
        setProjectsRoot(url)
    }

    // MARK: - Menu State

    var showNewCanvasAlert = false
    var newItemName = ""
}

