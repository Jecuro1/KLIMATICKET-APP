import SwiftUI
import KlimaCore

/// Frosted summary card floating over the bottom of the map: "8 von 9 Bundesländern", the nine state stamps
/// (west → east) and the key numbers. Opens the details sheet.
struct AtlasPanel: View {
    let summary: AtlasSummary
    let scopeLabel: String
    let modeName: String?
    var onDetails: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if summary.tripCount == 0 {
                empty
            } else {
                content
            }
        }
        .padding(.horizontal, Theme.Spacing.l - 2)
        .padding(.vertical, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedCard(cornerRadius: Theme.Radius.card)
    }

    // MARK: Content

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            header
            // At accessibility sizes the nine states need a labelled grid – too tall for a panel over the map;
            // the details sheet lists them in full.
            if !typeSize.isAccessibilitySize {
                AtlasStateStamps(visited: summary.visitedStates)
            }
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1)
            stats
            if summary.unmappedTripCount > 0 {
                unmappedNote
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 0) {
                Kicker(text: kicker)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(summary.visitedStateCount)")
                        .font(Theme.Typography.priceNumeral)
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText(value: Double(summary.visitedStateCount)))
                    Text("von 9")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(summary.isAllAustria ? "Bundesländern – ganz Österreich!" : "Bundesländern bereist")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bundesländer bereist")
            .accessibilityValue("\(summary.visitedStateCount) von 9")
            Spacer(minLength: Theme.Spacing.xs)
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                Button(action: onDetails) {
                    Label("Details", systemImage: "list.bullet")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .accessibilityHint("Extrempunkte, alle Strecken und Fahrten ohne Kartenposition")
                if summary.isAllAustria {
                    Label("Ganz Österreich", systemImage: "flag.checkered")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.positiveText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.positive.opacity(0.16), in: .capsule)
                }
            }
        }
    }

    private var kicker: String {
        guard let modeName else { return scopeLabel }
        return "\(scopeLabel) · \(modeName)"
    }

    private var stats: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                statItems(divided: true)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                statItems(divided: false)
            }
        }
    }

    @ViewBuilder
    private func statItems(divided: Bool) -> some View {
        stat(value: "\(summary.places.count)", label: summary.places.count == 1 ? "Bahnhof" : "Bahnhöfe")
        if divided { divider }
        stat(value: "\(summary.routes.count)", label: summary.routes.count == 1 ? "Strecke" : "Strecken")
        if divided { divider }
        stat(value: longestValue, label: "längste Fahrt")
    }

    private var longestValue: String {
        guard let trip = summary.longestTrip, trip.distanceKm > 0 else { return "–" }
        return Format.km(trip.distanceKm)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1, height: 30)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private var unmappedNote: some View {
        Button(action: onDetails) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.slash")
                    .font(.caption.weight(.semibold))
                Text("\(AtlasFormat.routes(summary.unmapped.count)) ohne Kartenposition")
                    .font(.footnote.weight(.medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(Theme.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Zeigt Strecken, für deren Haltestellen keine Koordinaten bekannt sind")
    }

    // MARK: Empty

    private var empty: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: "map")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .background(Theme.accent.opacity(0.14), in: .rect(cornerRadius: Theme.Radius.modeTile, style: .continuous))
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Kicker(text: kicker)
                Text("Deine Karte ist noch leer")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(modeName == nil
                     ? "Erfasse Fahrten mit Start- und Zielbahnhof – jede Strecke erscheint hier als Linie quer durch Österreich."
                     : "Mit diesem Verkehrsmittel bist du in diesem Zeitraum noch nicht gefahren.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Mode filter chips under the navigation bar (Liquid Glass controls, morphing in one container).
struct AtlasModeBar: View {
    let modes: [TransportMode]
    @Binding var selection: TransportMode?

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Chip(title: "Alle", symbol: "square.stack.3d.up.fill", isSelected: selection == nil) {
                        withAnimation(.snappy) { selection = nil }
                    }
                    ForEach(modes) { mode in
                        Chip(title: mode.displayName, symbol: mode.symbolName, isSelected: selection == mode) {
                            withAnimation(.snappy) { selection = selection == mode ? nil : mode }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.vertical, Theme.Spacing.xxs)
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Verkehrsmittel filtern")
    }
}
