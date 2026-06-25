import SwiftData
import SwiftUI

/// Root navigation for the app.
struct ContentView: View {
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    var body: some View {
        NavigationStack {
            MapListView()
        }
        .environment(\.locale, selectedLanguage.locale)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SavedMap.self, inMemory: true)
}
