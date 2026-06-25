import SwiftUI

/// App preferences.
struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $languageCode) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.localizedName)
                            .tag(language.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Settings")
    }
}
