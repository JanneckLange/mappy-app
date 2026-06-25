import MapKit
import UIKit

/// MapKit overlay data object for a transformed bitmap image.
final class ImageMapOverlay: NSObject, MKOverlay {
    let image: UIImage
    var transform: MapTransform

    init(image: UIImage, transform: MapTransform) {
        self.image = image
        self.transform = transform
    }

    var coordinate: CLLocationCoordinate2D {
        transform.coordinate
    }

    /// Converts meter dimensions into a map rect so MapKit knows when to ask the renderer to draw.
    var boundingMapRect: MKMapRect {
        let center = MKMapPoint(coordinate)
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(coordinate.latitude)
        let width = transform.widthMeters * pointsPerMeter
        let height = transform.heightMeters * pointsPerMeter
        return MKMapRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }
}
