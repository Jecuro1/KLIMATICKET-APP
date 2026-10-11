import KlimaCore
import SwiftUI

// MARK: stops – the ski-pass card of the stop detail (BADGE_SPEC §2.3, LOGO_SPEC §4.4): Gipfelfarbe, punched hole,
// perforation, contour lines, valley station, resorts and alliances. With the official logo: the logo tile and
// „Logo © …“; without: the name as text.

struct SkiPassCard: View {
    let area: SkiArea
    /// „Talstation Dorfbahn Warth · 77 m · 1 min zu Fuß“.
    var valleyStation: String?
    var allianceNames: [String] = []
    var brand: LogoPackManifest.Brand?
    var liftBrand: LogoPackManifest.Brand?
    var onWebsite: ((LogoPackManifest.Brand) -> Void)?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var hue: Color { (SummitHue(rawValue: area.hue) ?? .fels).color }
    private var logos: LogoPackStore { .shared }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(LinearGradient(colors: [hue.mix(with: .white, by: 0.10), hue, hue.mix(with: .black, by: 0.32)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            ContourLines().stroke(.white.opacity(0.10), lineWidth: 1).clipShape(shape)
            BadgeGlyphView(glyph: BadgeGlyph(area.glyph), size: 150, weight: .bold)
                .foregroundStyle(.white.opacity(0.13))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 6).padding(.bottom, 0)
                .clipShape(shape)
            content
            Circle().fill(Theme.sheetBackground).frame(width: 15, height: 15)   // the punch hole
                .overlay { Circle().stroke(.black.opacity(0.18), lineWidth: 0.6) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 16).padding(.trailing, 18)
        }
        .overlay { shape.stroke(.white.opacity(contrast == .increased ? 0.6 : 0.16), lineWidth: contrast == .increased ? 1.5 : 1) }
        .shadow(color: hue.opacity(0.28), radius: 14, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                if let brand, let img = logos.image(brand, large: true, dark: scheme == .dark) {
                    Image(uiImage: img).resizable().scaledToFit().frame(width: 46, height: 46)
                        .padding(5).background(.white, in: .rect(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(("Skigebiet · " + (area.shortName ?? area.name)).uppercased(with: Format.locale))
                        .font(.system(size: 11, weight: .semibold)).tracking(1.1).foregroundStyle(.white.opacity(0.78))
                    Text(area.name).font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
            }
            if let valleyStation {
                HStack(spacing: 8) {
                    BadgeGlyphView(glyph: .gondola, size: 17, weight: .semibold).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(.white.opacity(0.18), in: .rect(cornerRadius: 9, style: .continuous))
                    Text(valleyStation).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                }
            }
            PerforationLine().stroke(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 4])).frame(height: 1)
            if !area.resorts.isEmpty {
                Text(area.resorts.joined(separator: " · ")).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95)).lineLimit(3)
            }
            if !allianceNames.isEmpty {
                Text("Teil von " + allianceNames.joined(separator: ", ")).font(.caption).foregroundStyle(.white.opacity(0.8))
            }
            footnote
        }
        .padding(18)
        .padding(.trailing, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var footnote: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let liftBrand, let img = logos.image(liftBrand, large: false, dark: true) {
                HStack(spacing: 8) {
                    Text("Lifte im Ort:").font(.caption).foregroundStyle(.white.opacity(0.8))
                    Image(uiImage: img).resizable().scaledToFit().frame(height: 14).frame(maxWidth: 80)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(hex: "#1C2433"), in: .capsule)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Lifte im Ort: \(liftBrand.name)"))
            }
            if let brand {
                Button { onWebsite?(brand) } label: {
                    Text(brand.attribution.isEmpty ? "Logo © \(brand.owner)" : brand.attribution)
                        + Text(" · Website ↗")
                }
                .font(.caption2).foregroundStyle(.white.opacity(0.78))
                .buttonStyle(.plain)
            } else {
                Text("Skigebietsname als Textangabe").font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var spoken: String {
        var s = SpokenLabels.skiArea(area.name)
        if let valleyStation { s += ", " + valleyStation }
        if !area.resorts.isEmpty { s += ", Orte: " + area.resorts.joined(separator: ", ") }
        if !allianceNames.isEmpty { s += ", Teil von " + allianceNames.joined(separator: ", ") }
        return s
    }
}

private struct PerforationLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

/// Soft height lines across the card.
private struct ContourLines: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0..<6 {
            let y = r.height * (0.18 + CGFloat(i) * 0.15)
            p.move(to: CGPoint(x: r.minX, y: y))
            p.addCurve(to: CGPoint(x: r.maxX, y: y - 14 + CGFloat(i) * 3),
                       control1: CGPoint(x: r.width * 0.3, y: y - 24), control2: CGPoint(x: r.width * 0.65, y: y + 20))
        }
        return p
    }
}
