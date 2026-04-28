import SwiftUI

@Observable
class GenerationJob: Identifiable {
    let id: UUID
    let modelID: String
    let prompt: String
    let projectID: String
    let createdAt: Date

    let aspectRatio: AspectRatio
    let resolution: ImageResolution?
    let imageCount: Int
    let parameters: [String: ParameterValue]

    var status: Status = .pending
    var resultImageData: [Data] = []
    var savedImagePaths: [String] = []
    var thumbnailPaths: [String] = []
    var referenceImagePaths: [String] = []
    var errorMessage: String?
    var requestParamsJSON: String?

    var cancelURLs: [String] = []
    var startedAt: Date?
    var completedAt: Date?

    enum Status: String, Codable {
        case pending
        case running
        case completed
        case failed
        case cancelled
    }

    var elapsedTime: TimeInterval? {
        guard let start = startedAt else { return nil }
        let end = completedAt ?? Date()
        return end.timeIntervalSince(start)
    }

    var model: ModelDefinition? {
        ModelRegistry.shared.model(id: modelID)
    }

    var displayName: String {
        model?.displayName ?? modelID
    }

    init(modelID: String, prompt: String, projectID: String,
         aspectRatio: AspectRatio, resolution: ImageResolution?,
         imageCount: Int, parameters: [String: ParameterValue]) {
        self.id = UUID()
        self.modelID = modelID
        self.prompt = prompt
        self.projectID = projectID
        self.createdAt = Date()
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.imageCount = imageCount
        self.parameters = parameters
    }

    init(from record: ActivityRecord) {
        self.id = record.id
        self.modelID = record.modelID
        self.prompt = record.prompt
        self.projectID = record.projectID
        self.createdAt = record.createdAt
        self.aspectRatio = record.aspectRatio
        self.resolution = record.resolution
        self.imageCount = record.imageCount
        self.parameters = record.parameters
        self.status = record.status
        self.savedImagePaths = record.savedImagePaths
        self.thumbnailPaths = record.thumbnailPaths
        self.referenceImagePaths = record.referenceImagePaths
        self.errorMessage = record.errorMessage
        self.startedAt = record.startedAt
        self.completedAt = record.completedAt
        self.requestParamsJSON = record.requestParamsJSON
    }

    func toRecord() -> ActivityRecord {
        ActivityRecord(
            id: id, modelID: modelID, prompt: prompt, projectID: projectID,
            createdAt: createdAt, aspectRatio: aspectRatio, resolution: resolution,
            imageCount: imageCount, parameters: parameters,
            status: status, savedImagePaths: savedImagePaths,
            thumbnailPaths: thumbnailPaths, referenceImagePaths: referenceImagePaths,
            errorMessage: errorMessage,
            startedAt: startedAt, completedAt: completedAt,
            requestParamsJSON: requestParamsJSON
        )
    }

    var settingsSummary: String {
        var parts: [String] = [aspectRatio.displayName]
        if let res = resolution { parts.append(res.displayName) }
        if imageCount > 1 { parts.append("\(imageCount) images") }
        if let specs = model?.parameters {
            for spec in specs {
                guard let value = parameters[spec.key] else { continue }
                switch value {
                case .string(let s): parts.append("\(spec.label): \(s)")
                case .double(let d): parts.append("\(spec.label): \(formatted(d))")
                case .bool(let b): parts.append("\(spec.label): \(b ? "on" : "off")")
                }
            }
        }
        return parts.joined(separator: " · ")
    }

    private func formatted(_ d: Double) -> String {
        d.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(d))
            : String(format: "%.2f", d)
    }

    var progressText: String {
        switch status {
        case .pending: return "Queued"
        case .running: return "Generating..."
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var statusIcon: String {
        switch status {
        case .pending: return "clock"
        case .running: return "arrow.trianglehead.2.counterclockwise"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }

    var statusColor: Color {
        switch status {
        case .pending: return .secondary
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}

struct ActivityRecord: Codable {
    let id: UUID
    let modelID: String
    let prompt: String
    let projectID: String
    let createdAt: Date
    let aspectRatio: AspectRatio
    let resolution: ImageResolution?
    let imageCount: Int
    let parameters: [String: ParameterValue]
    let status: GenerationJob.Status
    let savedImagePaths: [String]
    let thumbnailPaths: [String]
    let referenceImagePaths: [String]
    let errorMessage: String?
    let startedAt: Date?
    let completedAt: Date?
    let requestParamsJSON: String?

    init(id: UUID, modelID: String, prompt: String, projectID: String,
         createdAt: Date, aspectRatio: AspectRatio, resolution: ImageResolution?,
         imageCount: Int, parameters: [String: ParameterValue],
         status: GenerationJob.Status,
         savedImagePaths: [String], thumbnailPaths: [String], referenceImagePaths: [String] = [],
         errorMessage: String?,
         startedAt: Date? = nil, completedAt: Date? = nil, requestParamsJSON: String? = nil) {
        self.id = id
        self.modelID = modelID
        self.prompt = prompt
        self.projectID = projectID
        self.createdAt = createdAt
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.imageCount = imageCount
        self.parameters = parameters
        self.status = status
        self.savedImagePaths = savedImagePaths
        self.thumbnailPaths = thumbnailPaths
        self.referenceImagePaths = referenceImagePaths
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.requestParamsJSON = requestParamsJSON
    }

    enum CodingKeys: String, CodingKey {
        case id, prompt, projectID, createdAt, aspectRatio, resolution
        case imageCount, status, savedImagePaths, thumbnailPaths
        case referenceImagePaths, errorMessage, startedAt, completedAt
        case requestParamsJSON, parameters
        case modelID = "model"
        // legacy
        case gptQuality, gptBackground, gptInputFidelity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        modelID = try c.decode(String.self, forKey: .modelID)
        prompt = try c.decode(String.self, forKey: .prompt)
        projectID = try c.decode(String.self, forKey: .projectID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        aspectRatio = try c.decode(AspectRatio.self, forKey: .aspectRatio)
        resolution = try c.decodeIfPresent(ImageResolution.self, forKey: .resolution)
        imageCount = try c.decode(Int.self, forKey: .imageCount)
        status = try c.decode(GenerationJob.Status.self, forKey: .status)
        savedImagePaths = try c.decode([String].self, forKey: .savedImagePaths)
        thumbnailPaths = try c.decode([String].self, forKey: .thumbnailPaths)
        referenceImagePaths = try c.decodeIfPresent([String].self, forKey: .referenceImagePaths) ?? []
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        requestParamsJSON = try c.decodeIfPresent(String.self, forKey: .requestParamsJSON)
        parameters = ActivityRecord.decodeParameters(from: c)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(modelID, forKey: .modelID)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(projectID, forKey: .projectID)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(aspectRatio, forKey: .aspectRatio)
        try c.encodeIfPresent(resolution, forKey: .resolution)
        try c.encode(imageCount, forKey: .imageCount)
        try c.encode(parameters, forKey: .parameters)
        try c.encode(status, forKey: .status)
        try c.encode(savedImagePaths, forKey: .savedImagePaths)
        try c.encode(thumbnailPaths, forKey: .thumbnailPaths)
        try c.encode(referenceImagePaths, forKey: .referenceImagePaths)
        try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encodeIfPresent(requestParamsJSON, forKey: .requestParamsJSON)
    }

    static func decodeParameters(from c: KeyedDecodingContainer<CodingKeys>) -> [String: ParameterValue] {
        var params = (try? c.decode([String: ParameterValue].self, forKey: .parameters)) ?? [:]
        if let q = try? c.decodeIfPresent(String.self, forKey: .gptQuality) {
            params["quality"] = .string(q)
        }
        if let bg = try? c.decodeIfPresent(String.self, forKey: .gptBackground) {
            params["background"] = .string(bg)
        }
        if let f = try? c.decodeIfPresent(String.self, forKey: .gptInputFidelity) {
            params["input_fidelity"] = .string(f)
        }
        return params
    }
}

struct ImageMeta: Codable {
    let prompt: String
    let modelID: String
    let aspectRatio: AspectRatio
    let resolution: ImageResolution?
    let imageCount: Int
    let parameters: [String: ParameterValue]
    let referenceHashes: [String]
    let createdAt: Date

    init(prompt: String, modelID: String, aspectRatio: AspectRatio,
         resolution: ImageResolution?, imageCount: Int,
         parameters: [String: ParameterValue], referenceHashes: [String], createdAt: Date) {
        self.prompt = prompt
        self.modelID = modelID
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.imageCount = imageCount
        self.parameters = parameters
        self.referenceHashes = referenceHashes
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case prompt, aspectRatio, resolution, imageCount, parameters
        case referenceHashes, createdAt
        case modelID = "model"
        // legacy
        case gptQuality, gptBackground, gptInputFidelity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prompt = try c.decode(String.self, forKey: .prompt)
        modelID = try c.decode(String.self, forKey: .modelID)
        aspectRatio = try c.decode(AspectRatio.self, forKey: .aspectRatio)
        resolution = try c.decodeIfPresent(ImageResolution.self, forKey: .resolution)
        imageCount = try c.decode(Int.self, forKey: .imageCount)
        referenceHashes = try c.decode([String].self, forKey: .referenceHashes)
        createdAt = try c.decode(Date.self, forKey: .createdAt)

        var params = (try? c.decode([String: ParameterValue].self, forKey: .parameters)) ?? [:]
        if let q = try? c.decodeIfPresent(String.self, forKey: .gptQuality) {
            params["quality"] = .string(q)
        }
        if let bg = try? c.decodeIfPresent(String.self, forKey: .gptBackground) {
            params["background"] = .string(bg)
        }
        if let f = try? c.decodeIfPresent(String.self, forKey: .gptInputFidelity) {
            params["input_fidelity"] = .string(f)
        }
        parameters = params
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(modelID, forKey: .modelID)
        try c.encode(aspectRatio, forKey: .aspectRatio)
        try c.encodeIfPresent(resolution, forKey: .resolution)
        try c.encode(imageCount, forKey: .imageCount)
        try c.encode(parameters, forKey: .parameters)
        try c.encode(referenceHashes, forKey: .referenceHashes)
        try c.encode(createdAt, forKey: .createdAt)
    }
}
