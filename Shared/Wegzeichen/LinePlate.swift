import SwiftUI
import KlimaCore

// Line plates ("Liniensschilder", BADGE_SPEC §2.1): the badge model, the plate shapes and the plate rows.

// MARK: - Badge model

enum BadgeGlyph: Hashable, Sendable {
    case symbol(String)
    case peaks3, peaks2, peaks1, glacier, stationClock, gondola
}

struct LineBadge: Hashable, Sendable, Identifiable {
    var kind: LineKind
    /// Normalised plate text ("852", "RJX", "S45"); empty = glyph only.
    var text: String
    var glyph: BadgeGlyph? = nil
    /// Full VoiceOver label ("Bus 852", "Railjet Xpress", "Skibus").
    var spoken: String

    var id: String { "\(kind.rawValue)|\(text)|\(spoken)" }

    init(kind: LineKind, text: String, glyph: BadgeGlyph? = nil, spoken: String) {
        self.kind = kind
        self.text = text
        self.glyph = glyph
        self.spoken = spoken
    }

    /// The badge of a line at `size`: plate text and glyph from `LinePlateText`, VoiceOver from `SpokenLabels`.
    init(_ line: LineRef, size: PlateSize = .s, services: [PlaceService] = []) {
        let kind = LineKind.classify(line, services: services)
        let plate = LinePlateText.text(for: line, kind: kind, size: size.textSize)
        self.init(kind: kind, text: plate.text, glyph: plate.glyph.map { .symbol($0.symbolName) },
                  spoken: SpokenLabels.plate(line, services: services))
    }
}

// MARK: - Shapes

/// Long-distance plate: right edge slanted ("Keil"), small rounded corners.
struct WedgePlateShape: Shape {
    var corner: CGFloat = 0.18
    var slant: CGFloat = 0.24

    func path(in r: CGRect) -> Path {
        let h = r.height, rad = h * corner, s = h * slant, rr = rad * 0.5
        let len = (s * s + h * h).squareRoot()
        let dx = -s / len, dy = h / len
        var p = Path()
        p.move(to: CGPoint(x: r.minX + rad, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - rr, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX + dx * rr, y: r.minY + dy * rr), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - s - dx * rr, y: r.maxY - dy * rr))
        p.addQuadCurve(to: CGPoint(x: r.maxX - s - rr, y: r.maxY), control: CGPoint(x: r.maxX - s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - rad), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + rad))
        p.addQuadCurve(to: CGPoint(x: r.minX + rad, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

extension LineKind {
    func plateShape(height h: CGFloat) -> AnyShape {
        switch shape {
        case .wedge: AnyShape(WedgePlateShape())
        case .rect: AnyShape(RoundedRectangle(cornerRadius: h * 0.18, style: .continuous))
        case .soft: AnyShape(RoundedRectangle(cornerRadius: h * 0.30, style: .continuous))
        case .square: AnyShape(RoundedRectangle(cornerRadius: h * 0.24, style: .continuous))
        case .capsule: AnyShape(Capsule(style: .continuous))
        }
    }
}

// MARK: - Line plate

struct LinePlate: View {
    let badge: LineBadge
    var size: PlateSize = .s

    @ScaledMetric private var scale: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    init(_ badge: LineBadge, size: PlateSize = .s) {
        self.badge = badge
        self.size = size
        _scale = ScaledMetric(wrappedValue: 1, relativeTo: size.textStyle)
    }

    private var k: CGFloat { min(scale, size.maxHeight / size.height) }

    var body: some View {
        let h = size.height * k
        let wedgeExtra: CGFloat = badge.kind.shape == .wedge ? h * 0.22 : 0
        let minWidth: CGFloat = badge.kind.shape == .square ? h : (badge.text.isEmpty ? h * 1.2 : h * 1.3)
        HStack(spacing: 2 * k) {
            if let glyph = badge.glyph {
                BadgeGlyphView(glyph: glyph, size: size.fontSize * 1.05 * k, weight: size.weight)
            }
            if !badge.text.isEmpty {
                Text(badge.text)
                    .font(.system(size: size.fontSize * k, weight: size.weight))
                    .fontWidth(badge.text.count >= 4 ? .condensed : .standard)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(badge.kind.textColor)
        .padding(.leading, size.hPadding * k)
        .padding(.trailing, size.hPadding * k + wedgeExtra)
        .frame(minWidth: minWidth, minHeight: h, maxHeight: h)
        .background { PlateBackground(kind: badge.kind, text: badge.text, height: h, increased: contrast == .increased) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(badge.spoken))
    }
}

private struct PlateBackground: View {
    let kind: LineKind
    let text: String
    let height: CGFloat
    let increased: Bool

    var body: some View {
        let shape = kind.plateShape(height: height)
        ZStack {
            shape.fill(kind.fill(for: text))
            if kind == .rufbus {
                shape.stroke(kind.textColor, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
            } else {
                // Enamel: soft top-down sheen + top highlight.
                shape.fill(LinearGradient(stops: [.init(color: .white.opacity(0.17), location: 0),
                                                  .init(color: .white.opacity(0), location: 0.52),
                                                  .init(color: .black.opacity(0.07), location: 1)],
                                          startPoint: .top, endPoint: .bottom))
                shape.stroke(LinearGradient(colors: [.white.opacity(0.38), .clear], startPoint: .top, endPoint: .center),
                             lineWidth: 0.6)
                if let ring = kind.ring {
                    shape.stroke(ring, lineWidth: 1.1)
                }
            }
            if increased {
                shape.stroke(kind.textColor.opacity(0.45), lineWidth: 1)
            }
        }
        .shadow(color: Color(hex: "#0A1626").opacity(0.16), radius: 0.6, x: 0, y: 0.5)
    }
}

/// Plates with overflow: shows as many as fit (≤ maxCount) and "+k" for the rest. `badges` are in display order
/// already (`LinePlateOrder`); `extra` = lines that are not in `badges` at all (the „+k“ of a clipped row).
struct LinePlateRow: View {
    let badges: [LineBadge]
    var size: PlateSize = .s
    var maxCount: Int = 4
    var spacing: CGFloat = 4
    var extra: Int = 0

    var body: some View {
        let upper = min(maxCount, badges.count)
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: upper, through: 1, by: -1)), id: \.self) { n in
                HStack(spacing: spacing) {
                    ForEach(badges.prefix(n)) { LinePlate($0, size: size) }
                    if badges.count - n + extra > 0 { OverflowPlate(count: badges.count - n + extra, size: size) }
                }
                .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LineBadge.spokenList(badges, extra: extra)))
    }
}

struct OverflowPlate: View {
    let count: Int
    var size: PlateSize = .s

    var body: some View {
        Text("+\(count)")
            .font(.system(size: size.fontSize, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, size.hPadding)
            .frame(minWidth: size.height * 1.3, minHeight: size.height)
            .background(Theme.surfaceSecondary, in: .capsule)
            .accessibilityLabel(Text("und \(count) weitere"))
    }
}

extension LineBadge {
    /// Family order, natural sort inside a family, duplicates dropped (widgets and snapshots, which have no `LineRef`).
    /// The app orders `LineRef`s with `LinePlateOrder` before it builds badges.
    static func displayOrder(_ badges: [LineBadge]) -> [LineBadge] {
        var seen = Set<String>()
        let unique = badges.filter { seen.insert("\($0.kind.rawValue)|\($0.text)").inserted }
        return unique.sorted {
            if $0.kind.familyRank != $1.kind.familyRank { return $0.kind.familyRank < $1.kind.familyRank }
            return LinePlateOrder.naturalLess($0.text, $1.text)
        }
    }

    static func spokenList(_ badges: [LineBadge], extra: Int = 0) -> String {
        var s = (badges.count == 1 && extra == 0 ? "Linie: " : "Linien: ") + badges.map(\.spoken).joined(separator: ", ")
        if extra > 0 { s += ", und \(extra) weitere" }
        return s
    }
}

// MARK: - Glyph view

struct BadgeGlyphView: View {
    let glyph: BadgeGlyph
    var size: CGFloat
    var weight: Font.Weight = .bold

    var body: some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: size, weight: weight)).accessibilityHidden(true)
        case .peaks3: Peaks3Glyph().fill(style: FillStyle(eoFill: true)).frame(width: size, height: size).accessibilityHidden(true)
        case .peaks2: Peaks2Glyph().fill(style: FillStyle(eoFill: true)).frame(width: size, height: size).accessibilityHidden(true)
        case .peaks1: Peaks1Glyph().fill(style: FillStyle(eoFill: true)).frame(width: size, height: size).accessibilityHidden(true)
        case .glacier: GlacierGlyph().fill(style: FillStyle(eoFill: true)).frame(width: size, height: size).accessibilityHidden(true)
        case .stationClock: StationClockGlyph().fill(style: FillStyle(eoFill: true)).frame(width: size, height: size).accessibilityHidden(true)
        case .gondola: GondolaGlyph().fill(style: FillStyle(eoFill: true)).frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}

extension BadgeGlyph {
    /// The glyph of a ski area (`SkiArea.Glyph`).
    init(_ glyph: SkiArea.Glyph) {
        switch glyph {
        case .peaks3: self = .peaks3
        case .peaks2: self = .peaks2
        case .peaks1: self = .peaks1
        case .glacier: self = .glacier
        }
    }
}

// MARK: - Category plate (trips without a stored line)

/// The plate of a trip's mode category („S“, „U“, „Bus“, „Bim“): replaces the old outline capsules of trip rows, the
/// trip editor and the dashboard favourites (ENRICH_SPEC §3.3). Hidden from VoiceOver, like the capsule before: the
/// row's own label already names the mode.
struct CategoryPlate: View {
    let text: String
    var size: PlateSize = .xs

    var body: some View {
        LinePlate(LineBadge(kind: Self.kind(for: text), text: text, spoken: text), size: size)
            .accessibilityHidden(true)
    }

    static func kind(for category: String) -> LineKind {
        switch category {
        case "S": .sBahn
        case "U": .uBahn
        case "Bim": .tram
        case "Bus": .bus
        default: .sonst
        }
    }
}

/// What a widget or a Live Activity needs of a line plate, so they never load the place index (ENRICH_SPEC §3.1).
struct LineBadgeSnapshot: Codable, Hashable, Sendable {
    var kind: String
    var text: String
    var glyph: String?
    var spoken: String

    init(_ badge: LineBadge) {
        kind = badge.kind.rawValue
        text = badge.text
        if case .symbol(let name)? = badge.glyph { glyph = name }
        spoken = badge.spoken
    }

    var badge: LineBadge {
        LineBadge(kind: LineKind(rawValue: kind) ?? .sonst, text: text, glyph: glyph.map { .symbol($0) }, spoken: spoken)
    }
}
