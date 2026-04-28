import Foundation

struct GenerationRequest {
    let prompt: String
    let model: ModelDefinition
    let aspectRatio: AspectRatio
    let resolution: ImageResolution?
    let imageCount: Int
    let referenceImages: [Data]
    let parameters: [String: ParameterValue]
}

struct GenerationResult {
    let imageDataArray: [Data]
    var partialErrors: [String] = []
}

protocol AIProvider {
    func generateImage(request: GenerationRequest, parallelDelay: TimeInterval, onPredictionCreated: @Sendable @escaping (String, String?) -> Void) async throws -> GenerationResult
}
