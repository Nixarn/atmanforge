import Foundation

enum ModelKind: String, Codable {
    case generation
    case backgroundRemoval = "background-removal"
}

struct ReferenceKeySpec: Codable, Equatable {
    enum Kind: String, Codable { case single, array }
    let name: String
    let kind: Kind
}

enum ParameterControl: String, Codable {
    case picker, slider, toggle
}

enum ParameterValue: Codable, Equatable, Hashable {
    case string(String)
    case double(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        throw DecodingError.dataCorruptedError(
            in: c,
            debugDescription: "ParameterValue must be string, number, or bool"
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .double(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        }
    }

    var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    var doubleValue: Double? { if case .double(let d) = self { return d } else { return nil } }
    var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }

    /// Value to embed in `[String: Any]` for `JSONSerialization` (Replicate API body).
    var jsonObject: Any {
        switch self {
        case .string(let s): return s
        case .double(let d): return d
        case .bool(let b): return b
        }
    }
}

struct ParameterSpec: Codable, Identifiable {
    let key: String
    let label: String
    let control: ParameterControl
    let options: [String]?
    let min: Double?
    let max: Double?
    let step: Double?
    let defaultValue: ParameterValue

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, control, options, min, max, step
        case defaultValue = "default"
    }
}

struct ModelDefinition: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let kind: ModelKind
    let replicateModelID: String
    let aspectRatios: [AspectRatio]
    let resolutions: [ImageResolution]
    let maxImages: Int
    let nativeBatchKey: String?
    let maxReferenceImages: Int
    let referenceKey: ReferenceKeySpec?
    let staticInputs: [String: ParameterValue]
    let parameters: [ParameterSpec]

    var supportsResolution: Bool { !resolutions.isEmpty }
    var supportsNativeImageCount: Bool { nativeBatchKey != nil }

    static func == (lhs: ModelDefinition, rhs: ModelDefinition) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ModelRegistry {
    static let shared = ModelRegistry()

    let models: [ModelDefinition]
    private let byID: [String: ModelDefinition]

    init() {
        guard let url = Bundle.main.url(forResource: "Models", withExtension: "json") else {
            fatalError("Models.json not found in bundle")
        }
        do {
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            self.models = manifest.models
            self.byID = Dictionary(uniqueKeysWithValues: manifest.models.map { ($0.id, $0) })
        } catch {
            fatalError("Models.json invalid: \(error)")
        }
    }

    func model(id: String) -> ModelDefinition? { byID[id] }

    var generationModels: [ModelDefinition] {
        models.filter { $0.kind == .generation }
    }

    var backgroundRemovalModel: ModelDefinition? {
        models.first { $0.kind == .backgroundRemoval }
    }

    private struct Manifest: Decodable {
        let models: [ModelDefinition]
    }
}
