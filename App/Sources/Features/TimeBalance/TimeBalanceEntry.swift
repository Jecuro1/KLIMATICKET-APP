import SwiftUI
import SwiftData
import KlimaCore

// The two ways into the Zeitbilanz: the card in Statistik (zooms into the screen) and klimabilanz://timebalance (a sheet
// over whatever is open).

/// Statistik: „Zeitbilanz“ for the ticket year the screen shows.
struct TimeBalanceEntryCard: View {
    let period: TicketPeriod

    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date)
    private var trips: [TripEntity]

    static let zoomID = "timeBalance.entry"

    var body: some View {
        let balance = TimeBalanceMemo.balance(trips: trips, range: period.start...max(period.start, period.end), now: Date(),
                                              profile: WorkSettings.shared.carProfile(catalog: app.catalog))
        NavigationLink {
            TimeBalanceView(period: period)
                .zoomDestination(id: Self.zoomID)
        } label: {
            GlassCard(padding: Theme.Spacing.m + 2) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(alignment: .top, spacing: Theme.Spacing.s + 2) {
                        TimeBalanceTile()
                        VStack(alignment: .leading, spacing: 2) {
                            Kicker(text: "Zeitbilanz")
                            Text(headline(balance))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                            Text(detail(balance))
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                    }
                    if !balance.isEmpty {
                        StatsGrowOnView { grow in
                            TimeBalanceSplitBar(recorded: balance.recordedMinutes, estimated: balance.estimatedMinutes, grow: grow)
                                .frame(height: 8)
                        }
                        .accessibilityHidden(true)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .zoomSource(id: Self.zoomID, cornerRadius: Theme.Radius.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zeitbilanz")
        .accessibilityValue(balance.isEmpty ? "Noch keine Fahrten" : TimeBalanceText.heroSpoken(balance))
        .accessibilityHint("Öffnet deine Stunden in Bahn und Bus im Vergleich mit dem Auto")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("timeBalance.entry")
    }

    private func headline(_ balance: TimeBalance) -> String {
        balance.isEmpty ? "Wie lange du unterwegs bist" : "\(TimeBalanceText.short(balance.totalMinutes)) in Bahn & Bus"
    }

    private func detail(_ balance: TimeBalance) -> String {
        if balance.isEmpty { return "Stunden in Bahn und Bus, Vergleich mit dem Auto, Verspätungen." }
        var text = "\(TimeBalanceText.carSentence(balance.carMinutes))."
        if balance.recordedMinutes > 0 {
            text += " Davon \(Format.percent(balance.recordedShare)) erfasst, der Rest geschätzt."
        } else {
            text += " Noch alles geschätzt."
        }
        return text
    }
}

/// The card's tile: an hourglass on the dusk → glacier gradient.
struct TimeBalanceTile: View {
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: "hourglass")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Theme.dusk, Theme.glacier], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Deep link

/// klimabilanz://timebalance opens the screen in a sheet (RootView: `.timeBalanceLinkHost()`).
@Observable
@MainActor
final class TimeBalanceLink {
    static let shared = TimeBalanceLink()
    var isPresented = false

    func open() { isPresented = true }
}

extension View {
    /// Presents the Zeitbilanz when klimabilanz://timebalance arrives.
    func timeBalanceLinkHost() -> some View {
        modifier(TimeBalanceLinkHost())
    }
}

private struct TimeBalanceLinkHost: ViewModifier {
    @Bindable private var link = TimeBalanceLink.shared

    func body(content: Content) -> some View {
        content.sheet(isPresented: $link.isPresented) {
            NavigationStack {
                TimeBalanceView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .close) {
                                link.isPresented = false
                            }
                            .accessibilityLabel("Schließen")
                        }
                    }
            }
        }
    }
}
