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

    let mapLine = FeatureMask(width: 9, height: 9, pixels: Set([22, 31, 40, 49, 58]))
    let matchingLine = FeatureMask(width: 9, height: 9, pixels: Set([22, 31, 40, 49, 58]))
    let shiftedLine = FeatureMask(width: 9, height: 9, pixels: Set([24, 33, 42, 51, 60]))
    let matchingScore = AlignmentScorer.score(
        imageMask: matchingLine,
        mapMask: mapLine,
        pixelOffsetX: 0,
        pixelOffsetY: 0,
        scale: 1,
        rotationDegrees: 0
    )
    let shiftedScore = AlignmentScorer.score(
        imageMask: shiftedLine,
        mapMask: mapLine,
        pixelOffsetX: 0,
        pixelOffsetY: 0,
        scale: 1,
        rotationDegrees: 0
    )
    assert(matchingScore > shiftedScore)

    let recoverableLine = FeatureMask(width: 9, height: 9, pixels: Set([21, 30, 39, 48, 57]))
    let bestMatch = AlignmentScorer.bestMatch(imageMask: recoverableLine, mapMask: mapLine)
    assert(bestMatch?.confidence ?? 0 > 0)

    var twoPointTransform = MapTransform.defaultTransform
    twoPointTransform.widthMeters = 100
    twoPointTransform.heightMeters = 100
    var firstManualPoint = twoPointTransform
    firstManualPoint.nudge(eastMeters: -25, northMeters: 0)
    var secondManualPoint = twoPointTransform
    secondManualPoint.nudge(eastMeters: 25, northMeters: 0)
    let didSolveManualAlignment = twoPointTransform.alignImagePoints(
        CGPoint(x: 0.25, y: 0.5),
        to: firstManualPoint.coordinate,
        CGPoint(x: 0.75, y: 0.5),
        to: secondManualPoint.coordinate
    )
    assert(didSolveManualAlignment)
    assert(abs(twoPointTransform.widthMeters - 100) < 5)
}
