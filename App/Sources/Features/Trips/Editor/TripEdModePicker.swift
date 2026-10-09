import SwiftUI
import KlimaCore

/// Verkehrsmittel-Wahl: a scrolling strip of mode tiles (SF Symbol + label) on a calm card. The tinted
/// selection tile glides to the new mode (matchedGeometry); S-Bahn and U-Bahn carry their "S"/"U" plaques.
struct TripEdModePicker: View {
    let model: TripEditorModel

    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var tileWidth: CGFloat = 62
    @ScaledMetric(relativeTo: .caption) private var tileHeight: CGFloat = 54

    /// Order follows the mockup (Zug, S-Bahn, Bus, U-Bahn, Bim …).
    private static let modes: [TransportMode] = [.train, .sBahn, .bus, .metro, .tram, .cableCar, .ferry, .other]

    var body: some View {
        SurfaceCard(padding: 6, cornerRadius: Theme.Radius.formGroup) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        ForEach(Self.modes) { mode in
                            tile(mode)
                                .id(mode)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    // Keep a less common pre-selected mode (e.g. Seilbahn when editing) in view.
                    if let index = Self.modes.firstIndex(of: model.mode), index > 3 {
                        proxy.scrollTo(model.mode, anchor: .center)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Verkehrsmittel")
    }

    private func tile(_ mode: TransportMode) -> some View {
        let isSelected = model.mode == mode
        let tint = Theme.modeColor(mode)
        return Button {
            select(mode)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isSelected ? tint : Theme.textSecondary)
                    .frame(height: 24)
                    .overlay(alignment: .topTrailing) {
                        plaque(for: mode, tint: tint, isSelected: isSelected)
                    }
                Text(mode.displayName)
                    .font(.caption.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
            .frame(minWidth: tileWidth, minHeight: tileHeight)
            .background {
                if isSelected {
                    indicator(tint: tint)
                }
            }
            .contentShape(.rect(cornerRadius: Theme.Radius.modeTile))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The gliding selection tile.
    private func indicator(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.modeTile + 2, style: .continuous)
            .fill(tint.opacity(0.14))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.modeTile + 2, style: .continuous)
                    .strokeBorder(tint.opacity(0.5), lineWidth: 1)
            }
            .matchedGeometryEffect(id: "selection", in: selection)
    }

    /// Small "S" (circle) / "U" (square) plaque as known from Austrian stations.
    @ViewBuilder
    private func plaque(for mode: TransportMode, tint: Color, isSelected: Bool) -> some View {
        if mode == .sBahn || mode == .metro {
            Text(mode == .sBahn ? "S" : "U")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 12, height: 12)
                .background(isSelected ? tint : Theme.textTertiary,
                            in: mode == .sBahn ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: Theme.Radius.modeTile / 4, style: .continuous)))
                .offset(x: 9, y: -3)
                .accessibilityHidden(true)
        }
    }

    private func select(_ mode: TransportMode) {
        guard model.mode != mode else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.3, extraBounce: 0.08)) {
            model.setMode(mode)
        }
    }
}
