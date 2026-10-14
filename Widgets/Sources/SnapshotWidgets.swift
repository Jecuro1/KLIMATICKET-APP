import WidgetKit
import SwiftUI
import KlimaCore

// Widgets that need only the ticket snapshot (no network, no cache): the remaining validity, the break-even forecast, the
// year teaser, the twelve-week heatmap and the summit on the lock screen and in StandBy. Same provider as the amortisation
// widget, so the day counts roll over at midnight without reloads.

/// "Ticket-Restzeit": the days left on the ticket – a gauge on the lock screen.
struct TicketRemainingWidget: Widget {
    static let kind = WidKind.ticketRemaining

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            TicketRemainingEntryView(entry: entry)
        }
        .configurationDisplayName("Ticket-Restzeit")
        .description("Wie viele Tage dein KlimaTicket noch gültig ist.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

private struct TicketRemainingEntryView: View {
    let entry: SnapshotEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        TicketRemainingWidgetView(snapshot: entry.snapshot, family: family, now: entry.date,
                                  margins: WidLayout.resolved(contentMargins))
            .widContent(family, WidLayout.resolved(contentMargins))
            .environment(\.widNow, entry.date)
            .widgetURL(WidDeepLink.overview)
            .widgetBrandBackground(family)
    }
}

/// "Break-even": when the ticket pays off at the current pace, or the profit once it has.
struct BreakEvenWidget: Widget {
    static let kind = WidKind.breakEven

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            BreakEvenEntryView(entry: entry)
        }
        .configurationDisplayName("Break-even")
        .description("Wann sich dein KlimaTicket bei deinem Tempo rentiert – und wie weit du schon bist.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

private struct BreakEvenEntryView: View {
    let entry: SnapshotEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        BreakEvenWidgetView(snapshot: entry.snapshot, family: family, now: entry.date,
                            margins: WidLayout.resolved(contentMargins))
            .widContent(family, WidLayout.resolved(contentMargins))
            .environment(\.widNow, entry.date)
            .widgetURL(WidDeepLink.overview)
            .widgetBrandBackground(family)
    }
}

/// "Jahresrückblick": the year's figures in December or near the end of the ticket, otherwise the countdown.
struct YearReviewWidget: Widget {
    static let kind = WidKind.yearReview

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            YearReviewEntryView(entry: entry)
        }
        .configurationDisplayName("Jahresrückblick")
        .description("Fahrten, Kilometer und CO₂ deines Tickets – ab Dezember und in den letzten Wochen der Gültigkeit.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct YearReviewEntryView: View {
    let entry: SnapshotEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        YearReviewWidgetView(snapshot: entry.snapshot, family: family, now: entry.date,
                             margins: WidLayout.resolved(contentMargins))
            .widContent(family, WidLayout.resolved(contentMargins))
            .environment(\.widNow, entry.date)
            .widgetURL(WidDeepLink.stats)
            .widgetBrandBackground(family)
    }
}

/// "Fahrten-Kalender": twelve weeks of trips as a grid of days.
struct HeatmapWidget: Widget {
    static let kind = WidKind.heatmap

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            HeatmapEntryView(entry: entry)
        }
        .configurationDisplayName("Fahrten-Kalender")
        .description("Deine Fahrten der letzten zwölf Wochen – jeder Tag ein Quadrat.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

private struct HeatmapEntryView: View {
    let entry: SnapshotEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        HeatmapWidgetView(counts: entry.snapshot?.heat, storedDay: entry.snapshot?.generatedAt ?? entry.date,
                          now: entry.date, family: family, margins: WidLayout.resolved(contentMargins))
            .widContent(family, WidLayout.resolved(contentMargins))
            .environment(\.widNow, entry.date)
            .widgetURL(WidDeepLink.stats)
            .widgetBrandBackground(family)
    }
}

/// "Gipfel-Fortschritt": the way to the summit, on the lock screen and in StandBy.
struct SummitWidget: Widget {
    static let kind = WidKind.summit

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            SummitEntryView(entry: entry)
        }
        .configurationDisplayName("Gipfel-Fortschritt")
        .description("Wie weit du auf dem Weg zum Gipfel – dem Ticketpreis – bist. Auch in StandBy.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

private struct SummitEntryView: View {
    let entry: SnapshotEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        SummitWidgetView(snapshot: entry.snapshot, family: family, now: entry.date, margins: WidLayout.resolved(contentMargins))
            .environment(\.widNow, entry.date)
            .widgetURL(WidDeepLink.overview)
            .widgetBrandBackground(family)
    }
}
