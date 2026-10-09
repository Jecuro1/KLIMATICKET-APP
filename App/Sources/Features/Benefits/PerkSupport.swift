import SwiftUI
import SwiftData
import KlimaCore

// Shared plumbing of the "Vorteilswelt & Fahrgastrechte" module: the bundled catalogue, category styling,
// formatting, the period the "Zusatz-Ersparnis" is summed over, and small value conversions.
// Everything here is prefixed `Perk` to stay collision-free with modules written in parallel.

// MARK: - Catalogue

/// The bundled Vorteilswelt catalogue (App/Resources/benefits.json), decoded once.
enum PerkCatalogStore {
    static let shared: PerkCatalog = load()

    private static func load() -> PerkCatalog {
        guard let url = Bundle.main.url(forResource: "benefits", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? PerkCatalog.decode(data) else {
            return .empty
        }
        return catalog
    }

    /// Official overview of all partner offers.
    static var sourceURL: URL {
        URL(string: shared.source) ?? URL(string: "https://www.klimaticket.at/eins-fuer-mehr/")!
    }

    /// "9. Okt. 2026" – when the catalogue was last checked against klimaticket.at.
    static var asOfText: String? {
        guard let day = PerkFormat.isoDay(shared.asOf) else { return nil }
        return Format.date(day, .abbreviated)
    }
}

// MARK: - Styling

enum PerkStyle {
    /// Category colour (used for icon tiles and chart segments – never for small text).
    static func tint(_ category: PerkCategory) -> Color {
        switch category {
        case .mobility: Theme.glacier
        case .museums: Theme.dusk
        case .leisure: Theme.pine
        case .foodStay: Theme.dawn
        case .more: Theme.alpenglow
        case .custom: Theme.gold
        }
    }

    /// Section spacing (DESIGN.md §3: 18–24) and card spacing (10–12) on the 4 pt grid.
    static let sectionSpacing: CGFloat = Theme.Spacing.l + Theme.Spacing.xxs
    static let cardSpacing: CGFloat = Theme.Spacing.s

    /// Big light numeral (≈ 56 pt) for the hero totals, following Dynamic Type.
    static let heroNumber = Font.system(size: 56, weight: .light, design: .rounded).monospacedDigit()
    static let heroSymbol = Font.system(size: 26, weight: .light, design: .rounded)
}

// MARK: - Formatting

enum PerkFormat {
    /// "+ € 7,45" / "+ € 12,00" (always cents, like trip values)
    static func plusEuro(_ value: Double) -> String { "+ " + Format.euroPrecise(value) }

    /// Whole euros for headline totals ("+ € 86").
    static func plusEuroRounded(_ value: Double) -> String { "+ " + Format.euro(value, decimals: 0) }

    /// "1 Vorteil" / "12 Vorteile"
    static func count(_ n: Int) -> String {
        n == 1 ? "1 Vorteil" : "\(Format.number(Double(n))) Vorteile"
    }

    /// "Fr., 9. Okt."
    static func day(_ date: Date) -> String { Format.weekdayDayMonth(date) }

    /// "≈ € 7" / "≈ € 0,43"
    static func typical(_ value: Double) -> String { "≈ " + Format.euro(value) }

    /// "7,45" for editable amount fields (empty for 0).
    static func editable(_ value: Double) -> String {
        value > 0 ? Format.number(value, decimals: 2) : ""
    }

    /// Parses de-AT input ("7,45", "7.45", "€ 1.024,50") → 7.45. Nil for empty/invalid/implausible values.
    static func parseEuro(_ text: String) -> Double? {
        var s = text.replacingOccurrences(of: "€", with: "")
        s = s.components(separatedBy: .whitespacesAndNewlines).joined()
        if s.contains(",") {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        guard !s.isEmpty, let value = Double(s), value.isFinite, value > 0, value < 10_000 else { return nil }
        return (value * 100).rounded() / 100
    }

    /// "Oktober 2026"
    static func month(_ date: Date) -> String { Format.monthYear(date) }

    static func isoDay(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Vienna")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(string.prefix(10)))
    }
}

// MARK: - Period

/// The span the "Zusatz-Ersparnis" is summed over: the active ticket year, otherwise the calendar year.
struct PerkPeriod: Equatable {
    var start: Date
    var end: Date
    /// "Ticketjahr 2026/27" or "2026".
    var label: String
    var ticketID: UUID?

    func contains(_ date: Date) -> Bool { date >= start && date <= end }

    static func current(tickets: [TicketEntity], selectedID: UUID?, now: Date = Date()) -> PerkPeriod {
        let cal = Calendar.vienna
        if let ticket = Analytics.activeTicket(in: tickets, selectedID: selectedID) {
            return PerkPeriod(start: ticket.startDate, end: ticket.endDate, label: ticketYearLabel(ticket), ticketID: ticket.id)
        }
        let year = cal.dateInterval(of: .year, for: now) ?? DateInterval(start: now, duration: 0)
        return PerkPeriod(start: year.start, end: year.end.addingTimeInterval(-1),
                          label: String(cal.component(.year, from: now)), ticketID: nil)
    }

    /// "Ticketjahr 2026/27" (or "Ticketjahr 2026" when the validity stays within one calendar year).
    static func ticketYearLabel(_ ticket: TicketEntity) -> String {
        let cal = Calendar.vienna
        let startYear = cal.component(.year, from: ticket.startDate)
        let endYear = cal.component(.year, from: ticket.endDate)
        if startYear == endYear { return "Ticketjahr \(startYear)" }
        return "Ticketjahr \(startYear)/\(String(format: "%02d", endYear % 100))"
    }
}

// MARK: - Entity helpers

extension BenefitEntity {
    var perkUsage: PerkUsage { PerkUsage(date: date, partnerID: partnerID, savedEUR: savedEUR) }
}

extension PerkSummary {
    /// Summary of the live benefits inside `period`.
    static func make(benefits: [BenefitEntity], period: PerkPeriod) -> PerkSummary {
        PerkSummary.make(usages: benefits.filter { $0.deletedAt == nil }.map(\.perkUsage),
                         from: period.start, to: period.end, catalog: PerkCatalogStore.shared)
    }
}

/// A month of logged benefits ("Oktober 2026 · + € 21").
struct PerkMonthGroup: Identifiable {
    var month: Date
    var benefits: [BenefitEntity]
    var id: Date { month }
    var total: Double { benefits.reduce(0) { $0 + max(0, $1.savedEUR) } }

    /// `benefits` sorted newest first → groups newest month first.
    static func group(_ benefits: [BenefitEntity]) -> [PerkMonthGroup] {
        let cal = Calendar.vienna
        var groups: [PerkMonthGroup] = []
        for benefit in benefits.sorted(by: { $0.date > $1.date }) {
            let month = cal.dateInterval(of: .month, for: benefit.date)?.start ?? cal.startOfDay(for: benefit.date)
            if let index = groups.firstIndex(where: { $0.month == month }) {
                groups[index].benefits.append(benefit)
            } else {
                groups.append(PerkMonthGroup(month: month, benefits: [benefit]))
            }
        }
        return groups
    }
}

// MARK: - Backdrop

/// Calm sheet surface with the ambient sky fading out towards the middle ("kein Himmel-Mesh voll deckend –
/// höchstens blass", DESIGN.md §2). Opaque with Reduce Transparency.
struct PerkSheetBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .top) {
            Theme.sheetBackground
            if !reduceTransparency {
                AmbientBackground(style: .standard, glow: 0.55)
                    .opacity(0.5)
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0),
                                               .init(color: .black.opacity(0.6), location: 0.2),
                                               .init(color: .clear, location: 0.45)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Frosted list-row background for rows over the sky (insetGrouped clips it into the rounded section card).
struct PerkRowBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Theme.sheetBackground
        } else {
            ZStack {
                Rectangle().fill(.regularMaterial)
                Theme.surface.opacity(0.6)
            }
        }
    }
}

extension View {
    /// `.sensoryFeedback` that respects the "Haptisches Feedback" setting.
    func perkHaptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T, enabled: Bool) -> some View {
        sensoryFeedback(trigger: trigger) { _, _ in enabled ? feedback : nil }
    }
}
