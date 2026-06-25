import SwiftUI

/// Controls for opacity, movement mode, Auto Align preview, fallback, and fine tuning.
struct AlignmentControls: View {
    @Binding var transform: MapTransform
    @Binding var isEditingOverlay: Bool
    let isAutoAligning: Bool
    let autoAlignPreview: AutoAlignResult?
    let autoAlignMessage: String?
    let onAutoAlign: () -> Void
    let onApplyAutoAlignPreview: () -> Void
    let onCancelAutoAlignPreview: () -> Void
    let onManualAlignmentFallback: () -> Void
    let onNameMap: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $isEditingOverlay) {
                Label(isEditingOverlay ? "Move Image" : "Move Map", systemImage: isEditingOverlay ? "photo" : "map")
            }
            .toggleStyle(.button)

            HStack {
                Image(systemName: "circle.lefthalf.filled")
                Slider(value: $transform.opacity, in: 0.15...1)
            }

            HStack {
                Button { transform.nudge(eastMeters: -5, northMeters: 0) } label: { Image(systemName: "arrow.left") }
                Button { transform.nudge(eastMeters: 5, northMeters: 0) } label: { Image(systemName: "arrow.right") }
                Button { transform.nudge(eastMeters: 0, northMeters: 5) } label: { Image(systemName: "arrow.up") }
                Button { transform.nudge(eastMeters: 0, northMeters: -5) } label: { Image(systemName: "arrow.down") }
                Button { transform.rotate(by: -1) } label: { Image(systemName: "rotate.left") }
                Button { transform.rotate(by: 1) } label: { Image(systemName: "rotate.right") }
                Button { transform.scale(by: 0.98) } label: { Image(systemName: "minus.magnifyingglass") }
                Button { transform.scale(by: 1.02) } label: { Image(systemName: "plus.magnifyingglass") }
            }
            .buttonStyle(.bordered)

            if isAutoAligning {
                ProgressView("Auto Align")
                    .frame(maxWidth: .infinity)
            } else if autoAlignPreview != nil {
                previewControls
            } else {
                VStack(spacing: 8) {
                    Button(action: onAutoAlign) {
                        Label("Auto Align", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: onManualAlignmentFallback) {
                        Label("Two-Point Align", systemImage: "point.3.connected.trianglepath.dotted")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let autoAlignMessage {
                Text(autoAlignMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Button(action: onNameMap) {
                Label("Name Map", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Lets the user commit or reject the temporary transform shown on the map.
    private var previewControls: some View {
        VStack(spacing: 8) {
            if let confidence = autoAlignPreview?.confidence {
                Text("Confidence \(confidence.formatted(.percent.precision(.fractionLength(0))))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(action: onCancelAutoAlignPreview) {
                    Label("Cancel", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onApplyAutoAlignPreview) {
                    Label("Apply", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Button(action: onManualAlignmentFallback) {
                Label("Manual Align", systemImage: "hand.draw")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}
