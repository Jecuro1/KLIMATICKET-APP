import SwiftUI
import SwiftData
import KlimaCore

/// TEMPORARY prototype (replaced by the dashboard module) – used to preview the design system on device.
struct DashboardView: View {
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse) private var trips: [TripEntity]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) {
                    let snap = Analytics.make(ticket: ticket, trips: trips, catalog: app.catalog)
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        Kicker(text: Format.weekdayDayMonth(Date()))
                        VStack(spacing: 4) {
                            HStack(alignment: .top, spacing: 2) {
                                Text(Format.number(snap.summary.amortizedFraction * 100))
                                    .font(Theme.Typography.hero)
                                Text("%").font(.system(size: 40, weight: .light, design: .rounded)).padding(.top, 14)
                            }
                            Text("\(Format.euro(snap.summary.totalValue)) von \(Format.euro(snap.summary.ticketPrice)) amortisiert")
                                .font(.title3)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        SummitChart(series: snap.series, forecast: snap.forecast, start: ticket.startDate, end: ticket.endDate,
                                    price: ticket.price, breakEvenDate: snap.summary.forecastBreakEvenDate, isPaidOff: snap.summary.isPaidOff)
                            .frame(height: 260)
                            .padding(.horizontal, -Theme.Spacing.screen)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.s) {
                            StatTile(value: "\(snap.summary.tripCount)", label: "Fahrten", symbol: "train.side.front.car")
                            StatTile(value: Format.number(snap.summary.distanceKm), unit: "km", label: "Kilometer", symbol: "point.topleft.down.to.point.bottomright.curvepath", color: Theme.accentSecondary)
                            StatTile(value: Format.number(snap.summary.co2SavedKg), unit: "kg", label: "CO₂ gespart", symbol: "leaf.fill", color: Theme.eco)
                            StatTile(value: Format.euro(snap.summary.carCostEquivalent), label: "mit dem Auto", symbol: "car.fill", color: Theme.remaining)
                        }
                        SectionHeader(title: "Letzte Fahrten", actionTitle: "Alle") {}
                        GlassCard(padding: Theme.Spacing.m) {
                            VStack(spacing: 0) {
                                ForEach(trips.prefix(4)) { trip in
                                    TripRow(trip: trip)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.screen)
                    .padding(.bottom, 120)
                }
            }
            .ambientBackground()
            .navigationTitle("Übersicht")
        }
    }
}
