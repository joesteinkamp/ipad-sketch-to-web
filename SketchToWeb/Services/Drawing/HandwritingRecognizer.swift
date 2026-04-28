import Foundation
import Vision
import CoreGraphics

/// Async wrapper around `VNRecognizeTextRequest` for recognizing short handwritten labels
/// drawn inside boxes on a PencilKit canvas.
enum HandwritingRecognizer {

    enum RecognitionError: Error {
        case visionFailure(Error)
    }

    /// Recognizes text in the given image and returns up to `maxCandidates` of the
    /// highest-confidence strings, ordered best-first.
    ///
    /// - Parameters:
    ///   - image: The cropped CGImage containing handwriting (already composited onto a white background).
    ///   - customWords: Vocabulary the recognizer should bias toward (e.g. component names).
    ///   - maxCandidates: How many candidate strings to return per detected text region.
    static func recognize(
        in image: CGImage,
        customWords: [String],
        maxCandidates: Int = 3
    ) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            // Hop to a background queue so `handler.perform` doesn't block the calling
            // thread (often the main actor when invoked from the canvas overlay).
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: RecognitionError.visionFailure(error))
                        return
                    }
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let strings = observations.flatMap { observation in
                        observation.topCandidates(maxCandidates).map(\.string)
                    }
                    continuation.resume(returning: strings)
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.customWords = customWords
                request.recognitionLanguages = ["en-US"]

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: RecognitionError.visionFailure(error))
                }
            }
        }
    }
}
