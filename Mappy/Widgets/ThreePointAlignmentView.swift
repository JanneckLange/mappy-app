import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// A modal picker for matching two image points to two real map coordinates.
struct ThreePointAlignmentView: View {
    let image: UIImage
    @Binding var transform: MapTransform
    let onApply: ([ManualAlignmentPair]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var imagePoints: [CGPoint?] = Array(repeating: nil, count: 2)
    @State private var mapCoordinates: [CLLocationCoordinate2D?] = Array(repeating: nil, count: 2)

    private var pairs: [ManualAlignmentPair] {
        imagePoints.indices.compactMap { index in
            guard let imagePoint = imagePoints[index], let mapCoordinate = mapCoordinates[index] else {
                return nil
            }
            return ManualAlignmentPair(imagePoint: imagePoint, mapCoordinate: mapCoordinate)
        }
    }

    private var canApply: Bool {
        pairs.count == 2
    }

    private var nextImageIndex: Int? {
        imagePoints.firstIndex(where: { $0 == nil })
    }

    private var nextMapIndex: Int? {
        mapCoordinates.firstIndex(where: { $0 == nil })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Tap each pane twice. Drag placed markers to adjust them.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                ImagePointPicker(
                    image: image,
                    points: imagePoints,
                    nextIndex: nextImageIndex,
                    onSelect: selectImagePoint
                )
                .frame(maxHeight: .infinity)

                Divider()

                AlignmentPointMapPicker(
                    transform: transform,
                    coordinates: mapCoordinates,
                    nextIndex: nextMapIndex,
                    onSelect: selectMapCoordinate
                )
                .frame(maxHeight: .infinity)
            }
            .navigationTitle("Two-Point Align")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(pairs)
                        dismiss()
                    }
                    .disabled(!canApply)
                }
            }
        }
    }

    private func selectImagePoint(index: Int, point: CGPoint) {
        imagePoints[index] = point
    }

    private func selectMapCoordinate(index: Int, coordinate: CLLocationCoordinate2D) {
        mapCoordinates[index] = coordinate
    }
}

private struct ImagePointPicker: View {
    let image: UIImage
    let points: [CGPoint?]
    let nextIndex: Int?
    let onSelect: (Int, CGPoint) -> Void

    @State private var zoom = 1.0
    @State private var committedZoom = 1.0
    @State private var imageOffset = CGSize.zero
    @State private var committedImageOffset = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            let imageRect = fittedImageRect(imageSize: image.size, containerSize: proxy.size, zoom: zoom, offset: imageOffset)

            ZStack {
                Color(.secondarySystemBackground)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                ForEach(points.indices, id: \.self) { index in
                    if let point = points[index] {
                        AlignmentPointMarker(number: index + 1, isActive: index == nextIndex)
                            .position(
                                x: imageRect.minX + imageRect.width * point.x,
                                y: imageRect.minY + imageRect.height * point.y
                            )
                            .gesture(
                                DragGesture(coordinateSpace: .named("ImagePointPicker"))
                                    .onChanged { value in
                                        onSelect(index, normalizedPoint(from: value.location, in: imageRect))
                                    }
                            )
                    }
                }
            }
            .coordinateSpace(name: "ImagePointPicker")
            .contentShape(Rectangle())
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        zoom = min(max(value, 1), 4)
                    }
            )
            .onTapGesture { location in
                guard let nextIndex, imageRect.contains(location) else {
                    return
                }
                onSelect(nextIndex, normalizedPoint(from: location, in: imageRect))
            }
        }
        .clipped()
    }

    private func normalizedPoint(from location: CGPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max((location.x - imageRect.minX) / imageRect.width, 0), 1),
            y: min(max((location.y - imageRect.minY) / imageRect.height, 0), 1)
        )
    }

    private func fittedImageRect(imageSize: CGSize, containerSize: CGSize, zoom: Double) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let baseScale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let width = imageSize.width * baseScale * zoom
        let height = imageSize.height * baseScale * zoom
        return CGRect(
            x: (containerSize.width - width) / 2,
            y: (containerSize.height - height) / 2,
            width: width,
            height: height
        )
    }
}

private struct AlignmentPointMapPicker: UIViewRepresentable {
    let transform: MapTransform
    let coordinates: [CLLocationCoordinate2D?]
    let nextIndex: Int?
    let onSelect: (Int, CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .includingAll
        mapView.region = MKCoordinateRegion(
            center: transform.coordinate,
            latitudinalMeters: max(transform.heightMeters * 4, 1_500),
            longitudinalMeters: max(transform.widthMeters * 4, 1_500)
        )
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tapGesture)
        context.coordinator.mapView = mapView
        updateAnnotations(on: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.mapView = mapView
        updateAnnotations(on: mapView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func updateAnnotations(on mapView: MKMapView) {
        mapView.removeAnnotations(mapView.annotations)
        for index in coordinates.indices {
            guard let coordinate = coordinates[index] else {
                continue
            }
            let annotation = NumberedPointAnnotation(number: index + 1, coordinate: coordinate, isActive: index == nextIndex)
            mapView.addAnnotation(annotation)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: AlignmentPointMapPicker
        weak var mapView: MKMapView?

        init(parent: AlignmentPointMapPicker) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let mapView, let nextIndex = parent.nextIndex else {
                return
            }
            let point = recognizer.location(in: mapView)
            parent.onSelect(nextIndex, mapView.convert(point, toCoordinateFrom: mapView))
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? NumberedPointAnnotation else {
                return nil
            }
            let identifier = "AlignmentPointMarker"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.canShowCallout = false
            view.isDraggable = true
            view.image = MarkerImageFactory.image(number: annotation.number, isActive: annotation.isActive)
            view.centerOffset = CGPoint(x: 0, y: -12)
            return view
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            guard let annotation = view.annotation as? NumberedPointAnnotation else {
                return
            }

            switch newState {
            case .starting:
                view.dragState = .dragging
            case .ending, .canceling:
                parent.onSelect(annotation.index, annotation.coordinate)
                view.dragState = .none
            default:
                break
            }
        }
    }
}

private final class NumberedPointAnnotation: NSObject, MKAnnotation {
    let number: Int
    var index: Int {
        number - 1
    }
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let isActive: Bool

    init(number: Int, coordinate: CLLocationCoordinate2D, isActive: Bool) {
        self.number = number
        self.coordinate = coordinate
        self.isActive = isActive
    }
}

private struct AlignmentPointMarker: View {
    let number: Int
    let isActive: Bool

    var body: some View {
        Text("\(number)")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(isActive ? Color.accentColor : Color.red, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
    }
}

private enum MarkerImageFactory {
    static func image(number: Int, isActive: Bool) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 36))
        return renderer.image { context in
            let rect = CGRect(x: 2, y: 2, width: 32, height: 32)
            let fillColor = isActive ? UIColor.systemBlue : UIColor.systemRed
            fillColor.setFill()
            context.cgContext.fillEllipse(in: rect)
            UIColor.white.setStroke()
            context.cgContext.setLineWidth(2)
            context.cgContext.strokeEllipse(in: rect)

            let text = "\(number)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 15),
                .foregroundColor: UIColor.white
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: 18 - textSize.width / 2, y: 18 - textSize.height / 2),
                withAttributes: attributes
            )
        }
    }
}
