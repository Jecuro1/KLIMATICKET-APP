import SwiftUI
import KlimaCore

// MARK: stops – the mode tile of stop rows and the stop detail (ENRICH_SPEC §3.1, DESIGN §2.6). `ModeIcon` stays untouched.

struct StopTile: View {
    enum Glyph { case mode(TransportMode), town }

    var glyph: Glyph
    var size: CGFloat = 38
    /// „Haltestelle liegt in einem Skigebiet“: the white Schneehaube on top.
    var snowcap = false

    init(mode: TransportMode, size: CGFloat = 38, snowcap: Bool = false) {
        glyph = .mode(mode)
        self.size = size
        self.snowcap = snowcap
    }

    init(place: Place, size: CGFloat = 38) {
        glyph = place.kind == .town ? .town : .mode(place.products.primaryMode)
        self.size = size
        snowcap = place.tags.showsSnowcap
    }

    var body: some View {
        Group {
            switch glyph {
            case .mode(let mode):
                ModeIcon(mode: mode, size: size)
            case .town:
                Image(systemName: "mappin")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Theme.fernTile, in: .rect(cornerRadius: size * 0.31, style: .continuous))
            }
        }
        .snowcap(snowcap, size: size, cornerRadius: size * 0.31)
        .accessibilityHidden(true)
    }
}
