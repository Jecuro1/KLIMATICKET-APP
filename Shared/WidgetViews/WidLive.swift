import SwiftUI
import WidgetKit
import KlimaCore

// MARK: - Live widgets: states, rows and wording shared by the connection, departure and disruption widgets
// (docs/WIDGETS.md §6). The widgets never fetch: they show the app's cache and say how old it is ("Stand HH:mm").

extension WidFormat {
    /// "08:12" (24-hour clock, German).
    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }

    /// "+4", "−2" – a delay in minutes, nil when on time.
    static func delay(_ minutes: Int?) -> String? {
        guard let minutes, minutes != 0 else { return nil }
        return minutes > 0 ? "+\(minutes)" : "−\(-minutes)"
    }
}

/// "Stand 08:12" under the times; with a stale cache the hint to open the app.
struct WidStandLine: View {
    let status: WidgetLiveState

    var body: some View {
        switch status {
        case .fresh(let date):
            Text(verbatim: "Stand \(WidFormat.clock(date))")
                .widLiveFootnote()
        case .stale(let date):
            Text(verbatim: "Stand \(WidFormat.clock(date)) · App öffnen für aktuelle Zeiten")
                .widLiveFootnote()
        case .off, .empty:
            EmptyView()
        }
    }
}

private extension View {
    func widLiveFootnote() -> some View {
        font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.widSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// Explains a missing or off cache in the words the user needs ("Live-Daten aus", "Noch keine Abfrage"). `choice` names
/// what the user still has to pick ("Favorit wählen"), shown before any cache state.
struct WidLiveEmpty: View {
    var status: WidgetLiveState
    var family: WidgetFamily
    var choice: String? = nil
    /// A message that replaces the cache state's wording (e.g. "Keine Verbindung mehr heute").
    var message: (title: String, detail: String)? = nil

    private var wording: (symbol: String, title: String, detail: String) {
        if let choice {
            return ("slider.horizontal.3", choice, "In KlimaBilanz-Widgets auswählen")
        }
        if let message {
            return ("clock.arrow.circlepath", message.title, message.detail)
        }
        switch status {
        case .off:
            return ("antenna.radiowaves.left.and.right.slash", "Live-Daten aus", "In KlimaBilanz aktivieren")
        case .empty, .fresh, .stale:
            return ("arrow.triangle.2.circlepath", "Noch keine Abfrage", "KlimaBilanz öffnen, dann laden die Zeiten")
        }
    }

    var body: some View {
        let copy = wording
        switch family {
        case .accessoryInline:
            Label(copy.title, systemImage: copy.symbol)
                .accessibilityLabel("\(copy.title). \(copy.detail)")
        case .accessoryCircular:
            Image(systemName: copy.symbol)
                .font(.system(size: 20, weight: .semibold))
                .widgetAccentable()
                .accessibilityLabel("\(copy.title). \(copy.detail)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(copy.title, systemImage: copy.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Text(copy.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: copy.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .widgetAccentable()
                Text(copy.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(copy.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.widSecondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// One departure line: time (struck through when cancelled), delay, mode, line, destination and platform. Used by the
/// connection and station widgets; the accessibility label is one sentence.
struct WidDepartureLine: View {
    var time: Date
    var delay: Int?
    var lineName: String
    var modeSymbol: String
    var destination: String?
    var platform: String?
    var platformChanged: Bool = false
    var isCancelled: Bool = false
    var showsDelay: Bool = true
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 7) {
            Text(verbatim: WidFormat.clock(time))
                .font(.system(size: compact ? 12.5 : 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isCancelled ? Theme.negativeText : Theme.textPrimary)
                .strikethrough(isCancelled)
                .lineLimit(1)
            if showsDelay, let delay = WidFormat.delay(delay) {
                Text(verbatim: delay)
                    .font(.system(size: compact ? 10.5 : 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.negativeText)
                    .lineLimit(1)
            }
            if !compact {
                WidModeBadge(symbol: modeSymbol, size: 20)
            }
            Text(verbatim: lineName)
                .font(.system(size: compact ? 11.5 : 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let destination, !destination.isEmpty, !compact {
                Text(verbatim: "→ \(destination)")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.widSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 2)
            if isCancelled {
                Text(verbatim: "fällt aus")
                    .font(.system(size: compact ? 10.5 : 12, weight: .bold))
                    .foregroundStyle(Theme.negativeText)
                    .lineLimit(1)
            } else if let platform {
                Text(verbatim: platform)
                    .font(.system(size: compact ? 10.5 : 12.5, weight: .semibold))
                    .foregroundStyle(platformChanged ? Theme.summitText : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidLiveSpeech.departure(time: time, delay: showsDelay ? delay : nil, lineName: lineName,
                                                    destination: destination, platform: platform,
                                                    platformChanged: platformChanged, isCancelled: isCancelled))
    }
}

/// VoiceOver sentences for live rows (German).
enum WidLiveSpeech {
    static func departure(time: Date, delay: Int?, lineName: String, destination: String?, platform: String?,
                          platformChanged: Bool, isCancelled: Bool) -> String {
        if isCancelled { return "\(lineName), Abfahrt \(WidFormat.clock(time)), fällt aus" }
        var parts = ["\(lineName)", "Abfahrt \(WidFormat.clock(time))"]
        if let delay, delay > 0 { parts.append("\(delay) Minuten später") }
        if let delay, delay < 0 { parts.append("\(-delay) Minuten früher") }
        if let destination, !destination.isEmpty { parts.append("nach \(destination)") }
        if let platform { parts.append(platformChanged ? "\(platform), geändert" : platform) }
        return parts.joined(separator: ", ")
    }
}

/// The source note of live data (ÖBB-Fahrplanauskunft, docs/OEBB_LIVE.md §E7). Shown on medium and large widgets.
struct WidSourceLine: View {
    var text: String = "Quelle: ÖBB-Fahrplanauskunft"

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.widSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
