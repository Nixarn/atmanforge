import Foundation

struct GenerationRequest {
    let prompt: String
    let model: AIModel
    let aspectRatio: AspectRatio
    let resolution: ImageResolution?
    let imageCount: Int
    let referenceImages: [Data]
    let gptQuality: GPTQuality?
    let gptBackground: GPTBackground?
    let gptInputFidelity: GPTInputFidelity?
    let fluxPromptStrength: Double?
}

struct GenerationResult {
    let imageDataArray: [Data]
}

protocol AIProvider {
    func generateImage(request: GenerationRequest, parallelDelay: TimeInterval, onPredictionCreated: @Sendable @escaping (String, String?) -> Void) async throws -> GenerationResult
}
