import SwiftUI
import KlimaCore

/// Route card: "Von / Nach" with the DS `RouteGlyph`, station name + "Bahnhof · Tirol", the route meta
/// ("Zug · 101 km", rail-editorial style between the stops) and a glass swap button (180° turn, labels glide
/// to their new slot via matchedGeometry). Tapping a stop opens the station picker.
struct TripEdRouteCard: View {
    let model: TripEditorModel
    var onPick: (TripEdPick) -> Void

    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var labels
    @State private var swapTurns = 0
    /// Bottom edges of the "Von" / "Nach" captions in the stops' coordinate space (to pin the glyph's dots to the names).
    @State private var fromCaptionBottom: CGFloat = 0
    @State private var toCaptionBottom: CGFloat = 0
    /// Half the first line of a station name (title3) – where the glyph dot sits.
    @ScaledMetric(relativeTo: .title3) private var nameHalfLine: CGFloat = 12.5

    var body: some View {
        let haptics = app.settings.hapticsEnabled
        SurfaceCard(padding: 0, cornerRadius: Theme.Radius.formGroup) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                stops
                swapButton
            }
            .padding(.vertical, Theme.Spacing.s)
            .padding(.leading, Theme.Spacing.m)
            .padding(.trailing, Theme.Spacing.s)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: swapTurns) { _, _ in haptics }
    }

    // MARK: Stops

    private var stops: some View {
        VStack(alignment: .leading, spacing: 0) {
            endpoint(.from)
            meta
            endpoint(.to)
        }
        .padding(.leading, 26)
        .coordinateSpace(.named("tripEdRoute"))
        .overlay(alignment: .topLeading) { glyph }
    }

    @ViewBuilder
    private var glyph: some View {
        let top = fromCaptionBottom + 1 + nameHalfLine
        let bottom = toCaptionBottom + 1 + nameHalfLine
        if fromCaptionBottom > 0, bottom - top > 16 {
            RouteGlyph(color: Theme.accent, endColor: Theme.summit, height: bottom - top + 11)
                .frame(width: 15)
                .offset(x: 1, y: top - 5.5)
        }
    }

    private func endpoint(_ pick: TripEdPick) -> some View {
        let station = pick == .from ? model.fromStation : model.toStation
        let rawName = pick == .from ? model.resolvedFromName : model.resolvedToName
        let hasValue = !rawName.isEmpty
        let name = hasValue ? TripEdFormat.displayName(rawName) : (pick == .from ? "Start wählen" : "Ziel wählen")
        let subtitle: String? = station.map { TripEdFormat.stationSubtitle($0) } ?? (hasValue ? "Eigener Ort" : nil)
        let caption = pick == .from ? "Von" : "Nach"
        let key = labelKey(for: pick, name: rawName)
        var spoken = caption + ": " + (hasValue ? rawName : name)
        if hasValue, let subtitle { spoken += ", " + subtitle }

        return Button {
            onPick(pick)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(caption)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.frame(in: .named("tripEdRoute")).maxY
                    } action: { value in
                        if pick == .from { fromCaptionBottom = value } else { toCaptionBottom = value }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(hasValue ? Theme.textPrimary : Theme.textTertiary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .id(key)
                .matchedGeometryEffect(id: key, in: labels, properties: .position)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(TripEdPressStyle())
        .accessibilityLabel(spoken)
        .accessibilityHint(pick == .from ? "Öffnet die Suche für den Start" : "Öffnet die Suche für das Ziel")
    }

    /// Identity of a stop label: follows the station so that a swap lets the labels trade places.
    private func labelKey(for pick: TripEdPick, name: String) -> String {
        guard !name.isEmpty else { return "empty-\(pick.rawValue)" }
        let other = pick == .from ? model.resolvedToName : model.resolvedFromName
        return (pick == .to && name == other) ? "\(name)#to" : name
    }

    /// "Zug · 101 km" on the route line between the stops; a plain hairline until the route is known.
    private var meta: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let text = model.tripEdRouteMeta {
                if let badge = TripEdFormat.badge(for: model.mode) {
                    TripEdModeBadge(text: badge)
                }
                Text(text)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .layoutPriority(1)
            }
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    // MARK: Swap

    private var swapButton: some View {
        Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .bouncy(duration: 0.5, extraBounce: 0.1)) {
                swapTurns += 1
                model.swap()
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(swapTurns) * 180))
                .frame(width: 46, height: 46)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(model.resolvedFromName.isEmpty && model.resolvedToName.isEmpty)
        .accessibilityLabel("Start und Ziel tauschen")
    }
}
