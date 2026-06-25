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

    /// Converts a normalized image point into the matching real map coordinate using the current transform.
    func coordinate(forNormalizedOverlayPoint point: CGPoint) -> CLLocationCoordinate2D {
        let centerPoint = MKMapPoint(coordinate)
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(coordinate.latitude)
        let widthPoints = max(widthMeters * pointsPerMeter, 1)
        let heightPoints = max(heightMeters * pointsPerMeter, 1)
        let localX = Double(point.x - 0.5) * widthPoints
        let localY = Double(point.y - 0.5) * heightPoints
        let radians = rotationDegrees * .pi / 180
        let rotatedX = localX * cos(radians) - localY * sin(radians)
        let rotatedY = localX * sin(radians) + localY * cos(radians)
        return MKMapPoint(x: centerPoint.x + rotatedX, y: centerPoint.y + rotatedY).coordinate
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
        alignImagePointPairs([
            ManualAlignmentPair(imagePoint: firstImagePoint, mapCoordinate: firstMapCoordinate),
            ManualAlignmentPair(imagePoint: secondImagePoint, mapCoordinate: secondMapCoordinate)
        ])
    }

    /// Solves a best-fit similarity transform from user-confirmed image/map point pairs.
    mutating func alignImagePointPairs(_ pairs: [ManualAlignmentPair]) -> Bool {
        guard pairs.count >= 2 else {
            return false
        }

        let aspectWidth = max(widthMeters, 1)
        let aspectHeight = max(heightMeters, 1)
        let averageLatitude = pairs.map(\.mapCoordinate.latitude).reduce(0, +) / Double(pairs.count)
        let pointsPerMeter = max(MKMapPointsPerMeterAtLatitude(averageLatitude), 1)
        let sourcePoints = pairs.map { pair in
            CGPoint(
                x: Double(pair.imagePoint.x - 0.5) * aspectWidth,
                y: Double(pair.imagePoint.y - 0.5) * aspectHeight
            )
        }
        let targetPoints = pairs.map { pair in
            let mapPoint = MKMapPoint(pair.mapCoordinate)
            return CGPoint(x: mapPoint.x, y: mapPoint.y)
        }
        let sourceCentroid = sourcePoints.centroid
        let targetCentroid = targetPoints.centroid
        var numeratorA = 0.0
        var numeratorB = 0.0
        var denominator = 0.0

        for index in sourcePoints.indices {
            let sourceX = sourcePoints[index].x - sourceCentroid.x
            let sourceY = sourcePoints[index].y - sourceCentroid.y
            let targetX = targetPoints[index].x - targetCentroid.x
            let targetY = targetPoints[index].y - targetCentroid.y
            numeratorA += sourceX * targetX + sourceY * targetY
            numeratorB += sourceX * targetY - sourceY * targetX
            denominator += sourceX * sourceX + sourceY * sourceY
        }

        guard denominator > 1 else {
            return false
        }

        let a = numeratorA / denominator
        let b = numeratorB / denominator
        let scaleMultiplier = hypot(a, b) / pointsPerMeter
        guard scaleMultiplier.isFinite, scaleMultiplier > 0 else {
            return false
        }

        widthMeters = min(max(aspectWidth * scaleMultiplier, 20), 200_000)
        heightMeters = min(max(aspectHeight * scaleMultiplier, 20), 200_000)
        rotationDegrees = atan2(b, a) * 180 / .pi
        if rotationDegrees < 0 {
            rotationDegrees += 360
        }

        let centerX = targetCentroid.x - a * sourceCentroid.x + b * sourceCentroid.y
        let centerY = targetCentroid.y - b * sourceCentroid.x - a * sourceCentroid.y
        let centerPoint = MKMapPoint(x: centerX, y: centerY)
        centerLatitude = centerPoint.coordinate.latitude
        centerLongitude = centerPoint.coordinate.longitude
        return true
    }
}

private extension Array where Element == CGPoint {
    var centroid: CGPoint {
        guard !isEmpty else {
            return .zero
        }
        let total = reduce(CGPoint.zero) { partialResult, point in
            CGPoint(x: partialResult.x + point.x, y: partialResult.y + point.y)
        }
        return CGPoint(x: total.x / Double(count), y: total.y / Double(count))
    }
}
