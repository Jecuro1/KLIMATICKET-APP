import SwiftUI
import KlimaCore

// MARK: commute – the card inside the live window: header (direction, route, countdown, „Richtung tauschen“), the disruption
// banner, three connections, the age of the data and the four quick actions. Without live data: the plan and, while the
// decision is open, one offer to switch live data on (never again once declined – no consent loop).

struct CommuteLiveCard: View {
    let slot: CommuteSlot
    let now: Date

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsConsent = false
    @State private var swapTick = 0
    private var model: CommuteModel { .shared }

    var body: some View {
        let direction = model.direction(for: slot)
        let unavailable = model.liveUnavailable(app.live)
        let rows = unavailable == nil ? model.visibleRows(at: now) : []
        let advice = CommuteAdvisor.advice(rows: rows, now: now)
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                header(direction: direction, rows: rows, live: unavailable == nil)
                if let unavailable {
                    CommutePlanBody(slot: slot, direction: direction, unavailable: unavailable) { showsConsent = true }
                } else {
                    if let advice {
                        CommuteDisruptionBanner(advice: advice)
                            .motionTransition(.rise)
                    }
                    rowsBlock(rows: Array(rows.prefix(3)), advice: advice, direction: direction)
                    CommuteDataAgeLine(fetchedAt: model.fetchedAt, hasRealtime: rows.contains(where: \.hasRealtime),
                                       isOffline: model.phase == .failed(.offline), isDemo: model.demo != nil || app.live.isDemo)
                }
                CommuteActionGrid(items: actionItems(direction: direction, first: rows.first { !$0.isCancelled }))
                    .padding(.top, Theme.Spacing.xxs)
            }
        }
        .contextMenu { contextMenu(direction: direction, first: rows.first { !$0.isCancelled }) }
        .accessibilityElement(children: .contain)
        .accessibilityActions { accessibilityActions(direction: direction, first: rows.first { !$0.isCancelled }) }
        .celebrate(trigger: model.focusTick, haptic: nil)
        .motionAnimation(Motion.smooth, value: rows.map(\.id))
        .motionAnimation(Motion.smooth, value: advice?.affected.id)
        .sheet(isPresented: $showsConsent) { CommuteConsentSheet() }
    }

    // MARK: Header

    private func header(direction: CommuteDirection, rows: [CommuteRow], live: Bool) -> some View {
        let ends = model.ends(direction)
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
                             : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.s))
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 12.5, weight: .bold))   // the kicker's own fixed size
                        .foregroundStyle(Theme.accentText)
                        .accessibilityHidden(true)
                    Kicker(text: "Pendeln · \(direction.title)", color: Theme.accentText)
                }
                if let ends {
                    CommuteRouteTitle(from: ends.from.name, to: ends.to.name)
                }
            }
            .layoutPriority(1)
            if !stacked { Spacer(minLength: Theme.Spacing.xs) }
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                CommuteCountdown(target: countdownTarget(rows: rows, live: live), now: now, isPlan: !live)
                Button {
                    swapTick += 1
                    withMotion(Motion.bouncy) { model.swapDirection(for: slot) }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 15, weight: .bold))
                        .rotationEffect(.degrees(direction == .outbound ? 0 : 180))
                        .frame(width: 40, height: 40)
                        .contentShape(.circle)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .haptic(.tap, trigger: swapTick)
                .accessibilityLabel("Richtung tauschen")
                .accessibilityHint(direction == .outbound ? "Zeigt die Rückfahrt" : "Zeigt die Hinfahrt")
            }
        }
    }

    /// The departure the countdown counts to: the earliest connection that still runs, by its realtime departure (a late
    /// first train can leave after the second one), else the plan's time.
    private func countdownTarget(rows: [CommuteRow], live: Bool) -> Date {
        guard live else { return slot.departure }
        return rows.filter { !$0.isCancelled }.map(\.effectiveDeparture).min() ?? slot.departure
    }

    // MARK: Rows

    @ViewBuilder
    private func rowsBlock(rows: [CommuteRow], advice: CommuteAdvice?, direction: CommuteDirection) -> some View {
        let destination = model.ends(direction).map { TripRow.short($0.to.name) } ?? ""
        switch model.phase {
        case .loading where rows.isEmpty, .idle where rows.isEmpty:
            CommuteRowsSkeleton()
        case .failed(.noConnection) where rows.isEmpty:
            CommuteNotice(symbol: "moon.zzz", text: "Keine Verbindung in den nächsten Stunden gefunden.")
        case .failed(.unavailable) where rows.isEmpty:
            CommuteNotice(symbol: "antenna.radiowaves.left.and.right.slash", text: "Live-Daten sind gerade nicht erreichbar.")
        case .failed(.failed) where rows.isEmpty:
            CommuteNotice(symbol: "exclamationmark.icloud", text: "ÖBB-Auskunft gerade nicht erreichbar – versucht es in einer Minute wieder.")
        case .failed(.offline) where rows.isEmpty:
            CommuteNotice(symbol: "wifi.slash", text: "Offline – laut Plan um \(CommutePlan.clockText(model.settings.plan.minute(for: direction))).")
        default:
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    CommuteConnectionRow(row: row, destination: destination, now: now,
                                         isAlternative: row.id == advice?.alternative?.id, isFirst: index == 0)
                        .reveal(.rise, order: index)
                    if index < rows.count - 1 { Divider().overlay(Theme.separator) }
                }
            }
        }
    }

    // MARK: Actions

    /// Without live data there is nothing to follow: „Live verfolgen“ is left out instead of shown dimmed.
    private func actionItems(direction: CommuteDirection, first: CommuteRow?) -> [CommuteActionItem] {
        let actions = CommuteActions(app: app)
        let followRow = first.flatMap { actions.followTarget($0) == nil ? nil : $0 }
        var items = [CommuteActionItem(title: "Fahrt erfassen", symbol: "plus.circle.fill", isPrimary: true) { actions.logTrip(now: now) }]
        if model.liveUnavailable(app.live) == nil {
            items.append(CommuteActionItem(title: "Live verfolgen", symbol: "location.fill", isEnabled: followRow != nil) {
                if let followRow { actions.follow(followRow) }
            })
        }
        items.append(CommuteActionItem(title: "Rückfahrt planen", symbol: "arrow.uturn.backward") { actions.planReturn(shown: direction, now: now) })
        items.append(CommuteActionItem(title: "Verbindung ändern", symbol: "slider.horizontal.3") { actions.changeConnection(shown: direction) })
        return items
    }

    @ViewBuilder
    private func contextMenu(direction: CommuteDirection, first: CommuteRow?) -> some View {
        ForEach(actionItems(direction: direction, first: first)) { item in
            Button(item.title, systemImage: item.symbol, action: item.action).disabled(!item.isEnabled)
        }
        Button("Richtung tauschen", systemImage: "arrow.left.arrow.right") { withMotion(Motion.bouncy) { model.swapDirection(for: slot) } }
        Button("Pendel-Einstellungen", systemImage: "gearshape") { model.showsSetup = true }
    }

    @ViewBuilder
    private func accessibilityActions(direction: CommuteDirection, first: CommuteRow?) -> some View {
        ForEach(actionItems(direction: direction, first: first).filter(\.isEnabled)) { item in
            Button(item.title, action: item.action)
        }
        Button("Richtung tauschen") { model.swapDirection(for: slot) }
    }
}

// MARK: - Plan only (no live data)

/// The plan's departure and, while the decision is open, the offer to switch live data on. Declined or switched off: one quiet
/// line that says why there is no delay – no second offer.
struct CommutePlanBody: View {
    let slot: CommuteSlot
    let direction: CommuteDirection
    let unavailable: LiveDataService.Unavailable
    var onEnable: () -> Void

    @Environment(AppState.self) private var app
    private var model: CommuteModel { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(CommutePlan.clockText(model.settings.plan.minute(for: direction)))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text("laut deinem Plan · \(model.settings.plan.dayText)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            switch unavailable {
            case .consentUndecided:
                Button(action: onEnable) {
                    HStack(alignment: .top, spacing: Theme.Spacing.s) {
                        SetIconTile(symbol: "dot.radiowaves.left.and.right", tint: Theme.glacier, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Verspätung und Gleis live sehen?")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Mit Live-Daten zeigt die Karte hier die nächsten Züge, Verspätungen und eine Alternative bei Ausfall.")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                    }
                    .padding(Theme.Spacing.s)
                    .background(Theme.surfaceSecondary.opacity(0.6), in: .rect(cornerRadius: 16, style: .continuous))
                    .contentShape(.rect)
                }
                .buttonStyle(.pressableCard)
                .accessibilityHint("Erklärt die Live-Daten und fragt nach deiner Zustimmung")
            default:
                CommuteNotice(symbol: "antenna.radiowaves.left.and.right.slash", text: Self.reason(unavailable))
            }
        }
    }

    static func reason(_ unavailable: LiveDataService.Unavailable) -> String {
        switch unavailable {
        case .consentUndecided, .declined: "Live-Daten sind aus – die Karte zeigt deinen Plan. Einschalten kannst du sie unter Einstellungen › Live-Daten."
        case .switchedOff: "Fahrplan live ist ausgeschaltet – die Karte zeigt deinen Plan."
        case .killSwitch(let notice): notice ?? "Live-Daten sind gerade pausiert – die Karte zeigt deinen Plan."
        case .offline: "Offline – die Karte zeigt deinen Plan."
        }
    }
}

/// The consent card of the Fahrplan in a sheet: the same words, the same two buttons, closes itself after the decision.
struct CommuteConsentSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LiveConsentCard(style: .card)
                .padding(Theme.Spacing.cardGutter)
        }
        .background(Theme.sheetBackground)
        .presentationDetents([.medium, .large])
        .onChange(of: app.live.consent) { _, consent in
            if consent != .undecided { dismiss() }
        }
    }
}
