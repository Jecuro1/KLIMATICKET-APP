import KlimaCore
import SwiftUI
import UIKit

// MARK: stops – LOGO_SPEC §4: Landesmarke with Wappen, brand chip for rows, Gebietsleiste for the detail hero.
// Logos are shown unchanged (no tint, crop, rounding or distortion); the own Wegzeichen are the fallback everywhere
// and take the same space.

// MARK: - Landesmarke with Wappen (falls back to the own blaze)

struct StateMarkW: View {
    enum Style { case compact, full, mini }
    let state: Bundesland
    var style: Style = .compact

    private var logos: LogoPackStore { .shared }

    var body: some View {
        if let wappen = logos.wappen(state, size: style == .full ? .chipM : .chip) {
            HStack(spacing: style == .full ? 6 : 4) {
                wappenImage(wappen)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(height: style == .full ? 18 : (style == .mini ? 12 : 14))
                    .accessibilityHidden(true)
                if style == .full {
                    Text(state.name).font(.footnote.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                } else {
                    Text(state.code2).font(.system(size: style == .mini ? 9.5 : 10.5, weight: .bold)).tracking(0.4)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.leading, style == .full ? 5 : (style == .mini ? 2 : 3))
            .padding(.trailing, style == .full ? 10 : (style == .mini ? 4 : 6))
            .frame(height: style == .full ? 26 : (style == .mini ? 16 : 18))
            .background(Theme.textPrimary.opacity(0.055), in: .rect(cornerRadius: style == .full ? 9 : 6, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(SpokenLabels.stateMark(state.rawValue)))
        } else {
            StateMark(state: state, style: style == .full ? .full : .compact)
        }
    }

    private func wappenImage(_ w: LogoPackStore.Wappen) -> Image {
        switch w {
        case .asset(let name): Image(name)           // exact-size PNG (14 / 18 pt), never tinted or clipped
        case .pack(let ui): Image(uiImage: ui)
        }
    }
}

// MARK: - Compact brand chip for rows (tile / wordmark / own badge)

struct BrandChip<Fallback: View>: View {
    enum Size { case row, detail }

    let brand: LogoPackManifest.Brand?
    var size: Size = .row
    @ViewBuilder var fallback: () -> Fallback

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .caption2) private var logoH: CGFloat = 14

    private var logos: LogoPackStore { .shared }

    var body: some View {
        let dark = scheme == .dark
        if let b = brand, b.compact != .none, let img = logos.image(b, large: size == .detail, dark: dark) {
            let h = min(logoH * (size == .detail ? 16.0 / 14.0 : 1), size == .detail ? 22 : 20)
            Group {
                if b.compact == .tile {
                    HStack(spacing: size == .detail ? 6 : 5) {
                        plated(Image(uiImage: img).resizable().scaledToFit().frame(width: h + 2, height: h + 2), b, dark: dark, tight: true)
                        Text(b.name).font(.system(size: size == .detail ? 12.5 : 11.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    }
                } else {
                    plated(Image(uiImage: img).resizable().scaledToFit().frame(height: h).frame(maxWidth: size == .detail ? 100 : 66),
                           b, dark: dark, tight: false)
                }
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(BrandText.spoken(b)))
            .transition(.opacity)
        } else {
            fallback()
        }
    }

    /// Logos that need a plate (LOGO_SPEC §4.5): Firn in dark mode, Nacht in light mode.
    @ViewBuilder
    private func plated(_ content: some View, _ b: LogoPackManifest.Brand, dark: Bool, tight: Bool) -> some View {
        let needsFirn = dark && b.plate.dark && b.img.sd == nil
        let needsNight = !dark && b.plate.light
        if needsFirn || needsNight {
            content.padding(tight ? 1.5 : 4).padding(.horizontal, tight ? 0 : 1)
                .background(needsFirn ? Color(hex: "#EEF2F7") : Color(hex: "#1C2433"), in: .rect(cornerRadius: tight ? 4 : 5, style: .continuous))
                .overlay {
                    if contrast == .increased {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Theme.textPrimary.opacity(0.3), lineWidth: 1)
                    }
                }
        } else {
            content
        }
    }
}

/// Does a row show the logo of `brand` (pack ready, image decodes)? Layout code uses it to pick the degradation step.
@MainActor
func brandChipShowsLogo(_ brand: LogoPackManifest.Brand?, dark: Bool) -> Bool {
    guard let b = brand, b.compact != .none else { return false }
    return LogoPackStore.shared.image(b, large: false, dark: dark) != nil
}

// MARK: - Hero „Gebietsleiste“ (max. 2 cells)

struct GebietsLeiste: View {
    let cells: [LogoPackManifest.Brand]
    var onTap: (LogoPackManifest.Brand) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .body) private var square: CGFloat = 36

    private var logos: LogoPackStore { .shared }

    /// Cells whose image is available; the bar disappears when none is.
    private var visible: [LogoPackManifest.Brand] {
        cells.prefix(2).filter { logos.image($0, large: true, dark: scheme == .dark) != nil }
    }

    var body: some View {
        let cells = visible
        if !cells.isEmpty {
            let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                ForEach(Array(cells.enumerated()), id: \.element.id) { i, b in
                    if i > 0 {
                        if dts.isAccessibilitySize { Divider().padding(.horizontal, 12) } else { Divider().frame(height: 44) }
                    }
                    Button { onTap(b) } label: { cell(b) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(BrandText.spoken(b)))
                        .accessibilityHint(Text(b.level == .ski ? "Zeigt Infos zum Skigebiet" : "Zeigt Infos zur Region"))
                }
            }
            .background(reduceTransparency ? AnyShapeStyle(Theme.sheetBackground) : AnyShapeStyle(Color(light: "#FFFFFF", dark: "#FFFFFF0E")),
                        in: .rect(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.textPrimary.opacity(0.08), lineWidth: 0.5) }
            .transition(.opacity)
        }
    }

    private func cell(_ b: LogoPackManifest.Brand) -> some View {
        let dark = scheme == .dark
        let maxH = min(square, 48)
        let h = b.aspect <= 1.3 ? maxH : min(maxH * 30 / 36, 132 / max(b.aspect, 0.1))
        return VStack(spacing: 5) {
            if let img = logos.image(b, large: true, dark: dark) {
                let logo = Image(uiImage: img).resizable().scaledToFit().frame(height: h).frame(maxWidth: 140)
                if dark && b.plate.dark && b.img.ld == nil {
                    logo.padding(.vertical, 4).padding(.horizontal, 7).background(Color(hex: "#EEF2F7"), in: .rect(cornerRadius: 9, style: .continuous))
                } else if !dark && b.plate.light {
                    logo.padding(.vertical, 4).padding(.horizontal, 7).background(Color(hex: "#1C2433"), in: .rect(cornerRadius: 9, style: .continuous))
                } else {
                    logo
                }
            }
            Text(BrandText.kind(b).uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.9)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(.vertical, 9)
        .contentShape(.rect)
    }
}
