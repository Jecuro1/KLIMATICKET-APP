import Foundation

/// The one-line amortisation text above the lock-screen clock (accessoryInline; docs/WIDGETS_SMARTSTACK.md §2, the
/// decision of docs/WIDGETS.md §8.5): "€ 142 bis zum Ziel" before the break-even, "Lohnt sich · +€ 37" after it. The
/// line beside the date has room for about 22 characters, so every text stays within `maxLength`; very large amounts
/// fall back to shorter wordings instead of being cut by the system.
public enum InlineAmortizationText {
    public static let maxLength = 22

    /// What the line reports.
    public enum State: Equatable, Sendable {
        /// No ticket in the app yet.
        case noTicket
        /// Past the ticket's last day.
        case expired
        /// Not paid off: whole euros still missing to the ticket price.
        case unpaid(remaining: Double)
        /// Paid off: whole euros above the ticket price.
        case paid(profit: Double)
    }

    /// The state for a ticket. `remaining` and `profit` are the whole-euro figures the widgets show elsewhere (the
    /// rounding that keeps "noch € 354" and "€ 946 von € 1.300" adding up); expiry wins, then the paid-off flag.
    public static func state(hasTicket: Bool, isExpired: Bool, isPaidOff: Bool, remaining: Double, profit: Double) -> State {
        guard hasTicket else { return .noTicket }
        if isExpired { return .expired }
        return isPaidOff ? .paid(profit: profit) : .unpaid(remaining: remaining)
    }

    /// The line itself, at most `maxLength` characters.
    public static func text(_ state: State) -> String {
        for candidate in candidates(state) where candidate.count <= maxLength {
            return candidate
        }
        return String(candidates(state).last?.prefix(maxLength) ?? "")
    }

    /// Spoken form for VoiceOver (the euro sign and the dot read badly): "Noch 142 Euro bis zum Ticketpreis".
    public static func spoken(_ state: State) -> String {
        switch state {
        case .noTicket: return "Kein Ticket erfasst"
        case .expired: return "Ticket abgelaufen"
        case .unpaid(let remaining): return "Noch \(integer(remaining)) Euro bis zum Ticketpreis"
        case .paid(let profit): return "Ticket lohnt sich, \(integer(profit)) Euro im Plus"
        }
    }

    /// Wordings from the full one down to the bare figure.
    static func candidates(_ state: State) -> [String] {
        switch state {
        case .noTicket:
            return ["Kein Ticket erfasst", "Kein Ticket"]
        case .expired:
            return ["Ticket abgelaufen", "Abgelaufen"]
        case .unpaid(let remaining):
            let amount = euro(remaining)
            return ["\(amount) bis zum Ziel", "noch \(amount)", amount]
        case .paid(let profit):
            let amount = "+" + euro(profit)
            return ["Lohnt sich · \(amount)", "Im Plus · \(amount)", amount]
        }
    }

    /// "€ 1.300": the euro sign, a no-break space (the sign never stands alone at a line end) and whole euros with the
    /// Austrian thousands dot. Negative, NaN and infinite amounts read as € 0.
    public static func euro(_ value: Double) -> String {
        "€\u{00A0}" + integer(value)
    }

    static func integer(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0" }
        return AssistantFormat.wholeNumber(min(value, 9e14))
    }
}
