import SwiftUI
import SwiftData
import KlimaCore

/// Pure helpers that turn the stored ticket + trips into the car comparison (logic lives in KlimaCore.CarComparison).
@MainActor
enum WorkCarCalc {
    static func result(period: TicketPeriod, records: [TripRecord], catalog: TariffCatalog, now: Date = Date()) -> CarComparisonResult {
        CarComparison.compare(ticket: period, trips: records, profile: WorkSettings.shared.carProfile(catalog: catalog),
                              emissions: catalog.emissions, now: now)
    }

    /// The ticket matching a period handed over from the statistics tab (own share may have changed meanwhile).
    static func ticket(matching period: TicketPeriod?, in tickets: [TicketEntity], selectedID: UUID?) -> TicketEntity? {
        if let period, let match = tickets.first(where: { $0.deletedAt == nil && $0.productID == period.productID
            && $0.startDate == period.start && $0.endDate == period.end }) {
            return match
        }
        return Analytics.activeTicket(in: tickets, selectedID: selectedID)
    }

    /// "Kilometergeld · € 0,50/km"
    static func modeSummary(_ result: CarComparisonResult) -> String {
        "\(WorkSettings.shared.carMode.displayName) · \(WorkFormat.perKm(result.costPerKm))"
    }
}

/// "Öffis vs. Auto": what the same trips would have cost by car, when the ticket overtook the car, CO₂ and time.
struct WorkCarView: View {
    /// Ticket year chosen in the statistics tab (nil = the app-wide active ticket).
    var period: TicketPeriod? = nil

    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date)
    private var trips: [TripEntity]

    var body: some View {
        Group {
            if let ticket = WorkCarCalc.ticket(matching: period, in: tickets, selectedID: app.settings.selectedTicketID) {
                let ticketPeriod = ticket.period
                let records = trips.filter { ticketPeriod.contains($0.date) }.map(\.record)
                WorkCarScreen(ticket: ticket, period: ticketPeriod,
                              result: WorkCarCalc.result(period: ticketPeriod, records: records, catalog: app.catalog))
            } else {
                ScrollView {
                    EmptyStateView(symbol: "ticket", title: "Noch kein Ticket",
                                   message: "Lege dein KlimaTicket an – dann rechnet KlimaBilanz aus, was dieselben Wege mit dem Auto gekostet hätten.",
                                   actionTitle: "Zum Ticket") {
                        app.isShowingSettings = false
                        app.selectedTab = .ticket
                    }
                    .padding(.top, Theme.Spacing.xxl)
                }
            }
        }
        .ambientBackground()
        .navigationTitle("Öffis vs. Auto")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    WorkCarSettingsView(showsDetailLink: false)
                } label: {
                    Label("Berechnung anpassen", systemImage: "slider.horizontal.3")
                }
            }
        }
    }
}

/// The populated screen.
private struct WorkCarScreen: View {
    let ticket: TicketEntity
    let period: TicketPeriod
    let result: CarComparisonResult

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 64
    @ScaledMetric(relativeTo: .largeTitle) private var statSize: CGFloat = 40

    private var settings: WorkSettings { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Kicker(text: "Ticketjahr \(StatsCalc.ticketYearLabel(period)) · \(ticket.name)")
                    .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                    .padding(.bottom, Theme.Spacing.xxs)
                if result.tripCount == 0 {
                    GlassCard {
                        EmptyStateView(symbol: "car.side.fill", title: "Noch keine Fahrten",
                                       message: "Sobald du Fahrten erfasst, siehst du hier, was dieselben Wege mit dem Auto gekostet hätten – und ab wann dein Ticket günstiger ist.",
                                       actionTitle: "Erste Fahrt erfassen") {
                            app.presentAddTrip()
                        }
                    }
                } else {
                    heroCard
                        .reveal(order: 1)
                    StatsGrowOnView(delay: Motion.Stagger.delay(2)) { chartCard(grow: $0) }
                        .reveal(order: 2)
                        .scrollCardTransition()
                    assumptionsCard
                        .reveal(order: 3)
                        .scrollCardTransition()
                    StatsGrowOnView(delay: Motion.Stagger.delay(4)) { grow in
                        tilesLayout {
                            co2Tile(grow: grow)
                            timeTile
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .reveal(order: 4)
                    .scrollCardTransition()
                    WorkSourceLinks(sources: WorkSourceLinks.car)
                        .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                        .padding(.top, Theme.Spacing.s)
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .revealScope()
        .haptic(.selection, trigger: settings.carMode)
    }

    /// Side by side; stacked with large text.
    private var tilesLayout: AnyLayout {
        typeSize >= .xxLarge ? AnyLayout(VStackLayout(spacing: Theme.Spacing.s))
                             : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.s))
    }

    // MARK: Hero

    private var heroCard: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Kicker(text: result.isCheaperThanCar ? "Günstiger als mit dem Auto" : "Noch bis zum Gleichstand mit dem Auto")
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    WorkEuroNumeral(value: abs(result.isCheaperThanCar ? result.savings : result.remainingToBreakEven),
                                    size: numeralSize, color: result.isCheaperThanCar ? Theme.positive : Theme.textPrimary,
                                    countsIn: true)
                    verdict
                }
                Divider().overlay(Theme.separator)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Theme.Spacing.m) {
                        carColumn
                        Spacer(minLength: 0)
                        ticketColumn
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        carColumn
                        ticketColumn
                    }
                }
                modeChip
            }
        }
    }

    private var modeChip: some View {
        NavigationLink {
            WorkCarSettingsView(showsDetailLink: false)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: settings.carMode.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(settings.carMode.tint)
                Text("Berechnung: \(WorkCarCalc.modeSummary(result))")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Berechnung: \(WorkCarCalc.modeSummary(result))")
        .accessibilityHint("Öffnet die Einstellungen des Auto-Vergleichs")
    }

    @ViewBuilder
    private var verdict: some View {
        if result.isCheaperThanCar {
            Label {
                if let day = result.breakEvenDate, day > Calendar.vienna.startOfDay(for: period.start) {
                    Text("Seit \(Format.dayMonth(day)) fährst du günstiger als mit dem Auto")
                } else {
                    Text("Von Anfang an günstiger als das Auto")
                }
            } icon: {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.positive)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.positiveText)
        } else if let day = result.forecastBreakEvenDate {
            Label {
                Text("Voraussichtlich ab \(Format.dayMonth(day)) günstiger als das Auto")
            } icon: {
                Image(systemName: "flag.fill").foregroundStyle(Theme.positive)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
        } else {
            Label {
                Text(StatsCalc.isRunning(period)
                     ? "Bei deinem Tempo käme das Auto bis Ablauf auf rund \(Format.euro(result.projectedEndCarCost, decimals: 0)) – dein Ticket bleibt diesmal teurer."
                     : "Mit dem Auto wären es \(Format.euro(result.carCost, decimals: 0)) gewesen.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "car.fill").foregroundStyle(Theme.summit)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
        }
    }

    private var carColumn: some View {
        var detail = "\(Format.km(result.roadKm)) × \(Format.euroPrecise(result.costPerKm))"
        if result.fixedCostsToDate > 0 { detail += "\n+ \(Format.euro(result.fixedCostsToDate, decimals: 0)) Fixkosten" }
        return costColumn(symbol: "car.fill", tint: Theme.dawn, title: "Mit dem Auto", value: result.carCost, detail: detail)
    }

    private var ticketColumn: some View {
        let hasEmployer = ticket.employerContribution > 0
        let detail = hasEmployer ? "dein Eigenanteil" : (ticket.addOnPrice > 0 ? "inkl. Extras" : "Ticketpreis")
        return costColumn(symbol: "ticket.fill", tint: Theme.glacier, title: "Dein KlimaTicket", value: result.ticketCost, detail: detail)
    }

    private func costColumn(symbol: String, tint: Color, title: String, value: Double, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(Format.euro(value, decimals: 0))
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .numericValue(value.rounded())
                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Chart

    private func chartCard(grow: Double) -> some View {
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StatsCardHeader(kicker: "Kosten-Verlauf", title: "Jede Fahrt macht das Auto teurer – dein Ticket bleibt gleich") {
                    StatsInfoButton(title: "Kosten-Verlauf", text: chartExplanation)
                }
                WorkCarChart(result: result, period: period, grow: grow)
                    .frame(height: 236)
                    .padding(.top, Theme.Spacing.xs)
                legend
            }
        }
    }

    private var chartExplanation: String {
        var text = "Die Auto-Linie wächst mit jeder erfassten Fahrt: Straßenkilometer × \(WorkFormat.perKm(result.costPerKm))."
        if result.fixedCostsPerYear > 0 {
            text += " Dazu kommen die eingesparten Fixkosten (\(Format.euro(result.fixedCostsPerYear, decimals: 0)) pro Jahr) Tag für Tag anteilig."
        }
        text += " Die blaue Linie ist, was du für dein KlimaTicket bezahlt hast. Ab der Fahne fährst du günstiger als mit dem Auto – die grüne Fläche ist deine Ersparnis."
        return text
    }

    private var legend: some View {
        HStack(spacing: Theme.Spacing.s) {
            StatsLegendItem(label: "Auto", style: AnyShapeStyle(LinearGradient(colors: [Theme.dawn, Theme.alpenglow], startPoint: .leading, endPoint: .trailing)))
            StatsLegendItem(label: "KlimaTicket", style: AnyShapeStyle(Theme.glacier))
            if result.forecast.count == 2 {
                StatsLegendItem(label: "Prognose", style: AnyShapeStyle(Theme.alpenglow), dashed: true)
            }
            if result.savings > 0 || result.projectedEndSavings > 0 {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Theme.positive.opacity(0.45))
                        .frame(width: 12, height: 10)
                    Text("Ersparnis")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: So rechnen wir

    private var assumptionsCard: some View {
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                StatsCardHeader(kicker: "So rechnen wir", title: nil)
                WorkFactRow(symbol: "road.lanes", tint: Theme.dusk, title: "Straßenkilometer", value: Format.km(result.roadKm),
                            detail: "\(Format.km(result.railKm)) Bahn-km × \(Format.number(CarProfile.defaultRoadDistanceFactor, decimals: 2)) – mit dem Auto fährst du selten von Bahnhof zu Bahnhof: Wege, Umfahrungen und Parkplatzsuche kommen dazu.")
                WorkFactRow(symbol: settings.carMode.symbol, tint: settings.carMode.tint, title: "Kosten pro Kilometer",
                            value: Format.euroPrecise(result.costPerKm), detail: costDetail)
                if result.fixedCostsPerYear > 0 {
                    WorkFactRow(symbol: "car.side.fill", tint: Theme.pine, title: "Fixkosten gespart", value: Format.euro(result.fixedCostsToDate, decimals: 0),
                                detail: "Auto abgeschafft: \(Format.euro(result.fixedCostsPerYear, decimals: 0)) pro Jahr für Versicherung, Vignette, Parken und Service – anteilig bis heute.")
                }
                if settings.carProfile(catalog: app.catalog).mayDoubleCountFixedCosts {
                    Label {
                        Text("\(settings.carMode.displayName) enthält schon anteilige Fixkosten. Für eine faire Rechnung mit „Auto abgeschafft“ wähle „Nur Sprit“.")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.summit)
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                }
                NavigationLink {
                    WorkCarSettingsView(showsDetailLink: false)
                } label: {
                    Label("Berechnung anpassen", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
    }

    private var costDetail: String {
        switch settings.carMode {
        case .kilometergeld:
            "Amtliches Kilometergeld für Pkw (seit 1. Jänner 2025) – deckt Sprit, Wertverlust, Versicherung und Service ab."
        case .fuelOnly:
            "Nur Sprit: \(WorkFormat.liters(settings.litersPer100Km)) × \(Format.euroPrecise(settings.fuelPricePerLiter)) pro Liter."
        case .fullCost:
            "Deine Vollkosten pro Kilometer (laut ÖAMTC typisch €\u{00A0}0,45–0,60 für Kompakt- und Mittelklasse)."
        }
    }

    // MARK: CO₂ & time

    private func co2Tile(grow: Double) -> some View {
        let parts = StatsCalc.co2Parts(result.co2SavedKg)
        return GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.tile, tint: Theme.eco) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                tileIcon("leaf.fill", tint: Theme.positive)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(parts.value)
                        .font(.system(size: statSize, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.positive)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(parts.unit)
                        .font(.headline)
                        .foregroundStyle(Theme.positiveText)
                }
                Text("weniger CO₂ als mit dem Auto")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                co2Bars(grow: grow)
                Spacer(minLength: 0)
                Text("Pkw \(Format.number(app.catalog.emissions.car)) g/km, Öffis je Verkehrsmittel (Umweltbundesamt)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
    }

    private func co2Bars(grow: Double) -> some View {
        let maxKg = max(result.co2CarKg, result.co2TransitKg, 0.001)
        return VStack(alignment: .leading, spacing: 6) {
            co2Bar(symbol: "car.fill", label: "Auto", kg: result.co2CarKg, fraction: result.co2CarKg / maxKg * grow, color: Theme.dawn)
            co2Bar(symbol: "tram.fill", label: "Öffis", kg: result.co2TransitKg, fraction: result.co2TransitKg / maxKg * grow, color: Theme.positive)
        }
        .padding(.vertical, 2)
    }

    private func co2Bar(symbol: String, label: String, kg: Double, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption2.weight(.bold)).foregroundStyle(color)
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 2)
                Text(Format.kg(kg)).font(.caption2.weight(.bold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
            }
            GeometryReader { geo in
                Capsule().fill(Theme.textTertiary.opacity(0.14))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color).frame(width: max(6, geo.size.width * CGFloat(fraction)))
                    }
            }
            .frame(height: 6)
        }
    }

    private var timeTile: some View {
        let hours = result.drivingHours
        let workdays = hours / 8
        return GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.tile, tint: Theme.dusk) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                tileIcon("steeringwheel", tint: Theme.dusk)
                Text(WorkFormat.duration(hours: hours))
                    .font(.system(size: statSize, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("nicht am Steuer gesessen")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(workdays >= 1
                     ? "Rund \(StatsCalc.friendlyCount(workdays)) Arbeitstage – Zeit zum Lesen, Arbeiten oder Träumen."
                     : "Zeit zum Lesen, Arbeiten oder Träumen.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("Schätzung mit Durchschnittstempo, ohne Stau und Parkplatzsuche")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
    }

    private func tileIcon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.14), in: .circle)
            .accessibilityHidden(true)
    }
}
