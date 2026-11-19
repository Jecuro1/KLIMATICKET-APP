import Foundation

// MARK: funktionen – Funktionen › Datenschutz (docs/FUNCTIONS_HUB.md §5): who receives what, when – from the registry's data flows
// plus the four services that are no hub feature (Konto & Sync, Update-Prüfung, Tarife, Live-Konfiguration). Request counters exist
// for the three live providers only; they are in memory, start at zero at every launch and never hold a request's content.

/// A service of the app that sends data but is no switch of the hub.
public enum FeatureService: String, CaseIterable, Sendable, Hashable, Identifiable {
    // MARK: review-funktionen – serverConfig: `/v1/config` goes out at every launch, with or without an account
    case accountSync, serverConfig, updateCheck, tariffs, liveConfig

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accountSync: "Konto & Sync"
        case .serverConfig: "Server-Einstellungen"
        case .updateCheck: "Update-Prüfung"
        case .tariffs: "Tarife"
        case .liveConfig: "Live-Konfiguration"
        }
    }

    public var flow: FeatureDataFlow {
        switch self {
        case .accountSync:
            // MARK: review-funktionen – sync also carries the Vorteile and the display name; the sign-in brings the e-mail address
            FeatureDataFlow(.cloud, sends: "deine Fahrten, Tickets, Favoriten und Vorteile, dein Anzeigename und die E-Mail-Adresse deiner Anmeldung – verschlüsselt übertragen",
                            when: "nur mit Konto: beim Öffnen der App und nach deinen Änderungen")
        case .serverConfig:
            FeatureDataFlow(.cloud, sends: "nichts Persönliches – App- und iOS-Version beim Abruf, welche Anmeldungen und Logo-Pakete es gibt",
                            when: "beim Start der App und vor jedem Sync, auch ohne Konto")
        case .updateCheck:
            FeatureDataFlow(.github, sends: "nichts Persönliches – nur der Abruf der Versionsliste",
                            when: "beim Öffnen höchstens alle 6 Stunden, wenn „Automatisch prüfen“ an ist, und nach deinem Tipp")
        case .tariffs:
            FeatureDataFlow(.github, sends: "nichts Persönliches – nur der Abruf der Preistabellen",
                            when: "höchstens alle 12 Stunden, wenn „Automatisch prüfen“ an ist")
        case .liveConfig:
            FeatureDataFlow(.github, sends: "nichts Persönliches – nur der Abruf der Fernabschaltung",
                            when: "höchstens alle 12 Stunden, nur mit deiner Zustimmung zu Live-Daten")
        }
    }

    /// The Offline-Modus stops it (the update check only when it runs by itself).
    public var stoppedByOfflineMode: Bool {
        switch self {
        case .updateCheck, .liveConfig: true
        case .accountSync, .serverConfig, .tariffs: false
        }
    }
}

/// One line of the privacy table: a feature or a service, what it sends, when.
public struct FeaturePrivacyItem: Equatable, Sendable, Identifiable {
    public enum Source: Equatable, Sendable, Hashable {
        case feature(FeatureID)
        case service(FeatureService)
    }

    public let source: Source
    public let flow: FeatureDataFlow

    public var id: String {
        switch source {
        case .feature(let feature): "f.\(feature.rawValue).\(flow.recipient.rawValue)"
        case .service(let service): "s.\(service.rawValue)"
        }
    }

    public var title: String {
        switch source {
        case .feature(let feature): feature.title
        case .service(let service): service.title
        }
    }
}

/// A recipient with everything it can receive.
public struct FeaturePrivacyRecipient: Equatable, Sendable, Identifiable {
    public let recipient: FeatureRecipient
    public let items: [FeaturePrivacyItem]
    public var id: String { recipient.rawValue }
}

public enum FeaturePrivacy {
    /// Recipients outside the iPhone, live providers first.
    public static let remoteOrder: [FeatureRecipient] = [.oebbTimetable, .oebbShop, .vao, .cloud, .github, .appleMaps]

    /// The privacy table: every recipient outside the iPhone with the features and services that reach it.
    public static func recipients() -> [FeaturePrivacyRecipient] {
        remoteOrder.map { recipient in
            var items = FeatureRegistry.all.flatMap { descriptor in
                descriptor.dataFlows.filter { $0.recipient == recipient }
                    .map { FeaturePrivacyItem(source: .feature(descriptor.id), flow: $0) }
            }
            items += FeatureService.allCases.filter { $0.flow.recipient == recipient }
                .map { FeaturePrivacyItem(source: .service($0), flow: $0.flow) }
            return FeaturePrivacyRecipient(recipient: recipient, items: items)
        }
    }

    /// Features that send nothing at all.
    public static var localFeatures: [FeatureID] {
        FeatureRegistry.all.filter { !$0.sendsData }.map(\.id)
    }

    // MARK: Copy

    /// Fixed line under the counters.
    public static let counterHonesty = "Die Zähler gelten für Live-Daten. Sync, Updates und Logo-Pakete zählen nicht mit."
    /// Fixed line about the counters' lifetime.
    public static let counterLifetime = "Gezählt wird nur im Arbeitsspeicher, ab dem Start der App – ohne Inhalt der Anfragen."
    /// What every server sees.
    public static let networkLine = "Wie bei jeder Internet-Anfrage sieht der Empfänger die IP-Adresse deines Anschlusses."
    /// The consent promise (docs/OEBB_LIVE.md §2).
    public static let consentLine = "Live-Daten fragt dein iPhone erst ab, wenn du ihnen zugestimmt hast – direkt bei der ÖBB und der VAO, nie über einen Server von KlimaBilanz."

    /// What the Offline-Modus stops. MARK: review-funktionen – it also ends „Live verfolgen“ with its guard and its wake-up alarm
    /// (LiveFollowTracker: no answer → ExitAlarmService.liveDataOff) and stops the live widgets and the Pendel-Karte's search.
    public static let offlineStops: [String] = [
        "Fahrplan & Echtzeit samt Abfahrten, Pendel-Karte live und Live-Widgets",
        "Zug-Radar, Züge suchen, Störungen und Live-Ticketpreise",
        "„Live verfolgen“ mit Mitteilungen, Anschluss-Wächter und Aussteige-Wecker",
        "die automatische Update-Prüfung und die Live-Konfiguration",
    ]
    /// What it does not stop – with a server, the short fetch of its settings at launch goes on as well (MARK: review-funktionen).
    public static func offlineKeeps(cloudConfigured: Bool) -> String {
        let keeps = cloudConfigured
            ? "Konto-Sync, Tarif-Download und Logo-Pakete folgen ihren eigenen Schaltern, die Server-Einstellungen kommen weiter beim Start."
            : "Tarif-Download und Logo-Pakete folgen ihren eigenen Schaltern."
        return keeps + " Karten laden ihre Kacheln weiter bei Apple."
    }

    // MARK: review-funktionen – the state of the recipients that are no live provider („Jetzt: …“ on Datenschutz)

    /// How much a recipient gets right now.
    public enum Activity: Equatable, Sendable {
        case on, partly, off
    }

    /// GitHub: tariffs and the update check run by themselves with „Automatisch prüfen“ (the update check not in the
    /// Offline-Modus); the live configuration comes with the live-data consent at launch, whatever „Automatisch prüfen“ says
    /// (`LiveDataService.start`), and not in the Offline-Modus. A tap on „Jetzt prüfen“ always asks.
    public static func githubState(autoCheck: Bool, offlineMode: Bool, liveConsent: Bool) -> (text: String, activity: Activity) {
        var automatic: [String] = []
        var onTap: [String] = []
        if autoCheck { automatic.append("Tarife") } else { onTap.append("Tarife") }
        if autoCheck && !offlineMode { automatic.append("Updates") } else { onTap.append("Updates") }
        if liveConsent && !offlineMode { automatic.append("Live-Konfiguration") }
        guard !automatic.isEmpty else { return ("nur nach deinem Tipp", .off) }
        let auto = listed(automatic)
        if onTap.isEmpty { return ("\(auto) automatisch, höchstens alle paar Stunden", .on) }
        return ("\(auto) automatisch · \(listed(onTap)) nur nach deinem Tipp", .partly)
    }

    /// The KlimaBilanz server: nothing without one in the build, sync with an account, else the settings at launch (and the logo
    /// packs while „Offizielle Logos & Wappen“ is on).
    public static func cloudState(configured: Bool, signedIn: Bool, logosOn: Bool) -> (text: String, activity: Activity) {
        guard configured else { return ("kein Server eingerichtet – nichts", .off) }
        if signedIn { return ("angemeldet – Sync an", .on) }
        return (logosOn ? "ohne Konto – Server-Einstellungen beim Start und Logo-Pakete" : "ohne Konto – nur Server-Einstellungen beim Start",
                .partly)
    }

    /// „A“, „A und B“, „A, B und C“.
    static func listed(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " und " + (parts.last ?? "")
    }
    /// The consent stays as it is.
    public static let offlineConsent = "Deine Zustimmung zu Live-Daten bleibt, wie sie ist – schaltest du den Offline-Modus aus, geht alles wie vorher weiter."

    /// „3 Anfragen in der letzten Minute, 41 seit dem Start · zuletzt 14:31:12“ – `lastText` is the formatted time of the last one.
    public static func counterLine(_ counters: RequestCounters, lastText: String?) -> String {
        guard counters.total > 0 else { return "Keine Anfrage seit dem Start der App" }
        let minute = counters.lastMinute == 1 ? "1 Anfrage in der letzten Minute" : "\(counters.lastMinute) Anfragen in der letzten Minute"
        var line = "\(minute), \(counters.total) seit dem Start"
        if let lastText { line += " · zuletzt \(lastText)" }
        return line
    }
}
