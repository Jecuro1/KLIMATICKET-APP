import WidgetKit
import SwiftUI

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// True when rendered in the widget gallery / placeholder.
    let isPreview: Bool

    var resolved: WidgetSnapshot { snapshot ?? .sample }
}

/// Reads the snapshot the app writes into the App Group and refreshes a few times per day
/// (days-remaining changes at midnight; the app reloads timelines after every change).
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample, isPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snap = WidgetSnapshot.load()
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? (snap ?? .sample) : snap, isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load(), isPreview: false)
        let cal = Calendar.current
        let nextMidnight = cal.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 5), matchingPolicy: .nextTime) ?? .now.addingTimeInterval(6 * 3600)
        let refresh = min(nextMidnight, Date.now.addingTimeInterval(6 * 3600))
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}
