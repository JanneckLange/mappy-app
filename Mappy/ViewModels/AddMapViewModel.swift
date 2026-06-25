import CoreLocation
import Foundation
import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Owns the add/edit map workflow state and side effects so AddMapFlow can focus on rendering stages.
@MainActor
@Observable
final class AddMapViewModel {
    let editingMap: SavedMap?
    var stage: AddMapStage = .source
    var image: UIImage?
    var sourceFilename: String?
    var mapName = ""
    var transform = MapTransform.defaultTransform
    var hints: [String] = []
    var selectedPhoto: PhotosPickerItem?
    var isFileImporterPresented = false
    var isCameraPresented = false
    var isAnalyzing = false
    var isEditingOverlay = true
    var currentLocationCoordinate: CLLocationCoordinate2D?
    var errorMessage: String?
    var isAutoAligning = false
    var autoAlignPreview: AutoAlignResult?
    var autoAlignMessage: String?
    var isTwoPointAlignmentPresented = false
    var manualAlignmentStep: ManualAlignmentStep = .inactive

    @ObservationIgnored private var locationSeeder = InitialLocationSeeder()
    @ObservationIgnored private var autoAlignService = AutoAlignService()
    @ObservationIgnored private var transformBeforeAutoAlignPreview: MapTransform?
    @ObservationIgnored private var pendingManualImagePoint: CGPoint?
    @ObservationIgnored private var firstManualAlignmentPair: ManualAlignmentPair?
    @ObservationIgnored private var hasStarted = false

    init(editingMap: SavedMap?) {
        self.editingMap = editingMap
    }

    var navigationTitle: String {
        editingMap == nil ? MappyLocalization.string( "Add Map") : MappyLocalization.string( "Edit Map")
    }

    var saveButtonTitle: String {
        editingMap == nil ? MappyLocalization.string( "Save and Open Map") : MappyLocalization.string( "Save Changes")
    }

    var canSave: Bool {
        image != nil
    }

    /// Loads persisted edit state once and starts a one-shot current-location request for new maps.
    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        loadExistingMapIfNeeded()
        requestInitialLocationIfNeeded()
    }

    /// Loads an existing record into the editor, or keeps the source picker for a new map.
    private func loadExistingMapIfNeeded() {
        guard let editingMap, image == nil else {
            return
        }
        image = LocalMapStore.loadImage(filename: editingMap.assetFilename)
        mapName = editingMap.name
        transform = editingMap.transform
        sourceFilename = editingMap.originalFilename
        stage = .align
    }

    /// Starts the one-shot location seed for new maps before an image is imported.
    private func requestInitialLocationIfNeeded() {
        guard editingMap == nil else {
            return
        }
        locationSeeder.requestCurrentLocation { [weak self] coordinate in
            Task { @MainActor in
                self?.handleInitialUserLocation(coordinate)
            }
        }
    }

    /// Uses the first real location fix as the starting point for newly imported map overlays.
    func handleInitialUserLocation(_ coordinate: CLLocationCoordinate2D) {
        currentLocationCoordinate = coordinate
        if editingMap == nil, transform.usesDefaultCenter {
            transform.centerLatitude = coordinate.latitude
            transform.centerLongitude = coordinate.longitude
        }
    }

    /// Handles PhotosPicker data and starts analysis after decoding the selected image.
    func handlePhotoSelection(_ item: PhotosPickerItem?) async {
        guard let item else {
            return
        }

        do {
            if let data = try await item.loadTransferable(type: Data.self), let selectedImage = UIImage(data: data) {
                load(image: selectedImage, filename: MappyLocalization.string( "Photo Map"))
            }
        } catch {
            errorMessage = MappyLocalization.string( "Could not import that photo.")
        }
    }

    /// Imports either images or PDFs selected from Files.
    func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let fileURL = try result.get().first else {
                return
            }
            let didAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            if fileURL.pathExtension.lowercased() == "pdf" {
                guard let renderedImage = LocalMapStore.renderFirstPDFPage(from: fileURL) else {
                    errorMessage = MappyLocalization.string( "Could not render the first page of that PDF.")
                    return
                }
                load(image: renderedImage, filename: fileURL.lastPathComponent)
            } else if let importedImage = UIImage(contentsOfFile: fileURL.path) {
                load(image: importedImage, filename: fileURL.lastPathComponent)
            } else {
                errorMessage = MappyLocalization.string( "That file is not a supported image or PDF.")
            }
        } catch {
            errorMessage = MappyLocalization.string( "Could not import that file.")
        }
    }

    /// Stores the in-memory image, preserves its aspect ratio for the overlay, and asks local analysis for a useful default name.
    func load(image: UIImage, filename: String?) {
        let normalizedImage = image.normalizedForMappyStorage()
        self.image = normalizedImage
        sourceFilename = filename
        mapName = MappyLogic.fallbackName(filename: filename)
        if editingMap == nil {
            transform.fitToImageSize(normalizedImage.size)
            if let currentLocationCoordinate, transform.usesDefaultCenter {
                transform.centerLatitude = currentLocationCoordinate.latitude
                transform.centerLongitude = currentLocationCoordinate.longitude
            }
        }
        stage = .align

        Task {
            isAnalyzing = true
            let result = await MapAnalyzer.analyze(image: normalizedImage, fallbackName: mapName)
            mapName = result.suggestedName
            hints = result.hints
            isAnalyzing = false
        }
    }

    /// Runs local image matching against a MapKit snapshot and previews only reliable alignment results.
    func autoAlign() async {
        guard let image else {
            errorMessage = MappyLocalization.string( "Import a map image before using Auto Align.")
            return
        }
        guard currentLocationCoordinate != nil else {
            errorMessage = MappyLocalization.string( "Mappy needs your current location before Auto Align can compare nearby paths.")
            return
        }

        cancelAutoAlignPreview()
        isAutoAligning = true
        autoAlignMessage = nil

        do {
            let result = try await autoAlignService.align(image: image, baseTransform: transform)
            autoAlignMessage = result.message
            if result.isReliable {
                transformBeforeAutoAlignPreview = transform
                autoAlignPreview = result
                transform = result.transform
            }
        } catch {
            autoAlignMessage = MappyLocalization.string( "Auto Align could not analyze this map. Try manual alignment.")
        }

        isAutoAligning = false
    }

    /// Commits the previewed Auto Align result after the user visually checks it on the map.
    func applyAutoAlignPreview() {
        autoAlignPreview = nil
        transformBeforeAutoAlignPreview = nil
        autoAlignMessage = MappyLocalization.string( "Auto Align applied.")
    }

    /// Restores the transform from before preview so a bad automatic match never becomes permanent.
    func cancelAutoAlignPreview() {
        if let transformBeforeAutoAlignPreview {
            transform = transformBeforeAutoAlignPreview
        }
        autoAlignPreview = nil
        transformBeforeAutoAlignPreview = nil
    }

    /// Starts a guided two-point fallback for maps that automatic line matching cannot confidently align.
    func startManualAlignmentFallback() {
        cancelAutoAlignPreview()
        isEditingOverlay = false
        pendingManualImagePoint = nil
        firstManualAlignmentPair = nil
        manualAlignmentStep = .firstImagePoint
        autoAlignMessage = manualAlignmentStep.instruction
    }

    /// Advances the two-point alignment flow using taps from the map bridge.
    func handleAlignmentTap(_ coordinate: CLLocationCoordinate2D) {
        switch manualAlignmentStep {
        case .inactive:
            return
        case .firstImagePoint, .secondImagePoint:
            guard let imagePoint = transform.normalizedOverlayPoint(for: coordinate) else {
                autoAlignMessage = MappyLocalization.string( "Tap inside the image overlay for the image point.")
                return
            }
            pendingManualImagePoint = imagePoint
            manualAlignmentStep = manualAlignmentStep == .firstImagePoint ? .firstMapPoint : .secondMapPoint
            autoAlignMessage = manualAlignmentStep.instruction
        case .firstMapPoint:
            guard let pendingManualImagePoint else {
                manualAlignmentStep = .firstImagePoint
                autoAlignMessage = manualAlignmentStep.instruction
                return
            }
            firstManualAlignmentPair = ManualAlignmentPair(imagePoint: pendingManualImagePoint, mapCoordinate: coordinate)
            self.pendingManualImagePoint = nil
            manualAlignmentStep = .secondImagePoint
            autoAlignMessage = manualAlignmentStep.instruction
        case .secondMapPoint:
            guard let pendingManualImagePoint, let firstManualAlignmentPair else {
                manualAlignmentStep = .firstImagePoint
                autoAlignMessage = manualAlignmentStep.instruction
                return
            }
            var alignedTransform = transform
            let didAlign = alignedTransform.alignImagePoints(
                firstManualAlignmentPair.imagePoint,
                to: firstManualAlignmentPair.mapCoordinate,
                pendingManualImagePoint,
                to: coordinate
            )
            if didAlign {
                transform = alignedTransform
                autoAlignMessage = MappyLocalization.string( "Two-point alignment applied.")
            } else {
                autoAlignMessage = MappyLocalization.string( "Those points are too close together. Try two points farther apart.")
            }
            self.pendingManualImagePoint = nil
            self.firstManualAlignmentPair = nil
            manualAlignmentStep = .inactive
        }
    }

    /// Applies the modal two-point alignment result after all image/map point pairs are selected.
    func applyTwoPointAlignment(_ pairs: [ManualAlignmentPair]) {
        cancelAutoAlignPreview()
        var alignedTransform = transform
        if alignedTransform.alignImagePointPairs(pairs) {
            transform = alignedTransform
            autoAlignMessage = MappyLocalization.string( "Two-point alignment applied.")
        } else {
            autoAlignMessage = MappyLocalization.string( "Those points are too close together. Try two points farther apart.")
        }
    }

    /// Selects an OCR hint as the final map name.
    func selectHint(_ hint: String) {
        mapName = hint
    }

    /// Saves a new record or updates the edited one. Returns true when the caller should dismiss the flow.
    func saveMap(modelContext: ModelContext) -> Bool {
        guard let image else {
            return false
        }

        do {
            let trimmedName = mapName.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = trimmedName.isEmpty ? MappyLocalization.string( "Untitled Map") : trimmedName

            if let editingMap {
                editingMap.name = finalName
                editingMap.transform = transform
                try modelContext.save()
            } else {
                let filenames = try LocalMapStore.saveImage(
                    image,
                    originalFilename: sourceFilename ?? MappyLocalization.string( "Captured Map")
                )
                let savedMap = SavedMap(
                    name: finalName,
                    originalFilename: sourceFilename ?? MappyLocalization.string( "Captured Map"),
                    assetFilename: filenames.assetFilename,
                    thumbnailFilename: filenames.thumbnailFilename,
                    transform: transform
                )
                modelContext.insert(savedMap)
                try modelContext.save()
            }
            return true
        } catch {
            errorMessage = MappyLocalization.string( "Mappy could not save this map locally.")
            return false
        }
    }
}

enum AddMapStage {
    case source
    case align
    case name
}

/// Guides the four taps needed to align two image points with two real map points.
enum ManualAlignmentStep: Equatable {
    case inactive
    case firstImagePoint
    case firstMapPoint
    case secondImagePoint
    case secondMapPoint

    var instruction: String? {
        switch self {
        case .inactive:
            return nil
        case .firstImagePoint:
            return MappyLocalization.string( "Tap a clear point on the image overlay.")
        case .firstMapPoint:
            return MappyLocalization.string( "Tap the same point on the real map.")
        case .secondImagePoint:
            return MappyLocalization.string( "Tap a second point on the image overlay, far from the first.")
        case .secondMapPoint:
            return MappyLocalization.string( "Tap the matching second point on the real map.")
        }
    }
}

/// Stores one user-confirmed correspondence between the imported image and the real map.
struct ManualAlignmentPair {
    let imagePoint: CGPoint
    let mapCoordinate: CLLocationCoordinate2D
}
