import SwiftUI

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
