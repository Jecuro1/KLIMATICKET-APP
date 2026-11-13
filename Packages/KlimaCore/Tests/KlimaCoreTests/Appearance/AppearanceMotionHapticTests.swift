import XCTest
@testable import KlimaCore

/// Bewegung and Haptik (docs/THEMES.md §4–5).
final class AppearanceMotionHapticTests: XCTestCase {
    // MARK: Motion

    func testFullMotionRunsEverything() {
        let b = MotionBehavior.resolve(.full, systemReduceMotion: false)
        XCTAssertEqual(b, MotionBehavior(skyDrift: true, countIn: true, parallaxTilt: true, heroCondenseScale: true,
                                         movingTransitions: true, isStatic: false))
    }

    /// Ruhig: no sky drift, no count-in, no parallax tilt, no hero condense scale – transitions stay.
    func testCalmKeepsTransitionsOnly() {
        let b = MotionBehavior.resolve(.calm, systemReduceMotion: false)
        XCTAssertFalse(b.skyDrift)
        XCTAssertFalse(b.countIn)
        XCTAssertFalse(b.parallaxTilt)
        XCTAssertFalse(b.heroCondenseScale)
        XCTAssertTrue(b.movingTransitions)
        XCTAssertFalse(b.isStatic)
    }

    func testOffIsStatic() {
        let b = MotionBehavior.resolve(.off, systemReduceMotion: false)
        XCTAssertTrue(b.isStatic)
        XCTAssertFalse(b.movingTransitions)
        XCTAssertFalse(b.skyDrift || b.countIn || b.parallaxTilt || b.heroCondenseScale)
    }

    /// The system's Bewegung reduzieren always wins: no level brings back what it takes away.
    func testSystemReduceMotionAlwaysWins() {
        for level in MotionLevel.allCases {
            let b = MotionBehavior.resolve(level, systemReduceMotion: true)
            XCTAssertFalse(b.skyDrift, "\(level)")
            XCTAssertFalse(b.countIn, "\(level)")
            XCTAssertFalse(b.parallaxTilt, "\(level)")
            XCTAssertFalse(b.heroCondenseScale, "\(level)")
            XCTAssertFalse(b.movingTransitions, "\(level): cross-fades only")
            let without = MotionBehavior.resolve(level, systemReduceMotion: false)
            XCTAssertEqual(b.isStatic, without.isStatic, "\(level): Aus stays Aus")
        }
    }

    /// A lower level never shows more than a higher one.
    func testLevelsAreOrdered() {
        func count(_ b: MotionBehavior) -> Int {
            [b.skyDrift, b.countIn, b.parallaxTilt, b.heroCondenseScale, b.movingTransitions, !b.isStatic].filter { $0 }.count
        }
        let full = count(.resolve(.full, systemReduceMotion: false))
        let calm = count(.resolve(.calm, systemReduceMotion: false))
        let off = count(.resolve(.off, systemReduceMotion: false))
        XCTAssertGreaterThan(full, calm)
        XCTAssertGreaterThan(calm, off)
        XCTAssertEqual(off, 0)
    }

    func testMotionRawValuesAreStable() {
        XCTAssertEqual(MotionLevel.allCases.map(\.rawValue), ["voll", "ruhig", "aus"])
        XCTAssertEqual(MotionLevel.allCases.map(\.title), ["Voll", "Ruhig", "Aus"])
    }

    // MARK: Haptics

    /// The table covers every case of the app's `Haptic` enum, under the same names.
    func testHapticTableCoversEveryHapticCase() throws {
        let haptics = try AppearanceRepo.source("App/Sources/DesignSystem/Motion/Haptics.swift")
        let appCases = AppearanceRepo.enumCases("Haptic", in: haptics)
        XCTAssertEqual(appCases.count, 11, "Haptics.swift: \(appCases)")
        XCTAssertEqual(Set(appCases), Set(HapticEvent.allCases.map(\.rawValue)))
        for event in HapticEvent.allCases {
            for level in HapticLevel.allCases {
                _ = HapticTable.output(event, level: level)   // total by construction; listed for the coverage report
            }
            XCTAssertFalse(HapticTable.full(event).isSilent, "\(event) plays at Voll")
        }
    }

    /// Voll is exactly what the app played before levels existed (Haptics.swift `feedback`).
    func testFullIsUnchanged() {
        XCTAssertEqual(HapticTable.output(.tap, level: .full), .impact(.light, intensity: 0.7))
        XCTAssertEqual(HapticTable.output(.snap, level: .full), .impact(.medium, intensity: 0.85))
        XCTAssertEqual(HapticTable.output(.selection, level: .full), .selection)
        XCTAssertEqual(HapticTable.output(.milestone, level: .full), .levelChange)
        XCTAssertEqual(HapticTable.output(.success, level: .full), .success)
    }

    /// Voll plays exactly what `Haptic.feedback` in Haptics.swift says (the debug gallery and the pre-level behaviour).
    func testFullMatchesHapticsSwift() throws {
        let haptics = try AppearanceRepo.source("App/Sources/DesignSystem/Motion/Haptics.swift")
        func source(_ output: HapticOutput) -> String {
            switch output {
            case .none: return "nil"
            case .success: return ".success"
            case .warning: return ".warning"
            case .error: return ".error"
            case .selection: return ".selection"
            case let .impact(weight, intensity):
                let name = weight == .light ? "light" : (weight == .medium ? "medium" : "heavy")
                return ".impact(weight: .\(name), intensity: \(intensity))"
            case .increase: return ".increase"
            case .decrease: return ".decrease"
            case .levelChange: return ".levelChange"
            case .start: return ".start"
            case .stop: return ".stop"
            }
        }
        for event in HapticEvent.allCases {
            let line = "case .\(event.rawValue): \(source(HapticTable.full(event)))"
            XCTAssertTrue(haptics.contains(line), "Haptics.swift has no \(line)")
        }
    }

    /// Dezent lowers impacts one step and drops selection ticks; everything else stays.
    func testSubtleLowersImpactsAndDropsTicks() {
        XCTAssertEqual(HapticTable.output(.selection, level: .subtle), .none)
        XCTAssertEqual(HapticTable.output(.snap, level: .subtle), .impact(.light, intensity: 0.85))
        XCTAssertEqual(HapticTable.output(.tap, level: .subtle), .impact(.light, intensity: HapticTable.subtleLightIntensity))
        for event in HapticEvent.allCases where ![.selection, .tap, .snap].contains(event) {
            XCTAssertEqual(HapticTable.output(event, level: .subtle), HapticTable.full(event), "\(event)")
        }
        for event in HapticEvent.allCases {
            if case let .impact(subtleWeight, subtleIntensity) = HapticTable.output(event, level: .subtle),
               case let .impact(fullWeight, fullIntensity) = HapticTable.full(event) {
                XCTAssertTrue(subtleWeight < fullWeight || subtleIntensity < fullIntensity, "\(event) is lower")
            }
        }
    }

    func testOffIsSilent() {
        for event in HapticEvent.allCases {
            XCTAssertTrue(HapticTable.output(event, level: .off).isSilent, "\(event)")
        }
    }

    /// Migration of the old switch: false → Aus, true and never set → Voll.
    func testHapticsEnabledMigration() {
        XCTAssertEqual(HapticLevel.migrated(hapticsEnabled: false), .off)
        XCTAssertEqual(HapticLevel.migrated(hapticsEnabled: true), .full)
        XCTAssertEqual(HapticLevel.migrated(hapticsEnabled: nil), .full)
        XCTAssertEqual(AppearancePrefs.load(nil, legacyHapticsEnabled: false).haptics, .off)
        XCTAssertEqual(AppearancePrefs.load(nil, legacyHapticsEnabled: nil).haptics, .full)
        // Once theme.v1 exists it wins over the old switch.
        let stored = AppearancePrefs(haptics: .subtle).encoded()
        XCTAssertEqual(AppearancePrefs.load(stored, legacyHapticsEnabled: false).haptics, .subtle)
    }
}
