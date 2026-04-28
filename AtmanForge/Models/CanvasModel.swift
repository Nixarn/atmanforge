import Foundation

struct CanvasManifest: Codable {
    var name: String
    var prompt: String
    var model: String
    var width: Int
    var height: Int
    var history: [GenerationRecord]
    var createdAt: Date

    init(name: String, width: Int = 1024, height: Int = 1024) {
        self.name = name
        self.prompt = ""
        self.model = "gemini-2.5"
        self.width = width
        self.height = height
        self.history = []
        self.createdAt = Date()
    }
}

struct GenerationRecord: Codable, Identifiable {
    var id: UUID
    var prompt: String
    var model: String
    var width: Int
    var height: Int
    var timestamp: Date

    init(prompt: String, model: String, width: Int, height: Int) {
        self.id = UUID()
        self.prompt = prompt
        self.model = model
        self.width = width
        self.height = height
        self.timestamp = Date()
    }
}

struct Canvas: Identifiable {
    let id: String
    var folderURL: URL
    var manifest: CanvasManifest

    var name: String { manifest.name }

    var imageURL: URL {
        folderURL.appendingPathComponent("image.png")
    }

    var hasImage: Bool {
        FileManager.default.fileExists(atPath: imageURL.path)
    }
}

enum ImageResolution: String, CaseIterable, Codable {
    case r512 = "512"
    case r1k = "1K"
    case r2k = "2K"
    case r4k = "4K"

    var displayName: String { rawValue }

    var baseSize: Int {
        switch self {
        case .r512: return 512
        case .r1k: return 1024
        case .r2k: return 2048
        case .r4k: return 4096
        }
    }

    func dimensions(for aspect: AspectRatio) -> (width: Int, height: Int) {
        let base = baseSize
        let (w, h) = aspect.ratio
        if w >= h {
            let width = base
            let height = Int(Double(base) * Double(h) / Double(w))
            return (width, height)
        } else {
            let height = base
            let width = Int(Double(base) * Double(w) / Double(h))
            return (width, height)
        }
    }
}

enum AspectRatio: String, CaseIterable, Codable {
    case r8_1 = "8:1"
    case r4_1 = "4:1"
    case r21_9 = "21:9"
    case r16_9 = "16:9"
    case r3_2 = "3:2"
    case r4_3 = "4:3"
    case r5_4 = "5:4"
    case r1_1 = "1:1"
    case r4_5 = "4:5"
    case r3_4 = "3:4"
    case r2_3 = "2:3"
    case r9_16 = "9:16"
    case r1_4 = "1:4"
    case r1_8 = "1:8"

    var displayName: String { rawValue }

    var ratio: (w: Int, h: Int) {
        switch self {
        case .r8_1: return (8, 1)
        case .r4_1: return (4, 1)
        case .r21_9: return (21, 9)
        case .r16_9: return (16, 9)
        case .r3_2: return (3, 2)
        case .r4_3: return (4, 3)
        case .r5_4: return (5, 4)
        case .r1_1: return (1, 1)
        case .r4_5: return (4, 5)
        case .r3_4: return (3, 4)
        case .r2_3: return (2, 3)
        case .r9_16: return (9, 16)
        case .r1_4: return (1, 4)
        case .r1_8: return (1, 8)
        }
    }
}

enum CanvasTool: String, CaseIterable {
    case select
    case crop
    case brush

    var icon: String {
        switch self {
        case .select: return "arrow.up.left.and.arrow.down.right"
        case .crop: return "crop"
        case .brush: return "paintbrush"
        }
    }

    var label: String {
        switch self {
        case .select: return "Select"
        case .crop: return "Crop"
        case .brush: return "Brush"
        }
    }
}
