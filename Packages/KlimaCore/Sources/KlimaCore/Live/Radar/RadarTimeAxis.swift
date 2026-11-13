import Foundation

// Radar time travel, part 3: the time axis of the scrubber, the time-lapse, the glide, the words and the light of the day
// (docs/RADAR_TIMETRAVEL.md). Pure: every function takes its clock as a parameter. All wall-clock text is Europe/Vienna.

// MARK: - Axis

/// The scrubber's range: from half an hour back to three hours ahead, in five-minute steps. The past is offered because the server answers for
/// a past time too (measured, docs/RADAR_TIMETRAVEL.md §R12): it calculates the positions from the timetable and the delays known now. That is a
/// calculation, not a recording, and the words say so.
public enum RadarTimeAxis {
    public static let stepSeconds: TimeInterval = 300
    public static let maxOffset: TimeInterval = 10_800
    public static let minOffset: TimeInterval = -1_800
    /// Steps from the far left to the far right: -6 ... 36, so 42 steps and 43 positions.
    public static var stepCount: Int { Int((maxOffset - minOffset) / stepSeconds) }

    /// The offset limited to the range.
    public static func clamped(_ offset: TimeInterval) -> TimeInterval {
        guard offset.isFinite else { return 0 }
        return min(max(offset, minOffset), maxOffset)
    }

    /// The offset on the five-minute grid (nearest step), limited to the range.
    public static func snapped(_ offset: TimeInterval) -> TimeInterval {
        Double(step(for: offset)) * stepSeconds
    }

    /// The nearest step of an offset: -6 ... 36, 0 is "Jetzt".
    public static func step(for offset: TimeInterval) -> Int {
        Int((clamped(offset) / stepSeconds).rounded())
    }

    /// "Now" as the axis sees it: the current minute (seconds dropped), so the labels of "Jetzt" and of the steps are whole minutes.
    public static func base(now: Date) -> Date {
        Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    /// The time a step stands for: base plus the offset. Absolute, so a change of the clock offset (summer time) is no problem here.
    public static func target(base: Date, offset: TimeInterval) -> Date {
        base.addingTimeInterval(clamped(offset))
    }

    /// The offset of `target` from `now`, limited to the range (the thumb's place while the clock moves on).
    public static func offset(of target: Date, now: Date) -> TimeInterval {
        clamped(target.timeIntervalSince(base(now: now)))
    }

    /// 0 at the far left (30 minutes back), 1 at the far right (three hours ahead): where the thumb sits on the track.
    public static func fraction(of offset: TimeInterval) -> Double {
        (clamped(offset) - minOffset) / (maxOffset - minOffset)
    }

    /// The offset at a place on the track (0 ... 1), snapped to the grid.
    public static func offset(atFraction fraction: Double) -> TimeInterval {
        guard fraction.isFinite else { return 0 }
        return snapped(minOffset + min(max(fraction, 0), 1) * (maxOffset - minOffset))
    }
}

// MARK: - Time-lapse

public enum RadarPlaybackSpeed: Int, CaseIterable, Sendable, Hashable {
    case x1 = 1, x2 = 2

    /// One second of watching is five minutes of the timetable at 1x, ten at 2x.
    public var timetableSecondsPerSecond: Double { 300 * Double(rawValue) }

    public var title: String { self == .x1 ? "1×" : "2×" }
}

public enum RadarPlayback {
    /// The offset after `elapsed` seconds of playing, and whether it reached the end of the range (the time-lapse stops there).
    public static func advance(offset: TimeInterval, elapsed: TimeInterval, speed: RadarPlaybackSpeed) -> (offset: TimeInterval, reachedEnd: Bool) {
        let next = offset + max(elapsed, 0) * speed.timetableSecondsPerSecond
        if next >= RadarTimeAxis.maxOffset { return (RadarTimeAxis.maxOffset, true) }
        return (RadarTimeAxis.clamped(next), false)
    }

    /// Where playing starts: where the scrubber is, from "Jetzt" when it sits at the end.
    public static func startOffset(from offset: TimeInterval) -> TimeInterval {
        offset >= RadarTimeAxis.maxOffset ? 0 : RadarTimeAxis.clamped(offset)
    }

    /// How long a full run takes: three hours of timetable in 36 seconds at 1x.
    public static func duration(of speed: RadarPlaybackSpeed) -> TimeInterval {
        RadarTimeAxis.maxOffset / speed.timetableSecondsPerSecond
    }
}

/// The time the map shows glides to the time the scrubber says: markers move instead of jumping when the thumb moves a step.
public enum RadarTimeGlide {
    /// Time constant of the approach (seconds): after this long about 63 % of the way is done.
    public static let tau: TimeInterval = 0.14
    /// Closer than this (seconds of timetable) the shown time snaps to the target.
    public static let snap: TimeInterval = 12

    public static func step(shown: TimeInterval, target: TimeInterval, elapsed: TimeInterval) -> TimeInterval {
        let distance = target - shown
        guard abs(distance) > snap, elapsed > 0 else { return target }
        return shown + distance * (1 - exp(-elapsed / tau))
    }
}

// MARK: - Words

public enum RadarTimeText {
    public static let banner = "Zeitreise · Prognose aus dem Fahrplan"
    /// The same, for a time that has passed: the server calculates it from the timetable too; nothing was recorded.
    public static let bannerPast = "Zeitreise · Rückblick aus dem Fahrplan"
    public static let honesty = "Berechnet aus dem Fahrplan und den Verspätungen von jetzt. Spätere Verspätungen sind nicht vorhergesagt."
    public static let honestyPast = "Berechnet aus dem Fahrplan und den Verspätungen von jetzt. Das ist keine Aufzeichnung."
    public static let straightLine = "Zwischen den Halten fahren die Züge auf der Luftlinie. Nur beim gewählten Zug folgt die Spur der Strecke."

    public static func banner(for offset: TimeInterval) -> String { offset < 0 ? bannerPast : banner }
    public static func honesty(for offset: TimeInterval) -> String { offset < 0 ? honestyPast : honesty }

    /// "22:32", with " MEZ" or " MESZ" when the clock offset at `date` differs from the one at `now` (the night summer time ends).
    public static func clock(_ date: Date, now: Date) -> String {
        let calendar = Calendar.vienna
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        var text = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        let offset = calendar.timeZone.secondsFromGMT(for: date)
        if offset != calendar.timeZone.secondsFromGMT(for: now) {
            text += offset >= 7200 ? " MESZ" : " MEZ"
        }
        return text
    }

    /// nil on the same day as `now`, "morgen" on the next one (the scrubber crosses midnight), "gestern" on the one before (half an hour back
    /// just after midnight), else the weekday.
    public static func dayNote(for date: Date, now: Date) -> String? {
        let calendar = Calendar.vienna
        if calendar.isDate(date, inSameDayAs: now) { return nil }
        let start = calendar.startOfDay(for: now)
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: start), calendar.isDate(date, inSameDayAs: tomorrow) { return "morgen" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: start), calendar.isDate(date, inSameDayAs: yesterday) { return "gestern" }
        let names = ["", "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        let weekday = calendar.component(.weekday, from: date)
        return names.indices.contains(weekday) ? names[weekday] : nil
    }

    /// "Jetzt", "in 45 Min", "in 1 Std", "in 1 Std 15 Min", "vor 10 Min".
    public static func offsetTitle(_ offset: TimeInterval) -> String {
        let minutes = Int((RadarTimeAxis.clamped(offset) / 60).rounded())
        if minutes == 0 { return "Jetzt" }
        if minutes < 0 { return "vor \(-minutes) Min" }
        if minutes < 60 { return "in \(minutes) Min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "in \(hours) Std" : "in \(hours) Std \(rest) Min"
    }

    /// For VoiceOver: "in 45 Minuten", "in einer Stunde und 15 Minuten", "vor 10 Minuten", "jetzt".
    public static func spokenOffset(_ offset: TimeInterval) -> String {
        let minutes = Int((RadarTimeAxis.clamped(offset) / 60).rounded())
        if minutes == 0 { return "jetzt" }
        if minutes < 0 { return minutes == -1 ? "vor einer Minute" : "vor \(-minutes) Minuten" }
        let hours = minutes / 60, rest = minutes % 60
        let hourText = hours == 1 ? "einer Stunde" : "\(hours) Stunden"
        let minuteText = rest == 1 ? "einer Minute" : "\(rest) Minuten"
        if hours == 0 { return "in \(minuteText)" }
        return rest == 0 ? "in \(hourText)" : "in \(hourText) und \(minuteText)"
    }

    /// "22 Uhr 32", "21 Uhr" (a spoken time).
    public static func spokenClock(_ date: Date) -> String {
        let parts = Calendar.vienna.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        return minute == 0 ? "\(hour) Uhr" : "\(hour) Uhr \(minute)"
    }

    /// What VoiceOver says for the scrubber and the chip: "22 Uhr 32, in 45 Minuten", "0 Uhr 15, morgen, in 2 Stunden", "Jetzt".
    public static func spokenValue(target: Date?, now: Date, offset: TimeInterval) -> String {
        guard let target else { return "Jetzt" }
        let day = dayNote(for: target, now: now).map { ", \($0)" } ?? ""
        return "\(spokenClock(target))\(day), \(spokenOffset(RadarTimeAxis.snapped(offset)))"
    }

    /// The line when an answer of the server lies near the chosen minute (`RadarTimeScheduler.snapshotTime`). Only for this very minute are the
    /// positions the server's own (the markers are solid then); an answer up to two and a half minutes away is named, and the minute shown
    /// is calculated from it (the markers stay dashed).
    public static func snapshotNote(snapshot: Date, target: Date, now: Date) -> String {
        if abs(snapshot.timeIntervalSince(target)) <= RadarTimePin.solidWithin {
            return "Für diese Minute hat die Auskunft die Positionen selbst berechnet."
        }
        return "Für \(clock(snapshot, now: now)) hat die Auskunft die Positionen selbst berechnet, für \(clock(target, now: now)) rechnet die App von dort aus."
    }

    /// Low Power Mode: nothing is loaded, the picture is calculated from what is there (the live radar pauses the same way).
    public static let lowPowerTitle = "Stromspar-Modus"
    public static let lowPower = "Die Zeitreise lädt nichts nach, solange der Stromspar-Modus an ist. Gerechnet wird mit dem, was schon geladen ist."

    /// The hint of the play button: what one second of the time-lapse is.
    public static func playHint(_ speed: RadarPlaybackSpeed) -> String {
        "Eine Sekunde sind \(speed == .x1 ? "fünf" : "zehn") Minuten Fahrplan."
    }

    /// "Stand der Verspätungen: vor 42 s": how old the delays behind the picture are.
    public static func delayAge(_ seconds: TimeInterval) -> String {
        "Stand der Verspätungen: \(RadarStatusText.age(seconds))"
    }

    /// The caption under the picture: how old the delays are and that nothing later is predicted ("Stand der Verspätungen: vor 42 s. Spätere
    /// Verspätungen sind nicht vorhergesagt."). For the past: that it is no recording.
    public static func statusCaption(age: TimeInterval?, offset: TimeInterval) -> String {
        let second = offset < 0 ? "Das ist keine Aufzeichnung." : "Spätere Verspätungen sind nicht vorhergesagt."
        guard let age else { return second }
        return "\(delayAge(age)). \(second)"
    }

    public static func spokenDelayAge(_ seconds: TimeInterval) -> String {
        "Stand der Verspätungen: \(RadarStatusText.spokenAge(seconds))"
    }

    /// "Zeitreise lädt 3/9".
    public static func loading(loaded: Int, total: Int) -> String {
        "Zeitreise lädt \(min(loaded, total))/\(total)"
    }

    /// "812 Züge · berechnet für 22:32".
    public static func pill(count: Int, rail: Bool, clock: String) -> String {
        let noun = rail ? (count == 1 ? "Zug" : "Züge") : (count == 1 ? "Fahrzeug" : "Fahrzeuge")
        return "\(count) \(noun) · berechnet für \(clock)"
    }

    /// What was not loaded, in words: one or several points in time.
    public static func missing(_ failed: Int) -> String {
        failed == 1 ? "Ein Zeitpunkt konnte nicht geladen werden. Zügen, die erst später losfahren, fehlen dort Daten."
                    : "\(failed) Zeitpunkte konnten nicht geladen werden. Zügen, die erst später losfahren, fehlen dort Daten."
    }

    /// The volume, honestly: the largest measured answer (docs/OEBB_LIVE.md §R11.1: 1,83 MB for all of Austria in the evening peak; 1,2 MB
    /// at 22 Uhr, docs/RADAR_TIMETRAVEL.md §R12), so an upper bound: "bis etwa". Each minute loaded exactly adds one answer. The server does
    /// not compress (docs/OEBB_LIVE.md §A2.1), so this is about what goes over the network: before review 2 the card said it was less there.
    public static func volume(points: Int) -> String {
        let total = megabytes(Double(points) * RadarTimeScheduler.megabytesPerAnswer)
        let one = megabytes(RadarTimeScheduler.megabytesPerAnswer)
        let noun = points == 1 ? "Zeitpunkt" : "Zeitpunkte"
        return "Bis etwa \(total) MB für \(points) \(noun), dazu bis etwa \(one) MB für jede genau geladene Minute. Die Auskunft schickt die Daten ungepackt."
    }

    private static func megabytes(_ value: Double) -> String {
        let text = value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)
        return text.replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Light of the day

/// How dark it is in Austria at an instant: a soft tint for the map while the scrubber is away from now. Decoration, not a claim: the
/// sun's height is computed for 47.6° N, 14.3° E without the equation of time (good to about 15 minutes) and nothing is labelled with it.
public enum RadarDaylight {
    public struct Sample: Sendable, Equatable {
        /// The sun's height in degrees (negative: below the horizon).
        public var elevation: Double
        /// 0 by day, 1 in the dark: the sun is more than 12 degrees below the horizon.
        public var night: Double
        /// 1 at sunrise and sunset, falling to 0 six degrees away from the horizon: the warm hour.
        public var twilight: Double
    }

    static let latitude = 47.6
    static let longitude = 14.3

    public static func sample(at date: Date) -> Sample {
        let seconds = date.timeIntervalSince1970
        // Day of the year from the civil date in UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let n = Double(utc.ordinality(of: .day, in: .year, for: date) ?? 1)
        let declination = -23.44 * cos((360.0 / 365.0 * (n + 10)) * .pi / 180)
        let utcHours = seconds.truncatingRemainder(dividingBy: 86_400) / 3600
        let solarHours = (utcHours + longitude / 15).truncatingRemainder(dividingBy: 24)
        let hourAngle = 15 * (solarHours - 12)
        let phi = latitude * .pi / 180, delta = declination * .pi / 180, h = hourAngle * .pi / 180
        let elevation = asin(sin(phi) * sin(delta) + cos(phi) * cos(delta) * cos(h)) * 180 / .pi
        let night = min(max((-elevation - 3) / 9, 0), 1)
        let twilight = min(max(1 - abs(elevation) / 6, 0), 1)
        return Sample(elevation: elevation, night: night, twilight: twilight)
    }
}
