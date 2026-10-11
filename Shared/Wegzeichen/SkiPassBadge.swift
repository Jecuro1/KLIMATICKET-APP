import SwiftUI
import KlimaCore

// Own ski-pass badge ("Skipass-Badge", BADGE_SPEC §2.3): Gipfelfarbe + glyph + name. Fallback of the official logos.

struct SkiPassBadge: View {
    enum Style { case compact, iconOnly, full }
    let name: String
    var hue: SummitHue = .enzian
    var glyph: BadgeGlyph = .peaks3
    var style: Style = .compact
    /// Full area name for VoiceOver, also when only the glyph or the short name is visible.
    var spokenName: String? = nil

    /// Badge of a ski area: short name in rows, full name in the detail.
    init(name: String, hue: SummitHue = .enzian, glyph: BadgeGlyph = .peaks3, style: Style = .compact) {
        self.name = name
        self.hue = hue
        self.glyph = glyph
        self.style = style
    }

    init(area: SkiArea, style: Style = .compact) {
        self.init(name: area.name,
                  hue: SummitHue(rawValue: area.hue) ?? .fels, glyph: BadgeGlyph(area.glyph), style: style)
        spokenName = area.name
    }

    var body: some View {
        let disc = style == .full ? 18.0 : 15.0
        HStack(spacing: style == .full ? 6 : 4) {
            BadgeGlyphView(glyph: glyph, size: disc * 0.8)
                .foregroundStyle(.white)
                .frame(width: disc, height: disc)
                .background(LinearGradient(colors: [hue.color.mix(with: .white, by: 0.12), hue.color.mix(with: .black, by: 0.2)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), in: .circle)
            if style != .iconOnly {
                Text(name).font(.system(size: style == .full ? 12.5 : 11, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(Color(light: "#1B2A55", dark: "#EAF2FF"))
            }
        }
        .padding(.leading, style == .full ? 3 : 2)
        .padding(.trailing, style == .iconOnly ? 2 : (style == .full ? 10 : 7))
        .frame(height: style == .full ? 24 : 18)
        .background(LinearGradient(colors: [Color(light: "#FFFFFF", dark: "#CDE0FF33"), Color(light: "#EDF3FF", dark: "#AAC8FF1F")],
                                   startPoint: .top, endPoint: .bottom), in: .capsule)
        .overlay { Capsule().stroke(Color(light: "#C3D4F2", dark: "#BED7FF52"), lineWidth: 0.75) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(SpokenLabels.skiArea(spokenName ?? name)))
    }
}
