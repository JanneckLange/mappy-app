import CoreLocation
import MapKit

/// A value type for georeferencing controls, persisted separately from SwiftData's model object.
struct MapTransform: Codable, Equatable {
    var centerLatitude: Double
    var centerLongitude: Double
    var widthMeters: Double
    var heightMeters: Double
    var rotationDegrees: Double
    var opacity: Double

    static let defaultTransform = MapTransform(
        centerLatitude: 37.3349,
        centerLongitude: -122.0090,
        widthMeters: 700,
        heightMeters: 700,
        rotationDegrees: 0,
        opacity: 0.65
    )

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }

    var usesDefaultCenter: Bool {
        centerLatitude == Self.defaultTransform.centerLatitude && centerLongitude == Self.defaultTransform.centerLongitude
    }

    /// Fits the overlay to an imported image while preserving the image's original aspect ratio.
    mutating func fitToImageSize(_ imageSize: CGSize, maxDimensionMeters: Double = 700) {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return
        }

        if imageSize.width >= imageSize.height {
            widthMeters = maxDimensionMeters
            heightMeters = maxDimensionMeters * Double(imageSize.height / imageSize.width)
        } else {
            heightMeters = maxDimensionMeters
            widthMeters = maxDimensionMeters * Double(imageSize.width / imageSize.height)
        }
    }

    /// Moves the overlay center by approximate real-world meters for arrow-button fine tuning.
    mutating func nudge(eastMeters: Double, northMeters: Double) {
        let latitudeMeters = 111_320.0
        let longitudeMeters = max(1, cos(centerLatitude * .pi / 180) * latitudeMeters)
        centerLatitude += northMeters / latitudeMeters
        centerLongitude += eastMeters / longitudeMeters
    }

    /// Moves the overlay by the same map-space distance as a finger drag on the visible map.
    mutating func translateByMapDrag(from previousCoordinate: CLLocationCoordinate2D, to currentCoordinate: CLLocationCoordinate2D) {
        let previousPoint = MKMapPoint(previousCoordinate)
        let currentPoint = MKMapPoint(currentCoordinate)
        let centerPoint = MKMapPoint(coordinate)
        let translatedCenter = MKMapPoint(
            x: centerPoint.x + currentPoint.x - previousPoint.x,
            y: centerPoint.y + currentPoint.y - previousPoint.y
        )
        centerLatitude = translatedCenter.coordinate.latitude
        centerLongitude = translatedCenter.coordinate.longitude
    }

    /// Scales both dimensions while clamping away from unusable tiny or huge overlays.
    mutating func scale(by multiplier: Double) {
        let clampedMultiplier = min(max(multiplier, 0.1), 10)
        widthMeters = min(max(widthMeters * clampedMultiplier, 20), 200_000)
        heightMeters = min(max(heightMeters * clampedMultiplier, 20), 200_000)
    }

    /// Keeps rotation in a readable 0...360 range for display and persistence.
    mutating func rotate(by degrees: Double) {
        rotationDegrees = (rotationDegrees + degrees).truncatingRemainder(dividingBy: 360)
        if rotationDegrees < 0 {
            rotationDegrees += 360
        }
    }
}
