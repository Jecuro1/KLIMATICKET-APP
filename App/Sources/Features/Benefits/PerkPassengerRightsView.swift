import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import KlimaCore

/// "Fahrgastrechte" assistant (KlimaTicket Ö: AGB Pkt. 24, ÖBB-Tarifbestimmungen A.5.4; regional tickets: A.5.3).
/// An honest estimate range with the validity months to mark, how the guarantee works, a checklist
/// (Einwilligung → ÖBB-Anmeldung → Auszahlung nach Ablauf) with links to the official pages, and a local reminder
/// a few days after the ticket expires. Lives inside a NavigationStack provided by the presenter.
struct PerkPassengerRightsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]

    @State private var badMonths: Set<Int> = []
    @State private var completedSteps: Set<Int> = []
    @State private var reminderOn = false
    @State private var reminderStatus: PerkReminderStatus = .unknown
    @State private var asksPermission = false
    @State private var selectionTick = 0
    @State private var successTick = 0

    var body: some View {
        let haptics = app.settings.hapticsEnabled
        Group {
            if let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) {
                content(ticket)
                    .task(id: ticket.id) { await load(ticket) }
                    .onChange(of: scenePhase) { _, phase in
                        guard phase == .active else { return }
                        Task { await refreshReminder(ticket) }
                    }
                    .alert("Erinnerung erlauben?", isPresented: $asksPermission) {
                        Button("Weiter") { Task { await scheduleReminder(ticket, requestingPermission: true) } }
                        Button("Nicht jetzt", role: .cancel) { reminderOn = false }
                    } message: {
                        Text("KlimaBilanz schickt dir genau eine Mitteilung am \(Format.date(reminderDate(ticket), .long)), damit du deine Entschädigung nicht vergisst. Im nächsten Schritt fragt iOS nach der Erlaubnis.")
                    }
            } else {
                noTicket
            }
        }
        .navigationTitle("Fahrgastrechte")
        .navigationBarTitleDisplayMode(.large)
        .perkHaptic(.selection, trigger: selectionTick, enabled: haptics)
        .perkHaptic(.success, trigger: successTick, enabled: haptics)
    }

    // MARK: Content

    private func content(_ ticket: TicketEntity) -> some View {
        let scheme = PerkRightsScheme.forFamily(ticket.family)
        let months = PerkPassengerRights.validityMonths(start: ticket.startDate, end: ticket.endDate)
        let estimate = PerkPassengerRights.estimate(scheme: scheme, ticketPrice: ticket.price, badMonths: badMonths.count,
                                                    months: max(1, months.count), firstClassUpgradePrice: upgradePrice(ticket))
        return ScrollView {
            VStack(spacing: PerkStyle.cardSpacing) {
                if scheme == .unknown {
                    unknownSchemeCard
                } else {
                    PerkRightsEstimateCard(ticket: ticket, estimate: estimate, months: months, badMonths: badMonths,
                                           onToggle: toggleMonth)
                    PerkRightsFactsCard(scheme: scheme)
                    PerkRightsChecklistCard(steps: steps(for: scheme, ticket: ticket), completed: completedSteps,
                                            onToggle: { toggleStep($0, ticket: ticket) },
                                            onOpen: { openURL($0) })
                    reminderCard(ticket)
                }
                footer
                    .padding(.top, Theme.Spacing.xs)
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xxs)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .ambientBackground(.standard, glow: 0.45)
        .navigationSubtitle(ticket.name)
    }

    private var noTicket: some View {
        ScrollView {
            EmptyStateView(symbol: "ticket",
                           title: "Noch kein Ticket",
                           message: "Lege dein KlimaTicket an – dann rechnen wir aus, was dir bei Verspätungen zusteht.",
                           actionTitle: "Zum Ticket") {
                app.isShowingSettings = false
                app.selectedTab = .ticket
            }
            .padding(.top, Theme.Spacing.xxl)
        }
        .ambientBackground(.standard, glow: 0.4)
    }

    private var unknownSchemeCard: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Kicker(text: "Eigenes Ticket")
                Text("Für dieses Ticket kennen wir die Regeln nicht")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Entschädigungen bei Verspätungen regelt dein Verkehrsunternehmen. Für Jahreskarten mit ÖBB-Strecken findest du die Bedingungen auf oebb.at/fahrgastrechte.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    openURL(PerkRightsLinks.oebb)
                } label: {
                    Label("oebb.at/fahrgastrechte", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
            }
        }
    }

    // MARK: Reminder

    private func reminderCard(_ ticket: TicketEntity) -> some View {
        let date = reminderDate(ticket)
        let isPast = date <= Date()
        return GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.tile) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if isPast {
                    HStack(alignment: .top, spacing: Theme.Spacing.s) {
                        reminderIcon(symbol: "bell.badge.fill")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Dein Ticket ist abgelaufen")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            Text("Jetzt ist die Auszahlung dran: Prüf auf oebb.at/fahrgastrechte, ob du angemeldet bist und was dir zusteht.")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Toggle(isOn: reminderBinding(ticket)) {
                        HStack(spacing: Theme.Spacing.s) {
                            reminderIcon(symbol: reminderOn ? "bell.badge.fill" : "bell.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Erinnerung nach Ablauf")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(reminderLine(date))
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .tint(Theme.accent)
                    .accessibilityHint("Erinnert dich \(PerkRightsRules.reminderDelayDays) Tage nach Ablauf an die Entschädigung")
                    if reminderStatus == .denied {
                        deniedRow
                    } else {
                        Text("\(PerkRightsRules.reminderDelayDays) Tage nach Ablauf, damit du die Auszahlung kontrollierst – eine einzige Mitteilung.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// "Fr., 21. Mai 2027 · 09:00 Uhr"
    private func reminderLine(_ date: Date) -> String {
        let year = String(Calendar.vienna.component(.year, from: date))
        return "\(Format.weekdayDayMonth(date)) \(year) · \(Format.time(date)) Uhr"
    }

    private func reminderIcon(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(LinearGradient(colors: [Theme.dawn, Theme.dawn.mix(with: .black, by: 0.15)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: 11, style: .continuous))
            .environment(\.colorScheme, .light)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }

    private var deniedRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Label("Mitteilungen sind für KlimaBilanz aus. Erlaube sie in den iOS-Einstellungen, damit die Erinnerung ankommt.",
                  systemImage: "bell.slash.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.negativeText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Einstellungen öffnen", systemImage: "gear")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }

    private func reminderBinding(_ ticket: TicketEntity) -> Binding<Bool> {
        Binding(
            get: { reminderOn },
            set: { newValue in
                reminderOn = newValue
                if newValue {
                    Task { await requestReminder(ticket) }
                } else {
                    PerkReminderScheduler.cancel(ticketID: ticket.id)
                    selectionTick += 1
                }
            }
        )
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Nicht einverstanden mit einer Entscheidung? Die Agentur für Passagier- und Fahrgastrechte (apf) schlichtet kostenlos.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: PerkRightsLinks.apf) {
                Label("apf.gv.at", systemImage: "arrow.up.right.square")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
            }
            Text("Schätzung ohne Gewähr. Grundlage: AGB KlimaTicket Ö (Pkt. 24), ÖBB-Tarifbestimmungen (A.5) und der von den ÖBB veröffentlichte Entschädigungswert von € 4,35 pro Monat (seit 1. Jänner 2025).")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Model

    private func steps(for scheme: PerkRightsScheme, ticket: TicketEntity) -> [PerkRightsStep] {
        let payoutDay = Format.date(PerkPassengerRights.payoutFrom(expiry: ticket.endDate), .long)
        switch scheme {
        case .klimaTicketOe:
            return [
                PerkRightsStep(id: 0, title: "Einwilligung erteilen",
                               detail: "Im KlimaTicket-Kundenkonto unter „Meine Karten“ das Häkchen zur Datenweitergabe für die Fahrgastrechte setzen.",
                               linkTitle: "Kundenkonto öffnen", link: PerkRightsLinks.klimaTicketAccount),
                PerkRightsStep(id: 1, title: "Bei den ÖBB anmelden",
                               detail: "Danach auf oebb.at/fahrgastrechte registrieren und das Bankkonto für die Auszahlung angeben.",
                               linkTitle: "oebb.at/fahrgastrechte", link: PerkRightsLinks.oebb),
                PerkRightsStep(id: 2, title: "Nach Ablauf Geld erhalten",
                               detail: "Die ÖBB überweisen die Summe einmalig nach Ablauf – ab \(payoutDay).",
                               linkTitle: "Infos auf klimaticket.at", link: PerkRightsLinks.klimaTicketFAQ),
            ]
        case .regional:
            return [
                PerkRightsStep(id: 0, title: "Bei den ÖBB anmelden",
                               detail: "Auf oebb.at/fahrgastrechte registrieren, deine Strecke angeben und das Konto für die Auszahlung hinterlegen.",
                               linkTitle: "oebb.at/fahrgastrechte", link: PerkRightsLinks.oebb),
                PerkRightsStep(id: 1, title: "Nach Ablauf Geld erhalten",
                               detail: "Lag ein Monat unter 95 %, zahlen die ÖBB nach Ablauf automatisch aus – ab \(payoutDay).",
                               linkTitle: nil, link: nil),
            ]
        case .unknown:
            return []
        }
    }

    /// Basis of the 1st-class upgrade compensation – only when the upgrade is the only add-on with a price.
    private func upgradePrice(_ ticket: TicketEntity) -> Double {
        ticket.addOns == ["firstClass"] ? ticket.addOnPrice : 0
    }

    private func reminderDate(_ ticket: TicketEntity) -> Date {
        PerkPassengerRights.reminderDate(expiry: ticket.endDate)
    }

    // MARK: Actions

    private func load(_ ticket: TicketEntity) async {
        badMonths = PerkRightsStore.badMonths(ticketID: ticket.id)
        completedSteps = PerkRightsStore.completedSteps(ticketID: ticket.id)
        await refreshReminder(ticket)
    }

    /// Reads the pending reminder; re-schedules it when the ticket's end date changed in the meantime.
    private func refreshReminder(_ ticket: TicketEntity) async {
        if LaunchMode.isScreenshot {
            reminderOn = true
            reminderStatus = .authorized
            return
        }
        let status = await PerkReminderScheduler.authorizationStatus()
        reminderStatus = PerkReminderStatus(status)
        let scheduled = await PerkReminderScheduler.isScheduled(ticketID: ticket.id)
        reminderOn = scheduled
        if scheduled {
            // Moves the reminder when the ticket's end date changed in the meantime (or drops it once it is too late).
            reminderOn = await PerkReminderScheduler.schedule(ticket, requestingPermission: false) != .tooLate
        }
    }

    private func requestReminder(_ ticket: TicketEntity) async {
        let status = await PerkReminderScheduler.authorizationStatus()
        if status == .notDetermined {
            asksPermission = true
        } else {
            await scheduleReminder(ticket, requestingPermission: false)
        }
    }

    private func scheduleReminder(_ ticket: TicketEntity, requestingPermission: Bool) async {
        let outcome = await PerkReminderScheduler.schedule(ticket, requestingPermission: requestingPermission)
        reminderStatus = PerkReminderStatus(await PerkReminderScheduler.authorizationStatus())
        switch outcome {
        case .scheduled(let date):
            reminderOn = true
            successTick += 1
            app.showToast("bell.badge.fill", "Erinnerung geplant", "\(Format.date(date, .long)) · \(Format.time(date)) Uhr")
        case .denied, .tooLate, .notApplicable:
            reminderOn = false
        }
    }

    private func toggleMonth(_ index: Int) {
        guard let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            if badMonths.contains(index) { badMonths.remove(index) } else { badMonths.insert(index) }
        }
        PerkRightsStore.setBadMonths(badMonths, ticketID: ticket.id)
        selectionTick += 1
    }

    private func toggleStep(_ id: Int, ticket: TicketEntity) {
        let wasDone = completedSteps.contains(id)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            if wasDone { completedSteps.remove(id) } else { completedSteps.insert(id) }
        }
        PerkRightsStore.setCompletedSteps(completedSteps, ticketID: ticket.id)
        if wasDone { selectionTick += 1 } else { successTick += 1 }
    }
}

// MARK: - Supporting types

/// Official pages (all found in the project research: klimaticket.at FAQ, ÖBB Fahrgastrechte, apf).
enum PerkRightsLinks {
    static let oebb = URL(string: "https://www.oebb.at/fahrgastrechte")!
    static let klimaTicketAccount = URL(string: "https://shop.klimaticket.at/")!
    static let klimaTicketFAQ = URL(string: "https://www.klimaticket.at/#faq-fahrgastrechte")!
    static let apf = URL(string: "https://www.apf.gv.at")!
}

enum PerkReminderStatus: Equatable {
    case unknown, notDetermined, denied, authorized

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized, .provisional, .ephemeral: self = .authorized
        @unknown default: self = .unknown
        }
    }
}

struct PerkRightsStep: Identifiable {
    var id: Int
    var title: String
    var detail: String
    var linkTitle: String?
    var link: URL?
}

// MARK: - Estimate card

/// "DEINE SCHÄTZUNG · € 0–62" with the twelve validity months to mark and the per-month / per-year figures.
struct PerkRightsEstimateCard: View {
    let ticket: TicketEntity
    let estimate: PerkRightsEstimate
    let months: [DateInterval]
    let badMonths: Set<Int>
    var onToggle: (Int) -> Void

    var body: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .center) {
                    Kicker(text: "Deine Schätzung")
                    Spacer(minLength: Theme.Spacing.xs)
                    PerkPill(text: "\(Format.number(estimate.scheme.threshold * 100)) %-Garantie", symbol: "checkmark.shield.fill",
                             foreground: Theme.positiveText, fill: Theme.pine)
                }
                VStack(alignment: .leading, spacing: 2) {
                    numeral
                    Text(subline)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                PerkMonthGrid(months: months, badMonths: badMonths, threshold: estimate.scheme.threshold, onToggle: onToggle)
                    .padding(.top, Theme.Spacing.xxs)
                Text("Tippe die Monate an, in denen die ÖBB laut oebb.at/fahrgastrechte unter \(Format.number(estimate.scheme.threshold * 100)) % pünktlich waren.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 1)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .accessibilityHidden(true)

                VStack(spacing: Theme.Spacing.xs) {
                    if estimate.scheme == .klimaTicketOe {
                        figureRow("Pro Monat unter 93 %", value: range(estimate.monthlyLow, estimate.monthlyHigh, decimals: 2))
                        figureRow("Höchstens im Ticketjahr", value: Format.euroPrecise(estimate.yearlyMaxHigh))
                    } else {
                        figureRow("Pro Monat unter 95 %", value: "bis \(Format.euroPrecise(estimate.monthlyHigh))")
                        figureRow("Höchstens im Ticketjahr", value: "bis \(Format.euroPrecise(estimate.yearlyMaxHigh))")
                    }
                    if estimate.upgradeMonthly > 0 {
                        figureRow("davon 1.-Klasse-Upgrade", value: "\(Format.euroPrecise(estimate.upgradeMonthly)) / Monat")
                    }
                    figureRow("Auszahlung", value: "ab \(Format.date(PerkPassengerRights.payoutFrom(expiry: ticket.endDate), .abbreviated))")
                }
                if estimate.mayFallBelowMinimum {
                    Label("Beträge unter € 4 werden eventuell nicht ausbezahlt.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.summitText)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder
    private var numeral: some View {
        let marked = estimate.badMonths > 0
        let low = marked ? estimate.expectedLow : 0
        let high = marked ? estimate.expectedHigh : estimate.yearlyMaxHigh
        let decimals = marked ? 2 : 0
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(estimate.scheme == .klimaTicketOe ? "€" : "bis €")
                .font(PerkStyle.heroSymbol)
                .foregroundStyle(Theme.textSecondary)
            Text(numberText(low: low, high: high, decimals: decimals))
                .font(PerkStyle.heroNumber)
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(value: high))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityAmount(low: low, high: high, decimals: decimals))
    }

    private func numberText(low: Double, high: Double, decimals: Int) -> String {
        if estimate.scheme != .klimaTicketOe { return Format.number(high.rounded(.up), decimals: 0) }
        let highValue = decimals == 0 ? high.rounded(.up) : high
        if abs(high - low) < 0.005 { return Format.number(highValue, decimals: decimals) }
        return "\(Format.number(low, decimals: decimals))–\(Format.number(highValue, decimals: decimals))"
    }

    private func accessibilityAmount(low: Double, high: Double, decimals: Int) -> String {
        if estimate.scheme != .klimaTicketOe || abs(high - low) < 0.005 {
            return "bis zu \(Format.euro(high, decimals: decimals))"
        }
        return "zwischen \(Format.euro(low, decimals: decimals)) und \(Format.euro(high, decimals: decimals))"
    }

    private var subline: String {
        let threshold = Format.number(estimate.scheme.threshold * 100)
        if estimate.badMonths > 0 {
            let monthsText = estimate.badMonths == 1 ? "1 Monat" : "\(estimate.badMonths) Monate"
            return "für \(monthsText) unter \(threshold) % – einmal im Jahr nach Ablauf"
        }
        if estimate.scheme == .klimaTicketOe {
            return "je nach Pünktlichkeit der ÖBB in deinen \(estimate.months) Gültigkeitsmonaten – ausbezahlt einmal nach Ablauf."
        }
        return "höchstens 10 % der Entschädigungsbasis – der Bahnanteil deines Ticketpreises."
    }

    private func range(_ low: Double, _ high: Double, decimals: Int) -> String {
        if abs(high - low) < 0.005 { return Format.euro(high, decimals: decimals) }
        return "\(Format.euro(low, decimals: decimals))–\(Format.number(high, decimals: decimals))"
    }

    private func figureRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: Theme.Spacing.xs)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The ticket's validity months as tappable capsules (6 per row). Past and current months can be marked as
/// "unter 93 %"; future months are dashed.
struct PerkMonthGrid: View {
    let months: [DateInterval]
    let badMonths: Set<Int>
    let threshold: Double
    var onToggle: (Int) -> Void

    var body: some View {
        let today = Date()
        let currentIndex = PerkPassengerRights.monthIndex(of: today, in: months)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 6),
                  spacing: Theme.Spacing.s) {
            ForEach(months.indices, id: \.self) { index in
                cell(index: index, isCurrent: index == currentIndex, isFuture: months[index].start > today)
            }
        }
    }

    private func cell(index: Int, isCurrent: Bool, isFuture: Bool) -> some View {
        let isBad = badMonths.contains(index)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            onToggle(index)
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    if isBad {
                        shape.fill(LinearGradient(colors: [Theme.dawn, Theme.alpenglow], startPoint: .top, endPoint: .bottom))
                        Image(systemName: "clock.badge.exclamationmark.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    } else if isFuture {
                        shape.strokeBorder(Theme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    } else {
                        shape.fill(Theme.surfaceSecondary)
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if isCurrent {
                        shape.strokeBorder(Theme.dawn, lineWidth: 2)
                    }
                }
                .frame(height: 32)
                Text(label(index))
                    .font(.caption2.weight(isCurrent ? .bold : .medium))
                    .foregroundStyle(isCurrent ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture && !isBad)
        .accessibilityLabel(longLabel(index))
        .accessibilityValue(isBad ? "unter \(Format.number(threshold * 100)) % markiert" : (isFuture ? "noch nicht vorbei" : "nicht markiert"))
        .accessibilityHint(isFuture ? "" : "Doppeltippen, um den Monat zu markieren")
        .accessibilityAddTraits(isBad ? .isSelected : [])
    }

    private func label(_ index: Int) -> String {
        months[index].start.formatted(.dateTime.month(.abbreviated).locale(Format.locale))
    }

    private func longLabel(_ index: Int) -> String {
        let start = months[index].start
        return "Gültigkeitsmonat \(index + 1): ab \(Format.date(start, .long))"
    }
}

// MARK: - Facts

/// "So funktioniert's" – the rule in three short rows plus the scope note and source.
struct PerkRightsFactsCard: View {
    let scheme: PerkRightsScheme

    var body: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Kicker(text: "So funktioniert's")
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    HStack(alignment: .top, spacing: Theme.Spacing.s) {
                        Image(systemName: fact.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 32, height: 32)
                            .background(Theme.accent.opacity(0.14), in: .circle)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fact.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(fact.detail)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Label(scopeNote, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Theme.Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceSecondary.opacity(0.6), in: .rect(cornerRadius: Theme.Radius.modeTile, style: .continuous))
            }
        }
    }

    private var facts: [(symbol: String, title: String, detail: String)] {
        switch scheme {
        case .klimaTicketOe, .unknown:
            return [
                ("checkmark.shield.fill", "93 % Pünktlichkeit garantiert",
                 "Pro Gültigkeitsmonat und Bahnunternehmen. Ab 5 Minuten 30 Sekunden gilt ein Zug als verspätet, Ausfälle zählen mit."),
                ("percent", "10 % je unpünktlichem Monat",
                 "Du bekommst 10 % des Monatsanteils der Entschädigungsbasis – laut ÖBB derzeit € 4,35 pro Monat."),
                ("calendar.badge.checkmark", "Einmal im Jahr, nach Ablauf",
                 "Höchstens 10 % der Entschädigungsbasis pro Jahr. Beträge unter € 4 können entfallen."),
            ]
        case .regional:
            return [
                ("checkmark.shield.fill", "95 % auf deiner Strecke",
                 "Für Verbund-Jahreskarten garantieren die ÖBB 95 % Pünktlichkeit ihrer Nahverkehrszüge pro Monat."),
                ("percent", "10 % je unpünktlichem Monat",
                 "Basis ist der Bahnanteil deines Ticketpreises (ohne Bus und Stadtverkehr)."),
                ("calendar.badge.checkmark", "Automatisch nach Ablauf",
                 "Bist du angemeldet, zahlen die ÖBB nach Ablauf deiner Jahreskarte automatisch aus."),
            ]
        }
    }

    private var scopeNote: String {
        switch scheme {
        case .klimaTicketOe, .unknown:
            return "Derzeit nur bei den ÖBB möglich. Busse, Stadtverkehre und nicht vernetzte Nebenbahnen zählen nicht."
        case .regional:
            return "Verspätungen im Fernverkehr, in Stadtverkehren, Kernzonen und bei Regionalbussen zählen nicht."
        }
    }
}

// MARK: - Checklist

/// "In 3 Schritten zu deiner Entschädigung" – tappable steps with progress and links to the official pages.
struct PerkRightsChecklistCard: View {
    let steps: [PerkRightsStep]
    let completed: Set<Int>
    var onToggle: (Int) -> Void
    var onOpen: (URL) -> Void

    var body: some View {
        let done = steps.filter { completed.contains($0.id) }.count
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker(text: "Checkliste")
                        Text("In \(steps.count) Schritten zu deinem Geld")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Theme.Spacing.xs)
                    Text("\(done) von \(steps.count)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(done == steps.count ? Theme.positiveText : Theme.textSecondary)
                        .contentTransition(.numericText(value: Double(done)))
                }
                ProgressRail(progress: steps.isEmpty ? 0 : Double(done) / Double(steps.count), height: 6,
                             fill: AnyShapeStyle(LinearGradient(colors: [Theme.glacier, Theme.pine], startPoint: .leading, endPoint: .trailing)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { offset, step in
                        stepRow(step, number: offset + 1, isLast: offset == steps.count - 1)
                    }
                }
            }
        }
    }

    private func stepRow(_ step: PerkRightsStep, number: Int, isLast: Bool) -> some View {
        let isDone = completed.contains(step.id)
        return HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Button {
                onToggle(step.id)
            } label: {
                ZStack {
                    Circle()
                        .fill(isDone ? AnyShapeStyle(Theme.pine) : AnyShapeStyle(Color.clear))
                    Circle()
                        .strokeBorder(isDone ? Theme.pine : Theme.textTertiary, lineWidth: 1.5)
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("\(number)")
                            .font(.footnote.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 30, height: 30)
                .environment(\.colorScheme, isDone ? .light : colorSchemeFallback)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, -7)
            .padding(.leading, -7)
            .accessibilityLabel("Schritt \(number): \(step.title)")
            .accessibilityValue(isDone ? "erledigt" : "offen")
            .accessibilityHint(isDone ? "Als offen markieren" : "Als erledigt markieren")
            .accessibilityAddTraits(isDone ? .isSelected : [])

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isDone ? Theme.textSecondary : Theme.textPrimary)
                    .strikethrough(isDone, color: Theme.textTertiary)
                Text(step.detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let linkTitle = step.linkTitle, let link = step.link {
                    Button {
                        onOpen(link)
                    } label: {
                        Label(linkTitle, systemImage: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accentText)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .accessibilityHint("Öffnet die offizielle Seite im Browser")
                }
            }
            .padding(.bottom, isLast ? 0 : Theme.Spacing.m)
            Spacer(minLength: 0)
        }
    }

    @Environment(\.colorScheme) private var colorSchemeFallback
}
