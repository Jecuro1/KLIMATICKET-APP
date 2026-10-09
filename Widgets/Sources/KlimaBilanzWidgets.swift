import WidgetKit
import SwiftUI
import KlimaCore

struct InfraEntry: TimelineEntry { let date: Date }

struct InfraProvider: TimelineProvider {
    func placeholder(in context: Context) -> InfraEntry { InfraEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (InfraEntry) -> Void) { completion(InfraEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<InfraEntry>) -> Void) {
        completion(Timeline(entries: [InfraEntry(date: .now)], policy: .atEnd))
    }
}

struct InfraWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "infra", provider: InfraProvider()) { _ in
            Text("KlimaBilanz").containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("KlimaBilanz")
    }
}

@main
struct KlimaBilanzWidgetsBundle: WidgetBundle {
    var body: some Widget { InfraWidget() }
}
