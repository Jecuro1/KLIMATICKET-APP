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
        .motionAnimation(Motion.smooth, value: step)
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
/// Over a SwiftUI scroll view it sits in `.safeAreaBar` (the system scroll-edge blur does the separation, `fades: false`);
/// over UIKit content (the PDF preview) it brings its own fade into the sheet background.
struct RepBottomBar<Content: View>: View {
    var fades: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            content
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.xxs)
        .frame(maxWidth: .infinity)
        .background {
            if fades {
                LinearGradient(stops: [.init(color: Theme.sheetBackground.opacity(0), location: 0),
                                       .init(color: Theme.sheetBackground.opacity(0.94), location: 0.32),
                                       .init(color: Theme.sheetBackground, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .padding(.top, -Theme.Spacing.l)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Secondary action next to the primary CTA: a Liquid Glass capsule of the same height ("Rückgängig").
struct RepGlassCapsuleButton: View {
    var title: String
    var symbol: String
    var tint: Color = Theme.accentText
    var role: ButtonRole? = nil
    var action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.l)
                .frame(minHeight: 56)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .fixedSize(horizontal: true, vertical: false)
    }
}

extension View {
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
