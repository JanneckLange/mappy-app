import UIKit

/// Coordinates snapshot creation, feature extraction, and transform scoring for Auto Align.
final class AutoAlignService {
    static let minimumReliableConfidence = 0.18

    private let snapshotProvider: MapSnapshotProvider

    init(snapshotProvider: MapSnapshotProvider = MapSnapshotProvider()) {
        self.snapshotProvider = snapshotProvider
    }

    func align(image: UIImage, baseTransform: MapTransform) async throws -> AutoAlignResult {
        let snapshot = try await snapshotProvider.snapshot(for: baseTransform)
        let imageMask = LineFeatureExtractor.extract(from: image)
        let mapMask = LineFeatureExtractor.extract(from: snapshot.image)

        guard !imageMask.isEmpty, !mapMask.isEmpty else {
            throw AutoAlignError.noFeaturesFound
        }
        guard let match = AlignmentScorer.bestMatch(imageMask: imageMask, mapMask: mapMask) else {
            throw AutoAlignError.noFeaturesFound
        }

        var proposedTransform = baseTransform
        proposedTransform.scale(by: match.scale)
        proposedTransform.rotate(by: match.rotationDegrees)
        proposedTransform.opacity = min(proposedTransform.opacity, 0.55)

        let eastMeters = Double(match.pixelOffsetX) / Double(max(1, mapMask.width)) * snapshot.region.widthMeters
        let northMeters = -Double(match.pixelOffsetY) / Double(max(1, mapMask.height)) * snapshot.region.heightMeters
        proposedTransform.nudge(eastMeters: eastMeters, northMeters: northMeters)

        let message: String
        if match.confidence >= Self.minimumReliableConfidence {
            message = MappyLocalization.string( "Previewing Auto Align result. Apply it if the map looks right.")
        } else {
            message = MappyLocalization.string( "Auto Align could not find a confident road or trail match.")
        }

        return AutoAlignResult(transform: proposedTransform, confidence: match.confidence, message: message)
    }
}
