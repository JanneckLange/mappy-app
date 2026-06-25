import MapKit
import UIKit

/// Creates a neutral Apple Maps snapshot around the current overlay so auto-align has real-map pixels to compare.
final class MapSnapshotProvider {
    func snapshot(for transform: MapTransform, size: CGSize = CGSize(width: 512, height: 512)) async throws -> MapSnapshot {
        let regionMeters = MapSnapshotRegion(transform: transform)
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: transform.coordinate,
            latitudinalMeters: regionMeters.heightMeters,
            longitudinalMeters: regionMeters.widthMeters
        )
        options.size = size
        options.scale = UIScreen.main.scale
        options.mapType = .standard
        options.showsBuildings = false
        options.pointOfInterestFilter = .excludingAll

        return try await withCheckedThrowingContinuation { continuation in
            MKMapSnapshotter(options: options).start { snapshot, error in
                if let snapshot {
                    continuation.resume(returning: MapSnapshot(image: snapshot.image, region: regionMeters))
                } else {
                    continuation.resume(throwing: error ?? AutoAlignError.snapshotUnavailable)
                }
            }
        }
    }
}

/// Captures the real-world size of the rendered snapshot for converting pixel offsets back into meters.
struct MapSnapshot {
    let image: UIImage
    let region: MapSnapshotRegion
}

/// The snapshot covers a larger area than the overlay so translation search has room to move.
struct MapSnapshotRegion: Equatable {
    let widthMeters: Double
    let heightMeters: Double

    init(transform: MapTransform) {
        widthMeters = max(transform.widthMeters * 3, 1_500)
        heightMeters = max(transform.heightMeters * 3, 1_500)
    }
}

enum AutoAlignError: Error {
    case missingImage
    case snapshotUnavailable
    case noFeaturesFound
}
