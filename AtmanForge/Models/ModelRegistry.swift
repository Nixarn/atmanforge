import Foundation
#if os(macOS)
import AppKit
#endif

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
    /// Omit to have the model shown in a fresh install's picker. Optional so
    /// that existing custom Models.json files keep decoding.
    let visibleByDefault: Bool?
    /// Provider key carrying the image size for models that take one literal
    /// value ("1536x1024") rather than separate ratio and resolution keys.
    /// `openai/gpt-image-2` overloads its own `aspect_ratio` this way.
    let sizeKey: String?
    /// Aspect ratio -> resolution -> the literal value to send for `sizeKey`.
    /// Sparse on purpose: gpt-image-2 offers 4K at 16:9 but not at 1:1.
    let sizeMatrix: [String: [String: String]]?

    /// Whether a fresh install shows this model before the user touches
    /// Settings -> Models. Hidden models are still selectable by un-hiding them.
    var isVisibleByDefault: Bool { visibleByDefault ?? true }

    var supportsResolution: Bool { !resolutions.isEmpty }
    var supportsNativeImageCount: Bool { nativeBatchKey != nil }

    /// Resolutions offered for `ratio`. Matrix-backed models vary by ratio;
    /// every other model offers the same list throughout.
    func resolutions(for ratio: AspectRatio) -> [ImageResolution] {
        guard let sizeMatrix else { return resolutions }
        guard let row = sizeMatrix[ratio.rawValue] else { return [] }
        return resolutions.filter { row[$0.rawValue] != nil }
    }

    /// The literal value to send for `sizeKey`, or nil when this model has no
    /// matrix or does not offer that combination.
    func sizeValue(for ratio: AspectRatio, resolution: ImageResolution?) -> String? {
        guard let sizeMatrix, let resolution else { return nil }
        return sizeMatrix[ratio.rawValue]?[resolution.rawValue]
    }

    /// Concrete pixels for a matrix-backed combination, parsed from "1536x1024".
    func dimensions(for ratio: AspectRatio, resolution: ImageResolution) -> (width: Int, height: Int)? {
        guard let size = sizeValue(for: ratio, resolution: resolution) else { return nil }
        return ModelDefinition.parseSize(size)
    }

    /// A tier name alone is ambiguous once literal sizes are in play — "1K" is
    /// 1536×1024 at 3:2 but 1024×1024 at 1:1 — so spell the pixels out.
    func resolutionLabel(for ratio: AspectRatio, resolution: ImageResolution) -> String {
        guard let dims = dimensions(for: ratio, resolution: resolution) else {
            return resolution.displayName
        }
        return "\(resolution.displayName) (\(dims.width)×\(dims.height))"
    }

    static func parseSize(_ size: String) -> (width: Int, height: Int)? {
        let parts = size.split(separator: "x")
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 else {
            return nil
        }
        return (w, h)
    }

    static func == (lhs: ModelDefinition, rhs: ModelDefinition) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
@Observable
final class ModelRegistry {
    static let shared = ModelRegistry()

    private(set) var models: [ModelDefinition] = []
    private(set) var loadError: String?
    private(set) var hasUserOverride: Bool = false

    private var byID: [String: ModelDefinition] = [:]

    static let userFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("AtmanForge", isDirectory: true)
            .appendingPathComponent("Models.json", isDirectory: false)
    }()

    init() {
        reload()
    }

    var generationModels: [ModelDefinition] {
        models.filter { $0.kind == .generation }
    }

    /// Model ids a fresh install starts with hidden.
    var defaultHiddenModelIDs: Set<String> {
        Set(generationModels.filter { !$0.isVisibleByDefault }.map(\.id))
    }

    var backgroundRemovalModel: ModelDefinition? {
        models.first { $0.kind == .backgroundRemoval }
    }

    func model(id: String) -> ModelDefinition? { byID[id] }

    /// Re-read bundled and user files. Sets `loadError` if the user file fails to parse or validate.
    func reload() {
        let bundled = Self.loadBundled()
        let userExists = FileManager.default.fileExists(atPath: Self.userFileURL.path)
        hasUserOverride = userExists

        guard userExists else {
            apply(bundled)
            loadError = nil
            return
        }

        do {
            let user = try Self.loadUserFile()
            apply(Self.merge(base: bundled, override: user))
            loadError = nil
        } catch {
            apply(bundled)
            loadError = error.localizedDescription
        }
    }

    /// Copy the bundled JSON to the user path if missing, then open it in the user's default editor.
    func openUserFileForEditing() throws {
        if !FileManager.default.fileExists(atPath: Self.userFileURL.path) {
            try Self.copyBundledToUserPath()
            hasUserOverride = true
        }
        #if os(macOS)
        NSWorkspace.shared.open(Self.userFileURL)
        #endif
    }

    /// Show the user file in Finder. Caller should ensure `hasUserOverride` is true.
    func revealUserFileInFinder() {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([Self.userFileURL])
        #endif
    }

    /// Delete the user override file and reload from bundled.
    func revertToBundled() throws {
        if FileManager.default.fileExists(atPath: Self.userFileURL.path) {
            try FileManager.default.removeItem(at: Self.userFileURL)
        }
        reload()
    }

    private func apply(_ models: [ModelDefinition]) {
        self.models = models
        self.byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
    }

    /// Merge by id: each base entry is replaced by an override entry with the same id;
    /// override entries with new ids are appended.
    private static func merge(base: [ModelDefinition], override: [ModelDefinition]) -> [ModelDefinition] {
        let overrideByID = Dictionary(uniqueKeysWithValues: override.map { ($0.id, $0) })
        var seen = Set<String>()
        var result: [ModelDefinition] = []
        for model in base {
            result.append(overrideByID[model.id] ?? model)
            seen.insert(model.id)
        }
        for model in override where !seen.contains(model.id) {
            result.append(model)
        }
        return result
    }

    private static func loadBundled() -> [ModelDefinition] {
        guard let url = Bundle.main.url(forResource: "Models", withExtension: "json") else {
            fatalError("Bundled Models.json missing")
        }
        do {
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            try validate(manifest.models)
            return manifest.models
        } catch {
            fatalError("Bundled Models.json invalid: \(error)")
        }
    }

    private static func loadUserFile() throws -> [ModelDefinition] {
        let data = try Data(contentsOf: userFileURL)
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
        } catch let DecodingError.keyNotFound(key, ctx) {
            throw RegistryError.validation("Missing field \"\(key.stringValue)\"\(pathSuffix(ctx.codingPath))")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw RegistryError.validation("Wrong type\(pathSuffix(ctx.codingPath)): \(ctx.debugDescription)")
        } catch let DecodingError.valueNotFound(_, ctx) {
            throw RegistryError.validation("Missing value\(pathSuffix(ctx.codingPath))")
        } catch let DecodingError.dataCorrupted(ctx) {
            throw RegistryError.validation("Invalid JSON: \(ctx.debugDescription)")
        }
        try validate(manifest.models)
        return manifest.models
    }

    private static func pathSuffix(_ path: [CodingKey]) -> String {
        guard !path.isEmpty else { return "" }
        return " at " + path.map { $0.stringValue }.joined(separator: ".")
    }

    private static func copyBundledToUserPath() throws {
        let dir = userFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let bundled = Bundle.main.url(forResource: "Models", withExtension: "json") else {
            throw RegistryError.bundledMissing
        }
        if FileManager.default.fileExists(atPath: userFileURL.path) {
            try FileManager.default.removeItem(at: userFileURL)
        }
        try FileManager.default.copyItem(at: bundled, to: userFileURL)
    }

    private static func validate(_ models: [ModelDefinition]) throws {
        var ids = Set<String>()
        for m in models {
            if m.id.isEmpty { throw RegistryError.validation("Model has empty \"id\"") }
            if !ids.insert(m.id).inserted {
                throw RegistryError.validation("Duplicate model id: \"\(m.id)\"")
            }
            if m.replicateModelID.isEmpty {
                throw RegistryError.validation("\(m.id): \"replicateModelID\" is empty")
            }
            if m.aspectRatios.isEmpty {
                throw RegistryError.validation("\(m.id): \"aspectRatios\" is empty")
            }
            if m.maxImages < 1 {
                throw RegistryError.validation("\(m.id): \"maxImages\" must be ≥ 1")
            }
            if m.maxReferenceImages < 0 {
                throw RegistryError.validation("\(m.id): \"maxReferenceImages\" must be ≥ 0")
            }
            try validateSizeMatrix(m)
            var paramKeys = Set<String>()
            for spec in m.parameters {
                if !paramKeys.insert(spec.key).inserted {
                    throw RegistryError.validation("\(m.id): duplicate parameter key \"\(spec.key)\"")
                }
                try validate(spec, modelID: m.id)
            }
        }
    }

    /// A matrix-backed model has to cover every ratio it advertises, or the
    /// picker offers combinations the provider will reject.
    private static func validateSizeMatrix(_ m: ModelDefinition) throws {
        guard m.sizeKey != nil || m.sizeMatrix != nil else { return }
        guard let sizeKey = m.sizeKey, !sizeKey.isEmpty else {
            throw RegistryError.validation("\(m.id): \"sizeMatrix\" requires a non-empty \"sizeKey\"")
        }
        guard let matrix = m.sizeMatrix else {
            throw RegistryError.validation("\(m.id): \"sizeKey\" requires a \"sizeMatrix\"")
        }
        if m.resolutions.isEmpty {
            throw RegistryError.validation("\(m.id): \"sizeMatrix\" requires a non-empty \"resolutions\"")
        }
        for (ratioKey, row) in matrix {
            guard let ratio = AspectRatio(rawValue: ratioKey) else {
                throw RegistryError.validation("\(m.id): sizeMatrix has unknown aspect ratio \"\(ratioKey)\"")
            }
            guard m.aspectRatios.contains(ratio) else {
                throw RegistryError.validation(
                    "\(m.id): sizeMatrix lists \"\(ratioKey)\", which is not in \"aspectRatios\"")
            }
            if row.isEmpty {
                throw RegistryError.validation("\(m.id): sizeMatrix entry \"\(ratioKey)\" is empty")
            }
            for (resKey, size) in row {
                guard let res = ImageResolution(rawValue: resKey) else {
                    throw RegistryError.validation(
                        "\(m.id): sizeMatrix[\(ratioKey)] has unknown resolution \"\(resKey)\"")
                }
                guard m.resolutions.contains(res) else {
                    throw RegistryError.validation(
                        "\(m.id): sizeMatrix[\(ratioKey)] lists \"\(resKey)\", which is not in \"resolutions\"")
                }
                guard ModelDefinition.parseSize(size) != nil else {
                    throw RegistryError.validation(
                        "\(m.id): sizeMatrix[\(ratioKey)][\(resKey)] = \"\(size)\" is not WIDTHxHEIGHT")
                }
            }
        }
        for ratio in m.aspectRatios where matrix[ratio.rawValue] == nil {
            throw RegistryError.validation("\(m.id): sizeMatrix has no entry for aspect ratio \"\(ratio.rawValue)\"")
        }
    }

    private static func validate(_ spec: ParameterSpec, modelID: String) throws {
        let prefix = "\(modelID).\(spec.key)"
        if spec.key.isEmpty { throw RegistryError.validation("\(modelID): parameter has empty \"key\"") }
        switch spec.control {
        case .picker:
            guard let options = spec.options, !options.isEmpty else {
                throw RegistryError.validation("\(prefix): picker requires non-empty \"options\"")
            }
            guard let str = spec.defaultValue.stringValue else {
                throw RegistryError.validation("\(prefix): picker default must be a string")
            }
            guard options.contains(str) else {
                throw RegistryError.validation("\(prefix): default \"\(str)\" not in options \(options)")
            }
        case .slider:
            guard let min = spec.min, let max = spec.max else {
                throw RegistryError.validation("\(prefix): slider requires \"min\" and \"max\"")
            }
            guard min < max else {
                throw RegistryError.validation("\(prefix): slider \"min\" must be < \"max\"")
            }
            guard let d = spec.defaultValue.doubleValue else {
                throw RegistryError.validation("\(prefix): slider default must be a number")
            }
            guard d >= min, d <= max else {
                throw RegistryError.validation("\(prefix): default \(d) outside [\(min), \(max)]")
            }
        case .toggle:
            guard spec.defaultValue.boolValue != nil else {
                throw RegistryError.validation("\(prefix): toggle default must be a bool")
            }
        }
    }

    private struct Manifest: Decodable {
        let models: [ModelDefinition]
    }

    enum RegistryError: LocalizedError {
        case bundledMissing
        case validation(String)
        var errorDescription: String? {
            switch self {
            case .bundledMissing: return "Bundled Models.json is missing."
            case .validation(let msg): return msg
            }
        }
    }
}
