import PhotosUI
import SwiftUI

/// First add-map step: choose an image, file, or camera source.
struct AddMapSourceView: View {
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var isFileImporterPresented: Bool
    @Binding var isCameraPresented: Bool

    var body: some View {
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
}
