import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The creation and editing flow for a saved map.
struct AddMapFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: AddMapViewModel

    init(editingMap: SavedMap?) {
        _viewModel = State(initialValue: AddMapViewModel(editingMap: editingMap))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            switch viewModel.stage {
            case .source:
                AddMapSourceView(
                    selectedPhoto: $viewModel.selectedPhoto,
                    isFileImporterPresented: $viewModel.isFileImporterPresented,
                    isCameraPresented: $viewModel.isCameraPresented
                )
            case .align:
                AddMapAlignmentView(
                    image: viewModel.image,
                    transform: $viewModel.transform,
                    isEditingOverlay: $viewModel.isEditingOverlay,
                    isAutoAligning: viewModel.isAutoAligning,
                    autoAlignPreview: viewModel.autoAlignPreview,
                    autoAlignMessage: viewModel.autoAlignMessage,
                    onInitialUserLocation: viewModel.handleInitialUserLocation,
                    onMapTap: viewModel.handleAlignmentTap,
                    onAutoAlign: {
                        Task {
                            await viewModel.autoAlign()
                        }
                    },
                    onApplyAutoAlignPreview: viewModel.applyAutoAlignPreview,
                    onCancelAutoAlignPreview: viewModel.cancelAutoAlignPreview,
                    onManualAlignmentFallback: viewModel.startManualAlignmentFallback,
                    onNameMap: { viewModel.stage = .name }
                )
            case .name:
                AddMapNamingView(
                    mapName: $viewModel.mapName,
                    hints: viewModel.hints,
                    canSave: viewModel.canSave,
                    saveButtonTitle: viewModel.saveButtonTitle,
                    onSelectHint: viewModel.selectHint,
                    onSave: {
                        if viewModel.saveMap(modelContext: modelContext) {
                            dismiss()
                        }
                    }
                )
            }
        }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .fileImporter(
            isPresented: $viewModel.isFileImporterPresented,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: false,
            onCompletion: viewModel.handleFileImport
        )
        .sheet(isPresented: $viewModel.isCameraPresented) {
            CameraPicker { capturedImage in
                viewModel.load(image: capturedImage, filename: nil)
            }
        }
        .task {
            viewModel.start()
        }
        .onChange(of: viewModel.selectedPhoto) { _, newValue in
            Task {
                await viewModel.handlePhotoSelection(newValue)
            }
        }
        .alert("Mappy", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
