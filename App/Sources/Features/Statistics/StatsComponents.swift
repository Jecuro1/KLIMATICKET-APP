import SwiftUI
import KlimaCore

// Small building blocks shared by the statistics cards.

/// Eyebrow + headline used at the top of every statistics card.
struct StatsCardHeader<Trailing: View>: View {
    var kicker: String
    var title: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Kicker(text: kicker)
                if let title {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension StatsCardHeader where Trailing == EmptyView {
    init(kicker: String, title: String? = nil) {
        self.kicker = kicker
        self.title = title
        self.trailing = EmptyView()
    }
}

/// ⓘ button that opens a compact popover with an explanation (Copy.*).
struct StatsInfoButton: View {
    var title: String
    var text: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Erklärung: \(title)")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.m)
            .frame(width: 300, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// Small capsule badge ("Dein Ticket", "Am günstigsten").
struct StatsBadge: View {
    var text: String
    var symbol: String? = nil
    var foreground: Color
    var fill: Color

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.caption2.weight(.bold))
            }
            Text(text)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(fill, in: .capsule)
    }
}

/// Legend entry: short line sample (solid or dashed) + label.
struct StatsLegendItem: View {
    var label: String
    var style: AnyShapeStyle
    var dashed: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            StatsLegendLine()
                .stroke(style, style: StrokeStyle(lineWidth: dashed ? 2 : 3, lineCap: .round, dash: dashed ? [2, 4] : []))
                .frame(width: 18, height: 3)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .accessibilityHidden(true)
    }
}

/// Horizontal line through the middle of its frame.
struct StatsLegendLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 1, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.midY))
        return p
    }
}

/// Short staggered fade/rise when a card first appears (instant with Reduce Motion and in screenshot mode).
struct StatsEntrance: ViewModifier {
    var index: Int

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .onAppear {
                guard !shown else { return }
                if reduceMotion || LaunchMode.isScreenshot {
                    shown = true
                } else {
                    withAnimation(.spring(duration: 0.6, bounce: 0.12).delay(Double(min(index, 5)) * 0.06)) { shown = true }
                }
            }
    }
}

extension View {
    func statsEntrance(_ index: Int) -> some View { modifier(StatsEntrance(index: index)) }
}
