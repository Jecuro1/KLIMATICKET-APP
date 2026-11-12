import SwiftUI
import KlimaCore

// The printed pages of "Dein KlimaTicket-Jahr" (A4 portrait, 595 × 842 pt, always the light theme).
// Only plain SwiftUI drawing (shapes, gradients, text, Swift Charts) – no materials or glass, so ImageRenderer
// produces crisp vector PDF pages.

enum RepPrint {
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    static let margin: CGFloat = 44
    static let top: CGFloat = 40
    static let bottom: CGFloat = 26
    static let footerHeight: CGFloat = 24

    /// Soft panel fill on white paper.
    static let panel = Color(hex: "#F2F5F9")
    static let panelStroke = Color(hex: "#E2E8F0")
    static let zebra = Color(hex: "#F8FAFC")

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular, rounded: Bool = false) -> Font {
        .system(size: size, weight: weight, design: rounded ? .rounded : .default)
    }
}

/// Uppercase print eyebrow.
struct RepPrintKicker: View {
    var text: String
    var color: Color = Theme.textSecondary

    var body: some View {
        Text(text.uppercased(with: Format.locale))
            .font(RepPrint.font(7.5, .semibold))
            .tracking(1.1)
            .foregroundStyle(color)
    }
}

/// White A4 page with margins and the footer "Erstellt mit KlimaBilanz · keine offizielle Auswertung · Seite x von y".
struct RepPrintPage<Content: View, Backdrop: View>: View {
    var number: Int
    var count: Int
    @ViewBuilder var backdrop: Backdrop
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            RepPrintFooter(number: number, count: count)
                .frame(height: RepPrint.footerHeight)
        }
        .padding(.horizontal, RepPrint.margin)
        .padding(.top, RepPrint.top)
        .padding(.bottom, RepPrint.bottom)
        .frame(width: RepPrint.pageSize.width, height: RepPrint.pageSize.height)
        .background(alignment: .top) { backdrop }
        .background(Color.white)
        .clipped()
        .environment(\.colorScheme, .light)
        .environment(\.locale, Format.locale)
        .environment(\.dynamicTypeSize, .large)
    }
}

extension RepPrintPage where Backdrop == EmptyView {
    init(number: Int, count: Int, @ViewBuilder content: () -> Content) {
        self.number = number
        self.count = count
        self.backdrop = EmptyView()
        self.content = content()
    }
}

struct RepPrintFooter: View {
    var number: Int
    var count: Int

    var body: some View {
        VStack(spacing: 6) {
            Rectangle().fill(RepPrint.panelStroke).frame(height: 0.5)
            HStack(spacing: 6) {
                RepPrintLogo(size: 11)
                Text("Erstellt mit KlimaBilanz · keine offizielle Auswertung")
                    .font(RepPrint.font(7))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                Text("Seite \(number) von \(count)")
                    .font(RepPrint.font(7, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

/// Brand tile (gradient square with the mountain glyph).
struct RepPrintLogo: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "mountain.2.fill")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.ctaGradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Section title on a print page.
struct RepPrintSectionTitle: View {
    var kicker: String
    var title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            RepPrintKicker(text: kicker, color: Theme.accentText)
            Text(title)
                .font(RepPrint.font(21, .bold, rounded: true))
                .foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(RepPrint.font(9.5))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rounded light panel with an eyebrow.
struct RepPrintPanel<Content: View>: View {
    var title: String?
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { RepPrintKicker(text: title) }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RepPrint.panel, in: .rect(cornerRadius: 14, style: .continuous))
    }
}
