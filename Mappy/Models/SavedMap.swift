import Foundation
import SwiftData

/// A persisted map record. Large files stay in the app's Documents folder; SwiftData stores only metadata and alignment values.
@Model
final class SavedMap {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var originalFilename: String
    var assetFilename: String
    var thumbnailFilename: String?
    var centerLatitude: Double
    var centerLongitude: Double
    var widthMeters: Double
    var heightMeters: Double
    var rotationDegrees: Double
    var opacity: Double

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        originalFilename: String,
        assetFilename: String,
        thumbnailFilename: String? = nil,
        transform: MapTransform = .defaultTransform
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originalFilename = originalFilename
        self.assetFilename = assetFilename
        self.thumbnailFilename = thumbnailFilename
        self.centerLatitude = transform.centerLatitude
        self.centerLongitude = transform.centerLongitude
        self.widthMeters = transform.widthMeters
        self.heightMeters = transform.heightMeters
        self.rotationDegrees = transform.rotationDegrees
        self.opacity = transform.opacity
    }

    /// Converts the stored scalar fields into the value type used by the editor and MapKit overlay.
    var transform: MapTransform {
        get {
            MapTransform(
                centerLatitude: centerLatitude,
                centerLongitude: centerLongitude,
                widthMeters: widthMeters,
                heightMeters: heightMeters,
                rotationDegrees: rotationDegrees,
                opacity: opacity
            )
        }
        set {
            centerLatitude = newValue.centerLatitude
            centerLongitude = newValue.centerLongitude
            widthMeters = newValue.widthMeters
            heightMeters = newValue.heightMeters
            rotationDegrees = newValue.rotationDegrees
            opacity = newValue.opacity
            updatedAt = Date()
        }
    }
}
