import SwiftUI
import KlimaCore

// Landesmarke ("Bundesland", BADGE_SPEC §2.2): Landesfarben-Streifen + Kürzel. The own fallback of the Wappen.

typealias Bundesland = FederalState

extension FederalState {
    var code2: String {
        switch self {
        case .burgenland: "BG"
        case .kaernten: "KT"
        case .niederoesterreich: "NÖ"
        case .oberoesterreich: "OÖ"
        case .salzburg: "SB"
        case .steiermark: "ST"
        case .tirol: "TI"
        case .vorarlberg: "VB"
        case .wien: "WI"
        case .foreign: "XX"
        }
    }

    var name: String { displayName }

    /// Landesfarben top → bottom (heraldic approximations, no coat of arms).
    var stripes: [Color] {
        switch self {
        case .burgenland: [Color(hex: "#C8102E"), Color(hex: "#F2B705")]
        case .kaernten: [Color(hex: "#FFD200"), Color(hex: "#C8102E"), Color(hex: "#FFFFFF")]
        case .niederoesterreich: [Color(hex: "#0F4C97"), Color(hex: "#FFD200")]
        case .oberoesterreich, .tirol: [Color(hex: "#FFFFFF"), Color(hex: "#C8102E")]
        case .salzburg, .vorarlberg, .wien: [Color(hex: "#C8102E"), Color(hex: "#FFFFFF")]
        case .steiermark: [Color(hex: "#FFFFFF"), Color(hex: "#00843D")]
        case .foreign: [Color(hex: "#9AA3AE"), Color(hex: "#D0D5DB")]
        }
    }
}

struct LandesBlaze: View {
    let state: Bundesland
    var width: CGFloat = 8
    var height: CGFloat = 11

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.27, style: .continuous)
        VStack(spacing: 0) {
            ForEach(Array(state.stripes.enumerated()), id: \.offset) { _, color in
                Rectangle().fill(color)
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay { shape.stroke(Theme.textPrimary.opacity(0.22), lineWidth: 0.6) }
        .accessibilityHidden(true)
    }
}

struct StateMark: View {
    enum Style { case compact, full }
    let state: Bundesland
    var style: Style = .compact

    var body: some View {
        HStack(spacing: style == .compact ? 4 : 6) {
            if style == .compact {
                LandesBlaze(state: state)
                Text(state.code2).font(.system(size: 10.5, weight: .bold)).tracking(0.4).foregroundStyle(Theme.textSecondary)
            } else {
                LandesBlaze(state: state, width: 10, height: 14)
                Text(state.name).font(.footnote.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(state.code2).font(.caption2.weight(.bold)).tracking(0.5).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.leading, style == .compact ? 4 : 6)
        .padding(.trailing, style == .compact ? 6 : 9)
        .frame(height: style == .compact ? 18 : 24)
        .background(Theme.textPrimary.opacity(0.055), in: .rect(cornerRadius: style == .compact ? 6 : 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(SpokenLabels.stateMark(state.rawValue)))
    }
}
