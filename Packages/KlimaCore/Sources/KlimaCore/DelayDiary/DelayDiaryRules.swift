import Foundation

// MARK: - „Verspätungs-Tagebuch“ (docs/DELAY_DIARY.md) – when a recorded arrival counts as late
//
// AGB KlimaTicket Ö, Punkt 24 „Fahrgastrechte bei Verspätung und Ausfall“ (read from the AGB PDF on 20.11.2026):
// - 24.1: Entschädigung, wenn bei den verwendeten Eisenbahnverkehrsunternehmen (ausgenommen Stadtverkehre und nicht vernetzte
//   Nebenbahnen) während der Geltungsdauer wiederholt Verspätungen oder Ausfälle auftreten; die Abwicklung obliegt den
//   Eisenbahnverkehrsunternehmen.
// - 24.2: Garantiert wird ein Pünktlichkeitsgrad von 93,00 % pro Gültigkeitsmonat bei allen Eisenbahnverkehrsunternehmen; den
//   Pünktlichkeitsgrad veröffentlichen die Unternehmen auf ihren Websites.
// - 24.3: Liegt er in einem Gültigkeitsmonat unter 93,00 %, gibt es einmal im Jahr nach Ablauf 10 % des Monatsanteils der
//   Entschädigungsbasis.
// Punkt 24 names NO minute from which a single arrival counts as late: what counts is the railway's degree of punctuality per
// validity month, measured and published by the railway. So the diary cannot reproduce it. A recorded arrival counts as late
// from the holder's own mark (5 minutes unless changed), and every share on screen and in the PDF is called „persönlich“.
// (The ÖBB measure their own figure from 5 min 30 s – Tarifbestimmungen A.5.4.1.1, `PerkRightsRules.lateFromSeconds` – which
// whole minutes cannot tell apart; that rule is the railway's, not the AGB's, and not the diary's.)

/// The diary's rules: the personal „late“ mark, the stepper's range and when a share is shown.
public enum DelayDiaryRules {
    /// Default mark: an arrival this many minutes late (or later) counts as late. Personal, not from the AGB (see above).
    public static let defaultThresholdMinutes = 5
    /// The marks the holder can choose (Einstellungen of the diary).
    public static let thresholdChoices = [3, 5, 10, 15]
    /// The entry sheet's stepper: 0 („pünktlich“) to 240 minutes in 1-minute steps.
    public static let maximumMinutes = 240
    /// A share needs at least this many Fahrten with a recorded arrival (pünktlich or late) in the month (or the year).
    public static let minimumRecordedForShare = 5

    /// Minutes as the diary stores them: 0…240.
    public static func clamp(_ minutes: Int) -> Int { min(max(0, minutes), maximumMinutes) }

    /// A chosen mark, or the default for anything that is not one of the choices.
    public static func normalizedThreshold(_ minutes: Int) -> Int {
        thresholdChoices.contains(minutes) ? minutes : defaultThresholdMinutes
    }

    /// Late at or above the mark (4 is on time and 5 is late with the default mark).
    public static func isLate(_ minutes: Int, threshold: Int = defaultThresholdMinutes) -> Bool {
        minutes >= max(1, threshold)
    }

    /// The personal on-time share: on time ÷ recorded, nil below `minimumRecordedForShare` recorded Fahrten.
    public static func onTimeShare(recorded: Int, late: Int) -> Double? {
        guard recorded >= minimumRecordedForShare else { return nil }
        let onTime = max(0, recorded - min(late, recorded))
        return Double(onTime) / Double(recorded)
    }
}

/// Which Fahrten the diary counts.
public enum DelayDiaryScope: String, Codable, CaseIterable, Sendable {
    /// Every mode (a personal log).
    case all
    /// Only Zug and S-Bahn rides (the railways Punkt 24 is about); a journey counts with its rail legs only.
    case rail

    public func includes(_ mode: TransportMode) -> Bool {
        switch self {
        case .all: true
        case .rail: mode == .train || mode == .sBahn
        }
    }
}

/// The holder's diary settings (UserDefaults JSON `delaydiary.options.v1`; tolerant: unknown or broken values fall back).
public struct DelayDiaryOptions: Codable, Hashable, Sendable {
    public var thresholdMinutes: Int
    public var scope: DelayDiaryScope

    public init(thresholdMinutes: Int = DelayDiaryRules.defaultThresholdMinutes, scope: DelayDiaryScope = .all) {
        self.thresholdMinutes = DelayDiaryRules.normalizedThreshold(thresholdMinutes)
        self.scope = scope
    }

    private enum CodingKeys: String, CodingKey { case thresholdMinutes, scope }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let threshold = (try? container.decodeIfPresent(Int.self, forKey: .thresholdMinutes)) ?? nil
        let scopeRaw = (try? container.decodeIfPresent(String.self, forKey: .scope)) ?? nil
        self.init(thresholdMinutes: threshold ?? DelayDiaryRules.defaultThresholdMinutes,
                  scope: scopeRaw.flatMap(DelayDiaryScope.init(rawValue:)) ?? .all)
    }

    /// Decodes stored settings; nil or broken data gives the defaults.
    public static func decode(_ data: Data?) -> DelayDiaryOptions {
        guard let data, let options = try? JSONDecoder().decode(DelayDiaryOptions.self, from: data) else { return DelayDiaryOptions() }
        return options
    }

    public var isDefault: Bool { self == DelayDiaryOptions() }
}
