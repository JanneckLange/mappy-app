import CoreGraphics
import CoreLocation
import Playgrounds

#Playground {
    let hints = MappyLogic.cleanHints(from: [" Park Map ", "Park Map", "A", "North Gate"])
    assert(hints == ["Park Map", "North Gate"])
    assert(MappyLogic.suggestedName(fallbackName: "paper-map", hints: hints) == "Park Map")

    var fittedTransform = MapTransform.defaultTransform
    fittedTransform.fitToImageSize(CGSize(width: 1_400, height: 700))
    assert(fittedTransform.widthMeters == 700)
    assert(fittedTransform.heightMeters == 350)

    var transform = MapTransform.defaultTransform
    transform.scale(by: 2)
    assert(transform.widthMeters == MapTransform.defaultTransform.widthMeters * 2)
    transform.rotate(by: -1)
    assert(transform.rotationDegrees == 359)

    var draggedTransform = MapTransform.defaultTransform
    let originalLatitude = draggedTransform.centerLatitude
    let originalLongitude = draggedTransform.centerLongitude
    draggedTransform.translateByMapDrag(
        from: CLLocationCoordinate2D(latitude: originalLatitude, longitude: originalLongitude),
        to: CLLocationCoordinate2D(latitude: originalLatitude + 0.001, longitude: originalLongitude + 0.001)
    )
    assert(draggedTransform.centerLatitude > originalLatitude)
    assert(draggedTransform.centerLongitude > originalLongitude)
}
