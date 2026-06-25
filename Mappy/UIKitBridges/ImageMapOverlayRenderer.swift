import MapKit
import UIKit

/// Draws the imported bitmap over the map with opacity and rotation.
final class ImageMapOverlayRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? ImageMapOverlay, let cgImage = overlay.image.cgImage else {
            return
        }

        let rect = self.rect(for: overlay.boundingMapRect)
        context.saveGState()
        context.setAlpha(CGFloat(overlay.transform.opacity))
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: CGFloat(overlay.transform.rotationDegrees * .pi / 180))
        context.translateBy(x: -rect.width / 2, y: -rect.height / 2)
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}
