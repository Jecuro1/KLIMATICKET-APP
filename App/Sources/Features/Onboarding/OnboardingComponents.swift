import SwiftUI
import KlimaCore

// Building blocks shared by the onboarding steps (module prefix "Onb").

// MARK: - Page scaffold

/// Scrollable step page: eyebrow + large title + subtitle, followed by the step's cards.
struct OnbPage<Content: View>: View {
    var kicker: String?
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                OnbPageHeader(kicker: kicker, title: title, subtitle: subtitle)
                    .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                content
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }
}

struct OnbPageHeader: View {
    var kicker: String?
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let kicker {
                Kicker(text: kicker)
            }
            Text(title)
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small uppercase label above a group of cards.
struct OnbSectionLabel: View {
    var title: String

    var body: some View {
        Kicker(text: title)
            .padding(.leading, Theme.Spacing.xxs)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Form building blocks

/// Rounded square with a white SF Symbol on a soft gradient (settings-style icon tile).
struct OnbIconTile: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Calm frosted form group (rows separated by `OnbDivider`).
struct OnbFormGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedCard(cornerRadius: Theme.Radius.formGroup)
    }
}

/// Labelled input row: icon tile · caption label · control (text field etc.).
struct OnbFieldRow<Control: View>: View {
    var label: String
    var symbol: String
    var tint: Color
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            OnbIconTile(symbol: symbol, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                control
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.vertical, Theme.Spacing.s)
    }
}

/// Hairline between rows of a form group, inset past the icon tile.
struct OnbDivider: View {
    var inset: CGFloat = 44

    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

/// Label for toggles: icon tile, title and a one-line explanation.
struct OnbToggleLabel: View {
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            OnbIconTile(symbol: symbol, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Small capsule badge ("Offizieller Preis").
struct OnbBadge: View {
    var title: String
    var symbol: String
    var tint: Color
    var textColor: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(textColor)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.14), in: .capsule)
    }
}

/// Subtle press feedback for card-like buttons.
struct OnbPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

// MARK: - Motion

/// Staggered entrance (fade + rise + optional scale). Crossfade only with Reduce Motion.
struct OnbEntrance: ViewModifier {
    var isVisible: Bool
    var delay: Double
    var offset: CGFloat
    var scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible || reduceMotion ? 1 : scale)
            .offset(y: isVisible || reduceMotion ? 0 : offset)
            .animation(reduceMotion ? .easeOut(duration: 0.3) : .spring(duration: 0.6, bounce: 0.22).delay(delay), value: isVisible)
    }
}

extension View {
    func onbEntrance(_ isVisible: Bool, delay: Double = 0, offset: CGFloat = 14, scale: CGFloat = 1) -> some View {
        modifier(OnbEntrance(isVisible: isVisible, delay: delay, offset: offset, scale: scale))
    }
}

/// Gentle ±amplitude hover (floating glass chips). Static when inactive.
struct OnbFloating: ViewModifier {
    var amplitude: CGFloat
    var duration: Double
    var isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.phaseAnimator([false, true]) { view, isUp in
                view.offset(y: isUp ? -amplitude : amplitude)
            } animation: { _ in
                .easeInOut(duration: duration)
            }
        } else {
            content
        }
    }
}

// MARK: - Brand

// MARK: review-icons – the real home-screen icon ("Alpine Glass" or the App-Symbol the user picked, light/dark like the
// home screen) instead of a vector drawing of the old artwork, so onboarding, notification preview and home screen match.
/// The app icon as onboarding's brand mark.
struct OnbBrandMark: View {
    var size: CGFloat = 56

    var body: some View {
        AppIconImage(choice: AppIconStore.shared.current, size: size)
            .shadow(color: Theme.dusk.opacity(0.45), radius: size * 0.28, y: size * 0.12)
            .accessibilityHidden(true)
    }
}

/// Polygon / polyline in unit coordinates (0…1) of the drawing rect.
struct OnbPolygon: Shape {
    var points: [CGPoint]
    var closed: Bool = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }
        if closed { path.closeSubpath() }
        return path
    }
}

/// Horizontal line through the vertical centre (dashed rails).
struct OnbHorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Text helpers

/// Parses Austrian price input ("1.400", "1.400,50", "24,9", "€ 24.90").
enum OnbPriceParser {
    static func parse(_ text: String) -> Double? {
        var s = text
        for junk in ["€", " ", "\u{00A0}", "\u{202F}", "EUR", "eur"] {
            s = s.replacingOccurrences(of: junk, with: "")
        }
        guard !s.isEmpty else { return nil }
        if s.contains(",") {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if let dot = s.lastIndex(of: "."), s[s.index(after: dot)...].count == 3 {
            // "1.400" – dot as thousands separator.
            s = s.replacingOccurrences(of: ".", with: "")
        }
        guard let value = Double(s), value.isFinite, value >= 0, value < 100_000 else { return nil }
        return value
    }

    /// Text for an existing value ("1.400", "1.400,50").
    static func text(for value: Double?) -> String {
        guard let value else { return "" }
        return Format.number(value, decimals: value == value.rounded() ? 0 : 2)
    }
}

/// Short, human labels for catalog products (titles, eligibility, symbols).
enum OnbProductCopy {
    static func title(for product: TicketProduct) -> String {
        guard product.family == .oe else { return product.name }
        let stripped = product.name.replacingOccurrences(of: "KlimaTicket Ö ", with: "")
        return stripped.isEmpty ? product.name : stripped
    }

    static func detail(for product: TicketProduct) -> String {
        if product.family == .oe {
            switch product.id {
            case "oe-klassik": return "26 bis 64 Jahre"
            case "oe-jugend": return "Unter 26 Jahre"
            case "oe-senior": return "Ab 65 Jahren"
            case "oe-spezial": return "Mit Behindertenpass (GdB ab 70 %)"
            case "oe-familie-klassik": return "Klassik + bis zu 4 Kinder (6–14 Jahre)"
            case "oe-familie-ermaessigt": return "Jugend, Senior, Spezial + bis zu 4 Kinder"
            default: break
            }
        }
        if product.isLocal == true, !product.coverage.isEmpty {
            return firstClause(of: product.coverage)
        }
        let eligibility = firstClause(of: product.eligibility)
        if (eligibility.isEmpty || ["Alle Personen", "Erwachsene"].contains(eligibility)), !product.coverage.isEmpty {
            return firstClause(of: product.coverage)
        }
        return eligibility
    }

    /// First meaningful clause of a catalog text: drops a short "Senior: " / "MAXIMO: " prefix, cuts at ";", ": " or " (".
    static func firstClause(of text: String, limit: Int = 70) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let prefix = s.range(of: ": "), s.distance(from: s.startIndex, to: prefix.lowerBound) < 14 {
            s = String(s[prefix.upperBound...])
        }
        for separator in [";", ": ", " ("] {
            if let range = s.range(of: separator) { s = String(s[..<range.lowerBound]) }
        }
        s = firstSentence(of: s).trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".") { s.removeLast() }
        if let first = s.first, first.isLowercase {
            s = first.uppercased() + s.dropFirst()
        }
        if s.count > limit {
            s = String(s.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return s
    }

    /// Cuts at the first real sentence end (". " + capital), ignoring abbreviations ("St. Anton", "inkl. Kernzone")
    /// and ordinals ("26. Geburtstag", "1. Jänner").
    static func firstSentence(of s: String) -> String {
        let abbreviations: Set<String> = ["inkl", "exkl", "bzw", "ca", "St", "Nr", "max", "min", "usw", "etc", "vgl", "z", "B", "u", "a", "Hbf", "Bf"]
        let ordinalNouns: Set<String> = ["Geburtstag", "Lebensjahr", "Jänner", "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli",
                                         "August", "September", "Oktober", "November", "Dezember", "Klasse"]
        var searchStart = s.startIndex
        while let range = s.range(of: ". ", range: searchStart..<s.endIndex) {
            let before = s[..<range.lowerBound]
            let lastWord = before.split(whereSeparator: { $0 == " " || $0 == "(" }).last.map(String.init) ?? ""
            let nextWord = (s[range.upperBound...].split(separator: " ").first.map(String.init) ?? "")
                .trimmingCharacters(in: .punctuationCharacters)
            let startsUppercase = nextWord.first?.isUppercase ?? false
            let isNumber = !lastWord.isEmpty && lastWord.allSatisfy { $0.isNumber }
            let isBoundary = startsUppercase && !abbreviations.contains(lastWord)
                && (isNumber ? !ordinalNouns.contains(nextWord) : lastWord.count >= 3)
            if isBoundary { return String(before) }
            searchStart = range.upperBound
        }
        return s
    }

    static func symbol(for variant: TicketVariant) -> String {
        switch variant {
        case .klassik: "person.fill"
        case .jugend: "graduationcap.fill"
        case .senior: "figure.walk"
        case .spezial: "figure.roll"
        case .familie: "figure.2.and.child.holdinghands"
        }
    }

    static func tint(for variant: TicketVariant) -> Color {
        switch variant {
        case .klassik: Theme.glacier
        case .jugend: Theme.dusk
        case .senior: Theme.dawn
        case .spezial: Theme.pine
        case .familie: Theme.alpenglow
        }
    }
}
