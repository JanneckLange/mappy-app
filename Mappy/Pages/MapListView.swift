import SwiftData
import SwiftUI

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
