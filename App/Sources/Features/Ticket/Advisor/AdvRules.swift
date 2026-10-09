import Foundation

/// The official rules behind every Ratgeber card (ⓘ sheets). Source: `data/klimaticket_products.json` › `rules`
/// (AGB KlimaTicket Ö, gültig ab 01.01.2026), ÖBB „Extras zum KlimaTicket Ö“ and „Mit Kindern unterwegs“,
/// AK „Dienstreise“ and BMF „Pendlerförderung“ – all checked on 09.10.2026.
enum AdvRules {
    static let renewal = AdvInfo(
        title: "Verlängern",
        paragraphs: [
            "Etwa 2 Monate vor Ablauf schickt dir KlimaTicket eine Einladung zur Verlängerung.",
            "Zahlst du per SEPA-Lastschrift, verlängert sich dein Ticket automatisch um 12 Monate – außer du widersprichst schriftlich bis zur Frist, die im Brief steht.",
            "Mit Einmalzahlung verlängerst du nur, wenn du den Zahlschein einzahlst oder im Kundenkonto unter „Meine Karten“ auf „Karte erneuern“ tippst. Tust du nichts, endet dein Ticket.",
            "Der neue Vertrag beginnt am Tag nach dem Ablauf. Der Preis richtet sich nach diesem ersten Gültigkeitstag.",
            "Die Prognose rechnet mit deinem bisherigen Fahrtempo (die letzten sechs Wochen zählen stärker) und mit den angekündigten Tarifänderungen der ÖBB. Zusatzprodukte wie das 1.-Klasse-Upgrade sind beim nächsten Jahr nicht eingerechnet.",
        ],
        source: "AGB KlimaTicket Ö (01.01.2026): Erneuerung · Zahlung"
    )

    static let cancellation = AdvInfo(
        title: "Kündigen",
        paragraphs: [
            "Ab dem 7. Gültigkeitsmonat kannst du ohne Angabe von Gründen kündigen. Ein Gültigkeitsmonat beginnt immer am selben Kalendertag wie dein Ticket.",
            "Das Kündigungsentgelt beträgt einen Monatsbetrag (1/12 des Preises), 2026 etwa € 116,70 für Classic und € 87,50 für Jugend, Senior und Spezial.",
            "Einmalzahlung: Du bekommst je nicht angefangenem Gültigkeitsmonat 1/12 des Preises zurück, abzüglich des Kündigungsentgelts.",
            "Monatsraten: Nach der Kündigung werden keine Raten mehr abgebucht; das Kündigungsentgelt wird einmal eingezogen – auch das entspricht einer Rate.",
            "Maßgeblich ist der Tag, an dem du das unterschriebene Kündigungsformular und deine Karte bei einer Servicestelle abgibst. Innerhalb eines Gültigkeitsmonats bleibt die Erstattung gleich – du kannst also bis zum letzten Tag des Monats weiterfahren.",
            "Vor dem ersten Gültigkeitstag kannst du dein Ticket gebührenfrei zurückgeben. Online gekauft hast du außerdem 14 Tage Widerrufsrecht.",
            "Kennenlern-Aktion 2026 (Gültigkeitsbeginn 1. Mai bis 30. Juni 2026): gebührenfrei kündbar ab dem 2. Gültigkeitsmonat.",
        ],
        source: "AGB KlimaTicket Ö (01.01.2026): ordentliche Kündigung · Gültigkeitsmonate · Rückgabe; Kennenlern-Aktion 2026"
    )

    static let extraordinary = AdvInfo(
        title: "Außerordentlich kündigen",
        paragraphs: [
            "Ohne Kündigungsentgelt kannst du jederzeit kündigen, wenn du ins Ausland ziehst, mindestens 3 Monate krank bist (mit ärztlichem Attest) oder arbeitslos wirst.",
            "Gib Formular, Nachweis und Karte binnen 4 Wochen nach Eintritt des Grundes ab. Erstattet wird jeder nicht angefangene Gültigkeitsmonat.",
            "Im Todesfall erstattet KlimaTicket den Erb:innen jeden nicht genutzten Monat.",
        ],
        source: "AGB KlimaTicket Ö (01.01.2026): außerordentliche Kündigung"
    )

    static let firstClass = AdvInfo(
        title: "1.-Klasse-Upgrade",
        paragraphs: [
            "Das KlimaTicket Ö gilt in der 2. Klasse. Die ÖBB verkaufen dazu ein 1.-Klasse-Upgrade für ein Jahr: € 1.490 (Classic), € 1.645 (Classic Familie), € 1.130 (Jugend/Senior/Spezial) und € 1.285 (Jugend/Senior/Spezial Familie).",
            "Es gilt in den ÖBB-Fernverkehrszügen und in den 7 ÖBB-Lounges, dazu kommen 10 Sitzplatzreservierungen und der CAT zum Flughafen Wien.",
            "Für den Vergleich rechnen wir für jede deiner Zugfahrten den ÖBB-Normalpreis der 1. Klasse minus den der 2. Klasse. Regionalzüge sind mitgezählt, obwohl das Upgrade dort nicht gilt – der Wert ist also eher eine Obergrenze.",
            "Vorteilsabo (€ 100, Jugend/Senior/Spezial € 90): −30 % auf den Klassenwechsel, −50 % auf Reservierungen und 2 Gratis-Klassenwechsel. Wir nehmen an, dass ein Klassenwechsel die Preisdifferenz der beiden Klassen kostet.",
        ],
        source: "ÖBB „Extras zum KlimaTicket Ö“, Stand 09.10.2026"
    )

    static let family = AdvInfo(
        title: "Familien-Bilanz",
        paragraphs: [
            "Mit dem Familienaufschlag (2026: € 140 auf Classic und auf die ermäßigten Tickets) dürfen bis zu 4 Kinder vom 6. Geburtstag bis einen Tag vor dem 15. Geburtstag gratis mitfahren – ohne Nachweis, und es müssen nicht immer dieselben sein. Kinder unter 6 fahren ohnehin gratis.",
            "Wir bewerten jedes mitfahrende Kind mit dem ÖBB-Kinderpreis, also dem halben Normalpreis der 2. Klasse. Gezählt werden die Mitfahrenden, die du bei deinen Fahrten einträgst – höchstens 4 pro Fahrt.",
            "Auf KlimaTicket Ö Familie wechseln kannst du jederzeit gebührenfrei. Abgerechnet wird tagesgenau, und dein Ticket gilt dann 12 Monate ab dem Wechseltag.",
        ],
        source: "AGB KlimaTicket Ö (01.01.2026): Familie · Kategoriewechsel; ÖBB „Mit Kindern unterwegs“"
    )

    static let jobticket = AdvInfo(
        title: "Jobticket",
        paragraphs: [
            "Dein Arbeitgeber darf dir das KlimaTicket steuerfrei zur Verfügung stellen oder die Kosten steuerfrei ersetzen. Auf ein Jobticket deines Arbeitgebers wechseln kannst du jederzeit gebührenfrei.",
            "KlimaBilanz misst die Amortisation an dem, was du selbst bezahlst: Ticketpreis plus Extras minus Zuschuss.",
            "Pendlerpauschale: Sie wird um den steuerfreien Zuschuss gekürzt, der Pendlereuro bleibt (BMF).",
            "Dienstreisen mit deinem eigenen Ticket: Absetzbar sind die Kosten eines Einzelfahrscheins 2. Klasse, insgesamt höchstens der Betrag, den du selbst für das Ticket bezahlt hast (AK).",
            "Das ist eine Orientierung, keine Steuerberatung.",
        ],
        source: "AGB KlimaTicket Ö (01.01.2026): Kategoriewechsel; BMF Pendlerförderung; AK Dienstreise"
    )
}
