import SwiftUI
import SwiftData
import KlimaCore

// MARK: tripdetect – one proposal of the "Fahrten-Vorschläge" inbox (docs/TRIP_DETECTION.md §7): mini route, times, the value in
// euro the existing fare logic gives, a label that never claims more than the data can ("Vielleicht", "Wahrscheinlich",
// "Sicher") and always three choices: Übernehmen, Bearbeiten, Verwerfen. Nothing is entered without a tap.

/// The stations of a candidate resolved from their ids (the place database may not be attached yet).
struct CandidateStations: Equatable {
    var from: Station?
    var to: Station?
    var via: [Station] = []

    var isComplete: Bool { from != nil && to != nil && from?.id != to?.id }
}

extension CandidateStations {
    @MainActor
    static func resolve(_ candidate: TripCandidateEntity, app: AppState) async -> CandidateStations {
        func station(_ id: String?) async -> Station? {
            guard let id, !id.isEmpty else { return nil }
            if let known = app.stations.station(id: id) { return known }
            return await app.bundled.station(id: id)
        }
        var vias: [Station] = []
        for via in candidate.via { if let s = await station(via.stationID) { vias.append(s) } }
        return CandidateStations(from: await station(candidate.fromStationID), to: await station(candidate.toStationID), via: vias)
    }
}

/// Accept / dismiss with everything that belongs to it: the ordinary ride through the Repository, the log, the raw points gone,
/// the toast with "Rückgängig", and the tick the savings counter celebrates.
@MainActor
struct TripCandidateActions {
    let app: AppState
    let context: ModelContext

    /// "Übernehmen" (optionally with edited stations and mode). Returns whether a ride was created.
    @discardableResult
    func accept(_ candidate: TripCandidateEntity, stations: CandidateStations, mode: TransportMode? = nil) -> Bool {
        guard let from = stations.from, let to = stations.to else { return false }
        let repository = Repository(context: context, app: app)
        if let mode { candidate.mode = mode }
        guard let trip = repository.accept(candidate, from: from, to: to, via: stations.via) else { return false }
        app.detection.didDecide(candidate, accepted: true)
        app.detection.noteAcceptance()
        let route = "\(TripRow.short(from.name)) → \(TripRow.short(to.name))"
        app.showToast("checkmark.circle.fill", "Fahrt erfasst", route + " · + " + Format.euroPrecise(trip.fareEUR), actionTitle: "Rückgängig") {
            repository.undoAccept(candidate, trip: trip)
        }
        return true
    }

    /// "Verwerfen" – with a toast and "Rückgängig" like every destructive tap of the app (a legitimate ride is not lost to a slip).
    func dismiss(_ candidate: TripCandidateEntity) {
        let repository = Repository(context: context, app: app)
        repository.dismiss(candidate)
        app.detection.didDecide(candidate, accepted: false)
        let from = candidate.fromName.isEmpty ? "Start offen" : TripRow.short(candidate.fromName)
        let to = candidate.toName.isEmpty ? "Ziel offen" : TripRow.short(candidate.toName)
        app.showToast("arrow.uturn.backward.circle", "Vorschlag verworfen", "\(from) → \(to)", actionTitle: "Rückgängig", haptic: .tap) {
            repository.undoDismiss(candidate)
        }
    }
}

/// "Vielleicht" / "Wahrscheinlich" / "Sicher" as a capsule: icon, word and colour (never colour alone).
struct ConfidenceChip: View {
    let confidence: DetectionConfidence

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption.weight(.bold))
            Text(confidence.label).font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(background.opacity(0.16), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Einschätzung: \(confidence.label)")
    }

    private var symbol: String {
        switch confidence {
        case .sicher: "checkmark.seal.fill"
        case .wahrscheinlich: "checkmark.circle.fill"
        case .vielleicht: "questionmark.circle.fill"
        }
    }

    private var tint: Color {
        switch confidence {
        case .sicher: Theme.positiveText
        case .wahrscheinlich: Theme.accentText
        case .vielleicht: Theme.summitText
        }
    }

    private var background: Color {
        switch confidence {
        case .sicher: Theme.positive
        case .wahrscheinlich: Theme.accent
        case .vielleicht: Theme.gold
        }
    }
}

struct TripCandidateCard: View {
    let candidate: TripCandidateEntity
    /// The card's own buttons; false for a read-only look (log, review headers).
    var showsActions = true

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var stations = CandidateStations()
    @State private var facts: CandidateTripFacts?
    @State private var showsReasons = false
    @State private var showsEditor = false

    var body: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                header
                summary
                note
                reasons
                if showsActions { actions }
            }
        }
        .task(id: candidate.id) { await resolve() }
        .sheet(isPresented: $showsEditor) {
            TripCandidateEditSheet(candidate: candidate, initial: stations)
        }
    }

    // MARK: Parts

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                kicker
                Spacer(minLength: Theme.Spacing.xs)
                chip
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                kicker
                chip
            }
        }
    }

    private var kicker: some View {
        Kicker(text: candidate.source == .recording ? "Aufgezeichnete Fahrt" : "Erkannte Fahrt", color: Theme.accentText)
    }

    @ViewBuilder
    private var chip: some View {
        if candidate.source != .recording { ConfidenceChip(confidence: candidate.confidence) }
    }

    /// Left to right (sketch, text, value) – at accessibility sizes the three stack, so no word breaks per letter.
    private var summary: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
                                                  : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.s))
        return layout {
            RouteSketchTile(sketch: candidate.sketch, mode: candidate.mode,
                            size: typeSize.isAccessibilitySize ? CGSize(width: 120, height: 84) : CGSize(width: 84, height: 72))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(whenText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Image(systemName: candidate.mode.symbolName).font(.caption.weight(.semibold))
                    Text(modeText).font(.caption.weight(.semibold))
                }
                .foregroundStyle(Theme.modeColor(candidate.mode))
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: Theme.Spacing.xxs) }
            valueView
        }
        .accessibilityElement(children: .combine)
    }

    private var valueView: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            if let facts {
                Text(Format.euroPrecise(facts.fareEUR))
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .numericValue(facts.fareEUR)
                Text("Wert").font(.caption2).foregroundStyle(Theme.textTertiary)
            } else {
                Text(stations.isComplete || candidate.isComplete ? "…" : "Ziel wählen")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    /// The honest sentence under the route: a car is not excluded unless the timetable agrees with the track.
    @ViewBuilder
    private var note: some View {
        if candidate.source == .background || candidate.source == .legacy {
            VStack(alignment: .leading, spacing: 3) {
                if !candidate.timetableLine.isEmpty {
                    Label("Fahrplan: \(candidate.timetableLine)", systemImage: "clock.badge.checkmark")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.positiveText)
                }
                Text(candidate.carNotExcluded
                     ? "Aus den Standortdaten allein lässt sich eine Autofahrt nicht ausschließen. Bitte prüfen."
                     : "Fahrplan und Strecke passen zusammen. Ein Auto ist unwahrscheinlich, aber nicht ausgeschlossen.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var reasons: some View {
        let items = candidate.reasons.filter { $0.code != "rules" }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Button {
                    withMotion(Motion.smooth) { showsReasons.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text("Warum dieser Vorschlag?").font(.footnote.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(showsReasons ? 180 : 0))
                    }
                    .foregroundStyle(Theme.accentText)
                }
                .buttonStyle(.plain)
                .accessibilityHint(showsReasons ? "Blendet die Gründe aus" : "Zeigt die Gründe")
                if showsReasons {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, reason in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: reason.isPositive ? "plus.circle.fill" : "minus.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(reason.isPositive ? Theme.positiveText : Theme.summitText)
                                    .accessibilityLabel(reason.isPositive ? "dafür" : "dagegen")
                                Text(reason.text)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .motionTransition(.rise)
                }
            }
        }
    }

    /// "Übernehmen" on its own line, "Bearbeiten" and "Verwerfen" side by side below it (one under the other when they do not fit).
    private var actions: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                if stations.isComplete { TripCandidateActions(app: app, context: context).accept(candidate, stations: stations) } else { showsEditor = true }
            } label: {
                Label("Übernehmen", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.prominentTint)
            .accessibilityLabel("Fahrt \(spokenRoute) übernehmen")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xs) { secondaryButtons }
                VStack(spacing: Theme.Spacing.xs) { secondaryButtons }
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var secondaryButtons: some View {
        Button { showsEditor = true } label: {
            Label("Bearbeiten", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Fahrt \(spokenRoute) bearbeiten")
        Button {
            withMotion(Motion.smooth) { TripCandidateActions(app: app, context: context).dismiss(candidate) }
        } label: {
            Label("Verwerfen", systemImage: "xmark")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Fahrt \(spokenRoute) verwerfen")
    }

    // MARK: Text

    private var title: String {
        let from = candidate.fromName.isEmpty ? "Start wählen" : TripRow.short(candidate.fromName)
        let to = candidate.toName.isEmpty ? "Ziel wählen" : TripRow.short(candidate.toName)
        return "\(from) → \(to)"
    }

    /// "von Innsbruck Hbf nach Landeck" – what VoiceOver says for the buttons, so three cards do not each offer a bare "Übernehmen".
    private var spokenRoute: String {
        "von \(candidate.fromName.isEmpty ? "unbekanntem Start" : TripRow.short(candidate.fromName)) nach \(candidate.toName.isEmpty ? "unbekanntem Ziel" : TripRow.short(candidate.toName))"
    }

    /// "Heute, 07:48–08:55"
    private var whenText: String {
        "\(Format.relativeDay(candidate.departedAt)), \(Format.time(candidate.departedAt))–\(Format.time(candidate.arrivedAt))"
    }

    /// "Zug · 38 km" – the mode's name next to the distance the ride will be saved with (the editor's), so the card, the edit sheet and
    /// the Fahrten list say the same number. Until the stations are resolved only the straight line is known, and says so.
    private var modeText: String {
        if let facts { return "\(candidate.mode.displayName) · \(Format.km(facts.distanceKm))" }
        return candidate.straightKm > 0 ? "\(candidate.mode.displayName) · \(Format.km(candidate.straightKm)) Luftlinie" : candidate.mode.displayName
    }

    // MARK: Value

    /// The stations and the value – the same numbers `Repository.accept` will file.
    private func resolve() async {
        let resolved = await CandidateStations.resolve(candidate, app: app)
        stations = resolved
        guard let from = resolved.from, let to = resolved.to, from.id != to.id else { facts = nil; return }
        facts = Repository(context: context, app: app).facts(mode: candidate.mode, date: candidate.departedAt, from: from, to: to, via: resolved.via)
    }
}
