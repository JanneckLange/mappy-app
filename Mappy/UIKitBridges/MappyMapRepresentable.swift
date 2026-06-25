import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Embeds MKMapView so Mappy can draw and edit a custom raster overlay.
struct MappyMapRepresentable: UIViewRepresentable {
    var image: UIImage?
    @Binding var transform: MapTransform
    var isEditingOverlay: Bool
    var showsUserLocation: Bool
    var centersOnUserLocationInitially: Bool
    var onInitialUserLocation: ((CLLocationCoordinate2D) -> Void)? = nil

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation
        mapView.userTrackingMode = .none
        mapView.pointOfInterestFilter = .includingAll
        mapView.region = MKCoordinateRegion(
            center: transform.coordinate,
            latitudinalMeters: max(transform.heightMeters * 4, 1_500),
            longitudinalMeters: max(transform.widthMeters * 4, 1_500)
        )
        context.coordinator.centersOnUserLocationInitially = centersOnUserLocationInitially
        context.coordinator.onInitialUserLocation = onInitialUserLocation
        context.coordinator.configureOverlayGestures(on: mapView, isEditingOverlay: isEditingOverlay)
        context.coordinator.configureLocation(for: mapView, enabled: showsUserLocation)
        context.coordinator.updateOverlay(on: mapView, image: image, transform: transform)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.showsUserLocation = showsUserLocation
        context.coordinator.centersOnUserLocationInitially = centersOnUserLocationInitially
        context.coordinator.onInitialUserLocation = onInitialUserLocation
        context.coordinator.configureOverlayGestures(on: mapView, isEditingOverlay: isEditingOverlay)
        context.coordinator.updateOverlay(on: mapView, image: image, transform: transform)
        mapView.isScrollEnabled = !isEditingOverlay
        mapView.isZoomEnabled = !isEditingOverlay
        mapView.isRotateEnabled = !isEditingOverlay
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(transform: $transform)
    }

    /// Owns MapKit delegate duties: overlay rendering, image-edit gestures, location permission, and accuracy-circle updates.
    final class Coordinator: NSObject, MKMapViewDelegate, CLLocationManagerDelegate {
        private let transform: Binding<MapTransform>
        private let locationManager = CLLocationManager()
        private var imageOverlay: ImageMapOverlay?
        private var imageRenderer: ImageMapOverlayRenderer?
        private var accuracyOverlay: MKCircle?
        private weak var mapView: MKMapView?
        private lazy var overlayPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleOverlayPan(_:)))
        private lazy var overlayPinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handleOverlayPinch(_:)))
        private var previousDragCoordinate: CLLocationCoordinate2D?
        var centersOnUserLocationInitially = false
        var onInitialUserLocation: ((CLLocationCoordinate2D) -> Void)?
        private var didUseInitialLocation = false

        init(transform: Binding<MapTransform>) {
            self.transform = transform
            super.init()
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
        }

        /// Installs the map-view gestures used only while the user is moving the image overlay.
        func configureOverlayGestures(on mapView: MKMapView, isEditingOverlay: Bool) {
            self.mapView = mapView
            if overlayPanGesture.view == nil {
                overlayPanGesture.maximumNumberOfTouches = 1
                overlayPanGesture.cancelsTouchesInView = false
                mapView.addGestureRecognizer(overlayPanGesture)
            }
            if overlayPinchGesture.view == nil {
                overlayPinchGesture.cancelsTouchesInView = false
                mapView.addGestureRecognizer(overlayPinchGesture)
            }

            overlayPanGesture.isEnabled = isEditingOverlay
            overlayPinchGesture.isEnabled = isEditingOverlay
            if !isEditingOverlay {
                previousDragCoordinate = nil
            }
        }

        /// Requests foreground location access only when the map actually wants to show the blue dot.
        func configureLocation(for mapView: MKMapView, enabled: Bool) {
            self.mapView = mapView
            guard enabled else {
                return
            }

            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                locationManager.startUpdatingLocation()
            default:
                break
            }
        }

        /// Converts a one-finger pan into a real map-space translation so the image stays under the finger.
        @objc private func handleOverlayPan(_ recognizer: UIPanGestureRecognizer) {
            guard let mapView else {
                previousDragCoordinate = nil
                return
            }

            let point = recognizer.location(in: mapView)
            let currentCoordinate = mapView.convert(point, toCoordinateFrom: mapView)

            switch recognizer.state {
            case .began:
                previousDragCoordinate = currentCoordinate
            case .changed:
                if let previousDragCoordinate {
                    transform.wrappedValue.translateByMapDrag(from: previousDragCoordinate, to: currentCoordinate)
                }
                self.previousDragCoordinate = currentCoordinate
            default:
                previousDragCoordinate = nil
            }
        }

        /// Converts a pinch into incremental overlay scaling while keeping MapKit's own zoom disabled in image mode.
        @objc private func handleOverlayPinch(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed else {
                recognizer.scale = 1
                return
            }

            transform.wrappedValue.scale(by: Double(recognizer.scale))
            recognizer.scale = 1
        }

        /// Reuses the image overlay so drag and pinch edits redraw instead of rebuilding MapKit overlay state.
        func updateOverlay(on mapView: MKMapView, image: UIImage?, transform: MapTransform) {
            self.mapView = mapView
            guard let image else {
                if let imageOverlay {
                    mapView.removeOverlay(imageOverlay)
                }
                imageOverlay = nil
                imageRenderer = nil
                return
            }

            if let imageOverlay, imageOverlay.image === image {
                let previousRect = imageOverlay.boundingMapRect
                imageOverlay.transform = transform
                imageRenderer?.setNeedsDisplay(previousRect)
                imageRenderer?.setNeedsDisplay(imageOverlay.boundingMapRect)
                return
            }

            if let imageOverlay {
                mapView.removeOverlay(imageOverlay)
            }
            imageRenderer = nil
            let overlay = ImageMapOverlay(image: image, transform: transform)
            imageOverlay = overlay
            mapView.addOverlay(overlay, level: .aboveLabels)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let overlay = overlay as? ImageMapOverlay {
                let renderer = ImageMapOverlayRenderer(overlay: overlay)
                imageRenderer = renderer
                return renderer
            }

            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.55)
                renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.14)
                renderer.lineWidth = 1
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let location = userLocation.location, location.horizontalAccuracy > 0 else {
                return
            }

            if !didUseInitialLocation {
                didUseInitialLocation = true
                onInitialUserLocation?(location.coordinate)
                if centersOnUserLocationInitially {
                    let region = MKCoordinateRegion(
                        center: location.coordinate,
                        latitudinalMeters: max(transform.wrappedValue.heightMeters * 4, 1_500),
                        longitudinalMeters: max(transform.wrappedValue.widthMeters * 4, 1_500)
                    )
                    mapView.setRegion(region, animated: true)
                }
            }

            if let accuracyOverlay {
                mapView.removeOverlay(accuracyOverlay)
            }
            let circle = MKCircle(center: location.coordinate, radius: location.horizontalAccuracy)
            accuracyOverlay = circle
            mapView.addOverlay(circle, level: .aboveLabels)
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.startUpdatingLocation()
            default:
                manager.stopUpdatingLocation()
            }
        }
    }
}
