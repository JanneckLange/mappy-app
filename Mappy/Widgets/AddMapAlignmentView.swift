import CoreLocation
import SwiftUI
import UIKit

/// Second add-map step: align the imported image overlay against the real map.
struct AddMapAlignmentView: View {
    let image: UIImage?
    @Binding var transform: MapTransform
    @Binding var isEditingOverlay: Bool
    @Binding var isTwoPointAlignmentPresented: Bool
    let isAutoAligning: Bool
    let autoAlignPreview: AutoAlignResult?
    let autoAlignMessage: String?
    let onInitialUserLocation: (CLLocationCoordinate2D) -> Void
    let onMapTap: (CLLocationCoordinate2D) -> Void
    let onAutoAlign: () -> Void
    let onApplyAutoAlignPreview: () -> Void
    let onCancelAutoAlignPreview: () -> Void
    let onApplyTwoPointAlignment: ([ManualAlignmentPair]) -> Void
    let onNameMap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                MappyMapRepresentable(
                    image: image,
                    transform: $transform,
                    isEditingOverlay: isEditingOverlay,
                    showsUserLocation: true,
                    centersOnUserLocationInitially: true,
                    onInitialUserLocation: onInitialUserLocation,
                    onMapTap: onMapTap
                )

                AlignmentControls(
                    transform: $transform,
                    isEditingOverlay: $isEditingOverlay,
                    isAutoAligning: isAutoAligning,
                    autoAlignPreview: autoAlignPreview,
                    autoAlignMessage: autoAlignMessage,
                    onAutoAlign: onAutoAlign,
                    onApplyAutoAlignPreview: onApplyAutoAlignPreview,
                    onCancelAutoAlignPreview: onCancelAutoAlignPreview,
                    onTwoPointAlignment: { isTwoPointAlignmentPresented = true },
                    onNameMap: onNameMap
                )
                .padding()
                .background(.regularMaterial)
            }
        }
        .sheet(isPresented: $isTwoPointAlignmentPresented) {
            if let image {
                ThreePointAlignmentView(
                    image: image,
                    transform: $transform,
                    onApply: onApplyTwoPointAlignment
                )
            }
        }
    }
}
