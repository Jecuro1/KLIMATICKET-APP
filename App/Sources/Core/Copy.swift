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
    Deine Daten gehören dir. Ohne Konto bleiben alle Fahrten ausschließlich auf deinem iPhone. Mit Konto werden sie verschlüsselt (TLS) in deine persönliche Cloud-Datenbank synchronisiert, auf die nur du Zugriff hast (Row Level Security). Es gibt kein Tracking, keine Werbung und keine Weitergabe an Dritte. Standortdaten werden nur kurz genutzt, um die nächste Haltestelle vorzuschlagen, und nie gespeichert.
    """

    static let dataSources: [(title: String, detail: String)] = [
        ("Ticketpreise", "klimaticket.at (AGB 2021–2026) sowie die Websites der Verkehrsverbünde"),
        ("Normalpreise", "ÖBB-Standardticket-Tarif (genähert), Kernzonen-Tarife der Verkehrsverbünde"),
        ("Haltestellen", "© OpenStreetMap-Mitwirkende, Open Database License (ODbL)"),
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
         "KlimaBilanz prüft automatisch auf neue Versionen und aktuelle Ticketpreise. Über AltStore oder SideStore installieren sich Updates sogar im Hintergrund."),
    ]
}
