import Foundation

/// Searches nearby transform candidates and scores how well imported-map linework overlaps real-map linework.
enum AlignmentScorer {
    struct Match: Equatable {
        let pixelOffsetX: Int
        let pixelOffsetY: Int
        let scale: Double
        let rotationDegrees: Double
        let confidence: Double
    }

    static func bestMatch(imageMask: FeatureMask, mapMask: FeatureMask) -> Match? {
        guard !imageMask.isEmpty, !mapMask.isEmpty, imageMask.width == mapMask.width, imageMask.height == mapMask.height else {
            return nil
        }

        var bestMatch: Match?
        let rotations = [-10.0, -5.0, 0.0, 5.0, 10.0]
        let scales = [0.92, 1.0, 1.08]
        let offsets = stride(from: -18, through: 18, by: 6)

        for scale in scales {
            for rotation in rotations {
                for offsetY in offsets {
                    for offsetX in offsets {
                        let confidence = score(
                            imageMask: imageMask,
                            mapMask: mapMask,
                            pixelOffsetX: offsetX,
                            pixelOffsetY: offsetY,
                            scale: scale,
                            rotationDegrees: rotation
                        )
                        if confidence > (bestMatch?.confidence ?? 0) {
                            bestMatch = Match(
                                pixelOffsetX: offsetX,
                                pixelOffsetY: offsetY,
                                scale: scale,
                                rotationDegrees: rotation,
                                confidence: confidence
                            )
                        }
                    }
                }
            }
        }

        return bestMatch
    }

    /// Scores one candidate by transforming imported-map feature pixels into snapshot space.
    static func score(
        imageMask: FeatureMask,
        mapMask: FeatureMask,
        pixelOffsetX: Int,
        pixelOffsetY: Int,
        scale: Double,
        rotationDegrees: Double
    ) -> Double {
        guard !imageMask.isEmpty, !mapMask.isEmpty, imageMask.width == mapMask.width, imageMask.height == mapMask.height else {
            return 0
        }

        let centerX = Double(imageMask.width - 1) / 2
        let centerY = Double(imageMask.height - 1) / 2
        let radians = rotationDegrees * .pi / 180
        let cosValue = cos(radians)
        let sinValue = sin(radians)
        var tested = 0
        var overlap = 0

        for pixel in imageMask.pixels {
            let sourceX = Double(pixel % imageMask.width) - centerX
            let sourceY = Double(pixel / imageMask.width) - centerY
            let scaledX = sourceX * scale
            let scaledY = sourceY * scale
            let rotatedX = scaledX * cosValue - scaledY * sinValue
            let rotatedY = scaledX * sinValue + scaledY * cosValue
            let targetX = Int((rotatedX + centerX).rounded()) + pixelOffsetX
            let targetY = Int((rotatedY + centerY).rounded()) + pixelOffsetY

            guard targetX >= 0, targetX < mapMask.width, targetY >= 0, targetY < mapMask.height else {
                continue
            }

            tested += 1
            if mapMask.contains(x: targetX, y: targetY, radius: 1) {
                overlap += 1
            }
        }

        guard tested > 0 else {
            return 0
        }

        let imageCoverage = Double(overlap) / Double(tested)
        let mapCoverage = Double(overlap) / Double(max(1, mapMask.pixels.count))
        return (imageCoverage * 0.75) + (mapCoverage * 0.25)
    }
}
