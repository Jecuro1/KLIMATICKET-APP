import Foundation

// MARK: themes – „Bewegung“ in Look & Feel (docs/THEMES.md §4). The system setting Bewegung reduzieren always wins.

/// How much the app moves. Stored in theme.v1 – never rename a raw value.
public enum MotionLevel: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Everything as designed (docs/MOTION.md).
    case full = "voll"
    /// Transitions stay; the decoration stops: no drifting sky, no count-in, no tilt parallax, no shrinking hero.
    case calm = "ruhig"
    /// No animation at all – every screen shows its end state at once (like the CI screenshots).
    case off = "aus"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .full: "Voll"
        case .calm: "Ruhig"
        case .off: "Aus"
        }
    }

    /// What the option does, in one honest line.
    public var detail: String {
        switch self {
        case .full: "Alles bewegt sich wie gestaltet: Himmel, Zahlen, Neigung, Übergänge."
        case .calm: "Übergänge bleiben. Himmel, hochzählende Zahlen und Neigungseffekte stehen still."
        case .off: "Keine Animationen – jede Ansicht steht sofort im Endzustand."
        }
    }
}

/// What actually runs for a level and the system's Reduce Motion setting.
public struct MotionBehavior: Equatable, Sendable {
    /// The sky's slow drift and the twinkling stars.
    public var skyDrift: Bool
    /// Hero numbers count up once when a screen first appears.
    public var countIn: Bool
    /// Ticket and medals follow the phone's tilt.
    public var parallaxTilt: Bool
    /// The big hero number shrinks and slides while you scroll.
    public var heroCondenseScale: Bool
    /// Springs, slides and zooms of transitions (false: cross-fades only).
    public var movingTransitions: Bool
    /// No animation at all: every view starts in its end state (`MotionPolicy.isStatic`).
    public var isStatic: Bool

    public init(skyDrift: Bool, countIn: Bool, parallaxTilt: Bool, heroCondenseScale: Bool, movingTransitions: Bool, isStatic: Bool) {
        self.skyDrift = skyDrift
        self.countIn = countIn
        self.parallaxTilt = parallaxTilt
        self.heroCondenseScale = heroCondenseScale
        self.movingTransitions = movingTransitions
        self.isStatic = isStatic
    }

    /// The level combined with the system: Reduce Motion takes away everything it takes away under every level;
    /// a level can only take away more, never bring something back.
    public static func resolve(_ level: MotionLevel, systemReduceMotion: Bool) -> MotionBehavior {
        let decoration = level == .full && !systemReduceMotion
        return MotionBehavior(skyDrift: decoration,
                              countIn: decoration,
                              parallaxTilt: decoration,
                              heroCondenseScale: decoration,
                              movingTransitions: level != .off && !systemReduceMotion,
                              isStatic: level == .off)
    }
}
