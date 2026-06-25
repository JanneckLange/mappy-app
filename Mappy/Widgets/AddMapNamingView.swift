import SwiftUI

/// Final add-map step: confirm the map name, optionally selecting one OCR hint.
struct AddMapNamingView: View {
    @Binding var mapName: String
    let hints: [String]
    let canSave: Bool
    let saveButtonTitle: String
    let onSelectHint: (String) -> Void
    let onSave: () -> Void

    var body: some View {
        Form {
            Section("Name") {
                TextField("Map name", text: $mapName)
            }

            if !hints.isEmpty {
                Section("Local Hints") {
                    ForEach(hints, id: \.self) { hint in
                        Button {
                            onSelectHint(hint)
                        } label: {
                            HStack {
                                Text(hint)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if mapName == hint {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button(saveButtonTitle, action: onSave)
                    .disabled(!canSave)
            }
        }
    }
}
