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

    @ObservationIgnored private var locationSeeder = InitialLocationSeeder()
    @ObservationIgnored private var autoAlignService = AutoAlignService()
    @ObservationIgnored private var transformBeforeAutoAlignPreview: MapTransform?
    @ObservationIgnored private var hasStarted = false

    init(editingMap: SavedMap?) {
        self.editingMap = editingMap
    }

    var navigationTitle: String {
        editingMap == nil ? "Add Map" : "Edit Map"
    }

    var saveButtonTitle: String {
        editingMap == nil ? "Save and Open Map" : "Save Changes"
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
                load(image: selectedImage, filename: "Photo Map")
            }
        } catch {
            errorMessage = "Could not import that photo."
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
                    errorMessage = "Could not render the first page of that PDF."
                    return
                }
                load(image: renderedImage, filename: fileURL.lastPathComponent)
            } else if let importedImage = UIImage(contentsOfFile: fileURL.path) {
                load(image: importedImage, filename: fileURL.lastPathComponent)
            } else {
                errorMessage = "That file is not a supported image or PDF."
            }
        } catch {
            errorMessage = "Could not import that file."
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
            errorMessage = "Import a map image before using Auto Align."
            return
        }
        guard currentLocationCoordinate != nil else {
            errorMessage = "Mappy needs your current location before Auto Align can compare nearby paths."
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
            autoAlignMessage = "Auto Align could not analyze this map. Try manual alignment."
        }

        isAutoAligning = false
    }

    /// Commits the previewed Auto Align result after the user visually checks it on the map.
    func applyAutoAlignPreview() {
        autoAlignPreview = nil
        transformBeforeAutoAlignPreview = nil
        autoAlignMessage = "Auto Align applied."
    }

    /// Restores the transform from before preview so a bad automatic match never becomes permanent.
    func cancelAutoAlignPreview() {
        if let transformBeforeAutoAlignPreview {
            transform = transformBeforeAutoAlignPreview
        }
        autoAlignPreview = nil
        transformBeforeAutoAlignPreview = nil
    }

    /// Gives the user a clear fallback path when local line matching is not confident enough.
    func startManualAlignmentFallback() {
        cancelAutoAlignPreview()
        isEditingOverlay = true
        autoAlignMessage = "Manual mode is active. Drag, pinch, rotate, or use the arrow controls to align the image."
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
            let finalName = trimmedName.isEmpty ? "Untitled Map" : trimmedName

            if let editingMap {
                editingMap.name = finalName
                editingMap.transform = transform
                try modelContext.save()
            } else {
                let filenames = try LocalMapStore.saveImage(
                    image,
                    originalFilename: sourceFilename ?? "Captured Map"
                )
                let savedMap = SavedMap(
                    name: finalName,
                    originalFilename: sourceFilename ?? "Captured Map",
                    assetFilename: filenames.assetFilename,
                    thumbnailFilename: filenames.thumbnailFilename,
                    transform: transform
                )
                modelContext.insert(savedMap)
                try modelContext.save()
            }
            return true
        } catch {
            errorMessage = "Mappy could not save this map locally."
            return false
        }
    }
}

enum AddMapStage {
    case source
    case align
    case name
}
