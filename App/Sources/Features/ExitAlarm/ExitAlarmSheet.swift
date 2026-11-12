import SwiftUI
import UIKit
import KlimaCore

// Aussteige-Wecker: the one sheet behind every entry point (docs/EXIT_ALARM.md §2): "Live verfolgen" of a connection, the
// trip sheet of the Zug-Radar and the connection detail. Each entry is a thin button that opens this sheet with a followed
// run. The sheet picks the stop (default: the end of the leg, or any stop of it, a transfer too), the lead (at arrival, 2, 5,
// 10 minutes), explains how the alarm wakes you and asks for the location only after its own explanation screen.

/// What an entry point hands the sheet.
struct ExitAlarmSheetInput: Identifiable {
    let id = UUID()
    var target: LiveFollowTarget
    /// The stops of the run when the entry point has them already; nil: the sheet loads them.
    var stopovers: [Stopover]?
    /// The stop to start with (the end of the leg when nil).
    var preselectedStopID: String?
    /// The leg ends at a transfer (the connection goes on).
    var transferAtEnd: Bool {
        target.transfer != nil
    }
    /// A fixed clock for CI screenshots.
    var now: Date?
    /// CI screenshots: scroll to this part ("how") when the sheet opens.
    var screenshotScroll: String?
}

struct ExitAlarmSheet: View {
    let input: ExitAlarmSheetInput

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private let service = ExitAlarmService.shared
    private let prefs = ExitAlarmPrefs.shared

    @State private var stopovers: [Stopover]?
    @State private var loadFailed = false
    @State private var selectedStopID: String?
    @State private var lead: ExitAlarmLead = ExitAlarmPrefs.shared.defaultLead
    @State private var showsExplainer = false
    @State private var isArming = false
    /// The leg ends at a transfer and Settings says "Auch für Umstiege" is off: nothing is preselected, the user picks the stop.
    @State private var needsChoice = false
    @State private var armedTick = 0

    private var now: Date { input.now ?? Date() }

    private var options: [ExitAlarmStopOption] {
        guard let stopovers else { return [] }
        let legs = ExitAlarmStops.legIndices(target: input.target, stopovers: stopovers)
        return ExitAlarmStops.options(stopovers: stopovers, boardingIndex: legs.boarding, endIndex: legs.end,
                                      transferAtEnd: input.transferAtEnd, now: now)
    }

    private var selected: ExitAlarmStopOption? {
        options.first { $0.lid == selectedStopID } ?? (needsChoice ? nil : options.last)
    }

    /// The alarm that exists for the selected stop, if any (the sheet then changes or removes it).
    private var existing: ExitAlarmState? {
        guard let selected else { return nil }
        return service.book.state(id: ExitAlarmSpec.makeID(tripID: input.target.tripID, stopID: selected.lid))
            .flatMap { $0.isActive ? $0 : nil }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    header.reveal(order: 0)
                    stopsSection.reveal(order: 1)
                    leadSection.reveal(order: 2)
                    howSection.reveal(order: 3).id("how")
                    footer.reveal(order: 4)
                }
                .padding(Theme.Spacing.cardGutter)
                .padding(.bottom, 96)
            }
            .task {
                guard let target = input.screenshotScroll else { return }
                try? await Task.sleep(for: .milliseconds(500))
                proxy.scrollTo(target, anchor: .top)
            }
            .revealScope()
            .ambientBackground(.standard, glow: 0.3)
            .navigationTitle("Aussteige-Wecker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
            .safeAreaInset(edge: .bottom) { actionBar }
            .navigationDestination(isPresented: $showsExplainer) {
                ExitAlarmLocationExplainer(
                    onContinue: {
                        service.requestLocation(always: true)
                        showsExplainer = false
                    },
                    onSkip: { showsExplainer = false })
            }
            .task { await loadStops() }
            .task { await service.prepare(askForPermissions: false) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await service.prepare(askForPermissions: false) } }
            }
            .haptic(.success, trigger: armedTick)
            }
        }
    }

    // MARK: Parts

    private var header: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Kicker(text: input.target.lineName, color: Theme.accentText)
                Text("\(input.target.boardingStop.name) → \(input.target.alightStop.name)")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("KlimaBilanz weckt dich kurz vor deinem Ausstieg, auch im Schlaf.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var stopsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeader(title: "Wo steigst du aus?")
            if stopovers == nil, !loadFailed {
                GlassCard(padding: Theme.Spacing.m) {
                    HStack(spacing: Theme.Spacing.s) {
                        ProgressView()
                        Text("Halte werden geladen …").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                }
            } else if options.isEmpty {
                GlassCard(padding: Theme.Spacing.m) {
                    Text(loadFailed ? "Die Halte dieser Fahrt kommen gerade nicht. Versuche es später noch einmal."
                                    : "Für diese Fahrt gibt es keinen Halt mehr, an dem der Wecker klingeln kann.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                if selected == nil {
                    Text("Hier steigst du um. Wähle den Halt, an dem dich der Wecker wecken soll.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                GlassCard(padding: Theme.Spacing.s) {
                    VStack(spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            stopRow(option)
                            if index < options.count - 1 { Divider().padding(.leading, 44) }
                        }
                    }
                }
            }
        }
    }

    private func stopRow(_ option: ExitAlarmStopOption) -> some View {
        let isSelected = option.lid == (selected?.lid ?? "")
        return Button {
            withMotion(Motion.snappy) { selectedStopID = option.lid }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .symbolReplaceTransition()
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if option.isTransfer { badge("Umstieg") } else if option.isEnd { badge("Ziel") }
                        if let platform = option.platform { Text("Gleis \(platform)").font(.caption).foregroundStyle(Theme.textSecondary) }
                    }
                }
                Spacer(minLength: 8)
                if let arrival = option.effectiveArrival {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(ExitAlarmPresentation.timeText(arrival))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        if let delay = option.delaySeconds, delay >= 60 {
                            Text("+\(Int((Double(delay) / 60).rounded())) Min").font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.summitText)
                        }
                    }
                }
            }
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.accent.opacity(0.14), in: .capsule)
    }

    private var leadSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeader(title: "Wann soll er klingeln?")
            GlassCard(padding: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ExitAlarmFlowLayout(spacing: Theme.Spacing.xs) { leadChips }
                    if let selected, let arrival = selected.effectiveArrival {
                        let moment = arrival.addingTimeInterval(-lead.seconds)
                        Label(moment > now.addingTimeInterval(5)
                              ? "Weckt dich um \(ExitAlarmPresentation.timeText(moment))"
                              : "Weckt dich sofort, die Ankunft ist näher als \(lead.minutes) Min",
                              systemImage: "bell.badge")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.opacity)
                    }
                }
            }
        }
    }

    @ViewBuilder private var leadChips: some View {
        ForEach(ExitAlarmLead.allCases, id: \.self) { value in
            Chip(title: value == .atArrival ? "Bei Ankunft" : "\(value.minutes) Min", isSelected: lead == value) {
                withMotion(Motion.snappy) { lead = value }
            }
            .fixedSize()
        }
    }

    private var howSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeader(title: "So wirst du geweckt")
            GlassCard(padding: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    howRow(symbol: "clock.badge.checkmark.fill", tint: Theme.glacier, title: "Nach Fahrplan",
                           text: "Der Wecker ist auf die erwartete Ankunft gestellt und rückt mit, wenn sich die Verspätung ändert.",
                           status: kindStatus)
                    Divider()
                    howRow(symbol: "location.fill", tint: Theme.pine, title: "Mit Standort",
                           text: "Dein iPhone erkennt, wann du dich der Haltestelle näherst, auch ohne Netz. Der frühere Weg gewinnt, geklingelt wird nur einmal.",
                           status: locationStatus)
                    locationButton
                }
            }
        }
    }

    private func howRow(symbol: String, tint: Color, title: String, text: String, status: (String, Bool)) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            SetIconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 6)
                    Text(status.0).font(.caption.weight(.semibold)).foregroundStyle(status.1 ? Theme.positiveText : Theme.summitText)
                }
                Text(text).font(.footnote).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var kindStatus: (String, Bool) {
        switch service.alarmKind {
        case .alarmKit: ("Wecker-Ton, auch lautlos", true)
        case .notifications: ("Mitteilung, lautlos möglich", false)
        case .none: ("noch nicht erlaubt", false)
        }
    }

    private var locationStatus: (String, Bool) {
        switch service.locationAuthorization {
        case .always: ("Immer erlaubt", true)
        case .whenInUse: ("Nur beim Verwenden", false)
        case .notDetermined: ("noch nicht erlaubt", false)
        case .denied, .restricted: ("in iOS aus", false)
        }
    }

    @ViewBuilder private var locationButton: some View {
        switch service.locationAuthorization {
        case .notDetermined:
            Button { showsExplainer = true } label: {
                Label("Standort erlauben", systemImage: "location.circle.fill").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        case .whenInUse:
            Button { showsExplainer = true } label: {
                Label("Auf „Immer“ stellen", systemImage: "lock.open.fill").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        case .denied, .restricted:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Standort in iOS erlauben", systemImage: "gearshape.fill").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        case .always:
            EmptyView()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let running = LiveFollowTracker.shared.target, running.tripID != input.target.tripID {
                Text("Dafür endet die Verfolgung von \(running.lineName), und mit ihr ihre Wecker.")
            }
            if service.alarmKind == .notifications {
                Text("Ohne Wecker-Erlaubnis kommen drei Mitteilungen im Abstand von 20 Sekunden. Lautlos-Schalter und Fokus können sie stumm schalten.")
            }
            if let reason = app.live.timetableUnavailable {
                // Offline is a passing state: the alarm is set by the timetable and catches up with the delay when the net is back.
                // Live-Daten that are off are not: the follow cannot ask, and the alarms of a follow end with it.
                Text(reason == .offline
                     ? "Gerade ohne Netz: Der Wecker richtet sich nach dem Fahrplan und holt die Verspätung nach, sobald wieder Netz da ist."
                     : "Live-Daten sind aus. Der Wecker braucht sie, um deine Fahrt zu verfolgen.")
            }
            Text("Dein Standort wird nur auf dem iPhone genutzt, solange ein Wecker scharf ist. Er wird weder gespeichert noch gesendet.")
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actionBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button { Task { await arm() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: existing == nil ? "bell.badge.fill" : "arrow.triangle.2.circlepath")
                    Text(existing == nil ? "Wecker stellen" : "Wecker ändern")
                }
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.primary)
            .disabled(selected == nil || isArming)
            if let existing {
                Button("Wecker ausschalten", role: .destructive) {
                    service.cancel(existing.id)
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.xs)
        .background(.bar)
        // The pinned bar stops growing at the second accessibility size: the stops above must keep room to scroll.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // MARK: Actions

    private func loadStops() async {
        let tracker = LiveFollowTracker.shared
        if let given = input.stopovers, !given.isEmpty {
            stopovers = given
        } else if tracker.target?.tripID == input.target.tripID, let snapshot = tracker.snapshot, !snapshot.stopovers.isEmpty {
            stopovers = snapshot.stopovers
        } else {
            do {
                stopovers = try await ExitAlarmStopLoader.stops(tripID: input.target.tripID, live: app.live)
            } catch {
                loadFailed = true
            }
        }
        if selectedStopID == nil {
            let preferred = input.preselectedStopID.flatMap { id in options.first { $0.lid == id } }
            // The end of the leg is the default. A transfer is preselected only when Settings says "Auch für Umstiege"; otherwise
            // nothing is, and the user picks. (The stop before the transfer would wake them at a stop they never chose.)
            let end = options.last
            if let preferred {
                selectedStopID = preferred.lid
            } else if end?.isTransfer == true, !prefs.alsoForTransfers {
                needsChoice = true
            } else {
                selectedStopID = end?.lid
            }
            // "Ändern" shows the alarm as it is set.
            if let existing { lead = existing.spec.lead }
        }
    }

    private func arm() async {
        guard let selected, let stopovers else { return }
        // Live-Daten off (switch, kill switch, no consent): the follow cannot ask and would end the alarm at once. Say so now
        // instead of "Wecker gestellt". Offline is different: the alarm is set and the delay is caught up later.
        if let reason = app.live.timetableUnavailable, reason != .offline {
            app.showToast("exclamationmark.triangle.fill", "Live-Daten sind aus", "Der Wecker braucht sie. Schalte sie in den Einstellungen ein.")
            return
        }
        isArming = true
        defer { isArming = false }
        await service.prepare(askForPermissions: true)
        let legs = ExitAlarmStops.legIndices(target: input.target, stopovers: stopovers)
        let spec = ExitAlarmStops.spec(target: input.target, stopovers: stopovers, boardingIndex: legs.boarding, option: selected,
                                       lead: lead, soundKey: prefs.sound.rawValue, now: Date())
        // The alarm lives with the follow of the run: it brings the timetable answers (docs/EXIT_ALARM.md §2).
        let tracker = LiveFollowTracker.shared
        if tracker.target?.tripID != input.target.tripID { tracker.start(input.target, live: app.live) }
        let timetable = ExitAlarmStops.timetable(for: spec, in: stopovers)
        let result = service.arm(spec, arrival: timetable?.arrival ?? selected.effectiveArrival, departure: timetable?.departure,
                                 delaySeconds: timetable?.delaySeconds)
        switch result {
        case .armed, .replaced:
            armedTick += 1
            // Nothing allowed (no alarm, no notifications): it only rings while the app is open, and the toast must not hide that.
            app.showToast("bell.badge.fill", "Wecker gestellt",
                          service.alarmKind == .none ? "Klingelt nur bei geöffneter App, erlaube Wecker oder Mitteilungen"
                                                     : "\(selected.name) · \(lead.title)")
            dismiss()
        case .full:
            app.showToast("exclamationmark.triangle.fill", "Schon drei Wecker aktiv", "Schalte einen aus, bevor du einen neuen stellst")
        case .arrivalOver:
            app.showToast("exclamationmark.triangle.fill", "Dieser Halt ist schon vorbei", "Wähle einen späteren Halt")
        }
    }
}

/// Loads the stops of a run for the sheet: the live timetable, or the demo run in demo and screenshot runs. One request.
@MainActor
enum ExitAlarmStopLoader {
    static func stops(tripID: String, live: LiveDataService) async throws -> [Stopover] {
        if live.isDemo {
            guard let trip = DemoFollow.trip(tripID, now: Date()) else { throw LiveError.noConnection }
            return trip.stopovers
        }
        guard let service = live.timetable else { throw LiveError.disabled(.oebbHafas) }
        return try await service.trip(tripID, includePolyline: false).stopovers
    }
}

// MARK: Location explainer

/// The pre-prompt screen: what the location does and does not do, before iOS asks. "Weiter" triggers the system prompt;
/// "Nur mit Fahrplan wecken" leaves it out (the alarm still works by the timetable).
struct ExitAlarmLocationExplainer: View {
    var onContinue: () -> Void
    var onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ZStack {
                    Circle().fill(Theme.pine.opacity(0.16)).frame(width: 84, height: 84)
                    Image(systemName: "location.viewfinder")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(Theme.pine)
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(maxWidth: .infinity)
                .reveal(.focus)
                Text("Damit dich der Wecker auch bei gesperrtem iPhone weckt")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    point("lock.iphone", "Warum „Immer“?",
                          "Nur mit „Immer“ kann iOS dich wecken, wenn du dich der Haltestelle näherst und das iPhone gesperrt in der Tasche liegt. Mit „Beim Verwenden“ klappt es nur, solange die App läuft; iOS zeigt dann den blauen Streifen oben.")
                    point("clock.arrow.circlepath", "Der Fahrplan bleibt die Grundlage",
                          "Auch ohne Standort klingelt der Wecker zur erwarteten Ankunft. Der Standort macht ihn früher und genauer, wenn du schneller bist als geplant.")
                    point("eye.slash.fill", "Nichts wird gespeichert oder gesendet",
                          "Der Standort wird nur auf deinem iPhone gelesen, solange ein Wecker scharf ist und die Fahrt läuft. Es gibt keinen Verlauf, nur die letzte Position im Arbeitsspeicher.")
                    point("hand.raised.fill", "Du behältst die Kontrolle",
                          "iOS fragt dich gleich in zwei Schritten. „Immer“ kannst du später in den Einstellungen zurücknehmen.")
                }
                .reveal(order: 1)
            }
            .padding(Theme.Spacing.screen)
            .padding(.bottom, 120)
        }
        .revealScope()
        .ambientBackground(.standard, glow: 0.3)
        .navigationTitle("Standort")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Spacing.xs) {
                Button(action: onContinue) { Text("Weiter").frame(maxWidth: .infinity, minHeight: 56) }
                    .buttonStyle(.primary)
                Button("Nur mit Fahrplan wecken", action: onSkip)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 40)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.xs)
            .background(.bar)
        }
    }

    private func point(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 28)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
