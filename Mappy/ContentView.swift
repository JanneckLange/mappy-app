import SwiftData
import SwiftUI

/// Root navigation for the app.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            MapListView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SavedMap.self, inMemory: true)
}
