import WidgetKit
import SwiftUI

/// "Schnellerfassung" – interactive favourite buttons (Button(intent: LogFavoriteTripIntent)).
struct QuickLogWidget: Widget {
    static let kind = "quicklog"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            QuickLogEntryView(entry: entry)
        }
        .configurationDisplayName("Schnellerfassung")
        .description("Erfasse deine Lieblingsfahrten mit einem Tipp – direkt am Home-Bildschirm.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct QuickLogEntryView: View {
    let entry: SnapshotEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    /// Tapping outside a favourite opens "Fahrt erfassen"; without a ticket the app opens on its start screen.
    private var url: URL { entry.snapshot == nil ? WidDeepLink.overview : WidDeepLink.addTrip }

    var body: some View {
        QuickLogWidgetView(snapshot: entry.snapshot, family: family, margins: WidLayout.resolved(contentMargins))
            .widgetURL(url)
            .widgetBrandBackground(family)
    }
}
