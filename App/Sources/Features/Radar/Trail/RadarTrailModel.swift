import SwiftUI
import KlimaCore

// MARK: radar2-radartrail – „Spuren“ (docs/RADAR_TRAILS.md, specs/radar2/radartrail.md). The radar's short memory: every answer the live loop merged
// (`Radar2Parts.didMerge`) adds one sample per vehicle at its request time, in memory only. Nothing is asked for it, nothing is written but the
// setting, and everything goes with the radar view (this model is part of `RadarModel`, which is `@State` of `RadarView`), when the access closes
// (`end(.accessClosed)`) and when the setting is „Aus“. Offline keeps the samples for the return (nothing arrives meanwhile: a gap).

@MainActor
@Observable
final class RadarTrailModel {
    /// „Spuren“ and „Länge“ of the Darstellung page.
    private(set) var setting: RadarTrailSetting
    /// Moves with every change of what is recorded: the map and the trip sheet's row read it, so they redraw with a new answer.
    private(set) var revision = 0

    @ObservationIgnored private var recorder: RadarTrailRecorder
    /// The thinned lines per trip, until a new answer, another moment or another zoom (only the drawn point is added on every redraw).
    @ObservationIgnored private var cache: [String: Cached] = [:]
    /// Demo only: the tiles whose synthetic history was filled in, and the city fleets' history being computed.
    @ObservationIgnored private var prefilledTiles: Set<RadarTileKey> = []
    @ObservationIgnored private var cityPrefill: Task<Void, Never>?

    private struct Cached {
        var revision: Int
        var first: Date
        var last: Date
        var bucket: Int
        var runs: [[RadarTrailPoint]]
    }

    /// „Spuren“ reach everyone once their screenshots are reviewed; until then only screenshot and perf launches see and record them.
    static var isAvailable: Bool { LaunchMode.isSandboxed }

    init(setting: RadarTrailSetting? = nil) {
        var setting = setting ?? RadarTrailSettingStore.load()
        if !Self.isAvailable { setting.mode = .off }
        self.setting = setting
        recorder = RadarTrailRecorder(window: setting.window)
    }

    // MARK: The seam (Radar2Parts)

    /// One answer the live loop merged: its vehicles at its request time. Nothing while „Aus“.
    func didMerge(_ event: RadarAnswerEvent) {
        guard setting.mode != .off else { return }
        prefillDemo(for: event)
        recorder.record(event.vehicles, at: event.requestedAt)
        revision &+= 1
    }

    /// A mode was switched off: its vehicles' trails go at once.
    func didRemove(products mask: ProductMask) {
        guard !recorder.isEmpty else { return }
        recorder.remove(products: mask)
        cache = [:]
        revision &+= 1
    }

    /// The access closed (no consent, „Live-Fahrplan“ off, kill switch, Offline-Modus): everything goes.
    func end(_ reason: RadarEndReason) {
        clear()
    }

    // MARK: Setting

    /// A new choice on the Darstellung page. „Aus“ forgets everything and stops recording; a shorter length drops what is older at once.
    func update(_ new: RadarTrailSetting) {
        guard Self.isAvailable, new != setting else { return }
        setting = new
        RadarTrailSettingStore.save(new)
        if new.mode == .off {
            clear()
            return
        }
        recorder.window = new.window
        if let latest = recorder.latestAt { recorder.prune(now: latest) }
        cache = [:]
        revision &+= 1
    }

    private func clear() {
        cityPrefill?.cancel()
        cityPrefill = nil
        recorder.clear()
        cache = [:]
        prefilledTiles = []
        revision &+= 1
    }

    // MARK: Reading

    /// The first answer recorded since the radar opened (the caption's „seit“).
    var firstRecordedAt: Date? {
        _ = revision
        return recorder.firstRecordedAt
    }

    /// Something is held for this trip (away from now: whether its trail would come back at „Jetzt“).
    func holds(_ tripID: String?) -> Bool {
        _ = revision
        guard let tripID else { return false }
        return recorder.revision(of: tripID) != nil
    }

    var holdsAnything: Bool {
        _ = revision
        return !recorder.isEmpty
    }

    /// „Verspätung, seit du zuschaust“ of one vehicle.
    func series(for tripID: String) -> RadarDelaySeries {
        _ = revision
        return RadarDelaySeries(samples: recorder.samples(for: tripID))
    }

    /// The trail of one vehicle for the chosen length, ending at `drawnPoint` (the marker, drawn at the moment `until`).
    func lines(for tripID: String, until: Date, drawnPoint: GeoPoint, spanDegrees: Double, heightPoints: Double) -> [RadarTrailLine] {
        _ = revision
        guard let tripRevision = recorder.revision(of: tripID) else { return [] }
        let start = until.addingTimeInterval(-setting.length)
        let samples = recorder.samples(for: tripID).filter { $0.from <= until && $0.to >= start }
        guard let first = samples.first?.from, let last = samples.last?.from else { return [] }
        let scale = RadarTrailGeometry.metersPerPoint(spanDegrees: spanDegrees, heightPoints: heightPoints)
        // Zoom buckets of half an octave: a small zoom keeps the thinned line, the tolerance is the bucket's.
        let bucket = Int((log2(max(scale, 0.01)) * 2).rounded())
        let runs: [[RadarTrailPoint]]
        if let cached = cache[tripID], cached.revision == tripRevision, cached.first == first, cached.last == last, cached.bucket == bucket {
            runs = cached.runs
        } else {
            runs = RadarTrailGeometry.simplifiedRuns(for: samples, until: until, metersPerPoint: pow(2, Double(bucket) / 2))
            cache[tripID] = Cached(revision: tripRevision, first: first, last: last, bucket: bucket, runs: runs)
        }
        return RadarTrailGeometry.finish(runs, until: until, drawnPoint: drawnPoint, metersPerPoint: scale)
    }

    /// Drops cached lines of trips that are not drawn any more (called with the trips drawn now).
    func keepCache(for tripIDs: Set<String>) {
        guard cache.count > tripIDs.count + 20 else { return }
        cache = cache.filter { tripIDs.contains($0.key) }
    }

    // MARK: Demo

    /// Demo and screenshot launches only, and only for synthetic vehicles (`demo|…`): the minutes before the radar opened, so a trail shows at
    /// once. Corridor trains from their invented timetable, the city fleets from the clock they run on (computed off the main actor).
    private func prefillDemo(for event: RadarAnswerEvent) {
        guard RadarTrailDemo.prefills, !prefilledTiles.contains(event.tile) else { return }
        let ids = Set(event.vehicles.lazy.map(\.tripID).filter(RadarTrailDemo.isSynthetic))
        guard !ids.isEmpty else { return }
        prefilledTiles.insert(event.tile)
        for answer in RadarTrailDemo.corridorHistory(ids: ids, now: event.requestedAt) {
            recorder.record(answer.vehicles, at: answer.at)
        }
        guard cityPrefill == nil, ids.contains(where: RadarTrailDemo.isCity) else { return }
        let now = event.requestedAt
        let around = RadarTileGrid.box(of: event.tile).center
        cityPrefill = Task { [weak self] in
            let history = await Task.detached(priority: .utility) { RadarTrailDemo.cityHistory(around: around, now: now) }.value
            guard let self, !Task.isCancelled, self.setting.mode != .off else { return }
            for answer in history { self.recorder.record(answer.vehicles, at: answer.at) }
            self.revision &+= 1
        }
    }
}
