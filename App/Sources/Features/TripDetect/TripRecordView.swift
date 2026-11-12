import SwiftUI
import SwiftData
import UIKit
import KlimaCore

// MARK: tripdetect – "Fahrt aufzeichnen" (docs/TRIP_DETECTION.md §2): the live screen. A map that draws the ride as it happens
// (no map tiles, no network: the line, the stations around it and a pulsing "du bist hier"), the running time, distance and
// speed, the station you are at, and – after "Beenden" – the proposed ride with the three choices.

struct TripRecordView: View {
    /// The recorder – the shared one on the device, a prepared one in the CI scenes.
    let recorder: TripRecorder

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var reviewing: TripCandidateEntity?
    @State private var nearby: [Station] = []
    @State private var stopTick = 0
    @State private var startTick = 0
    @State private var confirmsDiscard = false

    /// `previewReview`: CI scenes show the proposal of a finished recording right away.
    init(recorder: TripRecorder = .shared, previewReview: TripCandidateEntity? = nil) {
        self.recorder = recorder
        _reviewing = State(initialValue: previewReview)
    }

    var body: some View {
        ZStack {
            Color.clear.ambientBackground()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        content
                    }
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.xxl)
                }
                .scrollIndicators(.hidden)
                .revealScope()
                controls
            }
        }
        .haptic(.start, trigger: startTick)
        .haptic(.stop, trigger: stopTick)
        .interactiveDismissDisabled(recorder.isRecording)
        // Throwing a running recording away cannot be undone: one stray tap beside "Beenden" must not do it.
        .confirmationDialog("Aufzeichnung verwerfen?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Aufzeichnung verwerfen", role: .destructive) { withMotion(Motion.smooth) { recorder.discard() }; stopTick += 1 }
            Button("Weiter aufzeichnen", role: .cancel) {}
        } message: {
            Text("Die bisherige Strecke wird gelöscht, es wird keine Fahrt vorgeschlagen.")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button {
                // A finished recording is already in the inbox (pending) or decided: nothing is lost by closing.
                if recorder.phase == .finished { recorder.reset() }
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Schließen")
            Spacer()
            VStack(spacing: 1) {
                Kicker(text: "Fahrt aufzeichnen")
                if recorder.isRecording { statusLine }
            }
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .padding(.top, Theme.Spacing.xs)
    }

    @ViewBuilder
    private var statusLine: some View {
        let lost = (recorder.snapshot?.secondsSinceFix ?? 0) > 20
        HStack(spacing: 5) {
            Circle().fill(lost ? Theme.summit : Theme.pine).frame(width: 7, height: 7)
            Text(lost ? "GPS-Signal schwach" : "Aufzeichnung läuft")
                .font(.caption.weight(.semibold))
                .foregroundStyle(lost ? Theme.summitText : Theme.positiveText)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch recorder.phase {
        case .idle:
            idleCard.reveal(order: 0)
        case .needsPermission:
            waitingCard.reveal(order: 0)
        case .denied:
            deniedCard.reveal(order: 0)
        case .recording:
            liveContent
        case .finished:
            finishedContent
        }
    }

    private var liveContent: some View {
        let snapshot = recorder.snapshot
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            RecordMapCard(track: snapshot?.track ?? [], stations: nearby, current: snapshot?.currentStation?.station.id)
                .reveal(order: 0)
            clock(snapshot).reveal(.focus, order: 1)
            HStack(spacing: Theme.Spacing.s) {
                figure(title: "Strecke", value: Format.number(snapshot?.distanceKm ?? 0, decimals: (snapshot?.distanceKm ?? 0) < 10 ? 1 : 0),
                       unit: "km", symbol: "point.topleft.down.to.point.bottomright.curvepath", numeric: snapshot?.distanceKm ?? 0)
                figure(title: "Tempo", value: Format.number(snapshot?.speedKmh ?? 0), unit: "km/h", symbol: "speedometer", numeric: snapshot?.speedKmh ?? 0)
            }
            .reveal(order: 2)
            stationCard(snapshot).reveal(order: 3)
            if (snapshot?.secondsSinceFix ?? 0) > 20 {
                Label("Kein GPS-Signal – im Tunnel? Die Aufzeichnung läuft weiter und holt den Weg danach nach.", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.footnote)
                    .foregroundStyle(Theme.summitText)
                    .motionTransition(.rise)
            }
        }
        .task(id: (snapshot?.fixCount ?? 0) / 12) { await refreshNearby(snapshot) }
    }

    private func clock(_ snapshot: RecordingSnapshot?) -> some View {
        let elapsed = snapshot?.elapsed ?? 0
        return VStack(spacing: 2) {
            Text(Self.clockText(elapsed))
                .font(Theme.Typography.priceNumeral)
                .foregroundStyle(Theme.textPrimary)
                .numericValue(elapsed)
            Text("Fahrzeit").font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fahrzeit \(Self.spokenClock(elapsed))")
    }

    private func figure(title: String, value: String, unit: String, symbol: String, numeric: Double) -> some View {
        GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.tile) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(Theme.Typography.numberMedium).foregroundStyle(Theme.textPrimary).numericValue(numeric)
                    Text(unit).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stationCard(_ snapshot: RecordingSnapshot?) -> some View {
        GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.tile) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: snapshot?.currentStation != nil ? "mappin.and.ellipse" : "train.side.front.car")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(snapshot?.currentStation != nil ? Theme.pine : Theme.glacier)
                    .frame(width: 30)
                    .symbolReplaceTransition()
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot?.currentStation != nil ? "Du bist am Bahnhof" : "Zuletzt")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(snapshot?.currentStation?.station.name ?? snapshot?.lastStation?.name ?? "Noch keine Haltestelle erkannt")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
            }
        }
        .motionAnimation(Motion.smooth, value: snapshot?.currentStation?.station.id)
        .accessibilityElement(children: .combine)
    }

    private var idleCard: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Image(systemName: "record.circle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.pine)
                Text("Fahrt genau aufzeichnen")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                Text("Starte die Aufzeichnung beim Einsteigen und beende sie beim Aussteigen. KlimaBilanz zeigt dir Zeit, Strecke und Bahnhof live und schlägt danach die Fahrt vor – du bestätigst.")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    bullet("location.fill", "Der genaue Standort wird nur genutzt, solange die Aufzeichnung läuft (blaue Anzeige oben).")
                    bullet("lock.shield.fill", "Die Standortpunkte bleiben auf deinem iPhone und nur im Arbeitsspeicher. Gespeichert wird allein der Vorschlag: Haltestellen, Zeiten und eine Skizze ohne Koordinaten.")
                    bullet("bolt.badge.clock.fill", "Das braucht mehr Akku als sonst – bei langen Fahrten das Ladekabel dabei haben.")
                }
                .padding(.top, 4)
            }
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Image(systemName: symbol).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accentText).frame(width: 20)
            Text(text).font(.footnote).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var waitingCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Warte auf deine Erlaubnis").font(.headline).foregroundStyle(Theme.textPrimary)
                Text("Erlaube KlimaBilanz den Standort „Beim Verwenden der App“. Die Aufzeichnung startet dann von selbst.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var deniedCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Label("Standort ist aus", systemImage: "location.slash.fill").font(.headline).foregroundStyle(Theme.summitText)
                Text("KlimaBilanz darf deinen Standort nicht benutzen. Für die Aufzeichnung stell ihn in den Einstellungen auf „Beim Verwenden der App“.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Einstellungen öffnen", systemImage: "gear").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
            }
        }
    }

    // MARK: Finished

    @ViewBuilder
    private var finishedContent: some View {
        if let candidate = reviewing {
            TripRecordResult(candidate: candidate).reveal(order: 0)
        } else if recorder.proposal == nil {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Zu kurz für eine Fahrt").font(.headline).foregroundStyle(Theme.textPrimary)
                    Text("Es kam keine Strecke zusammen – vielleicht war es ein versehentlicher Start. Es wurde nichts gespeichert.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: Theme.Spacing.xs) {
            switch recorder.phase {
            case .idle, .denied:
                Button { start() } label: {
                    Label("Aufzeichnung starten", systemImage: "record.circle")
                }
                .buttonStyle(.primary)
                .disabled(recorder.phase == .denied)
            case .needsPermission:
                Button { recorder.discard() } label: { Text("Abbrechen").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.glass)
            case .recording:
                Button { finish() } label: {
                    Label("Aufzeichnung beenden", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.primary)
                Button("Verwerfen", role: .destructive) { confirmsDiscard = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.negativeText)
                    .frame(minHeight: 44)
            case .finished:
                Button {
                    recorder.reset()
                    dismiss()
                } label: { Text("Fertig") }
                .buttonStyle(.primary)
            }
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.vertical, Theme.Spacing.s)
        .background(.bar)
    }

    // MARK: Actions

    private func start() {
        startTick += 1
        withMotion(Motion.smooth) { recorder.start(lookup: app.stations) }
    }

    private func finish() {
        stopTick += 1
        let proposal = recorder.stop()
        guard let proposal else { return }
        let candidate = Repository(context: context, app: app).insertRecordingCandidate(proposal)
        recorder.attach(candidate: candidate)
        withMotion(Motion.smooth) { reviewing = candidate }
    }

    /// The rail stations around the ride so far (the map labels them; bus stops would only be noise at this scale).
    private func refreshNearby(_ snapshot: RecordingSnapshot?) async {
        guard let track = snapshot?.track, let first = track.first, let last = track.last else { return }
        let center = DetectionGeo.lerp(first, last, 0.5)
        let reach = max(2, min(40, max(first.distanceKm(to: last), 1) / 2 + 2))
        let hits = app.stations.nearest(to: center, limit: 150, maxKm: reach)
        nearby = Array(hits.map(\.station).filter(StationMatcher.isRailLike).prefix(24))
    }

    // MARK: Formatting

    static func clockText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    static func spokenClock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h) Stunden \(m) Minuten" }
        return "\(m) Minuten \(total % 60) Sekunden"
    }
}

// MARK: - Result of a recording

/// The proposal of a recording with its three choices; after the choice a calm confirmation.
struct TripRecordResult: View {
    let candidate: TripCandidateEntity

    @State private var celebrate = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            switch candidate.status {
            case .pending:
                Text("Das war deine Fahrt?").font(Theme.Typography.title).foregroundStyle(Theme.textPrimary)
                TripCandidateCard(candidate: candidate).motionTransition(.rise)
                Text("Du kannst sie jetzt übernehmen, bearbeiten oder verwerfen. Ohne Entscheidung wartet sie bei den Vorschlägen auf der Übersicht.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            case .accepted:
                resultCard(symbol: "checkmark.circle.fill", tint: Theme.positive, title: "Fahrt erfasst",
                           text: "\(TripRow.short(candidate.fromName)) → \(TripRow.short(candidate.toName)) zählt jetzt in deiner Bilanz.")
                    .celebrationBurst(trigger: celebrate)
                    .onAppear { celebrate += 1 }
            case .dismissed:
                resultCard(symbol: "xmark.circle.fill", tint: Theme.textSecondary, title: "Verworfen", text: "Die Aufzeichnung ist gelöscht.")
            }
        }
        .motionAnimation(Motion.smooth, value: candidate.statusRaw)
    }

    private func resultCard(symbol: String, tint: Color, title: String, text: String) -> some View {
        GlassCard {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                    Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .motionTransition(.pop)
    }
}

// MARK: - The map

/// The ride as it happens: grid, stations around, the track drawing itself, the head pulsing. Own projection – no tiles.
struct RecordMapCard: View {
    let track: [GeoPoint]
    let stations: [Station]
    /// The station the phone is at right now (highlighted).
    var current: String?

    @State private var drawn = MotionPolicy.isStatic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let projection = MapProjection(track: track, size: proxy.size)
            ZStack {
                grid
                Canvas { context, size in
                    // Important stations first, so their names win where labels would overlap.
                    let ordered = stations.sorted { a, b in
                        if (a.id == current) != (b.id == current) { return a.id == current }
                        return a.importance > b.importance
                    }
                    var placed: [CGRect] = []
                    for station in ordered {
                        guard let point = projection.point(for: station.location) else { continue }
                        let rail = StationMatcher.isRailLike(station)
                        let isCurrent = station.id == current
                        let radius: CGFloat = isCurrent ? 6 : (rail ? 4.5 : 2.5)
                        let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                        context.fill(dot, with: .color(isCurrent ? Theme.pine : (rail ? Theme.textSecondary : Theme.textTertiary)))
                        // At most eight names, none on top of another: the important ones (and the current one) win.
                        guard rail, placed.count < 8 else { continue }
                        let name = station.name.count > 20 ? String(station.name.prefix(19)) + "…" : station.name
                        let label = context.resolve(Text(name).font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.textSecondary))
                        let width = label.measure(in: size).width
                        // A name that would run off the card goes to the left of its dot.
                        let fitsRight = point.x + radius + 4 + width < size.width - 6
                        let x = fitsRight ? point.x + radius + 4 : point.x - radius - 4 - width
                        let rect = CGRect(x: x, y: point.y - 14, width: width, height: 13).insetBy(dx: -5, dy: -3)
                        guard !placed.contains(where: { $0.intersects(rect) }) else { continue }
                        placed.append(rect)
                        context.draw(label, at: CGPoint(x: x, y: point.y - 7.5), anchor: .leading)
                    }
                }
                SketchLine(points: track.compactMap { projection.point(for: $0) })
                    .trim(from: 0, to: drawn ? 1 : 0.001)
                    .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .shadow(color: Theme.accent.opacity(0.35), radius: 6)
                if let start = track.first.flatMap({ projection.point(for: $0) }) {
                    Circle().fill(Theme.glacier).frame(width: 10, height: 10).position(start)
                }
                if let head = track.last.flatMap({ projection.point(for: $0) }) {
                    Circle()
                        .fill(Theme.pine)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                        .pulsingHalo(Theme.pine)
                        .position(head)
                }
                if track.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "location.fill").font(.title2).foregroundStyle(Theme.textTertiary).breathing()
                        Text("Warte auf das erste GPS-Signal …").font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .frame(height: 300)
        .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.55))
        }
        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1) }
        .onAppear { withMotion(Motion.gentle) { drawn = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Karte der aufgezeichneten Strecke")
        .accessibilityValue(track.count < 2 ? "Noch keine Strecke" : "Strecke mit \(track.count) Punkten")
    }

    private var grid: some View {
        Canvas { context, size in
            var path = Path()
            let step: CGFloat = 36
            var x: CGFloat = step
            while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = step
            while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            context.stroke(path, with: .color(Theme.separator), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// Fits the track (and a few metres around it) into the card, north up, keeping the aspect ratio.
struct MapProjection {
    private let minLat: Double
    private let minLon: Double
    private let scale: Double
    private let offset: CGPoint
    private let k: Double
    private let width: Double
    private let height: Double

    init(track: [GeoPoint], size: CGSize) {
        let points = track.isEmpty ? [GeoPoint(latitude: 47.26, longitude: 11.4)] : track
        let lat0 = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let cosLat = cos(lat0 * .pi / 180)
        let lats = points.map(\.latitude)
        let lons = points.map { $0.longitude * cosLat }
        var lowLat = lats.min() ?? 0, highLat = lats.max() ?? 0
        var lowLon = lons.min() ?? 0, highLon = lons.max() ?? 0
        // At least ~700 m across, so the first metres of a recording do not zoom into noise.
        let minSpan = 700.0 / 111_000
        if highLat - lowLat < minSpan { let mid = (highLat + lowLat) / 2; lowLat = mid - minSpan / 2; highLat = mid + minSpan / 2 }
        if highLon - lowLon < minSpan { let mid = (highLon + lowLon) / 2; lowLon = mid - minSpan / 2; highLon = mid + minSpan / 2 }
        let pad = 34.0
        let usableW = max(Double(size.width) - pad * 2, 1), usableH = max(Double(size.height) - pad * 2, 1)
        let fit = min(usableW / (highLon - lowLon), usableH / (highLat - lowLat))
        k = cosLat
        minLat = lowLat
        minLon = lowLon
        scale = fit
        width = Double(size.width)
        height = Double(size.height)
        offset = CGPoint(x: pad + (usableW - (highLon - lowLon) * fit) / 2, y: pad + (usableH - (highLat - lowLat) * fit) / 2)
    }

    /// Screen point of a coordinate; nil far outside the card.
    func point(for geo: GeoPoint) -> CGPoint? {
        let x = offset.x + (geo.longitude * k - minLon) * scale
        let y = height - (offset.y + (geo.latitude - minLat) * scale)
        guard x > -40, x < width + 40, y > -40, y < height + 40 else { return nil }
        return CGPoint(x: x, y: y)
    }
}
