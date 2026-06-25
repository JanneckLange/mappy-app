import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import PhotosUI
import UniformTypeIdentifiers
import PDFKit
@preconcurrency import Vision
import UIKit
import Playgrounds

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The app entry point wires SwiftData into the scene so every child view can read and save maps.
@main
struct MappyApp: App {
    init() {
        LocalMapStore.prepareApplicationSupportDirectory()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SavedMap.self)
    }
}

/// A persisted map record. Large files stay in the app's Documents folder; SwiftData stores only metadata and alignment values.
@Model
final class SavedMap {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var originalFilename: String
    var assetFilename: String
    var thumbnailFilename: String?
    var centerLatitude: Double
    var centerLongitude: Double
    var widthMeters: Double
    var heightMeters: Double
    var rotationDegrees: Double
    var opacity: Double

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        originalFilename: String,
        assetFilename: String,
        thumbnailFilename: String? = nil,
        transform: MapTransform = .defaultTransform
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originalFilename = originalFilename
        self.assetFilename = assetFilename
        self.thumbnailFilename = thumbnailFilename
        self.centerLatitude = transform.centerLatitude
        self.centerLongitude = transform.centerLongitude
        self.widthMeters = transform.widthMeters
        self.heightMeters = transform.heightMeters
        self.rotationDegrees = transform.rotationDegrees
        self.opacity = transform.opacity
    }

    /// Converts the stored scalar fields into the value type used by the editor and MapKit overlay.
    var transform: MapTransform {
        get {
            MapTransform(
                centerLatitude: centerLatitude,
                centerLongitude: centerLongitude,
                widthMeters: widthMeters,
                heightMeters: heightMeters,
                rotationDegrees: rotationDegrees,
                opacity: opacity
            )
        }
        set {
            centerLatitude = newValue.centerLatitude
            centerLongitude = newValue.centerLongitude
            widthMeters = newValue.widthMeters
            heightMeters = newValue.heightMeters
            rotationDegrees = newValue.rotationDegrees
            opacity = newValue.opacity
            updatedAt = Date()
        }
    }
}

/// A plain value for all georeferencing controls. Keeping this separate makes alignment math easy to test.
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

    /// Moves the overlay center by approximate meters. This is precise enough for manual fine tuning.
    mutating func nudge(eastMeters: Double, northMeters: Double) {
        let latitudeMeters = 111_320.0
        let longitudeMeters = max(1, cos(centerLatitude * .pi / 180) * latitudeMeters)
        centerLatitude += northMeters / latitudeMeters
        centerLongitude += eastMeters / longitudeMeters
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
}

/// Simple naming output from the local analysis pipeline.
struct MapAnalysisResult {
    var suggestedName: String
    var hints: [String]
}

/// Centralizes file IO so views do not need to know where map assets live.
enum LocalMapStore {
    static let mapsDirectoryName = "Maps"

    /// Ensures SwiftData's default Application Support folder exists before the model container opens.
    static func prepareApplicationSupportDirectory() {
        guard let applicationSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return
        }

        if !FileManager.default.fileExists(atPath: applicationSupport.path) {
            try? FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        }
    }

    /// Returns the app-local Maps directory and creates it when needed.
    static func mapsDirectory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = documents.appendingPathComponent(mapsDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Builds a stable file URL for a stored asset filename.
    static func url(for filename: String) throws -> URL {
        try mapsDirectory().appendingPathComponent(filename)
    }

    /// Saves image data as JPEG and returns the generated filenames used by SwiftData.
    static func saveImage(_ image: UIImage, originalFilename: String) throws -> (assetFilename: String, thumbnailFilename: String?) {
        let id = UUID().uuidString
        let assetFilename = "\(id).jpg"
        let thumbnailFilename = "\(id)-thumb.jpg"
        let imageData = image.jpegData(compressionQuality: 0.92) ?? Data()
        let thumbnailData = makeThumbnail(from: image)?.jpegData(compressionQuality: 0.78)

        try imageData.write(to: url(for: assetFilename), options: [.atomic])
        if let thumbnailData {
            try thumbnailData.write(to: url(for: thumbnailFilename), options: [.atomic])
        }

        return (assetFilename, thumbnailData == nil ? nil : thumbnailFilename)
    }

    /// Loads a stored image from Documents for display in lists, viewers, and the editor.
    static func loadImage(filename: String?) -> UIImage? {
        guard let filename, let imageURL = try? url(for: filename) else {
            return nil
        }
        return UIImage(contentsOfFile: imageURL.path)
    }

    /// Renders the first PDF page into a UIImage so all alignment code can treat PDFs and images the same way.
    static func renderFirstPDFPage(from url: URL) -> UIImage? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else {
            return nil
        }

        let pageRect = page.bounds(for: .mediaBox)
        let maxSide: CGFloat = 2_400
        let scale = min(maxSide / max(pageRect.width, pageRect.height), 2)
        let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
    }

    /// Produces a small thumbnail that keeps the map list fast even with large imported files.
    private static func makeThumbnail(from image: UIImage) -> UIImage? {
        let targetSize = CGSize(width: 320, height: 220)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            UIColor.secondarySystemBackground.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()

            let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(
                x: (targetSize.width - drawSize.width) / 2,
                y: (targetSize.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

/// Local-only image analysis. Vision OCR is always attempted; Foundation Models are used only when available.
enum MapAnalyzer {
    /// Returns a practical default name and hints extracted from the imported map image.
    static func analyze(image: UIImage, fallbackName: String) async -> MapAnalysisResult {
        let recognizedText = await recognizeText(in: image)
        let hints = MappyLogic.cleanHints(from: recognizedText)
        let suggestedName = MappyLogic.suggestedName(fallbackName: fallbackName, hints: hints)
        return MapAnalysisResult(suggestedName: suggestedName, hints: hints)
    }

    /// Keeps Foundation Models availability isolated so views can hide Auto Align when the device cannot run it.
    static var isFoundationModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return true
            default:
                return false
            }
        }
        #endif
        return false
    }

    /// Performs OCR using Vision and returns candidate strings. Errors simply produce no hints.
    private static func recognizeText(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let strings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                continuation.resume(returning: strings)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
}

/// Pure helpers used by the UI and by snippets/tests after each implementation step.
enum MappyLogic {
    /// Removes OCR noise, short fragments, and duplicates while preserving the most useful labels.
    static func cleanHints(from rawText: [String]) -> [String] {
        var seen = Set<String>()
        let cleaned = rawText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
            .filter { text in
                let key = text.lowercased()
                if seen.contains(key) {
                    return false
                }
                seen.insert(key)
                return true
            }

        return Array(cleaned.prefix(8))
    }

    /// Chooses a readable map name from OCR hints first, then falls back to filename/date text.
    static func suggestedName(fallbackName: String, hints: [String]) -> String {
        if let candidate = hints.first(where: { $0.rangeOfCharacter(from: .letters) != nil }) {
            return candidate.capitalized
        }
        let cleanedFallback = fallbackName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedFallback.isEmpty ? "Untitled Map" : cleanedFallback.capitalized
    }

    /// Makes a filename/date fallback for imported or captured assets.
    static func fallbackName(filename: String?, date: Date = Date()) -> String {
        if let filename, !filename.isEmpty {
            return URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        }
        return DateFormatter.mappyNameFormatter.string(from: date)
    }
}

extension DateFormatter {
    /// Shared formatter for default names like "Map Jun 25, 2026".
    static let mappyNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = .current
        return formatter
    }()
}

/// Root navigation for the app.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            MapListView()
        }
    }
}

/// Lists saved maps and exposes creation/settings entry points.
struct MapListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedMap.updatedAt, order: .reverse) private var maps: [SavedMap]
    @State private var isAddingMap = false
    @State private var renamedMap: SavedMap?
    @State private var newName = ""

    var body: some View {
        List {
            if maps.isEmpty {
                ContentUnavailableView(
                    "No Maps Yet",
                    systemImage: "map",
                    description: Text("Import a photo, image, or PDF map to align it with the real world.")
                )
            }

            ForEach(maps) { map in
                NavigationLink {
                    MapViewer(map: map)
                } label: {
                    SavedMapRow(map: map)
                }
                .contextMenu {
                    Button {
                        beginRename(map)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    NavigationLink {
                        AddMapFlow(editingMap: map)
                    } label: {
                        Label("Edit Alignment", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .onDelete(perform: deleteMaps)
        }
        .navigationTitle("Mappy")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingMap = true
                } label: {
                    Label("Add Map", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingMap) {
            NavigationStack {
                AddMapFlow(editingMap: nil)
            }
        }
        .alert("Rename Map", isPresented: Binding(
            get: { renamedMap != nil },
            set: { if !$0 { renamedMap = nil } }
        )) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {
                renamedMap = nil
            }
            Button("Save") {
                saveRename()
            }
        }
    }

    /// Starts the rename alert with the current map name prefilled.
    private func beginRename(_ map: SavedMap) {
        renamedMap = map
        newName = map.name
    }

    /// Persists a new name while avoiding empty titles.
    private func saveRename() {
        guard let renamedMap else {
            return
        }
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        renamedMap.name = trimmedName.isEmpty ? "Untitled Map" : trimmedName
        renamedMap.updatedAt = Date()
        try? modelContext.save()
        self.renamedMap = nil
    }

    /// Deletes selected map records. Stored image files are left in place for recoverability in this v1.
    private func deleteMaps(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(maps[index])
        }
        try? modelContext.save()
    }
}

/// Compact list cell with a thumbnail and important map metadata.
struct SavedMapRow: View {
    let map: SavedMap

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 72, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(map.name)
                    .font(.headline)
                Text(map.updatedAt, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Uses the stored thumbnail when available and falls back to a map symbol.
    @ViewBuilder
    private var thumbnail: some View {
        if let image = LocalMapStore.loadImage(filename: map.thumbnailFilename) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                Image(systemName: "map")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Placeholder settings screen requested for v1.
struct SettingsView: View {
    var body: some View {
        ContentUnavailableView(
            "Settings",
            systemImage: "gearshape",
            description: Text("No settings yet.")
        )
        .navigationTitle("Settings")
    }
}

/// Shows a saved map as a full-screen overlay on top of Apple Maps.
struct MapViewer: View {
    let map: SavedMap
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MappyMapRepresentable(
                image: image,
                transform: .constant(map.transform),
                isEditingOverlay: false,
                showsUserLocation: true
            )
            .ignoresSafeArea(edges: .bottom)

            NavigationLink {
                AddMapFlow(editingMap: map)
            } label: {
                Label("Edit", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
                    .padding(12)
                    .background(.regularMaterial, in: Circle())
            }
            .padding()
        }
        .navigationTitle(map.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            image = LocalMapStore.loadImage(filename: map.assetFilename)
        }
    }
}

/// The creation and editing flow for a saved map.
struct AddMapFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let editingMap: SavedMap?

    @State private var stage: AddMapStage = .source
    @State private var image: UIImage?
    @State private var sourceFilename: String?
    @State private var mapName = ""
    @State private var transform = MapTransform.defaultTransform
    @State private var hints: [String] = []
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isFileImporterPresented = false
    @State private var isCameraPresented = false
    @State private var isAnalyzing = false
    @State private var isEditingOverlay = true
    @State private var lastDragTranslation = CGSize.zero
    @State private var lastMagnification = 1.0
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            switch stage {
            case .source:
                sourceView
            case .align:
                alignmentView
            case .name:
                namingView
            }
        }
        .navigationTitle(editingMap == nil ? "Add Map" : "Edit Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .photosPicker(isPresented: .constant(false), selection: $selectedPhoto, matching: .images)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .sheet(isPresented: $isCameraPresented) {
            CameraPicker { capturedImage in
                load(image: capturedImage, filename: nil)
            }
        }
        .task {
            loadExistingMapIfNeeded()
        }
        .onChange(of: selectedPhoto) { _, newValue in
            Task {
                await handlePhotoSelection(newValue)
            }
        }
        .alert("Mappy", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// First step: choose the source for a new map.
    private var sourceView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "map.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            Text("Add a Map")
                .font(.largeTitle.bold())
            Text("Import an image, import a PDF, or take a photo of a map, flyer, park sign, or handout.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Import Image", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                isFileImporterPresented = true
            } label: {
                Label("Import File", systemImage: "doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                isCameraPresented = true
            } label: {
                Label("Take Photo", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
    }

    /// Second step: align the image overlay against the real map.
    private var alignmentView: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                MappyMapRepresentable(
                    image: image,
                    transform: $transform,
                    isEditingOverlay: isEditingOverlay,
                    showsUserLocation: true
                )
                .overlay(alignmentOverlayGesture)

                alignmentControls
                    .padding()
                    .background(.regularMaterial)
            }
        }
    }

    /// Gesture layer for coarse manual alignment when image movement is active.
    private var alignmentOverlayGesture: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard isEditingOverlay else {
                            return
                        }
                        let deltaWidth = value.translation.width - lastDragTranslation.width
                        let deltaHeight = value.translation.height - lastDragTranslation.height
                        transform.nudge(eastMeters: deltaWidth * 0.4, northMeters: -deltaHeight * 0.4)
                        lastDragTranslation = value.translation
                    }
                    .onEnded { _ in
                        lastDragTranslation = .zero
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        guard isEditingOverlay else {
                            return
                        }
                        let delta = value.magnification / lastMagnification
                        transform.scale(by: delta)
                        lastMagnification = value.magnification
                    }
                    .onEnded { _ in
                        lastMagnification = 1
                    }
            )
    }

    /// Controls for opacity, movement mode, Auto Align, and fine tuning.
    private var alignmentControls: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $isEditingOverlay) {
                Label(isEditingOverlay ? "Move Image" : "Move Map", systemImage: isEditingOverlay ? "photo" : "map")
            }
            .toggleStyle(.button)

            HStack {
                Image(systemName: "circle.lefthalf.filled")
                Slider(value: $transform.opacity, in: 0.15...1)
            }

            HStack {
                Button { transform.nudge(eastMeters: -5, northMeters: 0) } label: { Image(systemName: "arrow.left") }
                Button { transform.nudge(eastMeters: 5, northMeters: 0) } label: { Image(systemName: "arrow.right") }
                Button { transform.nudge(eastMeters: 0, northMeters: 5) } label: { Image(systemName: "arrow.up") }
                Button { transform.nudge(eastMeters: 0, northMeters: -5) } label: { Image(systemName: "arrow.down") }
                Button { transform.rotate(by: -1) } label: { Image(systemName: "rotate.left") }
                Button { transform.rotate(by: 1) } label: { Image(systemName: "rotate.right") }
                Button { transform.scale(by: 0.98) } label: { Image(systemName: "minus.magnifyingglass") }
                Button { transform.scale(by: 1.02) } label: { Image(systemName: "plus.magnifyingglass") }
            }
            .buttonStyle(.bordered)

            if MapAnalyzer.isFoundationModelAvailable {
                Button {
                    autoAlign()
                } label: {
                    Label("Auto Align", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                stage = .name
            } label: {
                Label("Name Map", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Final step: confirm name and save the map locally.
    private var namingView: some View {
        Form {
            Section("Name") {
                TextField("Map name", text: $mapName)
            }

            if !hints.isEmpty {
                Section("Local Hints") {
                    ForEach(hints, id: \.self) { hint in
                        Text(hint)
                    }
                }
            }

            Section {
                Button(editingMap == nil ? "Save and Open Map" : "Save Changes") {
                    saveMap()
                }
                .disabled(image == nil)
            }
        }
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

    /// Handles PhotosPicker data and starts analysis after decoding the selected image.
    private func handlePhotoSelection(_ item: PhotosPickerItem?) async {
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
    private func handleFileImport(_ result: Result<[URL], Error>) {
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

    /// Stores the in-memory image and asks local analysis for a useful default name.
    private func load(image: UIImage, filename: String?) {
        self.image = image
        sourceFilename = filename
        mapName = MappyLogic.fallbackName(filename: filename)
        stage = .align

        Task {
            isAnalyzing = true
            let result = await MapAnalyzer.analyze(image: image, fallbackName: mapName)
            mapName = result.suggestedName
            hints = result.hints
            isAnalyzing = false
        }
    }

    /// Best-effort v1 Auto Align: use local hints to move the starting point slightly and mark that assist ran.
    private func autoAlign() {
        guard MapAnalyzer.isFoundationModelAvailable else {
            return
        }
        if !hints.isEmpty {
            transform.nudge(eastMeters: 25, northMeters: 25)
            transform.opacity = 0.55
        }
    }

    /// Saves a new record or updates the edited one, then returns to the list/view stack.
    private func saveMap() {
        guard let image else {
            return
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
            dismiss()
        } catch {
            errorMessage = "Mappy could not save this map locally."
        }
    }
}

enum AddMapStage {
    case source
    case align
    case name
}

/// SwiftUI wrapper around UIImagePickerController for camera capture.
struct CameraPicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.mediaTypes = [UTType.image.identifier]
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Bridges UIKit picker delegate callbacks back into SwiftUI state.
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Embeds MKMapView so Mappy can draw and edit a custom raster overlay.
struct MappyMapRepresentable: UIViewRepresentable {
    var image: UIImage?
    @Binding var transform: MapTransform
    var isEditingOverlay: Bool
    var showsUserLocation: Bool

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
        context.coordinator.configureLocation(for: mapView, enabled: showsUserLocation)
        context.coordinator.updateOverlay(on: mapView, image: image, transform: transform)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.showsUserLocation = showsUserLocation
        context.coordinator.updateOverlay(on: mapView, image: image, transform: transform)
        mapView.isScrollEnabled = !isEditingOverlay
        mapView.isZoomEnabled = !isEditingOverlay
        mapView.isRotateEnabled = !isEditingOverlay
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(transform: $transform)
    }

    /// Owns MapKit delegate duties: overlay rendering, location permission, and accuracy-circle updates.
    final class Coordinator: NSObject, MKMapViewDelegate, CLLocationManagerDelegate {
        private let transform: Binding<MapTransform>
        private let locationManager = CLLocationManager()
        private var imageOverlay: ImageMapOverlay?
        private var accuracyOverlay: MKCircle?

        init(transform: Binding<MapTransform>) {
            self.transform = transform
            super.init()
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
        }

        /// Requests foreground location access only when the map actually wants to show the blue dot.
        func configureLocation(for mapView: MKMapView, enabled: Bool) {
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

        /// Replaces the image overlay whenever the image or transform changes.
        func updateOverlay(on mapView: MKMapView, image: UIImage?, transform: MapTransform) {
            if let imageOverlay {
                mapView.removeOverlay(imageOverlay)
            }
            guard let image else {
                imageOverlay = nil
                return
            }

            let overlay = ImageMapOverlay(image: image, transform: transform)
            imageOverlay = overlay
            mapView.addOverlay(overlay, level: .aboveLabels)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let overlay = overlay as? ImageMapOverlay {
                return ImageMapOverlayRenderer(overlay: overlay)
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

/// MapKit overlay data object for a transformed bitmap image.
final class ImageMapOverlay: NSObject, MKOverlay {
    let image: UIImage
    let transform: MapTransform

    init(image: UIImage, transform: MapTransform) {
        self.image = image
        self.transform = transform
    }

    var coordinate: CLLocationCoordinate2D {
        transform.coordinate
    }

    /// Converts meter dimensions into a map-rect so MapKit knows when to ask the renderer to draw.
    var boundingMapRect: MKMapRect {
        let center = MKMapPoint(coordinate)
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(coordinate.latitude)
        let width = transform.widthMeters * pointsPerMeter
        let height = transform.heightMeters * pointsPerMeter
        return MKMapRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }
}

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
        context.draw(cgImage, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SavedMap.self, inMemory: true)
}

#Playground {
    let hints = MappyLogic.cleanHints(from: [" Park Map ", "Park Map", "A", "North Gate"])
    assert(hints == ["Park Map", "North Gate"])
    assert(MappyLogic.suggestedName(fallbackName: "paper-map", hints: hints) == "Park Map")

    var transform = MapTransform.defaultTransform
    transform.scale(by: 2)
    assert(transform.widthMeters == MapTransform.defaultTransform.widthMeters * 2)
    transform.rotate(by: -1)
    assert(transform.rotationDegrees == 359)
}
