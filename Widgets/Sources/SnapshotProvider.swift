import WidgetKit
import SwiftUI

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// True when rendered in the widget gallery / placeholder.
    let isPreview: Bool

    var resolved: WidgetSnapshot { snapshot ?? .sample }
}

/// Reads the snapshot the app writes into the App Group. The figures only change when the app saves (it reloads the
/// timelines then); what changes on its own is the day count ("noch 143 Tage", "in 66 Tagen") at Vienna midnight.
/// So the timeline holds one entry per coming day – correct at 00:00 even when WidgetKit's reload budget is spent,
/// and no reloads in between.
struct SnapshotProvider: TimelineProvider {
    /// Days covered by one timeline (then WidgetKit asks again).
    static let days = 7

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample, isPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snap = WidgetSnapshot.load()
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? (snap ?? .sample) : snap, isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.load()
        guard let snapshot else {
            // No ticket yet: the app reloads the timelines as soon as it writes the first snapshot (a slow re-check
            // covers a reload that never arrived).
            completion(Timeline(entries: [SnapshotEntry(date: now, snapshot: nil, isPreview: false)],
                                policy: .after(now.addingTimeInterval(6 * 3600))))
            return
        }
        completion(Timeline(entries: Self.entries(for: snapshot, from: now), policy: .atEnd))
    }

    /// Now, then the start of each of the next `days` Vienna days (DST-safe: calendar days, not 24-hour steps).
    static func entries(for snapshot: WidgetSnapshot, from now: Date) -> [SnapshotEntry] {
        let calendar = WidInsight.calendar
        var entries = [SnapshotEntry(date: now, snapshot: snapshot, isPreview: false)]
        var day = calendar.startOfDay(for: now)
        for _ in 0..<days {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
            entries.append(SnapshotEntry(date: next, snapshot: snapshot, isPreview: false))
        }
        return entries
    }
}
