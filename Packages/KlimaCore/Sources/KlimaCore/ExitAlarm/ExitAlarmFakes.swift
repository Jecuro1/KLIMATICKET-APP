import Foundation

// Aussteige-Wecker: stand-ins for the location provider, the scheduler and the storage (docs/EXIT_ALARM.md §5). CI, the demo
// scenes and the unit tests drive the real engine with these: a scripted track, a scheduler that records what it was asked,
// and a book kept in memory. No Apple framework, no permission, no sound.

/// A location provider the test or the demo drives by hand.
public final class ScriptedLocationProvider: ExitAlarmLocationProviding {
    public var authorization: ExitAlarmLocationAuthorization
    public var isRegionMonitoringAvailable = true
    /// "Genauer Standort" off (a test or a demo scene sets it).
    public var isReducedAccuracy = false
    public weak var handler: ExitAlarmLocationHandler?
    public private(set) var isUpdating = false
    public private(set) var regions: [String: (center: GeoPoint, radius: Double)] = [:]
    public private(set) var requests: [String] = []
    public private(set) var startCount = 0
    public private(set) var stopCount = 0

    public init(authorization: ExitAlarmLocationAuthorization = .always) {
        self.authorization = authorization
    }

    public func requestWhenInUse() { requests.append("whenInUse") }
    public func requestAlways() { requests.append("always") }
    public func startUpdates() { isUpdating = true; startCount += 1 }
    public func stopUpdates() { isUpdating = false; stopCount += 1 }
    public func startMonitoring(regionID: String, center: GeoPoint, radius: Double) { regions[regionID] = (center, radius) }
    public func stopMonitoring(regionID: String) { regions[regionID] = nil }

    /// A fix arrives, as it does only while updates run.
    public func deliver(_ fix: LocationFix) {
        guard isUpdating else { return }
        handler?.locationProvider(didUpdate: fix)
    }

    /// The system reports that the circle was entered (only for a circle that is set).
    public func enterRegion(_ id: String) {
        guard regions[id] != nil else { return }
        handler?.locationProvider(didEnterRegion: id)
    }

    public func changeAuthorization(_ value: ExitAlarmLocationAuthorization) {
        authorization = value
        handler?.locationProviderDidChangeAuthorization()
    }
}

/// A scheduler that records every call. `ringing` holds what rings now.
public final class FakeAlarmScheduler: ExitAlarmScheduling {
    public var kind: ExitAlarmKind
    public var onEvent: ((ExitAlarmSchedulerEvent) -> Void)?
    /// id → the moment of the scheduled alarm.
    public private(set) var scheduled: [String: Date] = [:]
    private var scheduledContent: [String: ExitAlarmRingContent] = [:]
    public private(set) var ringing: [String: ExitAlarmRingContent] = [:]
    /// Every call in order: "schedule <id>", "cancel <id>", "ring <id>", "stop <id>".
    public private(set) var log: [String] = []
    public private(set) var rings: [ExitAlarmRingContent] = []
    /// The scheduler refuses every alarm (no permission, too many alarms): it reports `.failed` instead of keeping it.
    public var rejectsScheduling = false
    /// Like AlarmKit: an alarm that leaves the ringing state because the engine stopped, cancelled or replaced it is reported as
    /// `.stopped`, the same event as a stop by the user on the Lock Screen. The engine must tell the two apart.
    public var echoesStops = false

    public init(kind: ExitAlarmKind = .alarmKit) {
        self.kind = kind
    }

    public func schedule(_ content: ExitAlarmRingContent, at date: Date) {
        if rejectsScheduling {
            log.append("failed \(content.id)")
            onEvent?(.failed(content.id))
            return
        }
        scheduled[content.id] = date
        scheduledContent[content.id] = content
        log.append("schedule \(content.id)")
    }

    public func cancel(id: String) {
        scheduled[id] = nil
        scheduledContent[id] = nil
        log.append("cancel \(id)")
        endRinging(id)
    }

    public func ringNow(_ content: ExitAlarmRingContent) {
        endRinging(content.id)   // an alarm of the same id that rings is replaced
        ringing[content.id] = content
        rings.append(content)
        log.append("ring \(content.id)")
    }

    public func stopRinging(id: String) {
        log.append("stop \(id)")
        endRinging(id)
    }

    private func endRinging(_ id: String) {
        guard ringing[id] != nil else { return }
        ringing[id] = nil
        if echoesStops { onEvent?(.stopped(id)) }
    }

    /// The system alarm of `id` goes off (a test or a demo advances time and calls this).
    public func fireScheduled(_ id: String) {
        guard let content = scheduledContent[id] else { return }
        scheduled[id] = nil
        scheduledContent[id] = nil
        ringing[id] = content
        onEvent?(.rang(id))
    }

    /// How often the scheduler was asked to ring or schedule (a quick check for "never twice").
    public var ringCount: Int { rings.count }
}

public final class MemoryAlarmPersistence: ExitAlarmPersisting {
    public private(set) var stored: ExitAlarmBook?
    public private(set) var saveCount = 0

    public init(_ book: ExitAlarmBook? = nil) {
        self.stored = book
    }

    public func load() -> ExitAlarmBook? { stored }

    public func save(_ book: ExitAlarmBook) {
        stored = book
        saveCount += 1
    }
}

/// A scripted track along the stops of a run: fixes at a fixed interval with a speed that changes by segment, optional gaps
/// (a tunnel), a standstill and an overshoot past the end. The tests and the demo scenes use it.
public struct ExitAlarmTrack {
    public struct Segment {
        public var meters: Double
        public var speed: Double
        public var reportsSpeed: Bool
        public init(meters: Double, speed: Double, reportsSpeed: Bool = true) {
            self.meters = meters
            self.speed = speed
            self.reportsSpeed = reportsSpeed
        }
    }

    public let path: GeoPath
    public var interval: TimeInterval
    /// Metres from the start of the path where the track begins.
    public var startAlong: Double

    public init(path: [GeoPoint], interval: TimeInterval = 5, startAlong: Double = 0) {
        self.path = GeoPath(path)
        self.interval = interval
        self.startAlong = startAlong
    }

    /// Fixes of a ride that starts at `start` and follows `segments` in order. The track runs along the path; past its end it
    /// continues in the direction of the last segment (an overshoot).
    public func fixes(from start: Date, segments: [Segment], accuracy: Double = 15) -> [LocationFix] {
        var out: [LocationFix] = []
        var along = startAlong
        var time = start
        for segment in segments {
            if segment.speed <= 0 {
                // A standstill: `meters` is read as seconds.
                for _ in 0..<max(Int(segment.meters / interval), 1) {
                    time = time.addingTimeInterval(interval)
                    out.append(fix(at: along, time: time, speed: 0, reportsSpeed: segment.reportsSpeed, accuracy: accuracy))
                }
                continue
            }
            let steps = max(Int((segment.meters / segment.speed / interval).rounded()), 1)
            let step = segment.meters / Double(steps)
            for _ in 0..<steps {
                along += step
                time = time.addingTimeInterval(step / segment.speed)
                out.append(fix(at: along, time: time, speed: segment.speed, reportsSpeed: segment.reportsSpeed, accuracy: accuracy))
            }
        }
        return out
    }

    private func fix(at along: Double, time: Date, speed: Double, reportsSpeed: Bool, accuracy: Double) -> LocationFix {
        var point = path.point(at: along) ?? GeoPoint(latitude: 0, longitude: 0)
        if along > path.length, path.points.count >= 2 {
            // Past the end: carry on in the direction of the last segment.
            let a = path.points[path.points.count - 2], b = path.points[path.points.count - 1]
            let segment = max(path.cumulative[path.points.count - 1] - path.cumulative[path.points.count - 2], 1)
            let extra = (along - path.length) / segment
            point = GeoPoint(latitude: b.latitude + (b.latitude - a.latitude) * extra, longitude: b.longitude + (b.longitude - a.longitude) * extra)
        }
        return LocationFix(time: time, coordinate: point, speed: reportsSpeed ? speed : nil, horizontalAccuracy: accuracy)
    }
}
