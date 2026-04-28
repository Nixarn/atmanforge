import Foundation
import CryptoKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

class ProjectManager {
    static let shared = ProjectManager()

    private let fileManager = FileManager.default
    private var metaCache: [String: ImageMeta] = [:]

    /// Returns cached ImageMeta for a generation file, reading from the companion .meta file on first access.
    /// The key is the base timestamp (e.g. "20250127-143052") derived from filenames like "20250127-143052.png" or "20250127-143052-2.png".
    func cachedMeta(forGenerationFile fileName: String, inFolder folder: URL) -> ImageMeta? {
        let base = metaBaseName(from: fileName)
        if let cached = metaCache[base] { return cached }

        let metaURL = folder.appendingPathComponent("generations/\(base).meta")
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let meta = try? decoder.decode(ImageMeta.self, from: data) else { return nil }
        metaCache[base] = meta
        return meta
    }

    /// Strips the image index suffix and extension to get the meta base name.
    /// "20250127-143052.png" → "20250127-143052"
    /// "20250127-143052-2.png" → "20250127-143052"
    private func metaBaseName(from fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        // If it ends with -<digit(s)>, strip that suffix
        if let range = stem.range(of: #"-\d+$"#, options: .regularExpression) {
            return String(stem[stem.startIndex..<range.lowerBound])
        }
        return stem
    }
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Root Folder

    var projectsRootURL: URL? {
        guard let data = UserDefaults.standard.data(forKey: "projectsRootBookmark") else {
            return nil
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        if isStale {
            saveRootBookmark(for: url)
        }
        return url
    }

    func setProjectsRoot(_ url: URL) {
        saveRootBookmark(for: url)
    }

    private func saveRootBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }
        UserDefaults.standard.set(data, forKey: "projectsRootBookmark")
    }

    // MARK: - Security-Scoped Access

    @discardableResult
    func startAccessing() -> Bool {
        projectsRootURL?.startAccessingSecurityScopedResource() ?? false
    }

    func stopAccessing() {
        projectsRootURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Load Projects

    func loadProjects() throws -> [Project] {
        guard let root = projectsRootURL else { return [] }

        let contents = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        var projects: [Project] = []
        for folderURL in contents {
            guard (try? folderURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                continue
            }
            let manifestURL = folderURL.appendingPathComponent("project.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }

            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try decoder.decode(ProjectManifest.self, from: data)
                let canvases = loadCanvases(in: folderURL, canvasNames: manifest.canvases)
                let project = Project(
                    id: folderURL.lastPathComponent,
                    folderURL: folderURL,
                    manifest: manifest,
                    canvases: canvases
                )
                projects.append(project)
            } catch {
                continue
            }
        }

        return projects.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    private func loadCanvases(in projectURL: URL, canvasNames: [String]) -> [Canvas] {
        let canvasesDir = projectURL.appendingPathComponent("canvases")
        guard fileManager.fileExists(atPath: canvasesDir.path) else { return [] }

        var canvases: [Canvas] = []
        for name in canvasNames {
            let canvasDir = canvasesDir.appendingPathComponent(name)
            let manifestURL = canvasDir.appendingPathComponent("canvas.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }

            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try decoder.decode(CanvasManifest.self, from: data)
                canvases.append(Canvas(id: name, folderURL: canvasDir, manifest: manifest))
            } catch {
                continue
            }
        }
        return canvases
    }

    // MARK: - Create Project

    func createProject(name: String) throws -> Project {
        guard let root = projectsRootURL else {
            throw ProjectError.noRootFolder
        }

        let folderName = uniqueFolderName(for: name, in: root)
        let folderURL = root.appendingPathComponent(folderName)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: folderURL.appendingPathComponent("canvases"),
            withIntermediateDirectories: true
        )

        let manifest = ProjectManifest(name: name)
        let data = try encoder.encode(manifest)
        try data.write(to: folderURL.appendingPathComponent("project.json"))

        return Project(id: folderName, folderURL: folderURL, manifest: manifest, canvases: [])
    }

    // MARK: - Delete Project

    func deleteProject(_ project: Project) throws {
        try fileManager.removeItem(at: project.folderURL)
    }

    // MARK: - Rename Project

    func renameProject(_ project: inout Project, to newName: String) throws {
        project.manifest.name = newName
        try saveProjectManifest(project)
    }

    // MARK: - Create Canvas

    func createCanvas(inProject project: inout Project, name: String, width: Int = 1024, height: Int = 1024) throws -> Canvas {
        let canvasesDir = project.folderURL.appendingPathComponent("canvases")
        let folderName = uniqueFolderName(for: name, in: canvasesDir)
        let canvasDir = canvasesDir.appendingPathComponent(folderName)
        try fileManager.createDirectory(at: canvasDir, withIntermediateDirectories: true)

        let manifest = CanvasManifest(name: name, width: width, height: height)
        let data = try encoder.encode(manifest)
        try data.write(to: canvasDir.appendingPathComponent("canvas.json"))

        project.manifest.canvases.append(folderName)
        try saveProjectManifest(project)

        return Canvas(id: folderName, folderURL: canvasDir, manifest: manifest)
    }

    // MARK: - Delete Canvas

    func deleteCanvas(_ canvas: Canvas, fromProject project: inout Project) throws {
        try fileManager.removeItem(at: canvas.folderURL)
        project.manifest.canvases.removeAll { $0 == canvas.id }
        project.canvases.removeAll { $0.id == canvas.id }
        try saveProjectManifest(project)
    }

    // MARK: - Save

    func saveProjectManifest(_ project: Project) throws {
        let data = try encoder.encode(project.manifest)
        try data.write(to: project.folderURL.appendingPathComponent("project.json"))
    }

    func saveCanvasManifest(_ canvas: Canvas) throws {
        let data = try encoder.encode(canvas.manifest)
        try data.write(to: canvas.folderURL.appendingPathComponent("canvas.json"))
    }

    func saveCanvasImage(_ canvas: Canvas, imageData: Data) throws {
        try imageData.write(to: canvas.imageURL)
    }

    func saveGeneratedImages(_ imageDataArray: [Data], toFolder folder: URL, meta: ImageMeta? = nil, thumbnailMaxSize: CGFloat = 128) throws -> (imagePaths: [String], thumbnailPaths: [String]) {
        let generationsDir = folder.appendingPathComponent("generations")
        let thumbnailsDir = folder.appendingPathComponent(".thumbnails")
        try fileManager.createDirectory(at: generationsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())

        var imagePaths: [String] = []
        var thumbnailPaths: [String] = []

        for (index, data) in imageDataArray.enumerated() {
            let suffix = imageDataArray.count > 1 ? "-\(index + 1)" : ""
            let filename = "\(timestamp)\(suffix).png"

            // Convert to actual PNG (API may return WebP/JPEG)
            let pngData = convertToPNG(data) ?? data

            // Save full image
            let imagePath = "generations/\(filename)"
            let imageURL = folder.appendingPathComponent(imagePath)
            try pngData.write(to: imageURL)
            imagePaths.append(imagePath)

            // Generate and save thumbnail
            let thumbPath = ".thumbnails/\(filename)"
            let thumbURL = folder.appendingPathComponent(thumbPath)
            if let thumbnailData = generateThumbnail(from: pngData, maxSize: thumbnailMaxSize) {
                try thumbnailData.write(to: thumbURL)
                thumbnailPaths.append(thumbPath)
            }
        }

        // Write companion .meta file
        if let meta {
            let metaPath = generationsDir.appendingPathComponent("\(timestamp).meta")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            try? encoder.encode(meta).write(to: metaPath)
        }

        return (imagePaths, thumbnailPaths)
    }

    // MARK: - Reference Images

    func saveReferenceImages(_ images: [Data], toFolder folder: URL) -> (paths: [String], hashes: [String]) {
        let referencesDir = folder.appendingPathComponent("references")
        try? fileManager.createDirectory(at: referencesDir, withIntermediateDirectories: true)

        var paths: [String] = []
        var hashes: [String] = []
        for data in images {
            let hash = sha256Hex(data)
            let filename = "\(hash).png"
            let relativePath = "references/\(filename)"
            let fileURL = folder.appendingPathComponent(relativePath)
            // Skip write if file already exists (dedup)
            if !fileManager.fileExists(atPath: fileURL.path) {
                do {
                    try data.write(to: fileURL)
                } catch {
                    continue
                }
            }
            paths.append(relativePath)
            hashes.append(hash)
        }
        return (paths, hashes)
    }

    // MARK: - Project Size

    func projectSize(at url: URL) -> Int64 {
        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var totalSize: Int64 = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            totalSize += Int64(size)
        }
        return totalSize
    }

    // MARK: - Image Conversion

    private func convertToPNG(_ data: Data) -> Data? {
        #if os(macOS)
        guard let image = NSImage(data: data),
              let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return nil }
        return pngData
        #else
        guard let image = UIImage(data: data),
              let pngData = image.pngData() else { return nil }
        return pngData
        #endif
    }

    // MARK: - Thumbnails

    private func generateThumbnail(from imageData: Data, maxSize: CGFloat) -> Data? {
        #if os(macOS)
        guard let image = NSImage(data: imageData),
              let rep = image.representations.first else { return nil }

        let srcWidth = CGFloat(rep.pixelsWide)
        let srcHeight = CGFloat(rep.pixelsHigh)
        guard srcWidth > 0 && srcHeight > 0 else { return nil }

        let scale: CGFloat
        if srcWidth >= srcHeight {
            scale = min(maxSize / srcWidth, 1.0)
        } else {
            scale = min(maxSize / srcHeight, 1.0)
        }
        let thumbWidth = Int(srcWidth * scale)
        let thumbHeight = Int(srcHeight * scale)

        let thumbImage = NSImage(size: NSSize(width: thumbWidth, height: thumbHeight))
        thumbImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight))
        thumbImage.unlockFocus()

        guard let tiffData = thumbImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return nil }
        return pngData
        #else
        guard let image = UIImage(data: imageData) else { return nil }

        let srcWidth = image.size.width
        let srcHeight = image.size.height
        guard srcWidth > 0 && srcHeight > 0 else { return nil }

        let scale: CGFloat
        if srcWidth >= srcHeight {
            scale = min(maxSize / srcWidth, 1.0)
        } else {
            scale = min(maxSize / srcHeight, 1.0)
        }
        let thumbSize = CGSize(width: srcWidth * scale, height: srcHeight * scale)

        UIGraphicsBeginImageContextWithOptions(thumbSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: thumbSize))
        let thumbImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return thumbImage?.pngData()
        #endif
    }

    /// Regenerate thumbnails whose longest dimension doesn't match `maxSize`.
    /// Calls `progress` with 0.0–1.0 after each file. Returns the number of files migrated.
    @discardableResult
    func migrateThumbnails(in folder: URL, maxSize: CGFloat, progress: @Sendable (Double) -> Void) -> Int {
        let thumbnailsDir = folder.appendingPathComponent(".thumbnails")
        let generationsDir = folder.appendingPathComponent("generations")
        guard let files = try? fileManager.contentsOfDirectory(at: thumbnailsDir, includingPropertiesForKeys: nil) else { return 0 }

        let pngFiles = files.filter { $0.pathExtension.lowercased() == "png" }

        // First pass: find files needing resize (lightweight header-only check)
        var needsResize: [(thumbURL: URL, fullURL: URL)] = []
        let maxSizeInt = Int(maxSize)
        for thumbURL in pngFiles {
            guard let source = CGImageSourceCreateWithURL(thumbURL as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let pw = props[kCGImagePropertyPixelWidth] as? Int,
                  let ph = props[kCGImagePropertyPixelHeight] as? Int else { continue }

            let longest = max(pw, ph)

            // Check if the full source image exists and is large enough to warrant resizing
            let fullURL = generationsDir.appendingPathComponent(thumbURL.lastPathComponent)
            guard fileManager.fileExists(atPath: fullURL.path) else { continue }

            // If the source image's longest edge is smaller than maxSize, the thumbnail
            // should match the source (no upscaling). Only flag if the source is >= maxSize
            // and the thumbnail doesn't match the target, or if the thumbnail is larger than maxSize.
            if longest > maxSizeInt + 2 {
                // Thumbnail is oversized — always regenerate
            } else if longest < maxSizeInt - 2 {
                // Thumbnail is smaller than target — check if source could produce a larger one
                guard let fullSource = CGImageSourceCreateWithURL(fullURL as CFURL, nil),
                      let fullProps = CGImageSourceCopyPropertiesAtIndex(fullSource, 0, nil) as? [CFString: Any],
                      let fw = fullProps[kCGImagePropertyPixelWidth] as? Int,
                      let fh = fullProps[kCGImagePropertyPixelHeight] as? Int else { continue }
                let fullLongest = max(fw, fh)
                // Source is large enough that thumbnail should be at maxSize but isn't
                guard fullLongest >= maxSizeInt else { continue }
            } else {
                // Within tolerance of target — no resize needed
                continue
            }

            needsResize.append((thumbURL: thumbURL, fullURL: fullURL))
        }

        guard !needsResize.isEmpty else { return 0 }

        let total = Double(needsResize.count)
        for (i, item) in needsResize.enumerated() {
            guard let fullData = try? Data(contentsOf: item.fullURL),
                  let newThumb = generateThumbnail(from: fullData, maxSize: maxSize) else {
                progress(Double(i + 1) / total)
                continue
            }
            try? newThumb.write(to: item.thumbURL)
            ThumbnailCache.shared.invalidate(url: item.thumbURL)
            progress(Double(i + 1) / total)
        }

        return needsResize.count
    }

    // MARK: - Activity Persistence

    @MainActor
    func loadActivity(from folder: URL) -> [GenerationJob] {
        let activityURL = folder.appendingPathComponent(".activity.json")
        guard fileManager.fileExists(atPath: activityURL.path),
              let data = try? Data(contentsOf: activityURL),
              let records = try? decoder.decode([ActivityRecord].self, from: data) else {
            return []
        }
        return records.map { GenerationJob(from: $0) }
    }

    @MainActor
    func saveActivity(_ jobs: [GenerationJob], to folder: URL) {
        let activityURL = folder.appendingPathComponent(".activity.json")
        let records = jobs
            .filter { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
            .map { $0.toRecord() }
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: activityURL)
    }

    // MARK: - Project Preferences

    func loadPreferences(from folder: URL) -> ProjectPreferences {
        let url = folder.appendingPathComponent(".preferences.json")
        guard let data = try? Data(contentsOf: url),
              let prefs = try? decoder.decode(ProjectPreferences.self, from: data) else {
            return ProjectPreferences()
        }
        return prefs
    }

    func savePreferences(_ prefs: ProjectPreferences, to folder: URL) {
        let url = folder.appendingPathComponent(".preferences.json")
        guard let data = try? encoder.encode(prefs) else { return }
        try? data.write(to: url)
    }

    // MARK: - Delete Generation Images

    /// Deletes image files, their thumbnails, and orphaned .meta files for the given filenames.
    func deleteGenerationImages(fileNames: Set<String>, from folder: URL) {
        let generationsDir = folder.appendingPathComponent("generations")
        let thumbnailsDir = folder.appendingPathComponent(".thumbnails")

        // Group filenames by meta base name to determine orphaned .meta files
        var baseNameToFiles: [String: [String]] = [:]
        for fileName in fileNames {
            let base = metaBaseName(from: fileName)
            baseNameToFiles[base, default: []].append(fileName)
        }

        // Delete each image and its thumbnail
        for fileName in fileNames {
            let imageURL = generationsDir.appendingPathComponent(fileName)
            let thumbURL = thumbnailsDir.appendingPathComponent(fileName)
            try? fileManager.removeItem(at: imageURL)
            try? fileManager.removeItem(at: thumbURL)
        }

        // Check if .meta files are now orphaned (no sibling images remain)
        for (baseName, _) in baseNameToFiles {
            let metaURL = generationsDir.appendingPathComponent("\(baseName).meta")
            guard fileManager.fileExists(atPath: metaURL.path) else { continue }

            // Check if any sibling images with the same base name still exist
            let siblingExists: Bool
            if let allFiles = try? fileManager.contentsOfDirectory(atPath: generationsDir.path) {
                siblingExists = allFiles.contains { file in
                    file.hasSuffix(".png") && metaBaseName(from: file) == baseName
                }
            } else {
                siblingExists = false
            }

            if !siblingExists {
                try? fileManager.removeItem(at: metaURL)
                metaCache.removeValue(forKey: baseName)
            }
        }
    }

    // MARK: - Helpers

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_ "))
        let filtered = name.unicodeScalars.filter { allowed.contains($0) }.map { Character($0) }
        let result = String(filtered).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "untitled" : result.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private func uniqueFolderName(for name: String, in parent: URL) -> String {
        let base = sanitize(name)
        var candidate = base
        var counter = 1
        while fileManager.fileExists(atPath: parent.appendingPathComponent(candidate).path) {
            counter += 1
            candidate = "\(base)-\(counter)"
        }
        return candidate
    }
}

// MARK: - Project Preferences

struct ProjectPreferences: Codable {
    var skipDeleteConfirmation: Bool = false
}

enum ProjectError: LocalizedError {
    case noRootFolder

    var errorDescription: String? {
        switch self {
        case .noRootFolder: return "No projects folder selected. Please choose a folder in Settings."
        }
    }
}
