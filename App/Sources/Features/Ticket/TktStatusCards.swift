import SwiftUI
import UIKit
import UserNotifications
import KlimaCore

// MARK: - Reminders

/// „Verlängerung erinnern“: master toggle (= app-wide renewal reminders) plus 30 / 7 / 1 Tage vorher for this ticket.
/// Asks for notification permission when needed and explains how to re-enable it when it was denied.
struct TktReminderCard: View {
    let ticket: TicketEntity

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    private static let options = [30, 7, 1]

    var body: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                masterRow
                if isOn {
                    TktHairline()
                        .padding(.leading, TktStyle.rowPaddingH)
                    offsetsRow
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    if authStatus == .denied {
                        deniedNotice
                            .transition(.opacity)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .animation(.smooth(duration: 0.3), value: isOn)
        .animation(.smooth(duration: 0.3), value: authStatus == .denied)
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshStatus() } }
        }
    }

    // MARK: Rows

    private var masterRow: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { setEnabled($0) })) {
            HStack(spacing: Theme.Spacing.s) {
                TktIconTile(symbol: "bell.fill", color: Theme.dawn)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verlängerung erinnern")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .contentTransition(.opacity)
                }
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, TktStyle.rowPaddingH)
        .padding(.vertical, TktStyle.rowPaddingV)
    }

    private var offsetsRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xs) { chips }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) { chips }
            }
            Text("Vor dem Ablauf am \(Format.date(ticket.endDate, .long)) · jeweils um 9:00 Uhr")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, TktStyle.rowPaddingH)
        .padding(.vertical, TktStyle.rowPaddingV)
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(Self.options, id: \.self) { offset in
            let selected = ticket.reminderOffsets.contains(offset)
            let past = isPast(offset)
            let state: String = past ? "bereits vorbei" : (selected ? "an" : "aus")
            Chip(title: Format.days(offset), isSelected: selected, tint: Theme.accent) {
                toggle(offset)
            }
            .disabled(past)
            .opacity(past ? 0.45 : 1)
            .accessibilityLabel("\(Format.days(offset)) vorher")
            .accessibilityValue(state)
        }
    }

    private var deniedNotice: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "bell.slash.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.summitText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Mitteilungen sind ausgeschaltet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Erlaube Mitteilungen für KlimaBilanz, damit deine Erinnerungen ankommen.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Einstellungen öffnen") { openSystemSettings() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .buttonStyle(.plain)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TktStyle.rowPaddingH)
        .padding(.vertical, TktStyle.rowPaddingV)
        .background(Theme.dawn.opacity(0.09))
    }

    // MARK: State

    private var isOn: Bool { app.settings.renewalRemindersEnabled }

    private var subtitle: String {
        guard isOn else { return "Aus" }
        let offsets = ticket.reminderOffsets
        if offsets.isEmpty { return "Am Ablauftag um 9:00 Uhr" }
        guard let next = nextReminder else { return "Keine weiteren Erinnerungen" }
        return "\(Format.date(next.date, .long)) · \(Format.days(next.offset)) vorher"
    }

    private var nextReminder: TktReminderSlot? {
        let now = Date()
        var best: TktReminderSlot?
        for offset in ticket.reminderOffsets {
            guard let date = reminderDate(offset), date > now else { continue }
            if let current = best, current.date <= date { continue }
            best = TktReminderSlot(date: date, offset: offset)
        }
        return best
    }

    private func reminderDate(_ offset: Int) -> Date? {
        let cal = Calendar.vienna
        guard let day = cal.date(byAdding: .day, value: -offset, to: ticket.endDate) else { return nil }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)
    }

    private func isPast(_ offset: Int) -> Bool {
        guard let date = reminderDate(offset) else { return true }
        return date < Date()
    }

    // MARK: Actions

    private func setEnabled(_ enabled: Bool) {
        app.settings.renewalRemindersEnabled = enabled
        if enabled {
            Repository(context: context, app: app).scheduleReminders(for: ticket)
            Task { await ensurePermission() }
        } else {
            let id = ticket.id
            Task { await app.notifications.cancelRenewalReminders(ticketID: id) }
        }
    }

    private func toggle(_ offset: Int) {
        var offsets = Set(ticket.reminderOffsets)
        let isAdding = !offsets.contains(offset)
        if isAdding { offsets.insert(offset) } else { offsets.remove(offset) }
        withAnimation(.snappy(duration: 0.25)) {
            ticket.reminderOffsets = offsets.sorted(by: >)
        }
        Repository(context: context, app: app).updateTicket(ticket)
        if isAdding { Task { await ensurePermission() } }
    }

    /// Asks once (status "not determined"); reschedules after a grant. A denial is explained inline,
    /// the toast only appears right after the user declined the system prompt.
    private func ensurePermission() async {
        var status = await app.notifications.authorizationStatus()
        if status == .notDetermined {
            let granted = await app.notifications.requestAuthorization()
            status = await app.notifications.authorizationStatus()
            if granted {
                Repository(context: context, app: app).scheduleReminders(for: ticket)
            } else {
                app.showToast("bell.slash.fill", "Ohne Mitteilungen keine Erinnerung", "Du kannst sie in den iOS-Einstellungen erlauben.")
            }
        }
        withAnimation(.smooth(duration: 0.3)) { authStatus = status }
    }

    private func refreshStatus() async {
        let status = await app.notifications.authorizationStatus()
        withAnimation(.smooth(duration: 0.3)) { authStatus = status }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

private struct TktReminderSlot {
    var date: Date
    var offset: Int
}

// MARK: - Monthly payment

/// „Monatlich bezahlen“: toggles `isMonthlyPayment`; when on shows what has been paid so far (n von 12 Raten)
/// and whether the logged value already covers it.
struct TktPaymentCard: View {
    let ticket: TicketEntity
    let totalValue: Double

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                toggleRow
                if ticket.isMonthlyPayment {
                    TktHairline()
                        .padding(.leading, TktStyle.rowPaddingH)
                    instalments
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: ticket.isMonthlyPayment)
    }

    private var rate: Double { ticket.price / 12 }

    private var paymentSubtitle: String {
        ticket.isMonthlyPayment ? "12 Raten à \(Format.euroPrecise(rate))" : "Einmalzahlung · \(Format.euroPrecise(ticket.price))"
    }

    private var toggleRow: some View {
        Toggle(isOn: Binding(get: { ticket.isMonthlyPayment }, set: { setMonthly($0) })) {
            HStack(spacing: Theme.Spacing.s) {
                TktIconTile(symbol: "calendar.badge.clock", color: Theme.glacier)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monatlich bezahlen")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(paymentSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .contentTransition(.opacity)
                }
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, TktStyle.rowPaddingH)
        .padding(.vertical, TktStyle.rowPaddingV)
    }

    private var instalments: some View {
        let paid = ticket.paidSoFar()
        let count = rate > 0 ? min(12, max(0, Int((paid / rate).rounded()))) : 0
        let covered = totalValue >= paid
        let status: String = covered ? "Deine Raten sind schon gedeckt" : "Noch \(Format.euroPrecise(paid - totalValue)) bis deine Raten gedeckt sind"
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Kicker(text: "Bisher bezahlt")
                    Text(Format.euroPrecise(paid))
                        .font(Theme.Typography.numberMedium)
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText(value: paid))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: Theme.Spacing.xs)
                Text("\(count) von 12 Raten")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .combine)
            TktInstalmentBar(paid: count)
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(status)
                } icon: {
                    Image(systemName: covered ? "checkmark.seal.fill" : "hourglass")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(covered ? Theme.positiveText : Theme.summitText)
                Text("\(Format.euro(totalValue, decimals: 0)) Fahrtwert · \(Format.euro(paid, decimals: 0)) bezahlt")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, TktStyle.rowPaddingH)
        .padding(.vertical, TktStyle.rowPaddingV + Theme.Spacing.xxs)
    }

    private func setMonthly(_ isOn: Bool) {
        ticket.isMonthlyPayment = isOn
        Repository(context: context, app: app).updateTicket(ticket)
    }
}

/// Twelve instalment segments; paid ones show the route gradient (one continuous gradient across all segments).
private struct TktInstalmentBar: View {
    var paid: Int

    var body: some View {
        ZStack {
            segments { _ in Theme.surfaceSecondary }
            Rectangle()
                .fill(Theme.routeGradient)
                .mask { segments { index in index < paid ? Color.black : Color.clear } }
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(paid) von 12 Raten bezahlt")
    }

    private func segments(_ color: @escaping (Int) -> Color) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                Capsule().fill(color(index))
            }
        }
    }
}

// MARK: - Renewal

/// Shown when the ticket expires within 45 days (or has expired): "Folgeticket anlegen" with the catalog price preview –
/// or, once a follow-up exists, a compact confirmation that jumps to it.
struct TktRenewalCard: View {
    let ticket: TicketEntity
    let followUp: TicketEntity?
    let daysRemaining: Int
    var onRenew: () -> Void
    var onShow: (TicketEntity) -> Void

    @Environment(AppState.self) private var app

    var body: some View {
        if let followUp {
            followUpCard(followUp)
        } else {
            renewCard
        }
    }

    private var nextStart: Date {
        let cal = Calendar.vienna
        return cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: ticket.endDate) ?? ticket.endDate)
    }

    private var nextPrice: Double {
        app.catalog.product(id: ticket.productID)?.price(forStart: nextStart) ?? ticket.price
    }

    private var title: String {
        if ticket.isExpired { return "Dein Ticket ist abgelaufen" }
        if daysRemaining == 0 { return "Heute ist der letzte Tag" }
        return "Noch \(Format.days(daysRemaining)) gültig"
    }

    private var renewCard: some View {
        GlassCard(tint: Theme.dawn) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    TktIconTile(symbol: "arrow.triangle.2.circlepath", color: Theme.dawn, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Kicker(text: "Verlängern", color: Theme.summitText)
                        Text(title)
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Leg dein Folgeticket an – die neue Bilanz startet am \(Format.date(nextStart, .long)). Deine bisherigen Jahre bleiben im Verlauf.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                pricePreview
                Button(action: onRenew) {
                    Label("Folgeticket anlegen", systemImage: "plus")
                }
                .buttonStyle(.primary)
            }
        }
    }

    private var pricePreview: some View {
        let delta = nextPrice - ticket.price
        let deltaText: String
        let deltaColor: Color
        if abs(delta) < 0.5 {
            deltaText = "gleicher Preis wie bisher"
            deltaColor = Theme.textSecondary
        } else if delta > 0 {
            deltaText = "\(Format.euro(delta)) mehr als bisher"
            deltaColor = Theme.summitText
        } else {
            deltaText = "\(Format.euro(-delta)) weniger als bisher"
            deltaColor = Theme.positiveText
        }
        return HStack(alignment: .center, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ticket.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("ab \(Format.date(nextStart, .long))")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.euro(nextPrice))
                    .font(Theme.Typography.numberMedium)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(deltaText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(deltaColor)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.surfaceSecondary, in: .rect(cornerRadius: Theme.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func followUpCard(_ next: TicketEntity) -> some View {
        GlassCard(padding: Theme.Spacing.m, tint: Theme.pine) {
            HStack(spacing: Theme.Spacing.s) {
                TktIconTile(symbol: "checkmark", color: Theme.pine)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Folgeticket angelegt")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("gültig ab \(Format.date(next.startDate, .long))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.xs)
                Button("Anzeigen") { onShow(next) }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
    }
}
