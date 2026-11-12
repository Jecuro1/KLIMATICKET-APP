import SwiftUI
import KlimaCore

// MARK: tarifstand – the notice on the Ticket tab when the prices in the app may be out of date (docs/TARIFF_FRESHNESS.md).
//
// Three situations (KlimaCore `TariffFreshness`): the timetable change in December (the Sunday after the second Saturday), New Year without
// KlimaTicket prices for the new year, and data older than 13 months. The banner never names a new price – it says that one
// may exist and that the app fetches it by itself. It is one element for VoiceOver (a spoken sentence, hint „Doppeltippen
// für Details“), carries an icon and words (no colour-only information) and wraps at the largest text size.

// MARK: - Input (and the demo clock)

/// What the notice is asked about. The app builds it from its own state; CI screenshots inject a clock and a catalogue
/// through `\.tariffNoticeInput` (demo fixture), so every state can be shown on any day.
struct TariffNoticeInput: Equatable {
    var catalog: TariffCatalog
    var now: Date
    var lastCheck: Date?
    /// Validity day of the relation table in use ("2025-12-14").
    var fareValidFrom: String?

    /// The state of the prices: judged with the table in use, so a newer pack that is only announced does not end the notice.
    var freshness: TariffFreshness.State {
        TariffFreshness.state(catalog: catalog, now: now, lastCheck: lastCheck, relationsValidFrom: fareValidFrom)
    }
}

private struct TariffNoticeInputKey: EnvironmentKey {
    static let defaultValue: TariffNoticeInput? = nil
}

extension EnvironmentValues {
    /// Demo fixture: replaces the app's catalogue, clock and last check for the tariff notice and the Tarifstand row.
    var tariffNoticeInput: TariffNoticeInput? {
        get { self[TariffNoticeInputKey.self] }
        set { self[TariffNoticeInputKey.self] = newValue }
    }
}

private struct TarifCheckPresetKey: EnvironmentKey {
    static let defaultValue: TarifCheck.Phase? = nil
}

extension EnvironmentValues {
    /// Demo fixture: the „Jetzt prüfen“ row shows this finished check instead of idling (CI has no network).
    var tarifCheckPreset: TarifCheck.Phase? {
        get { self[TarifCheckPresetKey.self] }
        set { self[TarifCheckPresetKey.self] = newValue }
    }
}

extension AppState {
    /// The input as the app sees it right now (`now` supplied by the caller's clock).
    func tariffNoticeInput(now: Date = Date()) -> TariffNoticeInput {
        TariffNoticeInput(catalog: catalog, now: now, lastCheck: tariffs.lastRefresh, fareValidFrom: relations.validFrom)
    }
}

// MARK: - Copy

/// The words for one state. Pure; every date comes from the catalogue, the table in use or the clock.
struct TariffNoticeCopy: Equatable {
    var state: TariffFreshness.State
    var symbol: String
    var kicker: String
    /// First, bold line of the banner (and the sheet's title).
    var title: String
    /// Second line of the banner.
    var message: String
    /// The paragraphs of the details sheet.
    var explanation: [String]
    /// The banner as one spoken sentence.
    var spoken: String

    init(_ input: TariffNoticeInput) {
        let state = input.freshness
        self.state = state
        let fetch = "die App aktualisiert sich, sobald neue Preise vorliegen"
        let fareFrom = input.fareValidFrom.map { TariffFreshness.germanDate(iso: $0) }
        let asOfISO = TariffFreshness.ticketPricesAsOf(catalog: input.catalog, now: input.now)
        let asOf = asOfISO.map { TariffFreshness.germanDate(iso: $0) }
        let year = Int(TariffFreshness.isoDay(input.now).prefix(4)) ?? 0

        switch state {
        case .upcomingChange(let change):
            let arrived = input.now >= change
            let short = TariffFreshness.germanDayMonth(change)
            let long = Self.longDay(change)
            symbol = "calendar.badge.exclamationmark"
            kicker = "Fahrplanwechsel"
            title = arrived ? "Seit dem Fahrplanwechsel am \(short)" : "Fahrplanwechsel am \(short)"
            message = arrived ? "Preise können sich geändert haben; \(fetch)" : "Preise können sich ändern; \(fetch)"
            spoken = arrived ? "Seit dem Fahrplanwechsel am \(long) können sich Preise geändert haben; \(fetch)"
                : "Fahrplanwechsel am \(long). Preise können sich ändern; \(fetch)"
            var paragraphs = [
                arrived ? "Am \(long) hat der ÖBB-Fahrplan gewechselt. Mit dem neuen Fahrplanjahr ändern sich üblicherweise auch die Preise der Standardtickets."
                    : "Am \(long) wechselt der ÖBB-Fahrplan. Mit dem neuen Fahrplanjahr ändern sich üblicherweise auch die Preise der Standardtickets.",
                "Die Normalpreise in der App stammen aus der ÖBB-Preisliste, die ab \(fareFrom ?? "dem hinterlegten Tag") gilt. Sobald neue Preise vorliegen, lädt die App sie von selbst – ohne App-Update.",
            ]
            if let index = input.catalog.fareIndex?.first(where: { $0.validFrom == TimetableChange.isoDay(year: year) }), index.factor > 1 {
                let percent = Format.number((index.factor - 1) * 100, decimals: 1)
                paragraphs.append("Bis neue Preise vorliegen, rechnet die App Fahrten ab dem \(short) mit einem Aufschlag von \(percent) % auf den Normalpreis – ein Durchschnittswert aus dem Tarifstand; einzelne Verbindungen weichen ab.")
            }
            explanation = paragraphs
        case .newYear:
            let from = asOfISO.flatMap { Int($0.prefix(4)) } ?? max(year - 1, 0)
            symbol = "calendar.badge.clock"
            kicker = "Jahreswechsel"
            title = "Die Preise in der App stammen noch aus \(from)"
            message = "Für \(year) sind noch keine KlimaTicket-Preise eingetragen; \(fetch)"
            spoken = "\(title). \(message)"
            explanation = [
                "KlimaTicket-Preise werden meist zum Jahreswechsel angepasst. Die App kennt die Preise mit Stand \(asOf ?? "–").",
                "Ob und wie sich die Preise für \(year) ändern, weiß die App erst, wenn sie veröffentlicht sind. Dann lädt sie sie von selbst – ohne App-Update.",
                "Preisvergleiche und Ticket-Empfehlungen in der App nutzen bis dahin die bisherigen Preise.",
            ]
        case .stale(let since):
            symbol = "clock.badge.exclamationmark"
            kicker = "Alte Daten"
            title = "Fahrpreise von \(Format.monthYear(since))"
            message = "Preise können abweichen; \(fetch)"
            spoken = "Die Fahrpreise in der App sind von \(Format.monthYear(since)). \(message)"
            explanation = [
                "Die jüngste Preisänderung in den Daten der App gilt seit \(Self.longDay(since)). Das ist mehr als \(TariffFreshness.staleAfterMonths) Monate her – seitdem können sich Preise geändert haben.",
                "Die App prüft regelmäßig, ob neue Preise vorliegen. Mit „Jetzt prüfen“ stößt du es sofort an; eine neuere App-Version bringt ebenfalls aktuelle Preise mit.",
            ]
        case .current:
            symbol = "checkmark.seal.fill"
            kicker = "Tarifstand"
            title = "Keine Preisänderung bekannt"
            message = "Neue Preise lädt die App von selbst – ohne App-Update."
            spoken = "\(title). \(message)"
            explanation = [
                "Die App kennt keine anstehende Preisänderung. Normalpreise stammen aus der ÖBB-Preisliste ab \(fareFrom ?? "–"), KlimaTicket-Preise sind mit Stand \(asOf ?? "–") hinterlegt.",
                "Die App prüft regelmäßig, ob neue Preise vorliegen, und lädt sie von selbst – ohne App-Update. Maßgeblich ist immer der Preis beim Kauf.",
            ]
        }
    }

    /// "13. Dezember 2026".
    static func longDay(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: Format.locale, timeZone: Format.timeZone))
    }
}

// MARK: - Banner

/// The notice above the validity card of the Ticket tab. Shows nothing while the prices are current.
struct TariffNoticeBanner: View {
    @Environment(AppState.self) private var app
    @Environment(\.tariffNoticeInput) private var injected
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsDetails = false
    @State private var wiggle = 0
    /// The notice as it was when the details were opened: „Jetzt prüfen“ in the sheet may bring newer prices and end the
    /// notice – the card (which presents the sheet) stays until the sheet is closed, the sheet itself shows the new state.
    @State private var pinned: TariffNoticeCopy?

    var body: some View {
        // Reading the scene phase re-evaluates the notice whenever the app comes back to the foreground – the day may have
        // changed (1 December, 1 January) since the tab was last drawn.
        let _ = scenePhase
        let input = injected ?? app.tariffNoticeInput()
        let live = TariffNoticeCopy(input)
        let shown: TariffNoticeCopy? = showsDetails ? (pinned ?? live) : (live.state.isCurrent ? nil : live)
        Group {
            if let shown {
                banner(shown)
                    .motionTransition(.rise)
            }
        }
        .motionAnimation(Motion.smooth, value: shown?.state)
    }

    private func banner(_ copy: TariffNoticeCopy) -> some View {
        Button {
            pinned = copy
            showsDetails = true
        } label: {
            GlassCard(padding: 0, cornerRadius: Theme.Radius.formGroup, tint: Theme.dawn) {
                layout(copy)
                    .padding(Theme.Spacing.m)
            }
        }
        .buttonStyle(.pressableCard)
        .haptic(.tap, trigger: showsDetails, when: { _, shown in shown })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.spoken)
        .accessibilityHint("Doppeltippen für Details")
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $showsDetails, onDismiss: { pinned = nil }) {
            TariffNoticeSheet(input: injected)   // nil outside the demo: the sheet reads the app's state itself
        }
        .task {
            // The icon wiggles once to say "look here" – never repeated, never under Reduce Motion or in screenshots.
            guard !reduceMotion, !MotionPolicy.isStatic else { return }
            try? await Task.sleep(for: .milliseconds(900))
            wiggle += 1
        }
    }

    @ViewBuilder
    private func layout(_ copy: TariffNoticeCopy) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                tile(copy)
                text(copy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                tile(copy)
                text(copy)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, Theme.Spacing.xs)
                    .accessibilityHidden(true)
            }
        }
    }

    private func tile(_ copy: TariffNoticeCopy) -> some View {
        TktIconTile(symbol: copy.symbol, color: Theme.dawn, size: 40)
            .symbolEffect(.wiggle, options: .nonRepeating, value: wiggle)
    }

    private func text(_ copy: TariffNoticeCopy) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(copy.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(copy.message)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Details

/// What the notice means, the dates behind it and „Jetzt prüfen“. Also reachable from Einstellungen › Preisberechnung.
struct TariffNoticeSheet: View {
    /// nil = the state of the app, read again after every check (so „Zuletzt geprüft“ and the notice follow „Jetzt prüfen“);
    /// only the CI screenshot hosts hand in a fixed one.
    private let fixedInput: TariffNoticeInput?
    /// „Schließen“ under the check button – off when the page is pushed in Einstellungen (the back button closes it).
    var showsClose = true

    @Environment(AppState.self) private var app
    @Environment(\.tariffNoticeInput) private var injected
    @Environment(\.dismiss) private var dismiss
    @State private var check: TarifCheck

    /// `check` is preset only by the CI screenshot hosts (a finished check).
    init(input: TariffNoticeInput? = nil, check: TarifCheck? = nil, showsClose: Bool = true) {
        fixedInput = input
        self.showsClose = showsClose
        _check = State(initialValue: check ?? TarifCheck())
    }

    var body: some View {
        let _ = check.finishedCount   // a finished check re-reads the app's state below
        let input = fixedInput ?? injected ?? app.tariffNoticeInput()
        let copy = TariffNoticeCopy(input)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                hero(copy)
                    .reveal(.focus)
                SurfaceCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.formGroup) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        ForEach(Array(copy.explanation.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .reveal(order: 1)
                facts(input)
                    .reveal(order: 2)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .revealScope()
        .background { SetBackdrop(skyOpacity: 0.55, fadeEnd: 0.55) }
        .tint(Theme.accent)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func hero(_ copy: TariffNoticeCopy) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                TktIconTile(symbol: copy.symbol, color: copy.state.isCurrent ? Theme.pine : Theme.dawn, size: 48)
                Kicker(text: copy.kicker)
            }
            Text(copy.title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(copy.message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func facts(_ input: TariffNoticeInput) -> some View {
        SurfaceCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.formGroup) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Kicker(text: "Stand der Daten")
                fact("Fahrpreise gültig ab", input.fareValidFrom.map { TariffFreshness.germanDate(iso: $0) })
                TktHairline()
                fact("Ticketpreise Stand",
                     TariffFreshness.ticketPricesAsOf(catalog: input.catalog, now: input.now).map { TariffFreshness.germanDate(iso: $0) })
                TktHairline()
                fact("Zuletzt geprüft", input.lastCheck.map { TariffFreshness.germanDate($0) } ?? "noch nicht")
                TktHairline()
                fact("Tarif-Version", "\(input.catalog.version)")
            }
        }
    }

    private func fact(_ title: String, _ value: String?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: Theme.Spacing.s)
                Text(value ?? "–").foregroundStyle(Theme.textPrimary).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.textSecondary)
                Text(value ?? "–").foregroundStyle(Theme.textPrimary).monospacedDigit()
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.xs) {
            TarifCheckButton(check: check)
            if showsClose {
                Button("Schließen") { dismiss() }
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 160, minHeight: 44)
                    .contentShape(.rect)
                    .buttonStyle(.pressable)
                    .foregroundStyle(Theme.accentText)
            }
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, showsClose ? 0 : Theme.Spacing.s)
        .background {
            // Fades in over the first 20 pt, then is solid: nothing of the cards shows through the button and its result.
            LinearGradient(stops: [.init(color: Theme.sheetBackground.opacity(0), location: 0),
                                   .init(color: Theme.sheetBackground, location: 0.2),
                                   .init(color: Theme.sheetBackground, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }
}

// MARK: - „Jetzt prüfen“

/// The check button with its result under it: the arrows turn while it runs, the result morphs in (Aktuell · Aktualisiert ·
/// Kein Netz · Fehlgeschlagen) with one haptic. Used by the sheet; the settings row has its own, list-styled version.
struct TarifCheckButton: View {
    var check: TarifCheck

    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Builds without an online source (local builds) have nothing to ask: the button says so instead of failing.
    private var hasSource: Bool {
        LaunchMode.isScreenshot || app.tariffs.tariffsURL(manifestHint: app.updates.manifest) != nil
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                Task { await check.run(app: app) }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .symbolEffect(.rotate.clockwise, options: .repeat(.continuous),
                                      isActive: check.isChecking && !reduceMotion && !MotionPolicy.isStatic)
                    Text(check.isChecking ? "Wird geprüft …" : "Jetzt prüfen")
                        .contentTransition(.opacity)
                }
            }
            .buttonStyle(.primary)
            .disabled(check.isChecking || !hasSource)
            .accessibilityValue(check.isChecking ? "Wird geprüft" : "")

            if !hasSource {
                Text("Keine Online-Quelle eingerichtet")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            if case .finished(let result) = check.phase {
                Label {
                    Text("\(result.title) · \(result.detail)")
                } icon: {
                    Image(systemName: result.symbol)
                        .foregroundStyle(result.isSuccess ? Theme.positiveText : Theme.summitText)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .motionTransition(.pop)
                .accessibilityElement(children: .combine)
            }
        }
        .motionAnimation(Motion.smooth, value: check.phase)
        .tarifCheckFeedback(check)
    }
}

extension View {
    /// One haptic (success or error) and one VoiceOver announcement per finished check.
    func tarifCheckFeedback(_ check: TarifCheck) -> some View {
        modifier(TarifCheckFeedback(check: check))
    }
}

private struct TarifCheckFeedback: ViewModifier {
    let check: TarifCheck

    func body(content: Content) -> some View {
        content
            .haptic(.success, trigger: check.finishedCount, when: { _, _ in check.phase.result?.isSuccess == true })
            .haptic(.error, trigger: check.finishedCount, when: { _, _ in check.phase.result?.isSuccess == false })
            .onChange(of: check.finishedCount) { _, _ in
                guard let result = check.phase.result else { return }
                AccessibilityNotification.Announcement("Tarifstand: \(result.title). \(result.detail)").post()
            }
    }
}
