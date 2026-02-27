import SwiftUI

@Observable
class GenerationJob: Identifiable {
    let id: UUID
    let model: AIModel
    let prompt: String
    let projectID: String
    let createdAt: Date

    // All generation settings
    let aspectRatio: AspectRatio
    let resolution: ImageResolution?
    let imageCount: Int
    let gptQuality: GPTQuality?
    let gptBackground: GPTBackground?
    let gptInputFidelity: GPTInputFidelity?

    var status: Status = .pending
    var resultImageData: [Data] = []
    var savedImagePaths: [String] = []
    var thumbnailPaths: [String] = []
    var referenceImagePaths: [String] = []
    var errorMessage: String?
    var requestParamsJSON: String?

    // Cancel & timing (transient, not persisted except startedAt/completedAt)
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

    init(model: AIModel, prompt: String, projectID: String,
         aspectRatio: AspectRatio, resolution: ImageResolution?,
         imageCount: Int, gptQuality: GPTQuality?,
         gptBackground: GPTBackground?, gptInputFidelity: GPTInputFidelity?) {
        self.id = UUID()
        self.model = model
        self.prompt = prompt
        self.projectID = projectID
        self.createdAt = Date()
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.imageCount = imageCount
        self.gptQuality = gptQuality
        self.gptBackground = gptBackground
        self.gptInputFidelity = gptInputFidelity
    }

    init(from record: ActivityRecord) {
        self.id = record.id
        self.model = record.model
        self.prompt = record.prompt
        self.projectID = record.projectID
        self.createdAt = record.createdAt
        self.aspectRatio = record.aspectRatio
        self.resolution = record.resolution
        self.imageCount = record.imageCount
        self.gptQuality = record.gptQuality
        self.gptBackground = record.gptBackground
        self.gptInputFidelity = record.gptInputFidelity
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
            id: id, model: model, prompt: prompt, projectID: projectID,
            createdAt: createdAt, aspectRatio: aspectRatio, resolution: resolution,
            imageCount: imageCount, gptQuality: gptQuality,
            gptBackground: gptBackground, gptInputFidelity: gptInputFidelity,
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
        if let q = gptQuality { parts.append("Q:\(q.displayName)") }
        if let bg = gptBackground, bg != .auto { parts.append("BG:\(bg.displayName)") }
        if let f = gptInputFidelity { parts.append("Fidelity:\(f.displayName)") }
        return parts.joined(separator: " · ")
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
    let model: AIModel
    let prompt: String
    let projectID: String
    let createdAt: Date
    let aspectRatio: AspectRatio
    let resolution: ImageResolution?
    let imageCount: Int
    let gptQuality: GPTQuality?
    let gptBackground: GPTBackground?
    let gptInputFidelity: GPTInputFidelity?
    let status: GenerationJob.Status
    let savedImagePaths: [String]
    let thumbnailPaths: [String]
    let referenceImagePaths: [String]
    let errorMessage: String?
    let startedAt: Date?
    let completedAt: Date?
    let requestParamsJSON: String?

    init(id: UUID, model: AIModel, prompt: String, projectID: String,
         createdAt: Date, aspectRatio: AspectRatio, resolution: ImageResolution?,
         imageCount: Int, gptQuality: GPTQuality?, gptBackground: GPTBackground?,
         gptInputFidelity: GPTInputFidelity?, status: GenerationJob.Status,
         savedImagePaths: [String], thumbnailPaths: [String], referenceImagePaths: [String] = [],
         errorMessage: String?,
         startedAt: Date? = nil, completedAt: Date? = nil, requestParamsJSON: String? = nil) {
        self.id = id
        self.model = model
        self.prompt = prompt
        self.projectID = projectID
        self.createdAt = createdAt
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.imageCount = imageCount
        self.gptQuality = gptQuality
        self.gptBackground = gptBackground
        self.gptInputFidelity = gptInputFidelity
        self.status = status
        self.savedImagePaths = savedImagePaths
        self.thumbnailPaths = thumbnailPaths
        self.referenceImagePaths = referenceImagePaths
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.requestParamsJSON = requestParamsJSON
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        model = try container.decode(AIModel.self, forKey: .model)
        prompt = try container.decode(String.self, forKey: .prompt)
        projectID = try container.decode(String.self, forKey: .projectID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        aspectRatio = try container.decode(AspectRatio.self, forKey: .aspectRatio)
        resolution = try container.decodeIfPresent(ImageResolution.self, forKey: .resolution)
        imageCount = try container.decode(Int.self, forKey: .imageCount)
        gptQuality = try container.decodeIfPresent(GPTQuality.self, forKey: .gptQuality)
        gptBackground = try container.decodeIfPresent(GPTBackground.self, forKey: .gptBackground)
        gptInputFidelity = try container.decodeIfPresent(GPTInputFidelity.self, forKey: .gptInputFidelity)
        status = try container.decode(GenerationJob.Status.self, forKey: .status)
        savedImagePaths = try container.decode([String].self, forKey: .savedImagePaths)
        thumbnailPaths = try container.decode([String].self, forKey: .thumbnailPaths)
        referenceImagePaths = try container.decodeIfPresent([String].self, forKey: .referenceImagePaths) ?? []
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        requestParamsJSON = try container.decodeIfPresent(String.self, forKey: .requestParamsJSON)
    }
}

struct ImageMeta: Codable {
    let prompt: String
    let model: AIModel
    let aspectRatio: AspectRatio
    let resolution: ImageResolution?
    let imageCount: Int
    let gptQuality: GPTQuality?
    let gptBackground: GPTBackground?
    let gptInputFidelity: GPTInputFidelity?
    let referenceHashes: [String]
    let createdAt: Date
}

