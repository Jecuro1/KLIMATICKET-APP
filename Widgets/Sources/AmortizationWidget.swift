import WidgetKit
import SwiftUI

/// "Amortisation" – how far the ticket has paid off, on the home screen and the lock screen.
struct AmortizationWidget: Widget {
    static let kind = "amortization"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            AmortizationEntryView(entry: entry)
        }
        .configurationDisplayName("Amortisation")
        .description("Wie weit sich dein KlimaTicket schon rentiert hat – mit Prognose für den Break-even.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

/// Reads the family / margins from the widget environment and hands them to the shared view.
private struct AmortizationEntryView: View {
    let entry: SnapshotEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        AmortizationWidgetView(snapshot: entry.snapshot, family: family, margins: WidLayout.resolved(contentMargins))
            .widgetURL(WidDeepLink.overview)
            .widgetBrandBackground(family)
    }
}
