import SwiftUI
import WidgetKit
import KlimaCore

/// "Nächste Verbindung": the next connections of one favourite route, from the app's cache. systemSmall (the next train),
/// systemMedium (three connections), systemLarge (three connections with arrival, changes, equipment) and the lock-screen
/// rectangular and inline families. Shared by the widget and the in-app preview.
struct NextConnectionWidgetView: View {
    /// The favourite's title; nil while none is chosen.
    var title: String?
    var state: WidgetLiveState
    var items: [WidgetConnection]
    var family: WidgetFamily
    var margins: EdgeInsets = WidLayout.defaultMargins

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if title == nil {
            WidLiveEmpty(status: state, family: family, choice: "Lieblingsfahrt wählen")
        } else if !state.hasTimes {
            WidLiveEmpty(status: state, family: family)
        } else if items.isEmpty {
            WidLiveEmpty(status: state, family: family,
                         message: ("Keine Verbindung mehr", "App öffnen für die nächsten Züge"))
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            small
        case .systemLarge:
            large
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            inline
        default:
            medium
        }
    }

    private var first: WidgetConnection? { items.first }

    /// Accessibility text sizes get fewer rows, so the rows stay readable.
    private var rowCount: Int { dynamicTypeSize.isAccessibilitySize ? 1 : 3 }

    // MARK: Home screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidEyebrow(text: "Nächste Verbindung", symbol: "tram.fill")
            Text(verbatim: title ?? "")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.widSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let first {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: WidFormat.clock(first.departureTime))
                        .font(.system(size: 30, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(first.isCancelled ? Theme.negativeText : Theme.textPrimary)
                        .strikethrough(first.isCancelled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .widgetAccentable()
                    if state.showsDelays, let delay = WidFormat.delay(first.delayMinutes) {
                        Text(verbatim: delay)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.negativeText)
                    }
                }
                Text(verbatim: first.isCancelled ? "\(first.lineName) fällt aus" : "\(first.lineName)\(platformSuffix(first))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if !first.isCancelled {
                    Text(first.departureTime, style: .relative)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.widSecondary)
                        .lineLimit(1)
                }
                WidStandLine(status: state)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            ForEach(items.prefix(rowCount)) { connection in
                VStack(alignment: .leading, spacing: 1) {
                    WidDepartureLine(time: connection.departureTime, delay: connection.delayMinutes,
                                     lineName: connection.lineName, modeSymbol: connection.modeSymbol,
                                     destination: connection.toName, platform: platformText(connection),
                                     platformChanged: connection.platformChanged, isCancelled: connection.isCancelled,
                                     showsDelay: state.showsDelays)
                    Text(verbatim: detail(connection))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.widSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.leading, 2)
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
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(items.prefix(rowCount)) { connection in
                VStack(alignment: .leading, spacing: 3) {
                    WidDepartureLine(time: connection.departureTime, delay: connection.delayMinutes,
                                     lineName: connection.lineName, modeSymbol: connection.modeSymbol,
                                     destination: connection.toName, platform: platformText(connection),
                                     platformChanged: connection.platformChanged, isCancelled: connection.isCancelled,
                                     showsDelay: state.showsDelays)
                    Text(verbatim: detail(connection))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.widSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.leading, 2)
                    if !connection.trainAttributes.isEmpty {
                        equipment(connection.trainAttributes)
                            .padding(.leading, 2)
                    }
                }
                .padding(.vertical, 2)
            }
            Spacer(minLength: 0)
            WidStandLine(status: state)
            WidSourceLine()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            WidEyebrow(text: "Nächste Verbindung", symbol: "tram.fill")
            Spacer(minLength: 4)
            Text(verbatim: title ?? "")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.widSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: Lock screen

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: title ?? "Verbindung")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .widgetAccentable()
            if let first {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: WidFormat.clock(first.departureTime))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if state.showsDelays, let delay = WidFormat.delay(first.delayMinutes) {
                        Text(verbatim: delay)
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(verbatim: first.isCancelled ? "fällt aus" : first.lineName)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(verbatim: "→ \(first.toName)\(platformSuffix(first))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(first.map { WidLiveSpeech.departure(time: $0.departureTime, delay: state.showsDelays ? $0.delayMinutes : nil,
                                                                lineName: $0.lineName, destination: $0.toName,
                                                                platform: $0.platform, platformChanged: $0.platformChanged,
                                                                isCancelled: $0.isCancelled) } ?? "")
    }

    private var inline: some View {
        Text(verbatim: inlineText)
            .lineLimit(1)
    }

    private var inlineText: String {
        guard let first else { return "Verbindung" }
        let delay = state.showsDelays ? WidFormat.delay(first.delayMinutes).map { " \($0)" } ?? "" : ""
        if first.isCancelled { return "\(first.lineName) fällt aus" }
        return "\(first.lineName) · \(WidFormat.clock(first.departureTime))\(delay)\(platformSuffix(first))"
    }

    // MARK: Text helpers

    private func platformText(_ connection: WidgetConnection) -> String? {
        connection.platform
    }

    private func platformSuffix(_ connection: WidgetConnection) -> String {
        connection.platform.map { " · \($0)" } ?? ""
    }

    /// "Ankunft 16:00 · 1 Umstieg · 1 h 28 min"
    private func detail(_ connection: WidgetConnection) -> String {
        var parts: [String] = []
        if let arrival = connection.arrival { parts.append("Ankunft \(WidFormat.clock(arrival))") }
        parts.append(connection.changes == 0 ? "direkt" : (connection.changes == 1 ? "1 Umstieg" : "\(connection.changes) Umstiege"))
        if let minutes = connection.durationMinutes, minutes > 0 {
            parts.append(minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min")
        }
        return parts.joined(separator: " · ")
    }

    private func equipment(_ symbols: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(symbols.prefix(6), id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.widSecondary)
                    .accessibilityLabel(WidTrainEquipment.label(for: symbol))
            }
            Text(verbatim: "im Zug")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.widSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Words for the train equipment symbols (VoiceOver and the large widget).
enum WidTrainEquipment {
    static func label(for symbol: String) -> String {
        switch symbol {
        case "wifi": "WLAN"
        case "fork.knife": "Bordrestaurant"
        case "moon": "Ruhezone"
        case "figure.2.and.child.holdinghands": "Familienzone"
        case "figure.roll": "Rollstuhlplatz"
        case "toilet": "WC rollstuhltauglich"
        case "bicycle": "Fahrradmitnahme"
        case "briefcase": "Businessabteil"
        default: "Ausstattung"
        }
    }
}
