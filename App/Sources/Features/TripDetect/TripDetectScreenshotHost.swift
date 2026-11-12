import SwiftUI
import SwiftData
import KlimaCore

// MARK: tripdetect – CI scenes of the trip detection (`-KBScreenshot <screen> -KBDemo YES`): synthetic tracks and proposals, no
// network, no system permission alert (the recorder and the service never ask in a sandboxed run).
// - `tripDetectInbox` / `tripDetectInboxAX5`: the "Fahrten-Vorschläge" with three proposals (Sicher, Wahrscheinlich, Vielleicht)
// - `tripDetectRecord`: a recording in progress (map line, time, distance, speed, station) · `tripDetectRecordIdle`: before the start
// - `tripDetectReview`: the proposal after "Beenden" · `tripDetectExplain`: the explanation screen
// - `tripDetectSettings` / `tripDetectSettingsOff`: Einstellungen › Fahrten erkennen · `tripDetectLog`: the Erkennungs-Protokoll
// - `tripDetectEdit`: "Bearbeiten" of a proposal · `tripDetectActivity`: the Live Activity "Aufzeichnung läuft" (Sperrbildschirm und Dynamic Island)
// - MARK: review2-tripdetect – `tripDetectRecordReduced`: "Genauer Standort ist aus" on the live screen · `tripDetectRecordAutoStop`: a recording that
//   ended by itself, with its proposal · `tripDetectRecordInterrupted`: "Letzte Aufzeichnung unterbrochen" · `tripDetectSettingsReduced`

struct TripDetectScreenshotHost: View {
    static let screens: Set<String> = [
        "tripDetectInbox", "tripDetectInboxAX5", "tripDetectRecord", "tripDetectRecordIdle", "tripDetectReview", "tripDetectExplain",
        "tripDetectSettings", "tripDetectSettingsOff", "tripDetectLog", "tripDetectEdit", "tripDetectActivity",
        // MARK: review2-tripdetect
        "tripDetectRecordReduced", "tripDetectRecordAutoStop", "tripDetectRecordInterrupted", "tripDetectSettingsReduced",
    ]

    let screen: String

    @Environment(AppState.self) private var app
    @State private var candidates: [TripCandidateEntity] = []
    @State private var recorder: TripRecorder?

    var body: some View {
        Group {
            switch screen {
            case "tripDetectInbox", "tripDetectInboxAX5":
                inbox
            case "tripDetectRecord":
                if let recorder { TripRecordView(recorder: recorder) } else { Color.clear.ambientBackground() }
            case "tripDetectRecordIdle":
                TripRecordView(recorder: TripRecorder())
            // MARK: review2-tripdetect
            case "tripDetectRecordReduced":
                if let recorder { TripRecordView(recorder: recorder) } else { Color.clear.ambientBackground() }
            case "tripDetectRecordAutoStop":
                review
            case "tripDetectRecordInterrupted":
                if let recorder { TripRecordView(recorder: recorder) } else { Color.clear.ambientBackground() }
            case "tripDetectSettingsReduced":
                NavigationStack { TripDetectSettingsView(preview: TripDetectDemo.settingsReduced) }
            case "tripDetectReview":
                review
            case "tripDetectExplain":
                TripDetectExplainView(onEnable: {}, onCancel: {})
            case "tripDetectSettings":
                NavigationStack { TripDetectSettingsView(preview: TripDetectDemo.settingsOn) }
            case "tripDetectSettingsOff":
                NavigationStack { TripDetectSettingsView(preview: TripDetectDemo.settingsOff) }
            case "tripDetectLog":
                NavigationStack { TripDetectLogView(preview: TripDetectDemo.logEntries(now: Date())) }
            case "tripDetectEdit":
                edit
            case "tripDetectActivity":
                activity
            default:
                Color.clear.ambientBackground()
            }
        }
        .dynamicTypeSize(screen == "tripDetectInboxAX5" ? .accessibility5 : .large)
        .onAppear(perform: prepare)
    }

    // MARK: Scenes

    private var inbox: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker(text: Format.weekdayDayMonth(Date()))
                        Text("Übersicht").font(Theme.Typography.heroTitle).foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.horizontal, DashStyle.headerInset)
                    TripInboxSection(candidates: candidates)
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.m)
            }
            .background { Color.clear.ambientBackground() }
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var review: some View {
        if let recorder, let candidate = candidates.first {
            TripRecordView(recorder: recorder, previewReview: candidate)
        } else {
            Color.clear.ambientBackground()
        }
    }

    /// The Live Activity of a recording at lock-screen size, with the compact and expanded Dynamic Island below it.
    private var activity: some View {
        let attributes = RecordingActivityAttributes(startedAt: Date().addingTimeInterval(-(23 * 60 + 10)))
        let state = RecordingActivityAttributes.ContentState(distanceKm: 34.2, speedKmh: 92, stationName: "Stams", isAtStation: false)
        // After "Beenden": the timer stands still at the moment of stopping (it does not count on until the activity is dismissed).
        let stopped = RecordingActivityAttributes.ContentState(distanceKm: 28.4, speedKmh: 0, stationName: "Telfs-Pfaffenhofen", isAtStation: true, isStopped: true,
                                                               stoppedAt: attributes.startedAt.addingTimeInterval(22 * 60 + 40))
        // MARK: review2-tripdetect – the app has sent nothing for two minutes (process ended, or no GPS): the timer stands still, nothing is claimed.
        let staleState = RecordingActivityAttributes.ContentState(distanceKm: 34.2, speedKmh: 92, stationName: "Stams", isAtStation: false,
                                                                  updatedAt: attributes.startedAt.addingTimeInterval(19 * 60 + 5))
        return ZStack {
            Color.clear.ambientBackground()
            VStack(spacing: Theme.Spacing.m) {
                RecordingLockScreenView(attributes: attributes, state: state)
                    .background(Theme.background.opacity(0.92), in: .rect(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                RecordingLockScreenView(attributes: attributes, state: stopped)
                    .background(Theme.background.opacity(0.92), in: .rect(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                RecordingLockScreenView(attributes: attributes, state: staleState, isStale: true)
                    .background(Theme.background.opacity(0.92), in: .rect(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                VStack(spacing: Theme.Spacing.xs) {
                    HStack {
                        RecordingIslandLeading()
                        Spacer()
                        RecordingIslandTimer(attributes: attributes)
                    }
                    .padding(.horizontal, 18)
                    .frame(width: 170, height: 38)
                    .background(.black, in: .capsule)
                    .foregroundStyle(.white)
                    VStack(spacing: 8) {
                        HStack {
                            RecordingIslandLeading()
                            Spacer()
                            Text("Aufzeichnung läuft").font(.headline)
                            Spacer()
                            RecordingIslandTimer(attributes: attributes)
                        }
                        RecordingIslandBottom(state: state)
                    }
                    .padding(18)
                    .frame(width: 340)
                    .background(.black, in: .rect(cornerRadius: 36, style: .continuous))
                    .foregroundStyle(.white)
                }
            }
        }
    }

    @ViewBuilder
    private var edit: some View {
        if let candidate = candidates.first {
            TripCandidateEditSheet(candidate: candidate, initial: TripDetectDemo.stations(for: candidate, in: app.stations))
        } else {
            Color.clear.ambientBackground()
        }
    }

    private func prepare() {
        guard candidates.isEmpty else { return }
        let all = TripDetectDemo.candidates(now: Date())
        switch screen {
        case "tripDetectInbox", "tripDetectInboxAX5": candidates = all
        case "tripDetectReview", "tripDetectRecordAutoStop": candidates = [TripDetectDemo.recordedCandidate(now: Date())]
        case "tripDetectEdit": candidates = [all[1]]
        default: break
        }
        if screen == "tripDetectRecord" || screen == "tripDetectReview" { recorder = TripDetectDemo.recorder(lookup: app.stations, finished: screen == "tripDetectReview") }
        // MARK: review2-tripdetect
        switch screen {
        case "tripDetectRecordReduced":
            // The first minutes of a recording that never finds a usable fix: no track, "Genauer Standort" off.
            let started = Date().addingTimeInterval(-95)
            let demo = TripRecorder.demo(lookup: app.stations, track: [], startedAt: started, until: 0)
            demo.demoState(accuracyIsReduced: true)
            recorder = demo
        case "tripDetectRecordAutoStop":
            // The phone stayed in the pocket after the ride: the recording ended by itself, the proposal ends with the ride.
            let demo = TripDetectDemo.recorder(lookup: app.stations, finished: true)
            demo.demoState(autoStop: .idle(since: Date().addingTimeInterval(-32 * 60)))
            recorder = demo
        case "tripDetectRecordInterrupted":
            let demo = TripRecorder()
            demo.demoState(interruptedStart: Date().addingTimeInterval(-3 * 3600))
            recorder = demo
        default: break
        }
    }
}

// MARK: - Synthetic data

enum TripDetectDemo {
    static let innsbruck = "at:47:1187", landeck = "at:47:1212", feldkirch = "at:48:817", bregenz = "at:48:452"
    static let wien = "at:49:1349", stPoelten = "at:43:4848"

    private static func rank(from: Station, to: Station, fromMeters: Double, toMeters: Double, km: Double, speed: Double, relation: Bool,
                             halts: Int = 0, timetable: TimetableVerdict = .unavailable) -> CandidateRank {
        CandidateRanking.rank(CandidateEvidence(source: .background, from: StationMatch(station: from, distanceMeters: fromMeters),
                                                to: StationMatch(station: to, distanceMeters: toMeters), straightKm: km, averageSpeedKmh: speed,
                                                knownRelation: relation, intermediateHalts: halts, timetable: timetable))
    }

    /// Three proposals: Wahrscheinlich (Innsbruck → Landeck), Sicher (Feldkirch → Bregenz, with the timetable), Vielleicht (Wien → St. Pölten).
    @MainActor
    static func candidates(now: Date) -> [TripCandidateEntity] {
        let cal = Calendar.vienna
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now)) ?? now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let ibk = Station(id: innsbruck, name: "Innsbruck Hauptbahnhof", lat: 47.26353, lon: 11.40028, state: "T")
        let lan = Station(id: landeck, name: "Landeck-Zams", lat: 47.14842, lon: 10.57828, state: "T")
        let fk = Station(id: feldkirch, name: "Feldkirch", lat: 47.2416, lon: 9.60493, state: "V")
        let bg = Station(id: bregenz, name: "Bregenz", lat: 47.50237, lon: 9.73977, state: "V")
        let wi = Station(id: wien, name: "Wien Hauptbahnhof", lat: 48.18519, lon: 16.37641, state: "W")
        let sp = Station(id: stPoelten, name: "St. Pölten Hauptbahnhof", lat: 48.20819, lon: 15.62404, state: "NÖ")

        func entity(_ from: Station, _ to: Station, _ dep: Date, _ arr: Date, km: Double, rank: CandidateRank, track: [GeoPoint], line: String = "") -> TripCandidateEntity {
            let e = TripCandidateEntity(source: .background, fromName: from.name, toName: to.name, fromStationID: from.id, toStationID: to.id, mode: .train,
                                        departedAt: dep, arrivedAt: arr, straightKm: km, confidence: rank.confidence,
                                        sketch: RouteSketch.make(from: from.location, to: to.location, track: track),
                                        reasons: rank.reasons, carNotExcluded: rank.carNotExcluded)
            e.score = rank.score
            e.timetableLine = line
            return e
        }
        // The line between the stations, a little bent (invented course).
        func bent(_ a: Station, _ b: Station, bend: Double) -> [GeoPoint] {
            (1...4).map { i in
                let t = Double(i) / 5
                let p = DetectionGeo.lerp(a.location, b.location, t)
                return GeoPoint(latitude: p.latitude + sin(t * .pi) * bend, longitude: p.longitude)
            }
        }
        let km1 = ibk.location.distanceKm(to: lan.location), km2 = fk.location.distanceKm(to: bg.location), km3 = wi.location.distanceKm(to: sp.location)
        let first = entity(ibk, lan, at(0, 7, 48), at(0, 8, 55), km: km1,
                           rank: rank(from: ibk, to: lan, fromMeters: 60, toMeters: 90, km: km1, speed: 56, relation: true), track: bent(ibk, lan, bend: 0.05))
        let connection = TimetableConnection(departure: at(-1, 17, 12), arrival: at(-1, 17, 41), line: "REX 5429")
        let second = entity(fk, bg, at(-1, 17, 14), at(-1, 17, 40), km: km2,
                            rank: rank(from: fk, to: bg, fromMeters: 70, toMeters: 110, km: km2, speed: 62, relation: true, timetable: .confirmed(connection)),
                            track: bent(fk, bg, bend: -0.02), line: connection.summary)
        let third = entity(wi, sp, at(-2, 12, 5), at(-2, 12, 50), km: km3,
                           rank: rank(from: wi, to: sp, fromMeters: 430, toMeters: 470, km: km3, speed: 78, relation: true), track: [])
        return [first, second, third]
    }

    /// The proposal of a finished recording (no label: nobody asks whether a recorded ride was a ride).
    @MainActor
    static func recordedCandidate(now: Date) -> TripCandidateEntity {
        let ibk = Station(id: innsbruck, name: "Innsbruck Hauptbahnhof", lat: 47.26353, lon: 11.40028, state: "T")
        let lan = Station(id: landeck, name: "Landeck-Zams", lat: 47.14842, lon: 10.57828, state: "T")
        let track = (1...5).map { i -> GeoPoint in
            let t = Double(i) / 6
            let p = DetectionGeo.lerp(ibk.location, lan.location, t)
            return GeoPoint(latitude: p.latitude + sin(t * .pi) * 0.04, longitude: p.longitude)
        }
        return TripCandidateEntity(source: .recording, fromName: ibk.name, toName: lan.name, fromStationID: ibk.id, toStationID: lan.id, mode: .train,
                                   departedAt: now.addingTimeInterval(-62 * 60), arrivedAt: now.addingTimeInterval(-2 * 60),
                                   straightKm: ibk.location.distanceKm(to: lan.location), confidence: .sicher,
                                   sketch: RouteSketch.make(from: ibk.location, to: lan.location, track: track), carNotExcluded: false)
    }

    /// A recording of the Inntalbahn Innsbruck → Landeck (invented speeds), taken in at once up to 55 %.
    @MainActor
    static func recorder(lookup: any StationLookup, finished: Bool) -> TripRecorder {
        let points: [GeoPoint] = [GeoPoint(latitude: 47.26353, longitude: 11.40028), GeoPoint(latitude: 47.2661, longitude: 11.22985),
                                  GeoPoint(latitude: 47.3004, longitude: 11.079), GeoPoint(latitude: 47.27006, longitude: 10.93665),
                                  GeoPoint(latitude: 47.21924, longitude: 10.76182), GeoPoint(latitude: 47.14842, longitude: 10.57828)]
        let start = Date().addingTimeInterval(-52 * 60)
        let track = ScriptedTrack.ride(waypoints: points, start: start, cruiseKmh: 92, interval: 10, halts: [1: 50, 2: 50, 3: 50, 4: 50, 5: 60])
        if finished {
            let recorder = TripRecorder.demo(lookup: lookup, track: track, startedAt: start, until: track.count)
            recorder.stop(now: track.last?.time ?? Date())
            return recorder
        }
        // Mid-ride, after the second stop: the train is moving at cruising speed and the last station is behind it.
        var stops = 0, until = Int(Double(track.count) * 0.5)
        for index in track.indices.dropFirst() where (track[index - 1].speedMetersPerSecond ?? 0) == 0 && (track[index].speedMetersPerSecond ?? 0) > 10 {
            stops += 1
            if stops == 3 { until = min(track.count, index + 12); break }
        }
        return TripRecorder.demo(lookup: lookup, track: track, startedAt: start, until: until)
    }

    @MainActor
    static func stations(for candidate: TripCandidateEntity, in index: StationIndex) -> CandidateStations {
        CandidateStations(from: candidate.fromStationID.flatMap { index.station(id: $0) }, to: candidate.toStationID.flatMap { index.station(id: $0) })
    }

    static let settingsOn = TripDetectSettingsState(isEnabled: true, isAuthorizedAlways: true, points: 14, visits: 3,
                                                    oldest: Date().addingTimeInterval(-19 * 3600), logCount: 7, timetableLookup: true, liveConsentGranted: true)
    // MARK: review2-tripdetect
    static let settingsReduced = TripDetectSettingsState(isEnabled: true, isAuthorizedAlways: true, isReducedAccuracy: true, points: 0, visits: 0,
                                                         logCount: 2, timetableLookup: true, liveConsentGranted: true)
    static let settingsOff = TripDetectSettingsState(isEnabled: false, isAuthorizedAlways: false, logCount: 0, timetableLookup: true, liveConsentGranted: false)

    static func logEntries(now: Date) -> [DetectionLogEntry] {
        let cal = Calendar.vienna
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now)) ?? now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func rejection(_ reason: DetectionRejection.Reason, _ from: String?, _ to: String?, _ dep: Date, _ minutes: Int, km: Double, kmh: Double?) -> DetectionLogEntry {
            .rejected(DetectionRejection(reason: reason, departure: dep, arrival: dep.addingTimeInterval(Double(minutes) * 60), fromName: from, toName: to,
                                         straightKm: km, averageSpeedKmh: kmh), at: dep)
        }
        return [
            DetectionLogEntry(loggedAt: at(0, 8, 57), kind: .proposed, title: "Innsbruck Hauptbahnhof → Landeck-Zams",
                              detail: "Vorgeschlagen (wahrscheinlich): Innsbruck Hauptbahnhof: Bahnhof nur 60 m entfernt; Landeck-Zams: Bahnhof nur 90 m entfernt; Die Verbindung steht in der ÖBB-Preistabelle; Beide Enden sind Bahnhöfe. Auto nicht ausgeschlossen.",
                              tripStart: at(0, 7, 48), tripEnd: at(0, 8, 55)),
            rejection(.tooSlow(kmh: 5), "Innsbruck Hauptbahnhof", "Hall in Tirol", at(0, 6, 10), 96, km: 8, kmh: 5),
            DetectionLogEntry.decision("Übernommen. Die Standortpunkte dieser Fahrt sind gelöscht.", title: "Feldkirch → Bregenz", at: at(-1, 18, 2)),
            DetectionLogEntry(loggedAt: at(-1, 17, 45), kind: .proposed, title: "Feldkirch → Bregenz",
                              detail: "Vorgeschlagen (sicher): Fahrplan: REX 5429 fährt um 17:12; Feldkirch: Bahnhof nur 70 m entfernt; Bregenz: Bahnhof nur 110 m entfernt.",
                              tripStart: at(-1, 17, 14), tripEnd: at(-1, 17, 40)),
            rejection(.tooShort(km: 3.3), "Wien Schottentor", "Wien Gudrunstraße", at(-1, 8, 31), 14, km: 3.3, kmh: 14),
            rejection(.tooUncertain(score: 0.24), "Mieming Kirche", "Tarrenz Dorfplatz", at(-2, 7, 30), 15, km: 13.7, kmh: 55),
            rejection(.noStationAtEnd(nearestKm: 1.8), "Innsbruck Hauptbahnhof", nil, at(-2, 17, 5), 48, km: 41, kmh: 51),
        ]
    }
}
