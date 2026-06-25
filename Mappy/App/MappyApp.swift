import SwiftUI
import SwiftData

/// The app entry point prepares local storage and wires SwiftData into the scene.
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
