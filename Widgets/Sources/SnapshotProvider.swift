import WidgetKit
import SwiftUI
import KlimaCore

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// True when rendered in the widget gallery / placeholder.
    let isPreview: Bool
    /// Lock-screen privacy the views follow (docs/WIDGETS_SMARTSTACK.md §1).  // MARK: smartwidgets
    var privacy: WidgetPrivacy = .standard
    /// Smart Stack score of this entry (`WidgetRelevance`); nil for widgets that do not compete for the stack.
    var relevanceScore: Double? = nil

    var resolved: WidgetSnapshot { snapshot ?? .sample }

    var relevance: TimelineEntryRelevance? {
        relevanceScore.map { TimelineEntryRelevance(score: Float($0)) }
    }
}

/// Which Smart Stack score the snapshot entries carry (docs/WIDGETS_SMARTSTACK.md §3).  // MARK: smartwidgets
enum SnapshotRelevance {
    /// No score: the system ranks the widget on its own.
    case none
    /// "Ticket-Restzeit": 30 in the last 14 days of the validity.
    case ticketEnd
    /// "Break-even": 60 on the forecast day.
    case breakEven

    func score(_ snapshot: WidgetSnapshot, at date: Date) -> Double? {
        switch self {
        case .none:
            return nil
        case .ticketEnd:
            return WidgetRelevance.ticketRemaining(now: date, validUntil: snapshot.validUntil, calendar: WidInsight.calendar)
        case .breakEven:
            let forecast = WidInsight.isPaidOff(snapshot) ? nil : WidInsight.upcomingBreakEven(snapshot, now: date)
            return WidgetRelevance.breakEven(now: date, breakEvenDate: forecast, calendar: WidInsight.calendar)
        }
    }
}

/// Reads the snapshot the app writes into the App Group. The figures only change when the app saves (it reloads the
/// timelines then); what changes on its own is the day count ("noch 143 Tage", "in 66 Tagen") at Vienna midnight.
/// So the timeline holds one entry per coming day – correct at 00:00 even when WidgetKit's reload budget is spent,
/// and no reloads in between.
struct SnapshotProvider: TimelineProvider {
    /// Days covered by one timeline (then WidgetKit asks again).
    static let days = 7

    /// The Smart Stack score the entries carry.  // MARK: smartwidgets
    var relevance: SnapshotRelevance = .none

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample, isPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snap = WidgetSnapshot.load()
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? (snap ?? .sample) : snap, isPreview: context.isPreview,
                                 privacy: WidgetPrivacy.current(snapshot: snap)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.load()
        guard let snapshot else {
            // No ticket yet: the app reloads the timelines as soon as it writes the first snapshot (a slow re-check
            // covers a reload that never arrived).
            completion(Timeline(entries: [SnapshotEntry(date: now, snapshot: nil, isPreview: false,
                                                        privacy: WidgetPrivacy.current(snapshot: nil))],
                                policy: .after(now.addingTimeInterval(6 * 3600))))
            return
        }
        completion(Timeline(entries: Self.entries(for: snapshot, from: now, relevance: relevance), policy: .atEnd))
    }

    /// Now, then the start of each of the next `days` Vienna days (DST-safe: calendar days, not 24-hour steps) – plus
    /// the moment a just-logged favourite's "Gerade erfasst" turns back into "+ € 22,80".
    static func entries(for snapshot: WidgetSnapshot, from now: Date, relevance: SnapshotRelevance = .none) -> [SnapshotEntry] {
        let calendar = WidInsight.calendar
        var dates = [now]
        var day = calendar.startOfDay(for: now)
        for _ in 0..<days {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
            dates.append(next)
        }
        if let log = snapshot.recentLog {
            let end = log.date.addingTimeInterval(WidgetSnapshot.RecentLog.feedbackSeconds)
            if end > now { dates.append(end) }
        }
        let privacy = WidgetPrivacy.current(snapshot: snapshot)   // MARK: smartwidgets
        return dates.sorted().map {
            SnapshotEntry(date: $0, snapshot: snapshot, isPreview: false, privacy: privacy,
                          relevanceScore: relevance.score(snapshot, at: $0))
        }
    }
}
