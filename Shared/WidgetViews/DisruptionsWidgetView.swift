import SwiftUI
import WidgetKit
import KlimaCore

/// "Störungen auf meinen Linien": disruptions that name a line the user rides (the lines of the favourite routes). A
/// quiet "Keine Störung" is a state of its own, with the time of the last check. Disruptions have no place, so the widget
/// names the lines, not a location.
struct DisruptionsWidgetView: View {
    var state: WidgetLiveState
    var items: [WidgetDisruption]
    var followedLines: [String]
    var family: WidgetFamily
    var margins: EdgeInsets = WidLayout.defaultMargins

    var body: some View {
        if state == .off || state == .empty {
            WidLiveEmpty(status: state, family: family)
        } else if followedLines.isEmpty {
            WidLiveEmpty(status: state, family: family,
                         message: ("Noch keine Linien", "Lieblingsfahrten erfassen, dann folgen die Linien"))
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            small
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            Text(verbatim: inlineText)
                .lineLimit(1)
        default:
            medium
        }
    }

    private var headline: String {
        items.isEmpty ? "Keine Störung" : (items.count == 1 ? "1 Störung" : "\(items.count) Störungen")
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidEyebrow(text: "Störungen", symbol: items.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                       tint: items.isEmpty ? Theme.positive : Theme.summitText)
            Text(verbatim: headline)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            if let first = items.first {
                Text(verbatim: "\(first.lines.joined(separator: ", ")) \(validity(first))")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.widSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            WidStandLine(status: state)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                WidEyebrow(text: "Störungen auf meinen Linien", symbol: "exclamationmark.triangle.fill", tint: Theme.summitText)
                Spacer(minLength: 0)
            }
            if items.isEmpty {
                Text(verbatim: "Keine Störung auf \(followedLines.prefix(3).joined(separator: ", "))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
            } else {
                ForEach(items.prefix(3)) { item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "\(item.lines.joined(separator: ", ")) · \(validity(item))")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(verbatim: item.summary)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.widSecondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                WidStandLine(status: state)
                Spacer(minLength: 0)
                WidSourceLine()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(items.isEmpty ? "Keine Störung" : "Störung", systemImage: items.isEmpty ? "checkmark.circle" : "exclamationmark.triangle.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .widgetAccentable()
            if let first = items.first {
                Text(verbatim: "\(first.lines.joined(separator: ", ")) \(validity(first))")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: first.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(verbatim: followedLines.prefix(2).joined(separator: ", "))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var inlineText: String {
        guard let first = items.first else { return "Keine Störung auf deinen Linien" }
        return "Störung \(first.lines.joined(separator: ", ")) \(validity(first))"
    }

    /// "bis 14:00" from the validity end; "" without one.
    private func validity(_ item: WidgetDisruption) -> String {
        guard let until = item.validUntil else { return "" }
        return "bis \(WidFormat.clock(until))"
    }
}
