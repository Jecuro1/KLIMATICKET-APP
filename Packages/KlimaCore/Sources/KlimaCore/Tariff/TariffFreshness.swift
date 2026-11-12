import Foundation

/// How current the prices in the app are (docs/TARIFF_FRESHNESS.md). Pure: the catalogue, the clock and the last check go
/// in, a state comes out; nothing here reads the network, the file system or the device calendar.
///
/// The app promises "does my ticket pay off", so it must say when its prices may be out of date: around the ÖBB timetable
/// change in December (the Standard-Ticket prices change then), after New Year (KlimaTicket prices are set per calendar
/// year) and when the data is simply old. A state never names a new price – it only says that one may exist.
public enum TariffFreshness {
    public enum State: Hashable, Sendable {
        /// Nothing known that would make the prices wrong.
        case current
        /// 1 December until the data was updated: the timetable change on that day (start of the day) is coming or just
        /// happened and the catalogue was not updated since 1 December.
        case upcomingChange(Date)
        /// From 1 January: no KlimaTicket Ö product has a price entry valid for the current calendar year.
        case newYear
        /// The newest fare-index entry is more than 13 months old (start of that day).
        case stale(since: Date)

        public var isCurrent: Bool { self == .current }
    }

    /// A fare index (or catalogue) older than this many months is "stale".
    public static let staleAfterMonths = 13

    /// The freshness of `catalog` on `now` (days count in `calendar`, Vienna by default). Precedence: newYear, upcomingChange,
    /// stale, current.
    ///
    /// `lastCheck` (the last successful look at the update server) is accepted so callers pass what they know, but it does
    /// not change the state: a check only proves that no newer catalogue exists, not that the prices in this one are right.
    ///
    /// `relationsValidFrom` is the validity day of the relation table the app **uses right now** (bundled or installed
    /// pack). With it, the December notice ends only when that table is from the day of the change or later: a catalogue that
    /// merely announces a newer pack, which was not (yet) downloaded, does not end it – the numbers on screen would still be
    /// the old ones. Without it (nil, or not a date) the catalogue's announcement counts, as before.
    public static func state(catalog: TariffCatalog, now: Date, lastCheck: Date? = nil, relationsValidFrom: String? = nil,
                             calendar: Calendar = .vienna) -> State {
        let today = isoDay(now, calendar: calendar)
        let year = Int(today.prefix(4)) ?? 0

        // (b) From 1 January the KlimaTicket Ö prices must have an entry for this year (they are set per calendar year).
        let priceDays = klimaTicketPriceDays(catalog)
        if !priceDays.isEmpty, !priceDays.contains(where: { $0 >= String(format: "%04d-01-01", year) }) {
            return .newYear
        }

        // (a) 1 December until the data update: the timetable change moves the Standard-Ticket prices.
        if today >= TimetableChange.noticeStartISODay(year: year) {
            let change = TimetableChange.isoDay(year: year)
            let updated = String(catalog.updatedAt.prefix(10))
            let checkedSinceDecember = isISODay(updated) && updated >= TimetableChange.noticeStartISODay(year: year)
            let announcedPack = catalog.relationsPack.map { isISODay($0.validFrom) && $0.validFrom >= change } ?? false
            let dataUpdated: Bool
            if let inUse = relationsValidFrom, isISODay(inUse) {
                // A table from the day of the change is in use: done. A newer pack announced but not in use: still waiting.
                dataUpdated = inUse >= change || (checkedSinceDecember && !announcedPack)
            } else {
                dataUpdated = checkedSinceDecember || announcedPack
            }
            if !dataUpdated {
                return .upcomingChange(TimetableChange.date(year: year, calendar: calendar))
            }
        }

        // (c) The newest fare-index entry (or, without a fare index, the catalogue date) is over 13 months old.
        if let reference = staleReference(catalog), let since = date(fromISODay: reference, calendar: calendar),
           let limit = calendar.date(byAdding: .month, value: staleAfterMonths, to: since),
           today > isoDay(limit, calendar: calendar) {
            return .stale(since: since)
        }
        return .current
    }

    // MARK: Facts shown in Einstellungen

    /// Newest KlimaTicket Ö price entry that applies on `now` (ISO day), e.g. "2026-01-01". nil without any.
    public static func ticketPricesAsOf(catalog: TariffCatalog, now: Date, calendar: Calendar = .vienna) -> String? {
        let today = isoDay(now, calendar: calendar)
        return klimaTicketPriceDays(catalog).filter { $0 <= today }.max()
    }

    /// "Fahrpreise gültig ab 14.12.2025 · Ticketpreise Stand 1.1.2026 · zuletzt geprüft 12.11.2026" – the dates come from
    /// the relation table (`fareValidFrom`), the catalogue and the cache; a missing date leaves its part out.
    public static func summaryLine(fareValidFrom: String?, ticketPricesAsOf: String?, lastCheck: Date?,
                                   calendar: Calendar = .vienna) -> String {
        var parts: [String] = []
        if let fareValidFrom, isISODay(fareValidFrom) { parts.append("Fahrpreise gültig ab \(germanDate(iso: fareValidFrom))") }
        if let ticketPricesAsOf, isISODay(ticketPricesAsOf) { parts.append("Ticketpreise Stand \(germanDate(iso: ticketPricesAsOf))") }
        if let lastCheck {
            parts.append("zuletzt geprüft \(germanDate(lastCheck, calendar: calendar))")
        } else {
            parts.append("noch nicht geprüft")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Dates

    /// "2026-01-01" → "1.1.2026" (day and month without leading zeros, as the Austrian short form).
    public static func germanDate(iso: String) -> String {
        let p = iso.prefix(10).split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return iso }
        return "\(d).\(m).\(y)"
    }

    public static func germanDate(_ date: Date, calendar: Calendar = .vienna) -> String {
        germanDate(iso: isoDay(date, calendar: calendar))
    }

    /// "13.12." – day and month only (the notice: "Fahrplanwechsel am 13.12.").
    public static func germanDayMonth(_ date: Date, calendar: Calendar = .vienna) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        return "\(c.day ?? 0).\(c.month ?? 0)."
    }

    /// "2026-12-13" for a date in `calendar`.
    public static func isoDay(_ date: Date, calendar: Calendar = .vienna) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Start of the ISO day in `calendar`; nil for anything that is not "yyyy-MM-dd".
    public static func date(fromISODay iso: String, calendar: Calendar = .vienna) -> Date? {
        guard isISODay(iso) else { return nil }
        let p = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// "yyyy-MM-dd" with plausible month and day.
    public static func isISODay(_ s: String) -> Bool {
        let p = s.split(separator: "-")
        guard s.count == 10, p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2,
              let m = Int(p[1]), let d = Int(p[2]), Int(p[0]) != nil else { return false }
        return (1...12).contains(m) && (1...31).contains(d)
    }

    // MARK: Catalogue facts

    /// Every validity start of a KlimaTicket Ö price (current price and history), ISO days, ascending.
    static func klimaTicketPriceDays(_ catalog: TariffCatalog) -> [String] {
        var days: [String] = []
        for product in catalog.products where product.family == .oe {
            days.append(product.validFrom)
            days.append(contentsOf: (product.priceHistory ?? []).map(\.validFrom))
        }
        return Array(Set(days.filter(isISODay))).sorted()
    }

    /// The newest fare-index day; the catalogue date when there is no usable fare index.
    static func staleReference(_ catalog: TariffCatalog) -> String? {
        if let newest = (catalog.fareIndex ?? []).map(\.validFrom).filter(isISODay).max() { return newest }
        let updated = String(catalog.updatedAt.prefix(10))
        return isISODay(updated) ? updated : nil
    }
}
