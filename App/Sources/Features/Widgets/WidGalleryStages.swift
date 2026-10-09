import SwiftUI
import WidgetKit
import KlimaCore

// MARK: - Section title

/// Title + caption above a gallery stage ("Home-Bildschirm").
struct WidStageTitle: View {
    var title: String
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.screen)
    }
}

// MARK: - Home screen stage

/// All home-screen widgets at their real size (small 170 × 170, medium 364 × 170, large 364 × 382),
/// scaled down only when the screen is narrower than a 6.3" iPhone, on a wallpaper-like gradient.
struct WidHomeStage: View {
    let snapshot: WidgetSnapshot
    let appeared: Bool

    @State private var stageWidth: CGFloat = 382

    private let columnWidth: CGFloat = 364

    private var scale: CGFloat {
        min(1, max(0.5, (stageWidth - 20) / columnWidth))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            WidStageTitle(title: "Home-Bildschirm", caption: "Klein, mittel und groß – Amortisation und Schnellerfassung.")
                .widAppear(1, appeared)
            stage
        }
    }

    private var stage: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous)
        return VStack(spacing: 18 * scale) {
            smallRow
            tile(.systemMedium, caption: "Amortisation · Mittel", index: 3) {
                AmortizationWidgetView(snapshot: snapshot, family: .systemMedium, isInteractive: false)
            }
            tile(.systemLarge, caption: "Amortisation · Groß", index: 4) {
                AmortizationWidgetView(snapshot: snapshot, family: .systemLarge, isInteractive: false)
            }
            .id(WidGallerySection.large)
            tile(.systemMedium, caption: "Schnellerfassung · Mittel", index: 5) {
                QuickLogWidgetView(snapshot: snapshot, family: .systemMedium, isInteractive: false)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background { WidWallpaper().clipShape(shape) }
        .overlay { shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 0.6) }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            stageWidth = width
        }
        .padding(.horizontal, Theme.Spacing.xs + 2)
    }

    private var smallRow: some View {
        HStack(alignment: .top, spacing: 24 * scale) {
            tile(.systemSmall, caption: "Amortisation · Klein", index: 2) {
                AmortizationWidgetView(snapshot: snapshot, family: .systemSmall, isInteractive: false)
            }
            tile(.systemSmall, caption: "Schnellerfassung · Klein", index: 2) {
                QuickLogWidgetView(snapshot: snapshot, family: .systemSmall, isInteractive: false)
            }
        }
    }

    private func tile<Content: View>(_ family: WidgetFamily, caption: String, index: Int,
                                     @ViewBuilder content: () -> Content) -> some View {
        WidGalleryTile(family: family, caption: caption, scale: scale, spokenValue: spokenValue, content: content())
            .widAppear(index, appeared)
    }

    private var spokenValue: String { WidInsight.spokenSummary(snapshot) }
}

/// One widget preview: brand sky, continuous corners, home-screen shadow and the name underneath.
private struct WidGalleryTile<Content: View>: View {
    let family: WidgetFamily
    let caption: String
    let scale: CGFloat
    let spokenValue: String
    let content: Content

    var body: some View {
        let size = WidLayout.size(for: family)
        let shape = RoundedRectangle(cornerRadius: WidLayout.cornerRadius, style: .continuous)
        VStack(spacing: 7) {
            content
                .frame(width: size.width, height: size.height)
                .background { WidSkyBackground(family: family) }
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 0.6) }
                .scaleEffect(scale)
                .frame(width: size.width * scale, height: size.height * scale)
                // The shadow is cast by a plain shape behind the tile: on the tile itself it would render the whole
                // widget offscreen again on every scroll frame.
                .background {
                    RoundedRectangle(cornerRadius: WidLayout.cornerRadius * scale, style: .continuous)
                        .fill(Theme.background)
                        .shadow(color: Color.black.opacity(0.24), radius: 16, y: 10)
                }
            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.4), radius: 3, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: size.width * scale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Widget-Vorschau: \(caption)")
        .accessibilityValue(spokenValue)
    }
}

/// Calm alpine-dusk wallpaper: muted glacier blue into dusk violet with a hint of alpenglow on the right (deeper in
/// dark mode). Mid-toned on purpose: the light widgets stand out against it, it does not tint them, and the white
/// captions keep ≥ 4.5:1 everywhere (the earlier rainbow mesh went down to 3.4:1 on its coral side).
private struct WidWallpaper: View {
    private static let points: [SIMD2<Float>] = [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.42], [0.6, 0.5], [1, 0.38],
        [0, 1], [0.45, 1], [1, 1],
    ]

    private static let colors: [Color] = [
        Color(light: "#3D679F", dark: "#1C3454"), Color(light: "#4B629F", dark: "#223154"), Color(light: "#5F5D9E", dark: "#2A2A55"),
        Color(light: "#5A7DB5", dark: "#28426A"), Color(light: "#6670AE", dark: "#2F3765"), Color(light: "#9A6A8E", dark: "#4A3150"),
        Color(light: "#3F6496", dark: "#18304E"), Color(light: "#485A92", dark: "#1D2B4E"), Color(light: "#4E4F8A", dark: "#222447"),
    ]

    var body: some View {
        MeshGradient(width: 3, height: 3, points: Self.points, colors: Self.colors)
    }
}

// MARK: - Lock screen stage

/// The lock-screen set (inline above the clock, circular gauge, rectangular line) on a dark stage,
/// rendered white like the system's vibrant style.
struct WidLockStage: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            WidStageTitle(title: "Sperrbildschirm", caption: "Ring, Zeile und Text über der Uhrzeit – im Stil deines Sperrbildschirms.")
            lockScreen
                .padding(.horizontal, Theme.Spacing.cardGutter)
        }
    }

    private var lockScreen: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous)
        return VStack(spacing: 0) {
            inlineRow
            clock
            accessoryRow
                .padding(.top, Theme.Spacing.s)
        }
        .padding(.top, Theme.Spacing.l + 4)
        .padding(.bottom, Theme.Spacing.xl)
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity)
        .background { WidLockWallpaper() }
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6) }
        .background { shape.fill(Theme.background).shadow(color: Color.black.opacity(0.25), radius: 18, y: 10) }
        .foregroundStyle(Color.white)
        .tint(Color.white)
        .environment(\.colorScheme, .dark)
    }

    private var inlineRow: some View {
        HStack(spacing: 6) {
            Text(Format.weekdayDayMonth(Date()))
            AmortizationWidgetView(snapshot: snapshot, family: .accessoryInline)
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.88))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var clock: some View {
        Text(verbatim: "9:41")
            .font(.system(size: 92, weight: .semibold, design: .rounded))
            .foregroundStyle(LinearGradient(colors: [Color.white, Color.white.opacity(0.78)], startPoint: .top, endPoint: .bottom))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityHidden(true)
    }

    private var accessoryRow: some View {
        HStack(spacing: 14) {
            AmortizationWidgetView(snapshot: snapshot, family: .accessoryCircular)
                .padding(2)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.white.opacity(0.1)))
            AmortizationWidgetView(snapshot: snapshot, family: .accessoryRectangular)
                .frame(width: 160, height: 72)
        }
    }
}

/// Blue-hour wallpaper with stars and a low ridge horizon (always dark). The stars leave a gap behind the inline
/// row (24–46 pt) – a star beside "75 % rentiert" reads as punctuation – and the ridges stay below the accessory row.
private struct WidLockWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.background, Theme.dusk.mix(with: Theme.background, by: 0.62)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.alpenglow.opacity(0.42), .clear],
                           center: UnitPoint(x: 0.74, y: 0.86), startRadius: 0, endRadius: 260)
            StarField(seed: 5, count: 46, t: 0)
                .mask { inlineRowGap }
            WidRidgeShape(peak: CGPoint(x: 0.72, y: 0.87), seed: 4, drop: 0.7, roughness: 1.1)
                .fill(Theme.dusk.opacity(0.26))
            WidRidgeShape(peak: CGPoint(x: 0.24, y: 0.91), seed: 9, drop: 0.6, roughness: 1)
                .fill(Theme.background.opacity(0.7))
        }
        .accessibilityHidden(true)
    }

    private var inlineRowGap: some View {
        VStack(spacing: 0) {
            Color.black.frame(height: 14)
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 8)
            Color.clear.frame(height: 30)
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 10)
            Color.black
        }
    }
}
