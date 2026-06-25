import UIKit
@preconcurrency import Vision

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Local-only image analysis. Vision OCR is always attempted; Foundation Models are used only when available.
enum MapAnalyzer {
    /// Returns a practical default name and hints extracted from the imported map image.
    static func analyze(image: UIImage, fallbackName: String) async -> MapAnalysisResult {
        let recognizedText = await recognizeText(in: image)
        let hints = MappyLogic.cleanHints(from: recognizedText)
        let suggestedName = MappyLogic.suggestedName(fallbackName: fallbackName, hints: hints)
        return MapAnalysisResult(suggestedName: suggestedName, hints: hints)
    }

    /// Keeps Foundation Models availability isolated so views can hide Auto Align when the device cannot run it.
    static var isFoundationModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return true
            default:
                return false
            }
        }
        #endif
        return false
    }

    /// Performs OCR using Vision and returns candidate strings. Errors simply produce no hints.
    private static func recognizeText(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let strings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                continuation.resume(returning: strings)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
}
