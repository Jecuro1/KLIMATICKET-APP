import XCTest
@testable import KlimaCore

/// Radar time travel: the scrubber's axis, the time-lapse, the glide, the words (Europe/Vienna, midnight, summer time) and the light of the day
/// (docs/RADAR_TIMETRAVEL.md §5, §6).
final class RadarTimeAxisTests: XCTestCase {
    private typealias F = RadarTimeFixtures

    // MARK: Axis

    func testTheAxisIsHalfAnHourBackToThreeHoursAheadInFiveMinuteSteps() {
        XCTAssertEqual(RadarTimeAxis.stepCount, 42, "-6 ... +36")
        XCTAssertEqual(RadarTimeAxis.snapped(0), 0)
        XCTAssertEqual(RadarTimeAxis.snapped(149), 0, "under 2.5 minutes: still now")
        XCTAssertEqual(RadarTimeAxis.snapped(151), 300)
        XCTAssertEqual(RadarTimeAxis.snapped(-151), -300)
        XCTAssertEqual(RadarTimeAxis.snapped(2700), 2700)
        XCTAssertEqual(RadarTimeAxis.snapped(99_999), 10_800, "never beyond three hours")
        XCTAssertEqual(RadarTimeAxis.snapped(-600), -600, "the past is offered: the server answers for it")
        XCTAssertEqual(RadarTimeAxis.snapped(-9_999), -1_800, "but only half an hour")
        XCTAssertEqual(RadarTimeAxis.snapped(.nan), 0)
        XCTAssertEqual(RadarTimeAxis.step(for: 2700), 9)
        XCTAssertEqual(RadarTimeAxis.step(for: -1800), -6)
    }

    func testTheThumbSitsOnTheTrackWhereTheOffsetIs() {
        XCTAssertEqual(RadarTimeAxis.fraction(of: -1800), 0)
        XCTAssertEqual(RadarTimeAxis.fraction(of: 10_800), 1)
        XCTAssertEqual(RadarTimeAxis.fraction(of: 0), 1800.0 / 12_600, accuracy: 1e-12, "Jetzt is a seventh from the left")
        XCTAssertEqual(RadarTimeAxis.offset(atFraction: 0), -1800)
        XCTAssertEqual(RadarTimeAxis.offset(atFraction: 1), 10_800)
        XCTAssertEqual(RadarTimeAxis.offset(atFraction: 1800.0 / 12_600), 0)
        XCTAssertEqual(RadarTimeAxis.offset(atFraction: 0.5), 4500, "the middle is 75 minutes ahead, on the grid")
        XCTAssertEqual(RadarTimeAxis.offset(atFraction: -3), -1800)
        XCTAssertEqual(RadarTimeAxis.offset(atFraction: .nan), 0)
        for step in -6...36 {
            let offset = Double(step) * 300
            XCTAssertEqual(RadarTimeAxis.offset(atFraction: RadarTimeAxis.fraction(of: offset)), offset, "step \(step) survives the round trip")
        }
    }

    func testTheBaseIsTheCurrentMinute() {
        let now = F.vienna(2026, 11, 12, 21, 47, 36)
        XCTAssertEqual(RadarTimeAxis.base(now: now), F.vienna(2026, 11, 12, 21, 47))
        XCTAssertEqual(RadarTimeAxis.target(base: RadarTimeAxis.base(now: now), offset: 2700), F.vienna(2026, 11, 12, 22, 32))
        XCTAssertEqual(RadarTimeAxis.target(base: RadarTimeAxis.base(now: now), offset: -600), F.vienna(2026, 11, 12, 21, 37))
        XCTAssertEqual(RadarTimeAxis.offset(of: F.vienna(2026, 11, 12, 22, 32), now: now.addingTimeInterval(60)), 2640, "the thumb drifts with the clock")
        XCTAssertEqual(RadarTimeAxis.offset(of: F.vienna(2026, 11, 12, 21, 0), now: now), -1800, "further back than half an hour sits at the left end")
    }

    // MARK: Time-lapse

    func testOneSecondIsFiveMinutesAtOneXAndTenAtTwoX() {
        XCTAssertEqual(RadarPlayback.advance(offset: 0, elapsed: 1, speed: .x1).offset, 300)
        XCTAssertEqual(RadarPlayback.advance(offset: 0, elapsed: 1, speed: .x2).offset, 600)
        XCTAssertEqual(RadarPlayback.advance(offset: 600, elapsed: 0.5, speed: .x1).offset, 750)
        XCTAssertEqual(RadarPlayback.duration(of: .x1), 36, "three hours in 36 seconds")
        XCTAssertEqual(RadarPlayback.duration(of: .x2), 18)
    }

    func testTheTimeLapseStopsAtTheEndAndStartsOverFromThere() {
        let end = RadarPlayback.advance(offset: 10_700, elapsed: 1, speed: .x1)
        XCTAssertEqual(end.offset, 10_800)
        XCTAssertTrue(end.reachedEnd)
        XCTAssertFalse(RadarPlayback.advance(offset: 10_000, elapsed: 1, speed: .x1).reachedEnd)
        XCTAssertEqual(RadarPlayback.startOffset(from: 10_800), 0, "play at the end: from now")
        XCTAssertEqual(RadarPlayback.startOffset(from: 2700), 2700)
        XCTAssertEqual(RadarPlayback.advance(offset: 100, elapsed: -3, speed: .x1).offset, 100, "a clock that went back moves nothing")
        var offset = 0.0
        var seconds = 0.0
        while true {
            let step = RadarPlayback.advance(offset: offset, elapsed: 0.2, speed: .x1)
            offset = step.offset
            seconds += 0.2
            if step.reachedEnd { break }
        }
        XCTAssertEqual(seconds, 36, accuracy: 0.21)
    }

    // MARK: Glide

    func testTheShownTimeGlidesToTheTargetAndSnapsWhenClose() {
        var shown = 0.0
        let target = 1800.0
        var previous = shown
        var steps = 0
        while shown != target, steps < 100 {
            shown = RadarTimeGlide.step(shown: shown, target: target, elapsed: 1.0 / 12)
            XCTAssertGreaterThan(shown, previous, "always towards the target")
            XCTAssertLessThanOrEqual(shown, target)
            previous = shown
            steps += 1
        }
        XCTAssertEqual(shown, target, "it arrives")
        XCTAssertLessThan(Double(steps) / 12, 1.6, "in about a second and a half for half an hour of timetable")
        XCTAssertEqual(RadarTimeGlide.step(shown: 1795, target: 1800, elapsed: 0.05), 1800, "5 seconds away: snaps")
        XCTAssertEqual(RadarTimeGlide.step(shown: 900, target: 0, elapsed: 1.0 / 12) < 900, true, "also backwards")
        XCTAssertEqual(RadarTimeGlide.step(shown: 0, target: 600, elapsed: 0), 600, "no time passed: no division, no stall")
    }

    // MARK: Words

    func testTheClockIsViennaTimeAndNamesTheSwitchOfTheClock() {
        let now = F.vienna(2026, 11, 12, 21, 47, 36)
        XCTAssertEqual(RadarTimeText.clock(F.vienna(2026, 11, 12, 22, 32), now: now), "22:32")
        XCTAssertEqual(RadarTimeText.clock(F.vienna(2026, 11, 13, 0, 5), now: now), "00:05")
        // Night of 2026-03-29: now 01:30 CET, +60 minutes is 03:30 CEST.
        let before = F.vienna(2026, 3, 29, 1, 30)
        XCTAssertEqual(RadarTimeText.clock(before.addingTimeInterval(3600), now: before), "03:30 MESZ")
        XCTAssertEqual(RadarTimeText.clock(before.addingTimeInterval(600), now: before), "01:40", "same offset: no suffix")
        // Night of 2026-10-25: now 02:30 CEST, +60 minutes is 02:30 CET: the same digits twice, so the suffix tells them apart.
        let autumn = Date(timeIntervalSince1970: 1_792_888_200)
        XCTAssertEqual(RadarTimeText.clock(autumn, now: autumn), "02:30")
        XCTAssertEqual(RadarTimeText.clock(autumn.addingTimeInterval(3600), now: autumn), "02:30 MEZ")
    }

    func testMidnightGetsADayNote() {
        let now = F.vienna(2026, 11, 12, 23, 40)
        XCTAssertNil(RadarTimeText.dayNote(for: F.vienna(2026, 11, 12, 23, 55), now: now))
        XCTAssertEqual(RadarTimeText.dayNote(for: F.vienna(2026, 11, 13, 0, 5), now: now), "morgen")
        XCTAssertEqual(RadarTimeText.dayNote(for: F.vienna(2026, 11, 13, 2, 40), now: now), "morgen", "three hours ahead")
        XCTAssertEqual(RadarTimeText.dayNote(for: F.vienna(2026, 11, 14, 8, 0), now: now), "Sa", "day after tomorrow: the weekday")
        XCTAssertEqual(RadarTimeText.dayNote(for: F.vienna(2026, 11, 11, 23, 50), now: F.vienna(2026, 11, 12, 0, 10)), "gestern", "half an hour back just after midnight")
        // The calendar day is the Vienna one, not UTC: 23:30 UTC on the 12th is already the 13th in Vienna.
        XCTAssertEqual(RadarTimeText.dayNote(for: Date(timeIntervalSince1970: 1_794_526_200), now: F.vienna(2026, 11, 12, 12, 0)), "morgen")
    }

    func testOffsetTitlesAndTheirSpokenForm() {
        XCTAssertEqual(RadarTimeText.offsetTitle(-600), "vor 10 Min")
        XCTAssertEqual(RadarTimeText.offsetTitle(-1800), "vor 30 Min")
        XCTAssertEqual(RadarTimeText.spokenOffset(-600), "vor 10 Minuten")
        XCTAssertEqual(RadarTimeText.spokenOffset(-60), "vor einer Minute")
        XCTAssertEqual(RadarTimeText.offsetTitle(0), "Jetzt")
        XCTAssertEqual(RadarTimeText.offsetTitle(300), "in 5 Min")
        XCTAssertEqual(RadarTimeText.offsetTitle(2700), "in 45 Min")
        XCTAssertEqual(RadarTimeText.offsetTitle(3600), "in 1 Std")
        XCTAssertEqual(RadarTimeText.offsetTitle(4500), "in 1 Std 15 Min")
        XCTAssertEqual(RadarTimeText.offsetTitle(10_800), "in 3 Std")
        XCTAssertEqual(RadarTimeText.spokenOffset(0), "jetzt")
        XCTAssertEqual(RadarTimeText.spokenOffset(300), "in 5 Minuten")
        XCTAssertEqual(RadarTimeText.spokenOffset(3600), "in einer Stunde")
        XCTAssertEqual(RadarTimeText.spokenOffset(4500), "in einer Stunde und 15 Minuten")
        XCTAssertEqual(RadarTimeText.spokenOffset(7260), "in 2 Stunden und einer Minute")
        XCTAssertEqual(RadarTimeText.spokenClock(F.vienna(2026, 11, 12, 22, 32)), "22 Uhr 32")
        XCTAssertEqual(RadarTimeText.spokenClock(F.vienna(2026, 11, 12, 22, 0)), "22 Uhr")
    }

    func testTheLinesSayWhatIsTrue() {
        XCTAssertEqual(RadarTimeText.banner, "Zeitreise · Prognose aus dem Fahrplan")
        XCTAssertEqual(RadarTimeText.banner(for: 600), RadarTimeText.banner)
        XCTAssertEqual(RadarTimeText.banner(for: -600), "Zeitreise · Rückblick aus dem Fahrplan", "the past is calculated too, not recorded")
        XCTAssertTrue(RadarTimeText.honesty(for: -600).contains("keine Aufzeichnung"))
        XCTAssertTrue(RadarTimeText.honesty(for: 600).contains("nicht vorhergesagt"))
        XCTAssertEqual(RadarTimeText.delayAge(42), "Stand der Verspätungen: vor 42 s")
        XCTAssertEqual(RadarTimeText.delayAge(2), "Stand der Verspätungen: gerade eben")
        XCTAssertEqual(RadarTimeText.delayAge(190), "Stand der Verspätungen: vor 3 Min")
        XCTAssertEqual(RadarTimeText.spokenDelayAge(42), "Stand der Verspätungen: vor 42 Sekunden")
        XCTAssertEqual(RadarTimeText.loading(loaded: 3, total: 9), "Zeitreise lädt 3/9")
        XCTAssertEqual(RadarTimeText.loading(loaded: 12, total: 9), "Zeitreise lädt 9/9")
        XCTAssertEqual(RadarTimeText.pill(count: 812, rail: true, clock: "22:32"), "812 Züge · berechnet für 22:32")
        XCTAssertEqual(RadarTimeText.pill(count: 1, rail: true, clock: "22:32"), "1 Zug · berechnet für 22:32")
        XCTAssertEqual(RadarTimeText.pill(count: 5, rail: false, clock: "22:32"), "5 Fahrzeuge · berechnet für 22:32")
        XCTAssertTrue(RadarTimeText.honesty.contains("nicht vorhergesagt"))
        XCTAssertTrue(RadarTimeText.straightLine.contains("Luftlinie"))
        XCTAssertTrue(RadarTimeText.missing(3).hasPrefix("3 Zeitpunkte"))
    }

    // MARK: Light of the day

    func testTheLightFollowsTheSun() {
        // Midsummer: noon is day, 01:00 is night, 21:30 Vienna time is dusk. Midwinter: 17:00 Vienna time is already dark.
        let noon = RadarDaylight.sample(at: F.vienna(2026, 6, 21, 13, 0))
        XCTAssertGreaterThan(noon.elevation, 55)
        XCTAssertEqual(noon.night, 0)
        XCTAssertEqual(noon.twilight, 0)
        let night = RadarDaylight.sample(at: F.vienna(2026, 6, 21, 1, 0))
        XCTAssertLessThan(night.elevation, -12)
        XCTAssertEqual(night.night, 1)
        let dusk = RadarDaylight.sample(at: F.vienna(2026, 6, 21, 21, 15))
        XCTAssertGreaterThan(dusk.twilight, 0.3, "the warm hour of a June evening")
        let winter = RadarDaylight.sample(at: F.vienna(2026, 12, 21, 17, 30))
        XCTAssertLessThan(winter.elevation, -6)
        XCTAssertGreaterThan(winter.night, 0.2)
        let winterNoon = RadarDaylight.sample(at: F.vienna(2026, 12, 21, 12, 0))
        XCTAssertEqual(winterNoon.night, 0)
        XCTAssertLessThan(winterNoon.elevation, 25, "low December sun")
    }

    func testTheEveningGrowsDarkerStepByStepAndTheValuesStayInRange() {
        var last = -1.0
        var date = F.vienna(2026, 11, 12, 15, 0)
        for _ in 0..<60 {
            let sample = RadarDaylight.sample(at: date)
            XCTAssertGreaterThanOrEqual(sample.night, last, "no flicker between two steps")
            XCTAssertTrue((0...1).contains(sample.night) && (0...1).contains(sample.twilight))
            last = sample.night
            date = date.addingTimeInterval(300)
        }
        XCTAssertEqual(last, 1, "by 20:00 in November it is night")
    }
}
