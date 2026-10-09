import Foundation

/// Realtime labels shared by cards, timeline, board and Live Activity (SPEC §C3.1).
public enum RealtimePresentation {
    /// - cancelled → `.cancelled` „Fällt aus“
    /// - no realtime → `.scheduled`, no text
    /// - Δ = round((realtime − planned) / 60): Δ ≤ 0 → `.onTime` („pünktlich“ for 0, else „HH:mm (Δ)“);
    ///   1…4 → `.late` „HH:mm +Δ“; ≥ 5 → `.veryLate` „HH:mm +Δ“.
    public static func label(_ event: StopEvent) -> RealtimeLabel {
        if event.isCancelled { return RealtimeLabel(state: .cancelled, text: "Fällt aus") }
        guard let realtime = event.realtime, let planned = event.planned else { return RealtimeLabel(state: .scheduled) }
        // Python `round` (half to even) as in the reference; HAFAS times are whole minutes in practice.
        let delta = Int((realtime.timeIntervalSince(planned) / 60).rounded(.toNearestOrEven))
        if delta <= 0 {
            return RealtimeLabel(state: .onTime, delayMinutes: delta, text: delta == 0 ? "pünktlich" : "\(time(realtime)) (\(delta))")
        }
        return RealtimeLabel(state: delta < 5 ? .late : .veryLate, delayMinutes: delta, text: "\(time(realtime)) +\(delta)")
    }

    /// „HH:mm“ in Europe/Vienna.
    public static func time(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// VoiceOver wording of a label next to its planned time: „pünktlich“, „4 Minuten später, 11:20“,
    /// „2 Minuten früher, 11:14“, „fällt aus“; nil without realtime.
    public static func spoken(_ label: RealtimeLabel, realtime: Date?) -> String? {
        switch label.state {
        case .scheduled: return nil
        case .cancelled: return "fällt aus"
        case .onTime, .late, .veryLate:
            guard let d = label.delayMinutes, d != 0 else { return "pünktlich" }
            let t = realtime.map { ", \(time($0))" } ?? ""
            return d > 0 ? "\(minutes(d)) später\(t)" : "\(minutes(-d)) früher\(t)"
        }
    }

    /// „1 Minute“, „4 Minuten“.
    static func minutes(_ n: Int) -> String { n == 1 ? "1 Minute" : "\(n) Minuten" }

    static let calendar: Calendar = .vienna
}
