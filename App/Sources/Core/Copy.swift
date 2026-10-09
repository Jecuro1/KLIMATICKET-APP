import Foundation

/// Long-form German copy used across the app (FAQ, explanations, legal). Du-Form, österreichisch.
enum Copy {
    static let tagline = "Hat sich dein Ticket schon rentiert?"
    static let subline = "Erfasse deine Fahrten – KlimaBilanz zeigt dir, wann dein KlimaTicket den Gipfel erreicht."

    static let fareExplanation = """
    Für jede Fahrt schätzt KlimaBilanz, was sie mit regulären Tickets gekostet hätte:

    • Bahn & Regionalbus: ÖBB-Standardticket nach Bahnkilometern (Luftlinie × Umwegfaktor), wahlweise mit Vorteilscard oder in der 1. Klasse.
    • Innerhalb einer Stadt (U-Bahn, Bim, Stadtbus): Einzelfahrschein der jeweiligen Kernzone.

    Die Schätzung ist bewusst konservativ. Du kannst jeden Preis antippen und anpassen – etwa wenn du sonst ein Sparschiene-Ticket genommen hättest.
    """

    static let amortizationExplanation = """
    Amortisiert heißt: Die Summe der Normalpreise deiner Fahrten hat den Ticketpreis erreicht. Ab dann ist jede Fahrt reiner Gewinn.

    Die Prognose rechnet mit deinem Fahrtempo – gewichtet nach den letzten sechs Wochen – und zeigt, wann du voraussichtlich den Break-even erreichst.
    """

    static let co2Explanation = """
    Die CO₂-Ersparnis vergleicht deine Fahrt mit derselben Strecke allein im Pkw. Grundlage sind die Emissionsfaktoren des Umweltbundesamts pro Personenkilometer (Pkw, Bahn, Bus, Bim/U-Bahn).
    """

    static let carExplanation = """
    Der Auto-Vergleich nutzt das amtliche Kilometergeld. Es deckt Treibstoff, Wertverlust, Versicherung und Service ab – eine realistische Untergrenze für die echten Autokosten.
    """

    static let disclaimer = """
    KlimaBilanz ist ein unabhängiges Projekt und steht in keiner Verbindung zur One Mobility GmbH, zur ÖBB oder zu Verkehrsverbünden. „KlimaTicket“ ist eine Marke der jeweiligen Inhaber:innen. Alle Preise und Schätzungen ohne Gewähr – maßgeblich sind die offiziellen Tarife.
    """

    static let privacy = """
    Deine Daten gehören dir. Ohne Konto bleiben alle Fahrten ausschließlich auf deinem iPhone. Mit Konto werden sie verschlüsselt (TLS) in deine persönliche Cloud-Datenbank synchronisiert, auf die nur du Zugriff hast. Es gibt kein Tracking, keine Werbung und keine Weitergabe an Dritte. Standortdaten werden nur kurz genutzt, um die nächste Haltestelle vorzuschlagen, und nie gespeichert.
    """

    static let dataSources: [(title: String, detail: String)] = [
        ("Ticketpreise", "klimaticket.at (AGB 2021–2026) sowie die Websites der Verkehrsverbünde"),
        ("Normalpreise", "ÖBB Relationspreise (Standardticket, Tarif ab 14.12.2025), sonst Näherung nach Bahnkilometern; Kernzonen-Tarife der Verkehrsverbünde"),
        ("Haltestellen", "Mobilitätsverbünde Österreich OG, Haltestellenverzeichnis (Stand 10/2025, über ÖV-Güteklassen 2025 von ÖROK/BMIMI/AustriaTech), verändert (zusammengeführt, gekürzt, Koordinaten umgerechnet) · ÖBB-Personenverkehr AG Soll-Fahrplan GTFS 2026 (CC BY 4.0) · ÖBB-Infrastruktur AG Verkehrsstationen (CC BY 3.0 AT) · Stadt Wien – data.wien.gv.at (CC BY 4.0) · Land Steiermark – data.steiermark.gv.at (CC BY 4.0) · Statistik Austria – Gemeindegrenzen 2026 (CC BY 4.0)"),
        ("Orte", "© OpenStreetMap-Mitwirkende, ODbL 1.0 (openstreetmap.org/copyright)"),
        ("CO₂-Faktoren", "Umweltbundesamt, Emissionsfaktoren Personenverkehr"),
        ("Kilometergeld", "Reisegebührenvorschrift / BMF"),
    ]

    static let faq: [(question: String, answer: String)] = [
        ("Wie schnell rentiert sich ein KlimaTicket Ö?",
         "Bei € 1.400 (Klassik, 2026) reichen grob elf Hin- und Rückfahrten Wien–Salzburg oder rund 30 Pendeltage Innsbruck–St. Anton im Jahr. KlimaBilanz rechnet es für dich exakt aus."),
        ("Warum weicht der geschätzte Preis vom ÖBB-Ticketshop ab?",
         "Der Ticketshop zeigt oft Sparschiene-Angebote oder Verbundtarife. KlimaBilanz verwendet den regulären Standardpreis. Du kannst jeden Preis manuell anpassen."),
        ("Zählen Mitfahrende bei KlimaTicket Familie?",
         "Du kannst Mitfahrende bei einer Fahrt notieren. In die Amortisation fließt standardmäßig nur deine eigene Fahrt ein."),
        ("Was passiert nach Ablauf meines Tickets?",
         "Lege einfach das Folgeticket an. Deine bisherigen Jahre bleiben im Verlauf erhalten – inklusive Bilanz."),
        ("Wie aktualisiert sich die App?",
         // Channel-neutral on purpose: this FAQ also ships in App Store/TestFlight builds, where App Review objects to
         // naming alternative app marketplaces (Guideline 2.3.10). The AltStore/SideStore hint is `Updates.footerSource`.
         "Neue Versionen werden automatisch erkannt – ein Tipp, und die App ist aktuell. Wo du aktualisierst, zeigt dir Einstellungen › Updates. Ticketpreise aktualisieren sich von selbst, ganz ohne App-Update."),
    ]

    /// Update wording. AltStore/SideStore/TestFlight detect new versions and notify (badge), but the user still taps
    /// „Aktualisieren“ – never promise silent background installs.
    enum Updates {
        static let headline = "Neue Versionen werden automatisch erkannt – ein Tipp, und die App ist aktuell; Ticketpreise aktualisieren sich von selbst."

        // Footers under Einstellungen › Updates (`UpdateService.channelFooter`).
        static let footerSource = "Füge KlimaBilanz einmal als Quelle in AltStore oder SideStore hinzu: Neue Versionen erscheinen dort automatisch – ein Tipp auf „Aktualisieren“, und die App ist aktuell."
        static let footerDirect = "KlimaBilanz erkennt neue Versionen automatisch und lädt sie auf Wunsch herunter. Tipp: Über AltStore oder SideStore geht das Aktualisieren mit einem Tipp."
        static let footerAppStore = "Neue Versionen kommen über den App Store – ein Tipp auf „Aktualisieren“, und die App ist aktuell."
        static let footerTestFlight = "Neue Testversionen kommen über TestFlight – ein Tipp auf „Aktualisieren“, und die App ist aktuell."
        static let footerTariffs = "Ticketpreise und das Tarifmodell aktualisieren sich von selbst, sobald online neue Werte liegen – ganz ohne App-Update."

        // AltStore/SideStore source rows.
        static let sourceRowSubtitle = "Neue Versionen automatisch erkennen"
        static let sourceRowUnavailable = "Verfügbar nach der ersten Update-Prüfung"

        // Primary button in the update sheet (`UpdateService.installActionTitle`).
        static let actionAltStore = "In AltStore aktualisieren"
        static let actionSideStore = "In SideStore aktualisieren"
        static let actionAppStore = "Im App Store aktualisieren"
        static let actionTestFlight = "In TestFlight aktualisieren"
        static let actionDownload = "Update herunterladen"

        // MARK: ota – Direkt installieren (ad-hoc builds over the air, docs/DIREKT_INSTALLIEREN.md)
        static let actionDirectInstall = "Jetzt installieren"
        static let handoffDirectInstall = "Weiter mit „Installieren“"
        static let directInstallNote = "Nach „Installieren“ schließt sich KlimaBilanz und lädt das Update – danach einfach wieder öffnen. Deine Daten bleiben."
        static let footerDirectInstall = "Direkt installiert: Neue Versionen kommen mit „Jetzt installieren“ – ohne Computer und ohne Store. Deine Daten bleiben erhalten."
        static let directInstallRowTitle = "Direkt installieren"
        static let directInstallRowActive = "Aktiv – Updates mit einem Tipp, ohne Store"
        static let directInstallRowGuide = "Ohne AltStore und SideStore – so richtest du es ein"
        static let directInstallGuideURL = URL(string: "https://github.com/Jecuro1/KLIMATICKET-APP/blob/main/docs/DIREKT_INSTALLIEREN.md")!

        static let toggleSubtitle = "Beim Start und alle paar Stunden"
    }
}
