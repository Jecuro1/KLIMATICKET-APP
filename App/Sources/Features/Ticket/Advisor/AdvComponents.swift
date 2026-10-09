import SwiftUI
import KlimaCore

// MARK: - Layout

/// Spacing rhythm of the Ratgeber (DESIGN.md §3: cards 12 apart, sections 24, card padding 20).
enum AdvStyle {
    static let cardPadding: CGFloat = Theme.Spacing.l
    static let cardSpacing: CGFloat = Theme.Spacing.s
    static let sectionSpacing: CGFloat = Theme.Spacing.l + Theme.Spacing.xxs
    static let blockSpacing: CGFloat = Theme.Spacing.m
    /// Section titles on the 20 pt text margin while cards use the 16 pt gutter.
    static let headerInset: CGFloat = Theme.Spacing.screen - Theme.Spacing.cardGutter
}

// MARK: - Card header

/// Eyebrow + verdict headline + optional ⓘ (rules sheet) at the top of every Ratgeber card.
struct AdvCardHeader: View {
    var kicker: String
    var title: String
    var tone: AdvTone? = nil
    var info: AdvInfo? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Kicker(text: kicker)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Neutral verdicts carry no symbol – an "i" here would compete with the ⓘ rules button.
                    if let tone, tone != .neutral {
                        Image(systemName: tone.symbol)
                            .font(.headline)
                            .foregroundStyle(tone.textColor)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let info {
                AdvInfoButton(info: info)
            }
        }
    }
}

// MARK: - Rules sheet

/// Rule explanation shown behind ⓘ: paragraphs plus the source.
struct AdvInfo: Identifiable, Hashable {
    var title: String
    var paragraphs: [String]
    var source: String
    var id: String { title }
}

struct AdvInfoButton: View {
    var info: AdvInfo
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, -Theme.Spacing.s)
        .padding(.trailing, -Theme.Spacing.s)
        .accessibilityLabel("So rechnen wir: \(info.title)")
        .sheet(isPresented: $isPresented) {
            AdvInfoSheet(info: info)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct AdvInfoSheet: View {
    var info: AdvInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ForEach(info.paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Label {
                        Text(info.source)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, Theme.Spacing.xs)
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.sheetBackground)
            .navigationTitle(info.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Figures

/// Big light numeral with a caption next to / below it ("€ 349,98 · zurück, wenn du bis 31. Okt. kündigst").
struct AdvFigure: View {
    var value: String
    var caption: String
    var color: Color = Theme.textPrimary

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: size, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(.numericText())
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Small capsule ("Am günstigsten", "Prognose").
struct AdvBadge: View {
    var text: String
    var symbol: String? = nil
    var tone: AdvTone

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.caption2.weight(.bold))
            }
            Text(text)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(tone.textColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tone.fill, in: .capsule)
        .fixedSize()
    }
}

// MARK: - Rows

/// "Label ……… Wert" with an optional explanation below; stacks when the line gets too long (Dynamic Type).
struct AdvFactRow: View {
    var label: String
    var value: String
    var detail: String? = nil
    var valueColor: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    labelText
                    Spacer(minLength: Theme.Spacing.s)
                    valueText
                }
                VStack(alignment: .leading, spacing: 2) {
                    labelText
                    valueText
                }
            }
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.Spacing.s - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label)
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(valueColor)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A group of fact rows separated by hairlines.
struct AdvFactList: View {
    var rows: [AdvFact]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { TktHairline() }
                AdvFactRow(label: row.label, value: row.value, detail: row.detail, valueColor: row.valueColor)
            }
        }
    }
}

struct AdvFact: Identifiable {
    var label: String
    var value: String
    var detail: String? = nil
    var valueColor: Color = Theme.textPrimary
    var id: String { label }
}

/// Labelled horizontal bar ("Erstattung · € 350") – value relative to `maxValue`.
struct AdvCompareBar: View {
    var label: String
    var symbol: String
    var value: Double
    var maxValue: Double
    var color: Color
    var valueText: String
    var badge: AdvBadge? = nil
    /// Footnote below the bar (what the amount includes).
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let badge { badge }
                Spacer(minLength: Theme.Spacing.xs)
                Text(valueText)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            ProgressRail(progress: maxValue > 0 ? value / maxValue : 0, height: 8, fill: AnyShapeStyle(color))
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(detail.map { "\(valueText), \($0)" } ?? valueText)
    }
}

/// Footnote with a leading symbol (rules, assumptions, how-to).
struct AdvNote: View {
    var symbol: String
    var text: String

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Theme.textSecondary)
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Inset tinted panel inside a card (status line, how-to, deadlines).
struct AdvPanel<Content: View>: View {
    var tint: Color = Theme.surfaceSecondary
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.Spacing.m - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: .rect(cornerRadius: Theme.Radius.chip + 2, style: .continuous))
    }
}

// MARK: - Entrance

/// Short staggered fade/rise (instant with Reduce Motion and in screenshot mode).
struct AdvEntrance: ViewModifier {
    var index: Int
    @State private var shown = LaunchMode.isScreenshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.25)) { shown = true }
                } else {
                    withAnimation(.spring(duration: 0.6, bounce: 0.14).delay(0.06 * Double(min(index, 5)))) { shown = true }
                }
            }
    }
}

extension View {
    func advEntrance(_ index: Int) -> some View { modifier(AdvEntrance(index: index)) }
}
