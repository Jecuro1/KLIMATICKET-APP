import Foundation

// MARK: funktionen – Einstellungen › Funktionen (docs/FUNCTIONS_HUB.md): one place that answers „Was kann die App, was davon ist
// an, und was sendet sie?“. This file is the registry: every feature the hub lists, where its switch lives, what it needs, what
// disappears while it is off and where its data goes. Pure data – the app maps it to symbols, colours and the real switches.

/// A feature of the hub. Raw values are the keys of `features.v1` (only the hub's own switches are stored there).
public enum FeatureID: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    // Live-Daten
    case liveTimetable, livePrices, followNotices
    // Karte & Radar
    case radar, trainSearch, disruptions
    // Erfassen
    case tripDetection
    // Übersicht
    case assistant, perksCard, achievementsTeaser, weekInsight
    // Mitteilungen
    case renewalReminders, weeklySummary
    // Darstellung
    case haptics, officialLogos

    public var id: String { rawValue }
    public var descriptor: FeatureDescriptor { FeatureRegistry.descriptor(self) }
    public var title: String { descriptor.title }
}

/// The hub's sections, in display order.
public enum FeatureGroup: String, CaseIterable, Sendable, Hashable, Identifiable {
    case liveData, mapRadar, capture, overview, notices, appearance

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .liveData: "Live-Daten"
        case .mapRadar: "Karte & Radar"
        case .capture: "Erfassen"
        case .overview: "Übersicht"
        case .notices: "Mitteilungen"
        case .appearance: "Darstellung"
        }
    }
}

/// Where a feature's switch is stored.
public enum FeatureStorage: Equatable, Sendable {
    /// A switch of the hub itself: stored as an override in `features.v1`; `defaultOn` while nothing is stored.
    case hub(defaultOn: Bool)
    /// A switch that existed before the hub. The hub shows and sets it; it stays stored at its own place.
    case wrapped(place: String)
}

/// How the hub changes a feature.
public enum FeatureControl: Equatable, Sendable {
    /// A switch right in the hub row.
    case toggle
    /// Switched on at its own page, because that needs a permission or a setup; the hub shows the state and the way there.
    case ownPage
}

/// Who receives data.
public enum FeatureRecipient: String, CaseIterable, Sendable, Hashable, Identifiable {
    case oebbTimetable, oebbShop, vao, cloud, github, appleMaps, device

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oebbTimetable: "ÖBB-Fahrplanauskunft"
        case .oebbShop: "ÖBB-Ticketshop"
        case .vao: "Verkehrsauskunft Österreich (VAO)"
        case .cloud: "KlimaBilanz-Server (Cloudflare)"
        case .github: "GitHub"
        case .appleMaps: "Apple Karten"
        case .device: "Nur auf dem iPhone"
        }
    }

    /// Whether anything leaves the iPhone.
    public var isRemote: Bool { self != .device }

    /// The live providers whose requests the app counts (`RequestThrottle`).
    public var liveProvider: LiveProvider? {
        switch self {
        case .oebbTimetable: .oebbHafas
        case .oebbShop: .oebbShop
        case .vao: .vaoTariff
        case .cloud, .github, .appleMaps, .device: nil
        }
    }
}

/// One way data leaves (or stays on) the iPhone: who gets what, and when.
public struct FeatureDataFlow: Equatable, Sendable, Hashable {
    public let recipient: FeatureRecipient
    public let sends: String
    public let when: String

    public init(_ recipient: FeatureRecipient, sends: String, when: String) {
        self.recipient = recipient
        self.sends = sends
        self.when = when
    }

    /// Nothing leaves the iPhone.
    public static func local(_ sends: String = "nichts – alles bleibt auf dem iPhone") -> FeatureDataFlow {
        FeatureDataFlow(.device, sends: sends, when: "nie")
    }
}

/// Everything the hub knows about a feature.
public struct FeatureDescriptor: Equatable, Sendable, Identifiable {
    public let id: FeatureID
    public let title: String
    /// One line under the title.
    public let line: String
    public let group: FeatureGroup
    public let storage: FeatureStorage
    public let control: FeatureControl
    /// Features that must be on for this one to work (resolved transitively).
    public let dependencies: [FeatureID]
    /// The Offline-Modus switches it off (directly; dependents follow through `dependencies`).
    public let usesLiveData: Bool
    /// What is different while the feature is off – a full sentence.
    public let offEffect: String
    /// The entry point that is hidden while the feature is off („der Radar-Knopf im Fahrplan“), nil when nothing is hidden.
    public let hiddenEntry: String?
    public let dataFlows: [FeatureDataFlow]

    /// The value of a hub switch while nothing is stored (wrapped switches have their own defaults at their place).
    public var hubDefault: Bool? {
        if case .hub(let on) = storage { return on }
        return nil
    }

    public var isHubSwitch: Bool { hubDefault != nil }

    /// Where a wrapped switch lives („Einstellungen › Live-Daten“).
    public var place: String? {
        if case .wrapped(let place) = storage { return place }
        return nil
    }

    /// Whether anything of this feature leaves the iPhone.
    public var sendsData: Bool { dataFlows.contains { $0.recipient.isRemote } }
}

/// The registry: every feature of the hub in display order.
public enum FeatureRegistry {
    public static let all: [FeatureDescriptor] = FeatureID.allCases.map(make)

    public static func descriptor(_ id: FeatureID) -> FeatureDescriptor {
        all.first { $0.id == id } ?? make(id)
    }

    public static func features(in group: FeatureGroup) -> [FeatureDescriptor] {
        all.filter { $0.group == group }
    }

    /// Features that need `id` (directly or through another one).
    public static func dependents(of id: FeatureID) -> [FeatureID] {
        all.filter { requires($0.id, id) }.map(\.id)
    }

    /// `feature` needs `other`, directly or transitively.
    public static func requires(_ feature: FeatureID, _ other: FeatureID) -> Bool {
        var seen: Set<FeatureID> = []
        var queue = descriptor(feature).dependencies
        while let next = queue.popLast() {
            if next == other { return true }
            guard seen.insert(next).inserted else { continue }
            queue.append(contentsOf: descriptor(next).dependencies)
        }
        return false
    }

    // MARK: Copy

    private static let liveAsk = "nur mit deiner Zustimmung zu Live-Daten"

    // swiftlint:disable:next function_body_length
    private static func make(_ id: FeatureID) -> FeatureDescriptor {
        switch id {
        case .liveTimetable:
            return FeatureDescriptor(
                id: id, title: "Fahrplan & Echtzeit", line: "Verbindungen, Abfahrten und Verspätungen von der ÖBB",
                group: .liveData, storage: .wrapped(place: "Einstellungen › Live-Daten"), control: .toggle,
                dependencies: [], usesLiveData: true,
                offEffect: "Der Fahrplan zeigt „Live-Daten sind aus“; Zug-Radar, Züge suchen und Störungen sind ausgeblendet.",
                hiddenEntry: nil,
                dataFlows: [FeatureDataFlow(.oebbTimetable,
                                            // MARK: radar2-anschluss – the Anschluss-Wächter checks the followed connection (docs/CONNECTION_GUARD.md §4)
                                            sends: "Haltestellen, Zeiten und Zugnummern deiner Suchen; für „In der Nähe“ dein Standort auf rund 100 m gerundet; "
                                                + "beim Live-Verfolgen einer Verbindung mit Umstieg diese Verbindung und bei Bedarf Umstiegsbahnhof und Ziel",
                                            when: "wenn du suchst oder eine Live-Ansicht offen ist, für deine Widgets beim Öffnen der App höchstens alle 15 Minuten – \(liveAsk)")])
        case .livePrices:
            return FeatureDescriptor(
                id: id, title: "Live-Ticketpreise", line: "Standardpreise aus dem ÖBB-Ticketshop und von den Verbünden",
                group: .liveData, storage: .wrapped(place: "Einstellungen › Live-Daten"), control: .toggle,
                dependencies: [], usesLiveData: true,
                offEffect: "Preise kommen aus den Tarif-Tabellen auf dem iPhone.",
                hiddenEntry: nil,
                dataFlows: [FeatureDataFlow(.oebbShop, sends: "Start, Ziel, Tag, Klasse und Ermäßigung einer Verbindung",
                                            when: "wenn ein Preis angezeigt wird – \(liveAsk)"),
                            FeatureDataFlow(.vao, sends: "Start und Ziel im Verkehrsverbund und der Tag",
                                            when: "wenn ein Verbundpreis angezeigt wird – \(liveAsk)")])
        case .followNotices:
            return FeatureDescriptor(
                id: id, title: "Live-Mitteilungen", line: "Verspätung, Gleis und Ankunft, wenn du einen Zug verfolgst",
                group: .liveData, storage: .wrapped(place: "Einstellungen › Live-Mitteilungen"), control: .ownPage,
                dependencies: [.liveTimetable], usesLiveData: false,
                offEffect: "„Live verfolgen“ zeigt den Zug nur in der App, ohne Mitteilungen.",
                hiddenEntry: nil,
                dataFlows: [FeatureDataFlow(.oebbTimetable, sends: "der Zug, den du verfolgst",
                                            when: "solange du ihn verfolgst, auch im Hintergrund, wenn iOS es zulässt")])
        case .radar:
            return FeatureDescriptor(
                id: id, title: "Zug-Radar", line: "Züge in Echtzeit auf der Karte",
                group: .mapRadar, storage: .hub(defaultOn: true), control: .toggle,
                dependencies: [.liveTimetable], usesLiveData: false,
                offEffect: "Der Radar-Knopf im Fahrplan ist ausgeblendet; Widget-Knopf und Link öffnen dann diese Seite.",
                hiddenEntry: "der Radar-Knopf im Fahrplan",
                dataFlows: [FeatureDataFlow(.oebbTimetable, sends: "der Kartenausschnitt, den du ansiehst",
                                            when: "solange der Radar offen ist, höchstens 24 Anfragen pro Minute – \(liveAsk)"),
                            FeatureDataFlow(.appleMaps, sends: "der Kartenausschnitt, den du ansiehst",
                                            when: "solange eine Karte zu sehen ist")])
        case .trainSearch:
            return FeatureDescriptor(
                id: id, title: "Züge suchen", line: "Einen Zug über seine Nummer finden, zum Beispiel RJX 66",
                group: .mapRadar, storage: .hub(defaultOn: true), control: .toggle,
                dependencies: [.liveTimetable], usesLiveData: false,
                offEffect: "Das Feld „Züge suchen“ im Fahrplan ist ausgeblendet.",
                hiddenEntry: "das Feld „Züge suchen“ im Fahrplan",
                dataFlows: [FeatureDataFlow(.oebbTimetable, sends: "die Zugnummer, die du eingibst",
                                            when: "erst nach deinem Tipp auf Suchen – \(liveAsk)")])
        case .disruptions:
            return FeatureDescriptor(
                id: id, title: "Störungen", line: "Aktuelle Störungen und Baustellen der ÖBB",
                group: .mapRadar, storage: .hub(defaultOn: true), control: .toggle,
                dependencies: [.liveTimetable], usesLiveData: false,
                offEffect: "Der Störungen-Knopf im Fahrplan ist ausgeblendet. Die Ebene „Störungen“ im Zug-Radar und das Störungen-Widget bleiben eigene Schalter.",
                hiddenEntry: "der Störungen-Knopf im Fahrplan",
                dataFlows: [FeatureDataFlow(.oebbTimetable, sends: "Verkehrsmittel und Zeitraum der Abfrage – nichts Persönliches",
                                            when: "wenn du die Störungen öffnest – \(liveAsk)")])
        case .tripDetection:
            return FeatureDescriptor(
                id: id, title: "Hintergrund-Erkennung", line: "Schlägt Fahrten aus Aufenthalten an Haltestellen vor (Beta)",
                group: .capture, storage: .wrapped(place: "Einstellungen › Fahrten erkennen"), control: .ownPage,
                dependencies: [], usesLiveData: false,
                offEffect: "Vorschläge kommen nur aus „Fahrt aufzeichnen“.",
                hiddenEntry: nil,
                dataFlows: [.local("Standortpunkte und Aufenthalte – höchstens 36 Stunden, nur auf dem iPhone"),
                            FeatureDataFlow(.oebbTimetable, sends: "für einen Vorschlag einmal zwei Haltestellen und die Uhrzeit, nie dein Standort",
                                            when: "nur mit Live-Daten, in „Fahrten erkennen“ abschaltbar")])
        case .assistant:
            return FeatureDescriptor(
                id: id, title: "KI auf dem Gerät", line: "Erklärt deine Bilanz und schreibt den Wochenrückblick",
                group: .overview, storage: .wrapped(place: "Einstellungen › KI auf dem Gerät"), control: .toggle,
                dependencies: [], usesLiveData: false,
                offEffect: "Texte kommen aus festen Regeln statt vom Sprachmodell.",
                hiddenEntry: nil,
                dataFlows: [.local("nichts – das Sprachmodell läuft auf dem iPhone")])
        case .perksCard:
            return FeatureDescriptor(
                id: id, title: "Vorteile-Karte", line: "Zusatz-Ersparnis durch Vorteile in Übersicht und Ticket",
                group: .overview, storage: .hub(defaultOn: true), control: .toggle,
                dependencies: [], usesLiveData: false,
                offEffect: "Die Vorteile-Karte ist ausgeblendet. Die Vorteilswelt bleibt unter Einstellungen › Vorteile.",
                hiddenEntry: "die Vorteile-Karte in Übersicht und Ticket",
                dataFlows: [.local()])
        case .achievementsTeaser:
            return FeatureDescriptor(
                id: id, title: "Gipfelbuch-Vorschau", line: "Dein nächster Erfolg in der Übersicht",
                group: .overview, storage: .hub(defaultOn: true), control: .toggle,
                dependencies: [], usesLiveData: false,
                offEffect: "Die Gipfelbuch-Zeile in der Übersicht ist ausgeblendet. Das Gipfelbuch bleibt in der Statistik.",
                hiddenEntry: "die Gipfelbuch-Zeile in der Übersicht",
                dataFlows: [.local()])
        case .weekInsight:
            return FeatureDescriptor(
                id: id, title: "Diese Woche", line: "Fahrten und Wert im Vergleich zur Vorwoche",
                group: .overview, storage: .hub(defaultOn: true), control: .toggle,
                dependencies: [], usesLiveData: false,
                offEffect: "Die Karte „Diese Woche“ in der Übersicht ist ausgeblendet.",
                hiddenEntry: "die Karte „Diese Woche“ in der Übersicht",
                dataFlows: [.local()])
        case .renewalReminders:
            return FeatureDescriptor(
                id: id, title: "Verlängerungs-Erinnerung", line: "Bevor dein Ticket abläuft",
                group: .notices, storage: .wrapped(place: "Einstellungen › Mitteilungen"), control: .toggle,
                dependencies: [], usesLiveData: false,
                offEffect: "Vor dem Ablauf deines Tickets kommt keine Erinnerung.",
                hiddenEntry: nil,
                dataFlows: [.local("nichts – dein iPhone plant die Mitteilung selbst")])
        case .weeklySummary:
            return FeatureDescriptor(
                id: id, title: "Wochenrückblick", line: "Sonntags um 18 Uhr eine kurze Bilanz",
                group: .notices, storage: .wrapped(place: "Einstellungen › Mitteilungen"), control: .toggle,
                dependencies: [], usesLiveData: false,
                offEffect: "Sonntags kommt kein Wochenrückblick.",
                hiddenEntry: nil,
                dataFlows: [.local("nichts – dein iPhone plant die Mitteilung selbst")])
        case .haptics:
            return FeatureDescriptor(
                id: id, title: "Haptik", line: "Spürbare Bestätigung bei Tipps und Erfolgen",
                group: .appearance, storage: .wrapped(place: "Einstellungen › Look & Feel"), control: .toggle,
                dependencies: [], usesLiveData: false,
                offEffect: "Dein iPhone vibriert bei keiner Aktion. Die Stufe „Dezent“ findest du in Look & Feel.",
                hiddenEntry: nil,
                dataFlows: [.local()])
        case .officialLogos:
            return FeatureDescriptor(
                id: id, title: "Offizielle Logos & Wappen", line: "Skigebiets-Logos und Landeswappen bei Haltestellen",
                group: .appearance, storage: .wrapped(place: "Einstellungen › Darstellung"), control: .toggle,
                dependencies: [], usesLiveData: false,
                offEffect: "Haltestellen zeigen eigene Wegzeichen, und kein Logo-Paket wird geladen.",
                hiddenEntry: nil,
                dataFlows: [FeatureDataFlow(.cloud, sends: "nichts Persönliches – nur der Abruf des Logo-Pakets",
                                            when: "einmal beim ersten Bedarf, danach nur bei einer neuen Version")])
        }
    }
}
