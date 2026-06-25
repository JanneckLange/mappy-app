import Foundation

/// The outcome of an automatic alignment attempt, including the transform to preview and a confidence score.
struct AutoAlignResult: Equatable {
    let transform: MapTransform
    let confidence: Double
    let message: String

    var isReliable: Bool {
        confidence >= AutoAlignService.minimumReliableConfidence
    }
}

/// A compact binary feature image used by the alignment scorer.
struct FeatureMask: Equatable {
    let width: Int
    let height: Int
    let pixels: Set<Int>

    var isEmpty: Bool {
        pixels.isEmpty
    }

    func contains(x: Int, y: Int, radius: Int = 0) -> Bool {
        guard width > 0, height > 0 else {
            return false
        }

        if radius <= 0 {
            return x >= 0 && x < width && y >= 0 && y < height && pixels.contains(y * width + x)
        }

        for candidateY in max(0, y - radius)...min(height - 1, y + radius) {
            for candidateX in max(0, x - radius)...min(width - 1, x + radius) {
                if pixels.contains(candidateY * width + candidateX) {
                    return true
                }
            }
        }
        return false
    }
}
