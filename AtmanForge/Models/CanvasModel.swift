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
        self.model = AIModel.gemini25.rawValue
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

enum AIModelProvider: String, Codable {
    case google
    case openai
    case qwen
    case prunaai
    case blackForest
}

enum AIModel: String, Codable {
    case gemini25 = "gemini-2.5"
    case gemini30 = "gemini-3.0"
    case gptImage15 = "gpt-image-1.5"
    case qwenImage = "qwen-image"
    case qwenImage2512 = "qwen-image-2512"
    case zImageTurbo = "z-image-turbo"
    case flux2Pro = "flux-2-pro"
    case flux2Max = "flux-2-max"
    case removeBackground = "remove-background"

    /// Models available for generation (excludes utility models)
    static let generationModels: [AIModel] = [.gemini25, .gemini30, .gptImage15, .qwenImage, .qwenImage2512, .zImageTurbo, .flux2Pro, .flux2Max]

    var displayName: String {
        switch self {
        case .gemini25: return "Gemini 2.5"
        case .gemini30: return "Gemini 3.0 Pro"
        case .gptImage15: return "GPT Image 1.5"
        case .qwenImage: return "Qwen Image"
        case .qwenImage2512: return "Qwen Image 2512"
        case .zImageTurbo: return "Z-Image Turbo"
        case .flux2Pro: return "FLUX.2 Pro"
        case .flux2Max: return "FLUX.2 Max"
        case .removeBackground: return "Remove Background"
        }
    }

    var provider: AIModelProvider {
        switch self {
        case .gemini25, .gemini30: return .google
        case .gptImage15: return .openai
        case .qwenImage, .qwenImage2512: return .qwen
        case .zImageTurbo: return .prunaai
        case .flux2Pro: return .blackForest
        case .flux2Max: return .blackForest
        case .removeBackground: return .google
        }
    }

    var replicateModelID: String {
        switch self {
        case .gemini25: return "google/nano-banana"
        case .gemini30: return "google/nano-banana-pro"
        case .gptImage15: return "openai/gpt-image-1.5"
        case .qwenImage: return "qwen/qwen-image"
        case .qwenImage2512: return "qwen/qwen-image-2512"
        case .zImageTurbo: return "prunaai/z-image-turbo"
        case .flux2Pro: return "black-forest-labs/flux-2-pro"
        case .flux2Max: return "black-forest-labs/flux-2-max"
        case .removeBackground: return "bria/remove-background"
        }
    }

    var supportsResolution: Bool {
        switch self {
        case .gemini30: return true
        case .gemini25, .gptImage15, .qwenImage, .qwenImage2512, .zImageTurbo, .flux2Pro, .flux2Max, .removeBackground: return false
        }
    }

    var maxImageCount: Int {
        switch self {
        case .gemini25, .gemini30: return 4
        case .gptImage15: return 10
        case .qwenImage, .qwenImage2512, .zImageTurbo, .flux2Pro, .flux2Max: return 4
        case .removeBackground: return 1
        }
    }

    var supportsNativeImageCount: Bool {
        switch self {
        case .gptImage15: return true
        case .gemini25, .gemini30, .qwenImage, .qwenImage2512, .zImageTurbo, .flux2Pro, .flux2Max, .removeBackground: return false
        }
    }

    var maxReferenceImages: Int {
        switch self {
        case .gemini25: return 6
        case .gemini30: return 14
        case .gptImage15: return 10
        case .qwenImage, .qwenImage2512: return 1
        case .zImageTurbo: return 1
        case .flux2Pro: return 1
        case .flux2Max: return 1
        case .removeBackground: return 1
        }
    }

    var supportedAspectRatios: [AspectRatio] {
        switch self {
        case .gemini25, .gemini30, .qwenImage, .qwenImage2512, .zImageTurbo, .flux2Pro, .flux2Max:
            return [.r9_16, .r2_3, .r3_4, .r4_5, .r1_1, .r5_4, .r4_3, .r3_2, .r16_9, .r21_9]
        case .gptImage15:
            return [.r2_3, .r1_1, .r3_2]
        case .removeBackground:
            return [.r1_1]
        }
    }
}

enum GPTQuality: String, CaseIterable, Codable {
    case high
    case medium
    case low

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}

enum GPTBackground: String, CaseIterable, Codable {
    case auto
    case transparent
    case opaque

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .transparent: return "Transparent"
        case .opaque: return "Opaque"
        }
    }
}

enum GPTInputFidelity: String, CaseIterable, Codable {
    case high
    case low

    var displayName: String {
        switch self {
        case .high: return "High"
        case .low: return "Low"
        }
    }
}

enum ImageResolution: String, CaseIterable, Codable {
    case r1k = "1K"
    case r2k = "2K"
    case r4k = "4K"

    var displayName: String { rawValue }

    var baseSize: Int {
        switch self {
        case .r1k: return 1024
        case .r2k: return 2048
        case .r4k: return 4096
        }
    }

    func dimensions(for aspect: AspectRatio) -> (width: Int, height: Int) {
        let base = baseSize
        let (w, h) = aspect.ratio
        // Scale so the larger dimension equals baseSize
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

    var displayName: String { rawValue }

    var ratio: (w: Int, h: Int) {
        switch self {
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

