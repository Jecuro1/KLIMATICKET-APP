import SwiftUI
import KlimaCore

// MARK: stops – line families and line rows of the stop detail (ENRICH_SPEC §3.1, §3.2, BADGE_SPEC §2.1, §4.4).

extension LineKind {
    /// German family name of the detail groups.
    var familyTitle: String {
        switch self {
        case .fern: "Fernverkehr"
        case .nacht: "Nachtzug"
        case .regio: "Regionalverkehr"
        case .sBahn: "S-Bahn"
        case .uBahn: "U-Bahn"
        case .tram: "Straßenbahn"
        case .bus: "Bus"
        case .nachtbus: "Nachtbus"
        case .skibus: "Skibus"
        case .wanderbus: "Wanderbus"
        case .rufbus: "Rufbus"
        case .sev: "Schienenersatzverkehr"
        case .seilbahn: "Seilbahn"
        case .schiff: "Schiff"
        case .sonst: "Weitere Linien"
        }
    }

    var familySymbol: String {
        switch self {
        case .fern, .regio: "train.side.front.car"
        case .nacht: "moon.stars.fill"
        case .sBahn: "lightrail.fill"
        case .uBahn: "tram.fill.tunnel"
        case .tram: "tram.fill"
        case .bus: "bus.fill"
        case .nachtbus: "moon.zzz.fill"
        case .skibus: "figure.skiing.downhill"
        case .wanderbus: "figure.hiking"
        case .rufbus: "phone.fill"
        case .sev: "bus.doubledecker.fill"
        case .seilbahn: "cablecar.fill"
        case .schiff: "ferry.fill"
        case .sonst: "signpost.right.fill"
        }
    }

    /// Tile colours of the family symbol (the plate fill, with a readable dark variant for light plates).
    var tileColor: Color {
        switch self {
        case .skibus: Color(light: "#3448C5", dark: "#8E9BFF")
        case .sev: Color(light: "#B38A00", dark: "#FFD866")
        case .rufbus: Color(light: "#C4500C", dark: "#FFAE73")
        default: fill(for: "")
        }
    }
}

/// Small rounded tile with the family symbol.
struct LineFamilyTile: View {
    let kind: LineKind
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: kind.familySymbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(kind.tileColor)
            .frame(width: size, height: size)
            .background(kind.tileColor.opacity(0.14), in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Hero: the symbol of a family and its plates (≤ `maxCount`, then „+k“).
struct LineFamilyRow: View {
    let kind: LineKind
    let badges: [LineBadge]
    var size: PlateSize = .l
    var maxCount = 5

    var body: some View {
        HStack(spacing: 8) {
            LineFamilyTile(kind: kind, size: 24)
            LinePlateRow(badges: badges, size: size, maxCount: maxCount, spacing: 6)
            Spacer(minLength: 0)
        }
    }
}

/// Family header of the line list: symbol, name, count, season tag.
struct LineFamilyHeader: View {
    let kind: LineKind
    let count: Int
    var season: String?

    var body: some View {
        HStack(spacing: 8) {
            LineFamilyTile(kind: kind, size: 24)
            Text(kind.familyTitle).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 4)
            if let season { SeasonTag(text: season) }
            Text(count == 1 ? "1 Linie" : "\(count) Linien")
                .font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(kind.familyTitle), \(count == 1 ? "1 Linie" : "\(count) Linien")" + (season.map { ", " + $0 } ?? "")))
        .accessibilityAddTraits(.isHeader)
    }
}

/// Dots and a line between them: the line runs from the first to the second text line.
struct LineTerminiGlyph: View {
    var color: Color = Theme.accent
    var endColor: Color = Theme.summit
    var height: CGFloat = 30

    var body: some View {
        ZStack {
            Capsule().fill(LinearGradient(colors: [color, endColor], startPoint: .top, endPoint: .bottom))
                .frame(width: 1.5, height: max(0, height - 8))
            VStack {
                Circle().strokeBorder(color, lineWidth: 1.6).frame(width: 7, height: 7)
                Spacer(minLength: 0)
                Circle().fill(endColor).frame(width: 7, height: 7)
            }
        }
        .frame(width: 8, height: height)
        .accessibilityHidden(true)
    }
}

/// One line at the stop: plate, termini stacked, operator · network, mini state marks, source note.
struct StopLineRow: View {
    let line: StopLine
    let badge: LineBadge
    let from: String?
    let to: String?
    let operatorText: String?
    let foreignStates: [Bundesland]
    var season: String?
    var spoken: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LinePlate(badge, size: .m)
                .frame(minWidth: 52, alignment: .leading)
            if let from, let to {
                LineTerminiGlyph(height: 36)
                    .padding(.top, 2)
                termini(from: from, to: to)
            } else {
                termini(from: nil, to: from ?? to)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }

    private func termini(from: String?, to: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let from { Text(from).font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(2) }
            if let to { Text(to).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(2) }
            HStack(spacing: 5) {
                if let operatorText { Text(operatorText).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1) }
                ForEach(foreignStates, id: \.rawValue) { StateMarkW(state: $0, style: .mini) }
                if let season { SeasonTag(text: season) }
            }
            if line.confidence == .osmOnly {
                Text("laut OpenStreetMap").font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// Long distance in one row: „→ Innsbruck · Salzburg · Wien“.
struct LongDistanceSummaryRow: View {
    let badges: [LineBadge]
    let destinations: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LinePlateRow(badges: badges, size: .m, maxCount: 6, spacing: 6)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
                Text(destinations.isEmpty ? "Halt im Fernverkehr" : destinations.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LineBadge.spokenList(badges) + (destinations.isEmpty ? "" : ", nach " + destinations.joined(separator: ", "))))
    }
}
