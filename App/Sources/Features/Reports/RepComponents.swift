import SwiftUI
import KlimaCore

// Small building blocks shared by the import flow and the annual report sheet.

/// "SCHRITT 2 VON 3" + title + explanation, with a three-segment route-gradient progress bar.
struct RepStepHeader: View {
    var step: Int
    var total: Int
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            RepStepProgress(step: step, total: total)
                .padding(.bottom, Theme.Spacing.xxs)
            Kicker(text: "Schritt \(step) von \(total)")
            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Segmented progress ("Datei · Spalten · Vorschau"): done segments filled with the route gradient.
struct RepStepProgress: View {
    var step: Int
    var total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index <= step ? AnyShapeStyle(Theme.routeGradient) : AnyShapeStyle(Theme.textTertiary.opacity(0.22)))
                    .frame(height: 5)
            }
        }
        .frame(maxWidth: 180)
        .animation(.spring(duration: 0.5), value: step)
        .accessibilityHidden(true)
    }
}

/// Feature line with a coloured icon tile (pick step).
struct RepFeatureRow: View {
    var symbol: String
    var tint: Color
    var title: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            SetIconTile(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Capsule badge with a text-safe tint ("geschätzt", "KlimaBilanz-Export erkannt").
struct RepBadge: View {
    var text: String
    var symbol: String? = nil
    var tint: Color

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.13), in: .capsule)
    }
}

/// Bottom action area above the home indicator (primary CTA + optional secondary action).
struct RepBottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            content
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.xs)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [Theme.sheetBackground.opacity(0), Theme.sheetBackground.opacity(0.92), Theme.sheetBackground],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// `.sensoryFeedback` that respects the "Haptisches Feedback" setting.
    func repHaptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T, enabled: Bool) -> some View {
        sensoryFeedback(trigger: trigger) { _, _ in enabled ? feedback : nil }
    }
}

/// German helpers for the module.
enum RepText {
    /// "1 Fahrt" / "12 Fahrten".
    static func trips(_ n: Int) -> String { n == 1 ? "1 Fahrt" : "\(Format.number(Double(n))) Fahrten" }
    static func rows(_ n: Int) -> String { n == 1 ? "1 Zeile" : "\(Format.number(Double(n))) Zeilen" }

    /// "09.10.2026" (always numeric, like the source file).
    static func numericDate(_ date: Date) -> String {
        let c = Calendar.vienna.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d.%02d.%04d", c.day ?? 1, c.month ?? 1, c.year ?? 2026)
    }

    /// "09.10." (table rows of the PDF).
    static func shortNumericDate(_ date: Date) -> String {
        let c = Calendar.vienna.dateComponents([.month, .day], from: date)
        return String(format: "%02d.%02d.", c.day ?? 1, c.month ?? 1)
    }

    /// "1. März 2026"
    static func longDate(_ date: Date) -> String {
        let c = Calendar.vienna.dateComponents([.year, .month, .day], from: date)
        return "\(c.day ?? 1). \(StatsNames.monthWide[max(0, min(11, (c.month ?? 1) - 1))]) \(c.year ?? 2026)"
    }

    static func fileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) Byte" }
        if bytes < 1_000_000 { return "\(Format.number(Double(bytes) / 1024)) KB" }
        return "\(Format.number(Double(bytes) / 1_000_000, decimals: 1)) MB"
    }
}
