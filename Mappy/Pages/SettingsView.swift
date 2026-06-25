import SwiftUI

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
