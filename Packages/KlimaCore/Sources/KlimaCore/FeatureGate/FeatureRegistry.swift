import Foundation

// MARK: funktionen – Einstellungen › Funktionen (docs/FUNCTIONS_HUB.md): one place that answers „Was kann die App, was davon ist
// an, und was sendet sie?“. This file is the registry: every feature the hub lists, where its switch lives, what it needs, what
// disappears while it is off and where its data goes. Pure data – the app maps it to symbols, colours and the real switches.

/// A feature of the hub. Raw values are the keys of `features.v1` (only the hub's own switches are stored there).
public enum FeatureID: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    // Live-Daten
    case liveTimetable, livePrices, followNotices
    case exitAlarm   // MARK: integrate-wave2 – the Aussteige-Wecker rides on „Live verfolgen“ (docs/EXIT_ALARM.md)
    // Karte & Radar
    case radar, trainSearch, disruptions
    // Erfassen
    case tripDetection
    // Übersicht
    case assistant, perksCard, achievementsTeaser, weekInsight
    case commute, calendarSuggestions   // MARK: integrate-wave2 – Pendel-Modus, Kalender-Vorschläge (their own pages)
    // Mitteilungen
    case renewalReminders, weeklySummary
    case automation   // MARK: integrate-wave2 – Automatik (its own page)
    // Darstellung
    case haptics, officialLogos
    // Daten
    case autoBackup   // MARK: integrate-wave2 – „Tägliche Sicherung“ of Daten & Sicherung (docs/DATA_HUB.md §4)

    public var id: String { rawValue }
    public var descriptor: FeatureDescriptor { FeatureRegistry.descriptor(self) }
    public var title: String { descriptor.title }
}

/// The hub's sections, in display order.
public enum FeatureGroup: String, CaseIterable, Sendable, Hashable, Identifiable {
    case liveData, mapRadar, capture, overview, notices, appearance
    case data   // MARK: integrate-wave2

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .liveData: "Live-Daten"
        case .mapRadar: "Karte & Radar"
        case .capture: "Erfassen"
        case .overview: "Übersicht"
        case .notices: "Mitteilungen"
        case .appearance: "Darstellung"
        case .data: "Daten"   // MARK: integrate-wave2
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

    /// MARK: review-funktionen – it speaks only through notices, so iOS refusing them keeps it quiet while its switch is on.
    public var usesNotifications: Bool { [.followNotices, .renewalReminders, .weeklySummary, .automation].contains(id) }   // MARK: integrate-wave2 – Automatik speaks only through notices
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
                                            when: "wenn du suchst oder eine Live-Ansicht zu sehen ist (auch die Pendel-Karte in ihrem Zeitfenster), für deine Widgets beim Öffnen der App höchstens alle 15 Minuten – \(liveAsk)")])
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
        // MARK: integrate-wave2 – no switch of its own: it is there whenever „Live verfolgen“ is (docs/EXIT_ALARM.md §1, §2)
        case .exitAlarm:
            return FeatureDescriptor(
                id: id, title: "Aussteige-Wecker", line: "Weckt dich kurz vor deinem Ausstieg – nach Fahrplan und Standort",
                group: .liveData, storage: .wrapped(place: "Einstellungen › Aussteige-Wecker"), control: .ownPage,
                dependencies: [.liveTimetable], usesLiveData: false,
                offEffect: "Es lässt sich kein Wecker stellen, und ein gestellter endet mit einer Mitteilung.",
                hiddenEntry: nil,
                dataFlows: [.local("dein Standort, solange ein Wecker gestellt ist – nur auf dem iPhone, nie gesendet und nicht gespeichert; den Fahrplan holt „Live verfolgen“, der Wecker fragt selbst nichts ab")])
        case .radar:
            return FeatureDescriptor(
                // MARK: integrate-radar3 – every mode the radar shows, and that its positions are calculated (docs/OEBB_LIVE.md §R11.3)
                id: id, title: "Zug-Radar", line: "Züge, Bus, Bim und U-Bahn auf der Karte – Positionen berechnet",
                group: .mapRadar, storage: .hub(defaultOn: true), control: .toggle,
                dependencies: [.liveTimetable], usesLiveData: false,
                // MARK: review-funktionen – „Auf der Karte zeigen“ in „Züge suchen“ opened the whole radar while it was off
                offEffect: "Der Radar-Knopf im Fahrplan und „Auf der Karte zeigen“ in „Züge suchen“ sind ausgeblendet; Widget-Knopf und Link öffnen dann diese Seite.",
                hiddenEntry: "der Radar-Knopf im Fahrplan samt „Auf der Karte zeigen“ in „Züge suchen“",
                // MARK: radar2-radarmine – „Wo bleibt mein Bus?“ asks the chosen stop's departures inside the same 24 (docs/RADAR_MINE.md §4)
                // MARK: integrate-radar3 – also the Zeitreise's time, the tapped trip (trip sheet) and the Cockpit's train (docs/OEBB_LIVE.md §R11.3)
                dataFlows: [FeatureDataFlow(.oebbTimetable, sends: "der Kartenausschnitt, den du ansiehst, bei der Zeitreise mit der gewählten Zeit; die Fahrt, die du antippst oder im Cockpit begleitest; bei „Wo bleibt mein Bus?“ die Haltestelle, die du wählst",
                                            when: "solange das Radar offen ist, höchstens 24 Anfragen pro Minute für Karte, Zeitreise und Cockpit; die Abfahrten deiner Haltestelle einmal pro Minute darin, solange diese Ansicht offen ist; eine Fahrt, wenn du sie antippst – \(liveAsk)"),
                            FeatureDataFlow(.appleMaps, sends: "der Kartenausschnitt, den du ansiehst",
                                            when: "solange eine Karte zu sehen ist"),
                            // MARK: radar2-radartrail – Spuren keep what the radar loaded, in memory only (docs/RADAR_TRAILS.md §3)
                            .local("Spuren: Positionen, die das Radar geladen hat – nur im Arbeitsspeicher, solange es offen ist"),
                            // MARK: radar2-radarmine – remembered lines and stops on the device only, the fix of „In der Nähe“ in memory (docs/RADAR_MINE.md §6)
                            .local("Meine Fahrzeuge: gemerkte Linien und die letzten fünf Haltestellen auf diesem iPhone, nicht in der iPhone-Sicherung; dein Standort für „In der Nähe“ nur im Arbeitsspeicher, nie gesendet")])
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
                offEffect: "Die Vorteile-Karte ist ausgeblendet. Die Vorteilswelt bleibt unter Einstellungen › Vorteile & Fahrgastrechte.",
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
        // MARK: integrate-wave2 – Pendel-Modus (docs/COMMUTE.md §1, §7): its switch lives on its own page
        case .commute:
            return FeatureDescriptor(
                id: id, title: "Pendel-Modus", line: "Die nächsten Züge deiner Stammstrecke in der Übersicht",
                group: .overview, storage: .wrapped(place: "Einstellungen › Pendeln"), control: .ownPage,
                dependencies: [], usesLiveData: false,
                offEffect: "Die Übersicht zeigt keine Pendel-Karte – höchstens einmal die Frage „Ist das dein Arbeitsweg?“.",
                hiddenEntry: nil,
                dataFlows: [FeatureDataFlow(.oebbTimetable, sends: "Start und Ziel deiner Stammstrecke und die Uhrzeit",
                                            when: "höchstens einmal pro Minute, solange die Pendel-Karte in ihrem Zeitfenster zu sehen ist – \(liveAsk)")])
        // MARK: integrate-wave2 – Kalender-Vorschläge (docs/CALENDAR_SUGGESTIONS.md): off until switched on, on its own page
        case .calendarSuggestions:
            return FeatureDescriptor(
                id: id, title: "Kalender-Vorschläge", line: "Zugfahrten zu deinen Terminen der nächsten 14 Tage",
                group: .overview, storage: .wrapped(place: "Einstellungen › Kalender-Vorschläge"), control: .ownPage,
                dependencies: [], usesLiveData: false,
                offEffect: "Die App liest keine Termine, und die Übersicht schlägt keine Fahrt zu einem Termin vor.",
                hiddenEntry: nil,
                dataFlows: [.local("Termine der nächsten 14 Tage aus den Kalendern, die du wählst – gelesen nur auf dem iPhone und bei offener App, Titel und Orte nie gespeichert")])
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
        // MARK: integrate-wave2 – Automatik (docs/AUTOMATION.md): „an“ while the master switch and at least one rule are on
        case .automation:
            return FeatureDescriptor(
                id: id, title: "Automatik", line: "Eigene Regeln „Wenn … dann …“ für Erinnerungen und Meilensteine",
                group: .notices, storage: .wrapped(place: "Einstellungen › Automatik"), control: .ownPage,
                dependencies: [], usesLiveData: false,
                offEffect: "Keine Regel läuft, und ihre geplanten Mitteilungen sind entfernt.",
                hiddenEntry: nil,
                dataFlows: [.local("nichts – Regeln laufen auf dem iPhone und fragen nichts im Netz ab")])
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
        // MARK: integrate-wave2 – the daily backup of Daten & Sicherung (docs/DATA_HUB.md §4); the safety backups do not depend on it
        case .autoBackup:
            return FeatureDescriptor(
                id: id, title: "Tägliche Sicherung", line: "Einmal am Tag eine Sicherung in Dateien, wenn sich etwas geändert hat",
                group: .data, storage: .wrapped(place: "Einstellungen › Daten & Sicherung"), control: .toggle,
                dependencies: [], usesLiveData: false,
                offEffect: "Es entsteht keine tägliche Sicherung. Vor dem Löschen und Wiederherstellen sichert die App trotzdem.",
                hiddenEntry: nil,
                dataFlows: [.local("alle deine Daten als Datei unter Dateien › Auf meinem iPhone › KlimaBilanz › Sicherungen – sie bleiben auf dem iPhone (und im iCloud-Backup des iPhones, falls es an ist) und gehen nur weiter, wenn du sie teilst")])
        }
    }
}
