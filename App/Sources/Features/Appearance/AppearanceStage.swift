import SwiftUI
import KlimaCore

// MARK: themes – the live preview at the top of Look & Feel: a small Übersicht in the palette, motion and number format you are
// choosing – before it reaches the app. Illustration only (hidden from VoiceOver, one summary label instead); the sun/moon
// switch is the one control on it. Every figure is a fixed demo value, formatted exactly like the Übersicht formats it
// (MARK: review-themes): its euro figures round on their own (whole euros for the totals, cents for a trip), so Beträge does
// not move them – the example line under Beträge shows that option; CO₂ and the week follow Zahlen like the Übersicht.

struct AppearanceStage: View {
    var prefs: AppearancePrefs
    var scheme: ColorScheme
    /// Bumped on every palette change: a one-shot glow behind the hero.
    var glow: Int
    /// Bumped when Bewegung changes: the hero shows that level once (count-in, cross-fade or nothing).
    var replay: Int
    @Binding var schemeSelection: ColorScheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Demo figures: 73 % of the ticket earned back, € 1.300 of value, € 23,40 a trip, 1.240 kg CO₂, a week of trips.
    static let demoFraction = 0.73
    static let demoValue = 1300.0
    static let demoPerTrip = 23.4
    static let demoCO2 = 1240.0
    /// Trips per weekday, Monday first.
    static let demoWeek: [Double] = [2, 3, 1, 3, 4, 1, 0]

    /// The totals in whole euros and a trip in cents – the Übersicht's own precision (`SummitFigures.euro`, `Format.euroPrecise`).
    static let valueText = AppearanceFormat.euro(demoValue, digits: 0)
    static let perTripText = AppearanceFormat.euro(demoPerTrip, digits: 2)

    @State private var heroValue = AppearanceStage.demoFraction
    @State private var heroOpacity = 1.0

    var body: some View {
        let colors = ThemeRuntime.colors(for: prefs.palette)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            topBar(colors)
            heroCard(colors)
            HStack(spacing: Theme.Spacing.xs) {
                figure(Self.valueText, label: "Wert", symbol: "eurosign", tint: Theme.pine)
                figure(Self.perTripText, label: "je Fahrt", symbol: "tram.fill",
                       tint: colors.accent)
                figure(AppearanceFormat.co2(Self.demoCO2, prefs: prefs.format), label: "CO₂", symbol: "leaf.fill", tint: Theme.pine)
            }
            weekCard(colors)
            ctaRow(colors)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                AmbientBackground(style: .standard, glow: 0.7, animated: false)
                // The palette tints the sky a little, the way the accent tints the app.
                RadialGradient(colors: [colors.accent.opacity(0.22), .clear], center: .topTrailing, startRadius: 0, endRadius: 320)
            }
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.5), lineWidth: 1) }
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.3 : 0.12), radius: 16, y: 8)
        .environment(\.colorScheme, scheme)
        // An illustration of fixed proportions: it grows with the text up to xLarge; the options below grow on to AX5.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
        .onChange(of: replay) { _, _ in replayHero() }
    }

    // MARK: Parts

    private func topBar(_ colors: ThemeColorSet) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Kicker(text: "Vorschau")
                Text("Übersicht")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .accessibilityHidden(true)
            Spacer(minLength: Theme.Spacing.xs)
            schemeToggle
        }
    }

    private func heroCard(_ colors: ThemeColorSet) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(AppearanceFormat.number(heroValue * 100, decimals: 0) + " %")
                    .font(.system(size: 46, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText(value: heroValue))
                    .opacity(heroOpacity)
                    .background {
                        AppearanceGlowPulse(color: colors.accent, trigger: glow)
                    }
                Text("amortisiert")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                // White on the prominent tint – the last trip, formatted like the app formats amounts.
                Text("+ " + AppearanceFormat.euro(22.8, digits: 2))   // a logged trip: always cents, like the quick log
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.onAccent)
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText())
                    .padding(.horizontal, Theme.Spacing.xs)
                    .padding(.vertical, 5)
                    .background(colors.prominentTint, in: .capsule)
            }
            // The route to the summit in the palette's gradient; the summit flag keeps its own colour.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceSecondary)
                    Capsule()
                        .fill(colors.routeGradient)
                        .frame(width: max(10, proxy.size.width * Self.demoFraction))
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(colors.accent, lineWidth: 3))
                        .offset(x: proxy.size.width * Self.demoFraction - 7)
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.summit)
                        .offset(x: proxy.size.width - 12, y: -12)
                }
            }
            .frame(height: 8)
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.m)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.tile, style: .continuous))
        .accessibilityHidden(true)
    }

    private func figure(_ value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.16), in: .circle)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.chip, style: .continuous))
        .accessibilityHidden(true)
    }

    /// The week in the chosen order: switching Montag / Sonntag slides Sunday from one end to the other.
    private func weekCard(_ colors: ThemeColorSet) -> some View {
        let maxTrips = Self.demoWeek.max() ?? 1
        let order = prefs.format.weekStart.mondayFirstOrder
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Diese Woche")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.Spacing.xs)
                Text("Details")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.accentText)
            }
            HStack(alignment: .bottom, spacing: Theme.Spacing.xs) {
            ForEach(order, id: \.self) { day in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(Self.demoWeek[day] > 0 ? AnyShapeStyle(colors.accent) : AnyShapeStyle(Theme.surfaceSecondary))
                        .frame(width: 12, height: 4 + 26 * Self.demoWeek[day] / maxTrips)
                    Text(AppearanceFormat.weekdayShort[day])
                        .font(.caption2.weight(day == order.first ? .bold : .regular))
                        .foregroundStyle(day == order.first ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity)
            }
            }
            .frame(height: 48, alignment: .bottom)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.tile, style: .continuous))
        .accessibilityHidden(true)
    }

    private func ctaRow(_ colors: ThemeColorSet) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Label("Fahrt erfassen", systemImage: "plus")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, 10)
                .background(colors.ctaGradient, in: .capsule)
            Spacer(minLength: 0)
            // A switch in the accent (drawn, not a control).
            Capsule()
                .fill(colors.accent)
                .frame(width: 46, height: 28)
                .overlay(alignment: .trailing) {
                    Circle().fill(.white).padding(3).shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                }
        }
        .accessibilityHidden(true)
    }

    // Light / dark preview switch (Liquid Glass – it is a control; the capsule glides, selection haptic built in).
    private var schemeToggle: some View {
        GlassSegmentedPicker(selection: $schemeSelection, options: [ColorScheme.light, ColorScheme.dark]) { option in
            Image(systemName: option == .light ? "sun.max.fill" : "moon.fill")
                .accessibilityLabel(option == .light ? "Vorschau hell" : "Vorschau dunkel")
        }
        .fixedSize()
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // MARK: Motion demo

    /// Shows the chosen Bewegung once: Voll counts the hero in, Ruhig cross-fades it, Aus sets it.
    private func replayHero() {
        let level = prefs.motion
        guard !MotionPolicy.isScreenshot else { return }
        if reduceMotion || level == .off {
            heroValue = Self.demoFraction
            heroOpacity = 1
            return
        }
        if level == .calm {
            heroOpacity = 0.15
            withAnimation(Motion.crossfade) { heroOpacity = 1 }
            return
        }
        heroValue = 0
        heroOpacity = 1
        withAnimation(Motion.countIn) { heroValue = Self.demoFraction }
    }

    private var accessibilitySummary: String {
        let palette = ThemeCatalog.palette(prefs.palette).name
        let mode = scheme == .dark ? "dunkel" : "hell"
        let week = prefs.format.weekStart == .monday ? "Woche ab Montag" : "Woche ab Sonntag"
        return "Vorschau \(palette), \(mode): Wert \(Self.valueText), "
            + "je Fahrt \(Self.perTripText), "
            + "CO₂ \(AppearanceFormat.co2(Self.demoCO2, prefs: prefs.format)), \(week)."
    }
}

/// One-shot bloom behind the hero after a palette change (no repeat, nothing left running).
struct AppearanceGlowPulse: View {
    var color: Color
    var trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if MotionPolicy.isStatic {
            Color.clear
        } else {
            // MARK: review-themes – Reduce Motion: the bloom only fades, it does not grow.
            let grows = !reduceMotion
            Capsule()
                .fill(color)
                .frame(width: 120, height: 60)
                .blur(radius: 24)
                .keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, value in
                    view
                        .opacity(value)
                        .scaleEffect(grows ? 0.7 + value * 0.5 : 1)
                } keyframes: { _ in
                    CubicKeyframe(0.75, duration: 0.18)
                    CubicKeyframe(0.0, duration: 0.9)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
