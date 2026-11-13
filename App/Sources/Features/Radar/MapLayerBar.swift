import SwiftUI
import KlimaCore

// Karte: the layer bar and the marker views of the Scotty-style map (docs/OEBB_LIVE.md §R10). The base map is MapKit and
// stays as it is. The station layer uses the bundled station index (no request); the train layer is the radar.

/// The glass bar that switches the layers on and off. Each layer is a chip: symbol, name, pressed state.
struct MapLayerBar: View {
    var selection: MapLayerSelection
    var onToggle: (MapLayer) -> Void

    var body: some View {
        // MARK: radarheat – five chips: the row of equal chips when every title fits on one line, else the same chips in a row that
        // scrolls sideways (large text sizes, narrow phones). A title is never cut ("Pünktlichkeit" is a long word).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xxs) { chips }
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.xxs) { chips }
            }
            .scrollIndicators(.hidden)
        }
        .padding(Theme.Spacing.xxs)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .capsule)
    }

    private var chips: some View {
        ForEach(MapLayer.allCases, id: \.self) { layer in
            let on = selection.isOn(layer)
            Button { onToggle(layer) } label: {
                VStack(spacing: 3) {
                    // One height for every symbol: the pin is taller than the train, and each chip centres its own column, so the five
                    // titles sat on five baselines (CI screenshots radar and mapLayers, integration run 43464953439).
                    Image(systemName: symbol(layer))
                        .font(.system(size: 16, weight: .semibold))
                        .frame(height: 20)
                    Text(layer.title)
                        .font(.caption2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundStyle(on ? Theme.accentText : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xs)
                .padding(.horizontal, 6)
                .background(on ? Theme.accent.opacity(0.18) : Color.clear, in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer.title)
            .accessibilityValue(on ? "an" : "aus")
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }

    private func symbol(_ layer: MapLayer) -> String {
        switch layer {
        case .stations: "mappin.and.ellipse"
        case .trains: "train.side.front.car"
        case .punctuality: "gauge.with.dots.needle.67percent"   // MARK: radarheat
        case .disruptions: "exclamationmark.triangle"
        case .routes: "bookmark"
        }
    }
}

/// A station on the map: a dot with its name on a glass capsule. A tap opens its departures.
struct StationMapMarker: View {
    var name: String

    var body: some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 3)
                .glassEffect(.regular, in: .capsule)
            Circle()
                .fill(Theme.accent)
                .frame(width: 8, height: 8)
        }
        .accessibilityLabel("Station \(name)")
        .accessibilityHint("Abfahrten öffnen")
    }
}

/// Several stations at this zoom: the count. A tap zooms in.
struct StationClusterBubble: View {
    var count: Int

    var body: some View {
        Text("\(count)")
            .font(.footnote.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .frame(minWidth: 34, minHeight: 34)
            .glassEffect(.regular, in: .circle)
            .accessibilityLabel("\(count) Stationen, zoom hinein")
    }
}
