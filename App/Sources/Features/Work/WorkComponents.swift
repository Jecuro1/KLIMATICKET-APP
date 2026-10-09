import SwiftUI
import KlimaCore

// Small building blocks shared by the "Öffis vs. Auto" and "Arbeit & Steuer" screens.

/// "Keine Steuerberatung – Angaben ohne Gewähr, Stand 9. Oktober 2026" – always visible on tax content.
struct WorkDisclaimerBanner: View {
    var body: some View {
        Label {
            Text(WorkFormat.disclaimer)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.summit)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.summit.opacity(0.10), in: .rect(cornerRadius: Theme.Radius.chip, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .strokeBorder(Theme.summit.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Decimal input that accepts Austrian *and* international notation ("1,65", "1.65", "1.100") and never turns
/// € 1,50 into € 150 (the classic bug of other trackers). Commits on every valid keystroke, reformats on blur.
struct WorkDecimalField: View {
    var title: String
    var symbol: String? = nil
    var tint: Color = Theme.glacier
    @Binding var value: Double
    var unit: String
    var fractionDigits: Int = 2
    var range: ClosedRange<Double>

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if let symbol {
                Label { Text(title) } icon: { SetIconTile(symbol: symbol, tint: tint) }
            } else {
                Text(title)
            }
            Spacer(minLength: Theme.Spacing.xs)
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .focused($isFocused)
                .frame(minWidth: 64, maxWidth: 104)
                .onChange(of: text) { _, newText in
                    guard isFocused, let parsed = CarInputParser.decimal(newText, in: range) else { return }
                    if parsed != value { value = parsed }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { text = formatted(value) }
                }
                .onChange(of: value) { _, newValue in
                    // Typing sets `value` from `text` (they agree); a change from outside (preset, reset) rewrites the text.
                    if !isFocused || CarInputParser.decimal(text, in: range) != newValue { text = formatted(newValue) }
                }
                .onAppear { text = formatted(value) }
                .accessibilityLabel(title)
                .accessibilityValue("\(formatted(value)) \(unit)")
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .toolbar {
            if isFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { isFocused = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        let digits = value == value.rounded() && fractionDigits > 0 && range.upperBound > 100 ? 0 : fractionDigits
        return Format.number(value, decimals: digits)
    }
}

/// Two-part capsule (e.g. employer vs. own share, business vs. private km) with direct labels below.
struct WorkSplitBar: View {
    struct Part: Identifiable {
        var id: String { label }
        var label: String
        var value: Double
        var detail: String
        var color: Color
    }

    var parts: [Part]
    var height: CGFloat = 14
    var grow: Double = 1

    var body: some View {
        let total = max(parts.reduce(0) { $0 + max(0, $1.value) }, 0.0001)
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            GeometryReader { geo in
                let spacing: CGFloat = 3
                let available = max(0, geo.size.width - spacing * CGFloat(max(0, parts.count - 1)))
                HStack(spacing: spacing) {
                    ForEach(parts) { part in
                        Capsule()
                            .fill(part.color)
                            .frame(width: max(part.value > 0 ? height : 0, available * CGFloat(max(0, part.value) / total * grow)))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: height)
            .accessibilityHidden(true)
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                ForEach(parts) { part in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle().fill(part.color).frame(width: 8, height: 8)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(part.label)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                            Text(part.detail)
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if part.id != parts.last?.id { Spacer(minLength: 0) }
                }
            }
        }
    }
}

/// Icon + title + detail + trailing value, used for explanations and assumptions ("So rechnen wir").
struct WorkFactRow: View {
    var symbol: String
    var tint: Color
    var title: String
    var value: String? = nil
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: Theme.Spacing.xs)
                    if let value {
                        Text(value)
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Short official sources as tappable links.
struct WorkSourceLinks: View {
    struct Source: Identifiable {
        var id: String { title }
        var title: String
        var url: String
    }

    var title: String = "Quellen"
    var sources: [Source]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Kicker(text: title)
            ForEach(sources) { source in
                if let url = URL(string: source.url) {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Text(source.title)
                                .font(.footnote.weight(.medium))
                                .multilineTextAlignment(.leading)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(Theme.accentText)
                    }
                    .accessibilityHint("Öffnet die Website")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static let tax: [Source] = [
        Source(title: "AK – Dienstreisen mit eigenem Öffi-Ticket", url: "https://www.arbeiterkammer.at/beratung/steuerundeinkommen/steuertipps/Dienstreise.html"),
        Source(title: "BMF – Pendlerförderung & Öffi-Ticket vom Arbeitgeber", url: "https://www.bmf.gv.at/themen/steuern/arbeitnehmerveranlagung/pendlerfoerderung-das-pendlerpauschale/informationen-zur-pendlerfoerderung.html"),
        Source(title: "WKO – Öffi-Ticket als Betriebsausgabe", url: "https://www.wko.at/sbg/news/wie-kann-man-kosten-fuer-ein-oeffi-ticket-als-betriebsausgabe"),
    ]

    static let car: [Source] = [
        Source(title: "oesterreich.gv.at – Kilometergeld", url: "https://www.oesterreich.gv.at/themen/steuern_und_finanzen/unterstuetzungen_beihilfen_und_foerderungen/pendlerpauschale_und_kilometergeld/Seite.350300.html"),
        Source(title: "ASFINAG – Vignette", url: "https://www.asfinag.at/maut-vignette/vignette/"),
        Source(title: "Umweltbundesamt – Emissionsfaktoren", url: "https://www.umweltbundesamt.at/themen/verkehr/daten-zum-verkehr/emissionen"),
    ]
}

/// Big light numeral with a small currency sign ("€ 980").
struct WorkEuroNumeral: View {
    var value: Double
    var size: CGFloat
    var color: Color = Theme.textPrimary
    /// The screen's hero value: counts in once on its first appearance (docs/MOTION.md §5), then rolls like the others.
    var countsIn = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("€")
                .font(.system(size: size * 0.5, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Group {
                if countsIn {
                    CountUpText(value: value) { Format.number($0) }
                } else {
                    Text(Format.number(value))
                        .numericValue(value)
                }
            }
            .font(.system(size: size, weight: .light, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Format.euro(value, decimals: 0))
    }
}
