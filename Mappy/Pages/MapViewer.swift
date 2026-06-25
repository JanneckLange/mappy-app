import SwiftUI
import UIKit

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
                showsUserLocation: true,
                centersOnUserLocationInitially: false
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
