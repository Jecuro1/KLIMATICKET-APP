import Foundation

// Cockpit-Ansicht, part 3: the camera (docs/RADAR_COCKPIT.md). Pure and deterministic: a target camera from the train, its speed and the
// route, and a controller that glides the camera to it (heading low-pass filtered so it does not whip at curves). The app only reads the
// result and hands it to `MapCamera`; nothing here knows MapKit.

/// The three ways to look at the train.
public enum CockpitCameraMode: String, Sendable, Hashable, CaseIterable {
    /// Behind and above the train, tilted, looking along the direction of travel. A fast train is shown further out.
    case follow
    /// From above, north up.
    case bird
    /// The user pans and zooms.
    case free

    public var title: String {
        switch self {
        case .follow: "Verfolgen"
        case .bird: "Vogelperspektive"
        case .free: "Frei"
        }
    }

    /// Follow and bird are driven by the app; free belongs to the user.
    public var isDriven: Bool { self != .free }
}

public struct CockpitCameraConfig: Sendable, Equatable {
    // Follow: how far out and how steep.
    /// Distance of the camera from the point it looks at, metres: `followBase` at a standstill plus `followPerKmh` per km/h, within the limits.
    public var followBase = 1_500.0
    public var followPerKmh = 26.0
    public var followMin = 1_500.0
    public var followMax = 8_500.0
    /// Pitch (0 = straight down) at a standstill and at `fastKmh`: closer in and steeper-looking when slow, a little flatter when fast.
    public var pitchSlow = 68.0
    public var pitchFast = 60.0
    public var fastKmh = 200.0
    /// The speed assumed while it is unknown (no two answers yet).
    public var cruiseKmh = 100.0

    // Bird: a multiple of the follow distance, within limits.
    public var birdScale = 2.2
    public var birdMin = 3_500.0
    public var birdMax = 16_000.0

    // Where the camera looks.
    /// The point the camera looks at is this many seconds of travel ahead of the train (within the limits, kilometres), so the train sits
    /// in the lower part of the picture and the track ahead fills the rest.
    public var lookAheadSeconds = 7.0
    public var lookAheadMinKm = 0.15
    public var lookAheadMaxKm = 1.4
    /// The heading looks this far ahead along the route, so a curve a few hundred metres on already turns the camera.
    public var headingLookKm = 0.6

    // Smoothing: time constants in seconds; a channel moves `1 - exp(-dt / tau)` of the remaining way each step.
    public var headingTau = 1.6
    /// The heading never turns faster than this, degrees per second.
    public var headingMaxRate = 28.0
    public var pitchTau = 0.8
    public var distanceTau = 2.4
    public var centerTau = 0.4

    public init() {}

    public static let standard = CockpitCameraConfig()
}

/// What MapKit's camera needs.
public struct CockpitCamera: Sendable, Equatable {
    public var center: GeoPoint
    /// Metres from the centre point to the camera.
    public var distance: Double
    /// Degrees clockwise from north.
    public var heading: Double
    /// Degrees from straight down (0) towards the horizon.
    public var pitch: Double

    public init(center: GeoPoint, distance: Double, heading: Double = 0, pitch: Double = 0) {
        self.center = center
        self.distance = distance
        self.heading = heading
        self.pitch = pitch
    }
}

/// What the planner needs to know now.
public struct CockpitCameraInput: Sendable {
    /// The train's position now (the estimate between two answers).
    public var train: GeoPoint
    /// Along the route, when it is known.
    public var trainKm: Double?
    public var path: CockpitPath?
    /// nil: unknown. 0: standing.
    public var speedKmh: Double?
    /// The position a moment ago (for the heading when there is no route).
    public var previous: GeoPoint?
    public var nextStop: GeoPoint?
    public var mode: CockpitCameraMode
    /// No swooping camera: a fixed top-down view, north up.
    public var reduceMotion: Bool

    public init(train: GeoPoint, trainKm: Double? = nil, path: CockpitPath? = nil, speedKmh: Double? = nil, previous: GeoPoint? = nil,
                nextStop: GeoPoint? = nil, mode: CockpitCameraMode = .follow, reduceMotion: Bool = false) {
        self.train = train
        self.trainKm = trainKm
        self.path = path
        self.speedKmh = speedKmh
        self.previous = previous
        self.nextStop = nextStop
        self.mode = mode
        self.reduceMotion = reduceMotion
    }
}

public enum CockpitCameraPlanner {
    /// Distance for the follow camera: further out for a faster train, within the limits. Never decreases with speed.
    public static func followDistance(speedKmh: Double?, config: CockpitCameraConfig = .standard) -> Double {
        let speed = max(speedKmh ?? config.cruiseKmh, 0)
        return min(max(config.followBase + config.followPerKmh * speed, config.followMin), config.followMax)
    }

    /// Distance for the bird's-eye view.
    public static func birdDistance(speedKmh: Double?, config: CockpitCameraConfig = .standard) -> Double {
        min(max(followDistance(speedKmh: speedKmh, config: config) * config.birdScale, config.birdMin), config.birdMax)
    }

    /// Pitch for the follow camera: `pitchSlow` at a standstill down to `pitchFast` at `fastKmh`.
    public static func followPitch(speedKmh: Double?, config: CockpitCameraConfig = .standard) -> Double {
        let speed = max(speedKmh ?? config.cruiseKmh, 0)
        let t = min(speed / max(config.fastKmh, 1), 1)
        return config.pitchSlow + (config.pitchFast - config.pitchSlow) * t
    }

    /// Kilometres ahead of the train that the camera looks at: `lookAheadSeconds` of travel, within the limits.
    public static func lookAheadKm(speedKmh: Double?, config: CockpitCameraConfig = .standard) -> Double {
        let speed = max(speedKmh ?? config.cruiseKmh, 0)
        return min(max(speed / 3600 * config.lookAheadSeconds, config.lookAheadMinKm), config.lookAheadMaxKm)
    }

    /// The direction of travel: along the route when there is one, else from the previous position when the train moved, else towards the
    /// next stop. nil when nothing tells (the camera keeps its heading).
    public static func travelHeading(_ input: CockpitCameraInput, config: CockpitCameraConfig = .standard) -> Double? {
        if let path = input.path, let km = input.trainKm {
            return path.bearing(atKm: km, lookKm: config.headingLookKm)
        }
        if let previous = input.previous, previous.distanceKm(to: input.train) >= 0.04 {
            return RadarBearing.degrees(from: previous, to: input.train)
        }
        if let next = input.nextStop, next.distanceKm(to: input.train) >= 0.04 {
            return RadarBearing.degrees(from: input.train, to: next)
        }
        return nil
    }

    /// The target camera, before any smoothing. `fallbackHeading` is used when the direction of travel is unknown.
    public static func target(for input: CockpitCameraInput, fallbackHeading: Double = 0, config: CockpitCameraConfig = .standard) -> CockpitCamera {
        // Reduce Motion, and the bird's-eye view: straight down, north up, the train in the middle.
        if input.reduceMotion || input.mode == .bird {
            return CockpitCamera(center: input.train, distance: birdDistance(speedKmh: input.speedKmh, config: config), heading: 0, pitch: 0)
        }
        let heading = travelHeading(input, config: config) ?? fallbackHeading
        let ahead = lookAheadKm(speedKmh: input.speedKmh, config: config)
        let center: GeoPoint
        if let path = input.path, let km = input.trainKm {
            center = path.point(atKm: km + ahead)
        } else {
            center = CockpitGeo.destination(from: input.train, bearing: heading, km: ahead)
        }
        return CockpitCamera(center: center, distance: followDistance(speedKmh: input.speedKmh, config: config), heading: heading,
                             pitch: followPitch(speedKmh: input.speedKmh, config: config))
    }
}

/// Glides the camera to the target. One value per cockpit; the app calls `step` a few times a second with the time since the last call.
public struct CockpitCameraController: Sendable {
    public private(set) var camera: CockpitCamera?
    private let config: CockpitCameraConfig
    private var lastHeadingTarget = 0.0

    public init(config: CockpitCameraConfig = .standard) {
        self.config = config
    }

    /// Starts from a given camera (the user's free camera when "Zurück zum Zug" is tapped) so the glide begins where the picture is. nil: the
    /// next step starts at its target.
    public mutating func reset(to camera: CockpitCamera? = nil) {
        self.camera = camera
        if let camera { lastHeadingTarget = camera.heading }
    }

    /// One step of `dt` seconds. The first step (no camera yet) and every step under Reduce Motion land on the target at once.
    public mutating func step(_ input: CockpitCameraInput, dt: TimeInterval) -> CockpitCamera {
        let heading = CockpitCameraPlanner.travelHeading(input, config: config)
        if let heading { lastHeadingTarget = heading }
        let target = CockpitCameraPlanner.target(for: input, fallbackHeading: lastHeadingTarget, config: config)
        guard let current = camera, !input.reduceMotion, dt.isFinite, dt > 0 else {
            camera = target
            return target
        }
        func share(_ tau: Double) -> Double { 1 - exp(-dt / max(tau, 0.01)) }

        // The heading turns the short way, by a share of the remaining turn, never faster than the rate limit.
        let turn = CockpitAngle.delta(from: current.heading, to: target.heading)
        let wanted = turn * share(config.headingTau)
        let limit = config.headingMaxRate * dt
        let heading2 = CockpitAngle.normalized(current.heading + min(max(wanted, -limit), limit))

        let c = share(config.centerTau)
        let center = CockpitGeo.lerp(current.center, target.center, c)
        let next = CockpitCamera(center: center,
                                 distance: current.distance + (target.distance - current.distance) * share(config.distanceTau),
                                 heading: heading2,
                                 pitch: current.pitch + (target.pitch - current.pitch) * share(config.pitchTau))
        camera = next
        return next
    }

    /// Seconds between camera updates: 20 a second normally, 8 in Low Power Mode.
    public static func frameInterval(lowPower: Bool) -> TimeInterval { lowPower ? 0.125 : 0.05 }
}
