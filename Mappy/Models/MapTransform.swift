import CoreGraphics
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

    /// Converts a map tap into the image's normalized overlay coordinates using the current transform.
    func normalizedOverlayPoint(for coordinate: CLLocationCoordinate2D) -> CGPoint? {
        let centerPoint = MKMapPoint(self.coordinate)
        let tapPoint = MKMapPoint(coordinate)
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(self.coordinate.latitude)
        let widthPoints = max(widthMeters * pointsPerMeter, 1)
        let heightPoints = max(heightMeters * pointsPerMeter, 1)
        let radians = rotationDegrees * .pi / 180
        let deltaX = tapPoint.x - centerPoint.x
        let deltaY = tapPoint.y - centerPoint.y
        let localX = deltaX * cos(radians) + deltaY * sin(radians)
        let localY = -deltaX * sin(radians) + deltaY * cos(radians)
        let normalizedX = localX / widthPoints + 0.5
        let normalizedY = localY / heightPoints + 0.5

        guard normalizedX >= 0, normalizedX <= 1, normalizedY >= 0, normalizedY <= 1 else {
            return nil
        }
        return CGPoint(x: normalizedX, y: normalizedY)
    }

    /// Solves center, scale, and rotation from two image points and their matching real map coordinates.
    mutating func alignImagePoints(
        _ firstImagePoint: CGPoint,
        to firstMapCoordinate: CLLocationCoordinate2D,
        _ secondImagePoint: CGPoint,
        to secondMapCoordinate: CLLocationCoordinate2D
    ) -> Bool {
        let aspectWidth = max(widthMeters, 1)
        let aspectHeight = max(heightMeters, 1)
        let imageDeltaX = Double(secondImagePoint.x - firstImagePoint.x) * aspectWidth
        let imageDeltaY = Double(secondImagePoint.y - firstImagePoint.y) * aspectHeight
        let imageDistance = hypot(imageDeltaX, imageDeltaY)
        let firstMapPoint = MKMapPoint(firstMapCoordinate)
        let secondMapPoint = MKMapPoint(secondMapCoordinate)
        let mapDeltaX = secondMapPoint.x - firstMapPoint.x
        let mapDeltaY = secondMapPoint.y - firstMapPoint.y
        let mapDistancePoints = hypot(mapDeltaX, mapDeltaY)
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(firstMapCoordinate.latitude)
        let mapDistanceMeters = mapDistancePoints / max(pointsPerMeter, 1)

        guard imageDistance > 1, mapDistanceMeters > 1 else {
            return false
        }

        let scaleMultiplier = mapDistanceMeters / imageDistance
        widthMeters = min(max(aspectWidth * scaleMultiplier, 20), 200_000)
        heightMeters = min(max(aspectHeight * scaleMultiplier, 20), 200_000)

        let sourceAngle = atan2(imageDeltaY, imageDeltaX)
        let targetAngle = atan2(mapDeltaY, mapDeltaX)
        rotationDegrees = ((targetAngle - sourceAngle) * 180 / .pi).truncatingRemainder(dividingBy: 360)
        if rotationDegrees < 0 {
            rotationDegrees += 360
        }

        let newPointsPerMeter = MKMapPointsPerMeterAtLatitude(firstMapCoordinate.latitude)
        let firstLocalX = Double(firstImagePoint.x - 0.5) * widthMeters * newPointsPerMeter
        let firstLocalY = Double(firstImagePoint.y - 0.5) * heightMeters * newPointsPerMeter
        let radians = rotationDegrees * .pi / 180
        let rotatedLocalX = firstLocalX * cos(radians) - firstLocalY * sin(radians)
        let rotatedLocalY = firstLocalX * sin(radians) + firstLocalY * cos(radians)
        let centerPoint = MKMapPoint(x: firstMapPoint.x - rotatedLocalX, y: firstMapPoint.y - rotatedLocalY)
        centerLatitude = centerPoint.coordinate.latitude
        centerLongitude = centerPoint.coordinate.longitude
        return true
    }
}
