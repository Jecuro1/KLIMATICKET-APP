import WidgetKit
import SwiftUI
import AppIntents
import KlimaCore

// The live widgets: connections of a favourite route, departures of a station and disruptions of the lines the user rides.
// All read WidgetCache (written by the app with the user's consent) and never fetch.

/// "Nächste Verbindung": the next connections of a favourite route – gate-level detail, delays, platform, cancellations.
struct NextConnectionWidget: Widget {
    static let kind = WidKind.nextConnection

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: NextConnectionConfigIntent.self, provider: NextConnectionProvider()) { entry in
            NextConnectionEntryView(entry: entry)
        }
        .configurationDisplayName("Nächste Verbindung")
        .description("Die nächsten Verbindungen einer Lieblingsfahrt mit Gleis und Verspätung – aus dem Stand der App.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

private struct NextConnectionEntryView: View {
    let entry: ConnectionEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        NextConnectionWidgetView(title: entry.title, state: entry.state, items: entry.items, family: family,
                                 margins: WidLayout.resolved(contentMargins), viaStops: entry.viaStops)
            .widContent(family, WidLayout.resolved(contentMargins))
            .environment(\.widNow, entry.date)
            .widgetURL(WidDeepLink.planner)
            .widgetBrandBackground(family)
    }
}

/// "Abfahrten": the next departures of a station; the home station unless another one is chosen.
struct DeparturesWidget: Widget {
    static let kind = WidKind.departures

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: DeparturesConfigIntent.self, provider: DepartureProvider()) { entry in
            DeparturesEntryView(entry: entry)
        }
        .configurationDisplayName("Abfahrten")
        .description("Die nächsten Abfahrten einer Station – Standard ist deine Heimat-Station.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

private struct DeparturesEntryView: View {
    let entry: DepartureEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        DeparturesWidgetView(stationName: entry.stationName, facilities: entry.facilities, state: entry.state,
                             items: entry.items, family: family, margins: WidLayout.resolved(contentMargins))
            .widContent(family, WidLayout.resolved(contentMargins))
            .environment(\.widNow, entry.date)
            .widgetURL(entry.stationID.map { WidDeepLink.board(stationID: $0) } ?? WidDeepLink.planner)
            .widgetBrandBackground(family)
    }
}

/// "Störungen auf meinen Linien": disruptions that name a line the user rides (the lines of the favourite routes).
struct DisruptionsWidget: Widget {
    static let kind = WidKind.disruptions

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: DisruptionProvider()) { entry in
            DisruptionsEntryView(entry: entry)
        }
        .configurationDisplayName("Störungen auf meinen Linien")
        .description("Meldungen zu den Linien, die du fährst – mit dem Stand der letzten Abfrage.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

private struct DisruptionsEntryView: View {
    let entry: DisruptionEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        DisruptionsWidgetView(state: entry.state, items: entry.items, followedLines: entry.followedLines, family: family,
                              margins: WidLayout.resolved(contentMargins))
            .widContent(family, WidLayout.resolved(contentMargins))
            .environment(\.widNow, entry.date)
            .widgetURL(WidDeepLink.planner)
            .widgetBrandBackground(family)
    }
}
