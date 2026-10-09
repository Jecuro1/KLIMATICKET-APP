import SwiftUI
import WidgetKit
import AppIntents
import KlimaCore

// MARK: - Typography

/// Small uppercase eyebrow with a leading glyph ("⛰ AMORTISIERT").
struct WidEyebrow: View {
    var text: String
    var symbol: String
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .widgetAccentable()
            Text(text.uppercased(with: WidFormat.locale))
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.widSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The signature thin "73 %" numeral (Apple-Weather style), sturdier with Bold Text.
struct WidPercentNumeral: View {
    var fraction: Double
    var size: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.legibilityWeight) private var legibilityWeight

    private var weight: Font.Weight {
        if legibilityWeight == .bold { return .regular }
        return colorScheme == .dark ? .thin : .light
    }

    var body: some View {
        let percent = WidFormat.percentValue(fraction)
        HStack(alignment: .top, spacing: 1) {
            // Counts up to the new value when a quick log or the app updates the widget; dimmed by the system while a
            // tap's update is pending (invalidatable).
            Text(verbatim: String(percent))
                .font(.system(size: size, weight: weight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(.numericText(value: Double(percent)))
                .invalidatableContent()
            Text(verbatim: "%")
                .font(.system(size: size * 0.4, weight: .light, design: .rounded))
                .foregroundStyle(.widSecondary)
                .padding(.top, size * 0.14)
        }
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amortisiert")
        .accessibilityValue(WidFormat.percent(fraction))
    }
}

/// "noch € 354" / "+ € 412 im Plus" – amounts emphasised, never colour-only.
struct WidVerdictLine: View {
    var snapshot: WidgetSnapshot
    var size: CGFloat = 13
    /// When paid off: "+ € 412 im Plus" (true) or the total value (false, if a forecast block already shows the profit).
    var showsProfit: Bool = true

    var body: some View {
        line
            .font(.system(size: size, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.widSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .contentTransition(.numericText(value: snapshot.totalValue))
            .invalidatableContent()
    }

    private var line: Text {
        if WidInsight.isPaidOff(snapshot) && !showsProfit {
            let amount = Text(verbatim: WidFormat.euroWhole(WidFigures.total(snapshot)))
                .fontWeight(.bold)
                .foregroundStyle(Theme.textPrimary)
            return Text("\(amount) Wert gesamt")
        }
        if WidInsight.isPaidOff(snapshot) {
            let amount = Text(verbatim: "+ " + WidFormat.euroWhole(WidFigures.profit(snapshot)))
                .fontWeight(.bold)
                .foregroundStyle(Theme.positiveText)
            return Text("\(amount) im Plus")
        }
        let amount = Text(verbatim: WidFormat.euroWhole(WidFigures.remaining(snapshot)))
            .fontWeight(.bold)
            .foregroundStyle(Theme.textPrimary)
        return Text("noch \(amount)")
    }
}

/// Right-aligned forecast block ("⚑ BREAK-EVEN · 14. Dez. · in 66 Tagen").
struct WidForecastBlock: View {
    var snapshot: WidgetSnapshot
    var valueSize: CGFloat = 21

    @Environment(\.widNow) private var entryDate

    var body: some View {
        let info = WidInsight.forecast(snapshot, now: entryDate ?? Date())
        VStack(alignment: .trailing, spacing: 1) {
            WidEyebrow(text: info.kicker, symbol: info.symbol, tint: info.isPositive ? Theme.positive : Theme.dawn)
            Text(info.value)
                .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(info.isPositive ? Theme.positiveText : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .invalidatableContent()
            Text(info.caption)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.widSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .multilineTextAlignment(.trailing)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Progress

/// Thin capsule progress bar; the fill is the accent group in tinted / clear styles.
struct WidLinearBar: View {
    var progress: Double
    var fill: AnyShapeStyle = AnyShapeStyle(.primary)
    var track: AnyShapeStyle = AnyShapeStyle(.tertiary)

    var body: some View {
        GeometryReader { geo in
            let clamped = CGFloat(min(max(progress.isFinite ? progress : 0, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: max(geo.size.height, geo.size.width * clamped))
                    .widgetAccentable()
            }
        }
        .accessibilityHidden(true)
    }
}

/// Tiny progress ring + "73 %" for headers.
struct WidMiniRing: View {
    var fraction: Double

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Theme.textTertiary, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(fraction, 0.02), 1)))
                    .stroke(renderingMode == .fullColor ? AnyShapeStyle(Theme.routeGradient) : AnyShapeStyle(.primary),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
            .frame(width: 14, height: 14)
            Text(WidFormat.percent(fraction))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(value: fraction))
                .invalidatableContent()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amortisiert")
        .accessibilityValue(WidFormat.percent(fraction))
    }
}

/// Mini amortisation footer for the quick-log widget ("▬▬▬▬░░ 73 %").
struct WidProgressFooter: View {
    var snapshot: WidgetSnapshot

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widNow) private var entryDate

    var body: some View {
        HStack(spacing: 7) {
            WidLinearBar(progress: snapshot.amortizedFraction,
                         fill: renderingMode == .fullColor ? AnyShapeStyle(Theme.routeGradient) : AnyShapeStyle(.primary),
                         track: AnyShapeStyle(Theme.textTertiary.opacity(0.45)))
                .frame(height: 5)
            Text(WidFormat.percent(snapshot.amortizedFraction))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .fixedSize()
                .contentTransition(.numericText(value: snapshot.amortizedFraction))
                .invalidatableContent()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amortisiert")
        .accessibilityValue(WidInsight.spokenSummary(snapshot, now: entryDate ?? Date()))
    }
}

// MARK: - Favourites

/// Round transport badge in the mode's landscape colour (always paired with the route title).
struct WidModeBadge: View {
    var symbol: String
    var size: CGFloat = 26

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .fullColor {
            let color = WidMode.color(forSymbol: symbol)
            glyph
                .foregroundStyle(Color.white)
                .background(
                    Circle().fill(LinearGradient(colors: [color, color.mix(with: .black, by: 0.22)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .accessibilityHidden(true)
        } else {
            // Tinted / clear: the system paints the whole accent group in one colour, so a white glyph on an accented
            // disc would vanish. The glyph carries the accent, the disc stays a faint neutral wash.
            glyph
                .widgetAccentable()
                .background(Circle().fill(Color.white.opacity(0.16)))
                .accessibilityHidden(true)
        }
    }

    private var glyph: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .frame(width: size, height: size)
    }
}

/// One-tap favourite: logs the route via `LogFavoriteTripIntent` (interactive widgets, iOS 17+).
struct WidFavoriteButton: View {
    var favorite: WidgetSnapshot.Favorite
    /// False in the in-app gallery (preview only – nothing gets logged).
    var isInteractive: Bool = true
    /// Logged a moment ago (`WidgetSnapshot.justLogged`): "✓ Gerade erfasst" instead of "+ € 22,80".
    var justLogged: Bool = false

    @Environment(\.widPreviewAction) private var previewAction

    var body: some View {
        if isInteractive {
            Button(intent: LogFavoriteTripIntent(favoriteID: favorite.id, title: favorite.title)) {
                WidFavoriteLabel(favorite: favorite, justLogged: justLogged)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(spokenTitle)
            .accessibilityValue(spokenValue)
        } else if let previewAction {
            // The gallery's "Probier's aus": the preview reacts like the widget, nothing is saved.
            Button { previewAction.logFavorite(favorite) } label: {
                WidFavoriteLabel(favorite: favorite, justLogged: justLogged)
            }
            .buttonStyle(WidPreviewPressStyle())
            .accessibilityLabel(spokenTitle)
            .accessibilityValue(spokenValue)
            .accessibilityHint("Vorschau – es wird nichts gespeichert")
        } else {
            WidFavoriteLabel(favorite: favorite, justLogged: justLogged)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenTitle)
                .accessibilityValue(spokenValue)
        }
    }

    private var spokenTitle: String { "\(favorite.title) erfassen" }
    private var spokenValue: String {
        justLogged ? "Gerade erfasst, \(WidFormat.euroPrecise(favorite.value))" : WidFormat.euroPrecise(favorite.value)
    }
}

private struct WidFavoriteLabel: View {
    let favorite: WidgetSnapshot.Favorite
    var justLogged: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        HStack(spacing: 8) {
            WidModeBadge(symbol: favorite.modeSymbol, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(favorite.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Group {
                    if justLogged {
                        Text("Gerade erfasst")
                            .foregroundStyle(renderingMode == .fullColor ? AnyShapeStyle(Theme.positiveText) : AnyShapeStyle(.primary))
                    } else {
                        Text(WidFormat.euroPrecise(favorite.value))
                            .foregroundStyle(.widSecondary)
                    }
                }
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .transition(.opacity.combined(with: .offset(y: 4)))
            }
            .layoutPriority(1)
            Spacer(minLength: 2)
            plus
        }
        .padding(.leading, 7)
        .padding(.trailing, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(fillColor))
        .overlay(shape.strokeBorder(rimColor, lineWidth: 0.8))
        .contentShape(shape)
    }

    /// "+" → "✓" (symbol replace) while the log is confirmed; the disc turns pine.
    @ViewBuilder
    private var plus: some View {
        let glyph = Image(systemName: justLogged ? "checkmark" : "plus")
            .font(.system(size: 11, weight: .bold))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 22, height: 22)
        if renderingMode == .fullColor {
            glyph
                .foregroundStyle(Theme.onAccent)
                .background(Circle().fill(justLogged ? AnyShapeStyle(Theme.positive.gradient) : AnyShapeStyle(Theme.ctaGradient)))
        } else {
            glyph
                .widgetAccentable()
                .background(Circle().fill(Color.white.opacity(0.18)))
        }
    }

    /// Dark: a night-glass capsule that sits *into* the sky (as in the widget mockup) – a white wash would brighten
    /// the alpenglow behind the right-hand buttons and pull the price below 4.5:1.
    private var fillColor: Color {
        guard renderingMode == .fullColor else { return Color.white.opacity(0.12) }
        return colorScheme == .dark ? Theme.background.opacity(0.3) : Color.white.opacity(0.62)
    }

    private var rimColor: Color {
        guard renderingMode == .fullColor else { return Color.white.opacity(0.2) }
        return colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.85)
    }
}

// MARK: - In-app previews

/// In-app previews only (widget gallery): what a tap on a preview's favourite does – the preview logs it for show,
/// nothing is saved. Nil in the widget extension, where the buttons run `LogFavoriteTripIntent`.
struct WidPreviewAction {
    var logFavorite: @MainActor (WidgetSnapshot.Favorite) -> Void
}

extension EnvironmentValues {
    @Entry var widPreviewAction: WidPreviewAction? = nil
}

/// Finger-down feedback of the gallery's preview buttons (`Motion.press` / `Motion.release`; Reduce Motion: a dim).
struct WidPreviewPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WidPreviewPressLabel(configuration: configuration)
    }
}

private struct WidPreviewPressLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? Motion.Distance.pressScale : 1)
            .opacity(pressed ? 0.86 : 1)
            .animation(pressed ? Motion.press : Motion.release, value: pressed)
    }
}

// MARK: - Empty state

/// Shown when the app has not written a snapshot yet (no ticket).
struct WidEmptyView: View {
    var family: WidgetFamily
    var margins: EdgeInsets = WidLayout.defaultMargins

    static let message = "Öffne KlimaBilanz, um dein Ticket anzulegen."

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                Circle().stroke(.tertiary, lineWidth: 4)
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .widgetAccentable()
            }
            .padding(5)
            .accessibilityLabel(Self.message)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("KlimaBilanz", systemImage: "mountain.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .widgetAccentable()
                Text("Ticket in der App anlegen")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Label("KlimaBilanz öffnen", systemImage: "mountain.2.fill")
        default:
            systemEmpty
        }
    }

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isSmall: Bool { family == .systemSmall }

    /// "App öffnen": white on the CTA gradient in full colour; tinted / clear paint the accent group in one colour,
    /// so there the label carries the accent on a neutral capsule (white on an accented capsule would vanish).
    @ViewBuilder
    private var openAppPill: some View {
        let label = Text("App öffnen")
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        if renderingMode == .fullColor {
            label
                .foregroundStyle(Theme.onAccent)
                .background(Capsule().fill(Theme.ctaGradient))
        } else {
            label
                .widgetAccentable()
                .background(Capsule().fill(Color.white.opacity(0.18)))
        }
    }
    private var messageWidth: CGFloat { isSmall ? CGFloat.infinity : 220 }

    private var systemEmpty: some View {
        ZStack(alignment: .topLeading) {
            WidSummitArt(model: .decorative, top: isSmall ? 0.6 : 0.5, bottom: 1, scale: isSmall ? 0.85 : 1, showsRoute: false)
            VStack(alignment: .leading, spacing: isSmall ? 6 : 8) {
                WidEyebrow(text: "KlimaBilanz", symbol: "mountain.2.fill")
                Text("Noch kein Ticket")
                    .font(.system(size: isSmall ? 16 : 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(Self.message)
                    .font(.system(size: isSmall ? 12 : 13.5))
                    .foregroundStyle(.widSecondary)
                    .lineLimit(isSmall ? 3 : 2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: messageWidth, alignment: .leading)
                if !isSmall {
                    openAppPill
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(margins)
        }
        .accessibilityElement(children: .combine)
    }
}
