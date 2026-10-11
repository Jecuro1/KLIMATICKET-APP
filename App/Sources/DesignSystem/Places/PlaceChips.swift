import SwiftUI
import KlimaCore

// MARK: stops – chips of the stop rows and the stop detail (ENRICH_SPEC §3.1, BADGE_SPEC §2.4, §2.5).

/// Region text chip („Bregenzerwald“): the own fallback of a region logo.
struct RegionChip: View {
    let name: String
    var size: Size = .row
    enum Size { case row, detail }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: size == .row ? 9 : 10.5, weight: .semibold))
                .accessibilityHidden(true)
            Text(name)
                .font(size == .row ? .caption2.weight(.medium) : .footnote.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(size == .row ? Theme.textSecondary : Theme.textPrimary)
        .padding(.horizontal, size == .row ? 0 : 9)
        .frame(height: size == .row ? 18 : 24)
        .background {
            if size == .detail { Capsule().fill(Theme.textPrimary.opacity(0.06)) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(SpokenLabels.region(name)))
    }
}

/// „Bezirk Bregenz“ / „10. Bezirk · Favoriten“.
struct BezirkChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(Theme.textPrimary.opacity(0.06)))
    }
}

/// „P+R · 28 m“, „barrierefrei“, „Talstation Dorfbahn Warth · 77 m“.
struct PlaceMarkChip: View {
    let mark: StopMark
    var size: Size = .detail
    enum Size { case row, detail }

    var body: some View {
        let kind = PlaceMarkKind(mark.kind)
        HStack(spacing: 5) {
            if let kind { PlaceMark(kind: kind, size: size == .row ? 16 : 18) }
            Text(mark.label)
                .font(size == .row ? .caption2.weight(.medium) : .footnote.weight(.semibold))
                .foregroundStyle(size == .row ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.leading, size == .row ? 0 : 3)
        .padding(.trailing, size == .row ? 0 : 9)
        .frame(height: size == .row ? 18 : 24)
        .background {
            if size == .detail { Capsule().fill(Theme.textPrimary.opacity(0.06)) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(mark.spoken))
    }
}

/// KlimaTicket validity: `valid` is silent in rows (it is the normal case); `check`, `notIncluded` and `border` always show.
struct KlimaTicketChip: View {
    let status: KlimaTicketValidity.Status
    var inRow = false

    var body: some View {
        if let spec {
            HStack(spacing: 4) {
                Image(systemName: spec.symbol).font(.system(size: 11, weight: .bold)).accessibilityHidden(true)
                Text(spec.text).font(.footnote.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(spec.color)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(spec.color.opacity(0.13)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(spec.spoken))
        }
    }

    private var spec: (symbol: String, text: String, spoken: String, color: Color)? {
        switch status {
        case .valid:
            inRow ? nil : ("checkmark.seal.fill", "KlimaTicket Ö", "Mit KlimaTicket gültig", Theme.positiveText)
        case .check:
            ("questionmark.circle.fill", "KlimaTicket prüfen", "KlimaTicket: Gültigkeit prüfen", Theme.summitText)
        case .notIncluded:
            ("xmark.seal.fill", "Nicht im KlimaTicket", "Nicht im KlimaTicket enthalten", Theme.negativeText)
        case .border:
            ("arrow.triangle.swap", "KlimaTicket Übergang", "KlimaTicket: Übergangsbereich", Theme.accentText)
        }
    }
}

/// „nur im Winter“, „Saison“ … (the family header and the line row).
struct SeasonTag: View {
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "snowflake").font(.system(size: 9, weight: .bold)).accessibilityHidden(true)
            Text(text).font(.caption2.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(Color(light: "#3448C5", dark: "#B9C4FF"))
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(Capsule().fill(Color(light: "#3448C5", dark: "#8E9BFF").opacity(0.14)))
    }

    /// „nur im Winter“ / „nur im Sommer“ / „Saisonbetrieb“ for a line, nil for year-round lines.
    static func text(for flags: LineFlags) -> String? {
        if flags.contains(.winter) && !flags.contains(.summer) { return "nur im Winter" }
        if flags.contains(.summer) && !flags.contains(.winter) { return "nur im Sommer" }
        if flags.contains(.seasonal) || flags.contains(.schoolOrSeasonal) { return "Saisonbetrieb" }
        return nil
    }
}
