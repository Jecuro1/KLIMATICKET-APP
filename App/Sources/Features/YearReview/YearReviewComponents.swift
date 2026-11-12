import SwiftUI
import KlimaCore

// Building blocks of the year story pages. Colours and spacing only through `Theme` tokens, animation only through the
// Motion tokens and `MotionPolicy` (docs/MOTION.md); in screenshot mode every entrance is its end state.

// MARK: - Page frame

/// A page's content: laid out to fit the screen, and – when the text is so large that it cannot (accessibility sizes) –
/// scrolling instead of clipping.
struct StoryPageScaffold<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.bottom, Theme.Spacing.m)
            }
            .scrollIndicators(.visible)
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.m)
    }
}

/// "ERSPARNIS" – the page's eyebrow with a symbol.
struct StoryKicker: View {
    let kind: YearReviewPageKind
    var symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(Theme.accentText)
                .accessibilityHidden(true)
            Kicker(text: YearReviewText.kicker(for: kind))
        }
    }
}

/// The soft colour wash behind a page (over the calm alpine sky). Cross-fades between pages.
struct YearReviewGlow: View {
    let kind: YearReviewPageKind
    @Environment(\.colorScheme) private var colorScheme

    private var colors: (Color, Color) {
        switch kind {
        case .intro: (Theme.glacier, Theme.dawn)
        case .savings: (Theme.pine, Theme.glacier)
        case .distance: (Theme.glacier, Theme.dusk)
        case .favoriteRoute: (Theme.dusk, Theme.alpenglow)
        case .rhythm: (Theme.alpenglow, Theme.gold)
        case .onTheRoad: (Theme.gold, Theme.glacier)
        case .purpose: (Theme.dusk, Theme.glacier)
        case .climate: (Theme.pine, Theme.glacier2)
        case .finale: (Theme.dawn, Theme.dusk)
        }
    }

    var body: some View {
        let strength = colorScheme == .dark ? 0.34 : 0.30
        ZStack {
            RadialGradient(colors: [colors.0.opacity(strength), colors.0.opacity(0)], center: .topTrailing, startRadius: 0, endRadius: 440)
            RadialGradient(colors: [colors.1.opacity(strength * 0.85), colors.1.opacity(0)], center: .bottomLeading, startRadius: 0, endRadius: 480)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Numbers & labels

/// The page's one big number: counts up once (revisiting the page shows it at once), rounded light, shrinks before it
/// would clip.
struct StoryNumeral: View {
    let value: Double
    /// 0 for the first visit, `value` when the page was seen before.
    var from: Double = 0
    var delay: Double = 0.12
    var unit: String? = nil
    var style: AnyShapeStyle = AnyShapeStyle(Theme.textPrimary)
    var format: (Double) -> String

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 88

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            CountUpText(value: value, from: from, delay: delay, format: format)
                .font(.system(size: size, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(style)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            if let unit {
                Text(unit)
                    .font(.system(size: size * 0.3, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

/// A rounded pill with a symbol: the break-even day, "Schätzung", a multiplier. Tinted surface, primary text – the tint
/// is decoration, the words carry the meaning.
struct StoryPill: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(tint.opacity(0.16), in: .capsule)
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
    }
}

/// A short secondary line.
struct StoryCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Entrances

/// Hands its content `isDrawn`: false until the page appeared, then true for good (animated with `Motion.gentle`). Bars
/// grow, routes draw. Reduce Motion and screenshot mode: drawn from the start.
struct StoryDraw<Content: View>: View {
    var delay: Double = 0.2
    @ViewBuilder var content: (Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = MotionPolicy.isStatic

    var body: some View {
        content(isDrawn || reduceMotion)
            .onAppear {
                guard !isDrawn else { return }
                withMotion(Motion.gentle.delay(delay)) { isDrawn = true }
            }
    }
}

/// A horizontal bar: track plus fill of `fraction` (0…1) that grows in from the leading edge.
struct StoryBar: View {
    let fraction: Double
    var tint: AnyShapeStyle = AnyShapeStyle(Theme.progressGradient)
    var height: CGFloat = 10
    var isDrawn: Bool = true

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.textTertiary.opacity(0.18))
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, proxy.size.width * CGFloat(min(max(fraction, 0), 1))))
                    .scaleEffect(x: isDrawn ? 1 : 0.02, anchor: .leading)
                    .opacity(isDrawn ? 1 : 0)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Decoration

/// The ridge under the first page: two layers of mountains and the morning sun – drawn once, nothing moves.
struct StoryRidge: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(RadialGradient(colors: [Theme.dawn.opacity(0.55), Theme.dawn.opacity(0)], center: .center, startRadius: 4, endRadius: 120))
                .frame(width: 240, height: 240)
                .offset(x: 70, y: -70)
            RidgeShape(peakX: 0.72, peakY: 0.16, seed: 11, roughness: 0.7)
                .fill(LinearGradient(colors: [Theme.dusk.opacity(0.34), Theme.dusk.opacity(0.06)], startPoint: .top, endPoint: .bottom))
            RidgeShape(peakX: 0.34, peakY: 0.3, seed: 5, roughness: 0.5)
                .fill(LinearGradient(colors: [Theme.glacier.opacity(0.42), Theme.glacier.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            RidgeShape(peakX: 0.34, peakY: 0.3, seed: 5, roughness: 0.5)
                .stroke(Theme.textPrimary.opacity(0.18), lineWidth: 1)
        }
        .frame(height: 190)
        .accessibilityHidden(true)
    }
}

// MARK: - Progress

/// The segmented progress bars on top: finished pages full, the current page filling over `pageSeconds` (full when the
/// story does not advance on its own), the rest empty. One accessibility element: "Seite 3 von 8".
struct YearReviewProgressBar: View {
    let store: YearReviewStore
    let advancesAutomatically: Bool

    var body: some View {
        let elapsed = store.clock.elapsed
        HStack(spacing: 4) {
            ForEach(0..<store.pageCount, id: \.self) { index in
                segment(index, elapsed: elapsed)
            }
        }
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fortschritt")
        .accessibilityValue(YearReviewText.pageOf(store.index + 1, store.pageCount))
    }

    private func segment(_ index: Int, elapsed: Double) -> some View {
        let fraction: Double
        if index < store.index {
            fraction = 1
        } else if index == store.index {
            fraction = advancesAutomatically && !store.isLast ? min(1, elapsed / YearReviewStore.pageSeconds) : 1
        } else {
            fraction = 0
        }
        return Capsule()
            .fill(Theme.textTertiary.opacity(0.28))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Theme.textPrimary)
                    .scaleEffect(x: max(fraction, 0.0001), anchor: .leading)
                    .opacity(fraction > 0 ? 1 : 0)
            }
            .clipShape(.capsule)
    }
}
