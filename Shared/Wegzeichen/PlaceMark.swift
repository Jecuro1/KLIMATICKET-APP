import SwiftUI
import KlimaCore

// Ortsmarken: round glyph tiles for facilities and places (BADGE_SPEC §2.5).

// MARK: - Ortsmarken (place glyph tiles)

enum PlaceMarkKind: String, CaseIterable, Sendable {
    case hauptbahnhof, bahnhof, fernverkehr, nachtzug, flughafen, bergbahn, talstation, schiff, parkAndRide, bikeAndRide
    case barrierefrei, nachtbus, skibus, wanderbus, gletscher, rufbus, saison, klimaticket, umstieg, krankenhaus
    case universitaet, einkaufszentrum, huette, nationalpark

    var glyph: BadgeGlyph {
        switch self {
        case .hauptbahnhof: .stationClock
        case .bahnhof, .fernverkehr: .symbol("train.side.front.car")
        case .nachtzug, .nachtbus: .symbol("moon.stars.fill")
        case .flughafen: .symbol("airplane.departure")
        case .bergbahn: .symbol("cablecar.fill")
        case .talstation: .gondola
        case .schiff: .symbol("ferry.fill")
        case .parkAndRide: .symbol("parkingsign")
        case .bikeAndRide: .symbol("bicycle")
        case .barrierefrei: .symbol("figure.roll")
        case .skibus: .symbol("figure.skiing.downhill")
        case .wanderbus: .symbol("figure.hiking")
        case .gletscher: .glacier
        case .rufbus: .symbol("phone.fill")
        case .saison: .symbol("calendar.badge.clock")
        case .klimaticket: .symbol("checkmark.seal.fill")
        case .umstieg: .symbol("arrow.triangle.swap")
        case .krankenhaus: .symbol("cross.case.fill")
        case .universitaet: .symbol("graduationcap.fill")
        case .einkaufszentrum: .symbol("bag.fill")
        case .huette: .symbol("house.lodge.fill")
        case .nationalpark: .symbol("tree.fill")
        }
    }

    /// Gradient top-leading → bottom-trailing.
    var colors: (Color, Color) {
        switch self {
        case .hauptbahnhof, .fernverkehr: (Color(hex: "#2E4A7F"), Color(hex: "#16284D"))
        case .bahnhof, .umstieg: (Color(hex: "#4B95E6"), Color(hex: "#2465BE"))
        case .nachtzug: (Color(hex: "#4A3FA8"), Color(hex: "#2B2470"))
        case .flughafen: (Color(hex: "#5574A6"), Color(hex: "#33507F"))
        case .bergbahn, .talstation: (Color(hex: "#38A07F"), Color(hex: "#1E7A5C"))
        case .schiff: (Color(hex: "#3DB3A4"), Color(hex: "#1F8478"))
        case .parkAndRide, .bikeAndRide: (Color(hex: "#3A78DB"), Color(hex: "#1F55B0"))
        case .barrierefrei: (Color(hex: "#2F86D6"), Color(hex: "#1C61A8"))
        case .nachtbus: (Color(hex: "#2A3563"), Color(hex: "#1A2140"))
        case .skibus: (Color(hex: "#4A5DD6"), Color(hex: "#3448C5"))
        case .wanderbus: (Color(hex: "#6A9A35"), Color(hex: "#4D7A1F"))
        case .gletscher: (Color(hex: "#6FB8E3"), Color(hex: "#3D8CC4"))
        case .rufbus: (Color(hex: "#E07A3E"), Color(hex: "#C4500C"))
        case .saison: (Color(hex: "#7D8BA0"), Color(hex: "#56657A"))
        case .klimaticket: (Color(hex: "#2E9C79"), Color(hex: "#1F7A5E"))
        case .krankenhaus: (Color(hex: "#1FA08A"), Color(hex: "#138A72"))   // never a red cross
        case .universitaet: (Color(hex: "#8A7FE8"), Color(hex: "#6A5ED6"))
        case .einkaufszentrum: (Color(hex: "#E86C8A"), Color(hex: "#C94E74"))
        case .huette: (Color(hex: "#7D8BA0"), Color(hex: "#56657A"))
        case .nationalpark: (Color(hex: "#38A07F"), Color(hex: "#1E7A5C"))
        }
    }

    var isSquare: Bool { self == .parkAndRide || self == .bikeAndRide }

    /// Every SF Symbol the badge system uses – keep in sync with BADGE_SPEC §6 (unit test: UIImage(systemName:) != nil).
    static let allSymbols: [String] = [
        "train.side.front.car", "train.side.middle.car", "tram.fill", "tram.fill.tunnel", "lightrail.fill", "bus.fill",
        "bus.doubledecker.fill", "cablecar.fill", "ferry.fill", "moon.stars.fill", "moon.zzz.fill", "snowflake", "snowflake.circle",
        "figure.skiing.downhill", "figure.hiking", "figure.roll", "figure.walk", "airplane.departure", "parkingsign",
        "parkingsign.circle.fill", "bicycle", "phone.fill", "calendar.badge.clock", "checkmark.seal.fill",
        "exclamationmark.triangle.fill", "arrow.triangle.swap", "arrow.up.arrow.down", "arrow.up.right", "arrow.right",
        "mountain.2.fill", "map.fill", "building.2.fill", "building.columns.fill", "cross.case.fill", "graduationcap.fill", "bag.fill",
        "house.lodge.fill", "tree.fill", "signpost.right.fill", "dot.radiowaves.left.and.right", "mappin", "mappin.and.ellipse",
        "star.fill", "star", "square.and.arrow.up", "chevron.left", "chevron.right", "xmark", "magnifyingglass", "bolt.fill",
        "globe.europe.africa.fill", "clock.arrow.circlepath", "location.fill",
    ]

    var label: String {
        switch self {
        case .hauptbahnhof: "Hauptbahnhof"
        case .bahnhof: "Bahnhof"
        case .fernverkehr: "Fernverkehr"
        case .nachtzug: "Nachtzug"
        case .flughafen: "Flughafen"
        case .bergbahn: "Bergbahn"
        case .talstation: "Talstation einer Bergbahn"
        case .schiff: "Schiffsanlegestelle"
        case .parkAndRide: "Park and Ride"
        case .bikeAndRide: "Bike and Ride"
        case .barrierefrei: "barrierefrei"
        case .nachtbus: "Nachtbus"
        case .skibus: "Skibus"
        case .wanderbus: "Wanderbus"
        case .gletscher: "Gletscher in der Nähe"
        case .rufbus: "Rufbus, nur auf Bestellung"
        case .saison: "Saisonlinie"
        case .klimaticket: "mit KlimaTicket gültig"
        case .umstieg: "Umstieg zur Bahn"
        case .krankenhaus: "Krankenhaus"
        case .universitaet: "Universität oder Hochschule"
        case .einkaufszentrum: "Einkaufszentrum"
        case .huette: "Hütte oder Alm"
        case .nationalpark: "Nationalpark"
        }
    }
}

struct PlaceMark: View {
    let kind: PlaceMarkKind
    var size: CGFloat = 18

    var body: some View {
        let (a, b) = kind.colors
        BadgeGlyphView(glyph: kind.glyph, size: size * 0.66, weight: .semibold)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: kind.isSquare ? size * 0.28 : size / 2, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(kind.label))
    }
}

extension PlaceMarkKind {
    /// 1:1 by raw value (`StopMark.Kind` in KlimaCore is the same list).
    init?(_ kind: StopMark.Kind) { self.init(rawValue: kind.rawValue) }
}
