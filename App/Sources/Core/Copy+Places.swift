import Foundation
import KlimaCore

// MARK: stops – texts of the stop enrichment (docs/ENRICH_SPEC.md §1.10.2, docs/LOGO_SPEC.md §4.4, §5). A new file, so
// `Copy.swift` stays untouched. German, exact.

extension Copy {
    /// Einstellungen › Über › Datenquellen: the entries the stop detail adds.
    static let placeDataSources: [(title: String, detail: String)] = [
        ("Linien", "ÖBB-Personenverkehr AG Soll-Fahrplan GTFS 2026 (CC BY 4.0) · Stadt Wien – data.wien.gv.at, Wiener Linien Fahrplandaten (CC BY 4.0) · Land Steiermark – data.steiermark.gv.at, Haltestellen und Linienverkehr des Verkehrsverbundes Steiermark (CC BY 4.0) · Linien je Haltestelle: ÖV-Güteklassen 2025 (ÖROK/BMIMI/AustriaTech; Daten der Mobilitätsverbünde Österreich OG), verändert (zusammengeführt)."),
        ("Linienverläufe, Skigebiete, Lifte, Barrierefreiheit, Orte", "© OpenStreetMap-Mitwirkende, ODbL 1.0 (openstreetmap.org/copyright)"),
        ("Ausstattung an Haltestellen", PlaceCopy.facilitySource),
        ("Gemeinden und Bezirke", "Statistik Austria, Gemeinden 01.01.2026 (CC BY 4.0)"),
        ("Zeichen, Logos und Wappen", PlaceCopy.marksNote),
    ]
}

enum PlaceCopy {
    /// Names, logos and Landeswappen (LOGO_SPEC §4.4 footer, §5 Impressum).
    static let marksNote = "Skigebiets-, Regions-, Verbund- und Betreibernamen dienen nur der Ortsangabe; es besteht keine Verbindung zu den Betreibern. Logos sind Marken ihrer jeweiligen Inhaber und werden nur zur Ortsangabe gezeigt. Landeswappen sind amtliche Werke und dienen nur der geografischen Zuordnung. KlimaBilanz ist kein Angebot der Länder, der Republik, der KlimaTicket-Betreiber, der Skigebiete oder Tourismusverbände."

    /// Names only (no official logos or Wappen on screen).
    static let namesNote = "Skigebiets-, Regions-, Verbund- und Betreibernamen dienen nur der Ortsangabe; es besteht keine Verbindung zu den Betreibern. Farben und Symbole sind eigene Gestaltung."

    /// Ausstattung (Aufzug, WC, Fahrradständer, Fahrkartenautomat, Wartehäuschen, Sitzbank, Blindenleitsystem,
    /// Abfahrtstafel, Barrierefreiheit): ODbL attribution (ENRICH_SPEC §1.10.2) and the reading rule of the grid.
    static let facilitySource = "© OpenStreetMap-Mitwirkende, ODbL 1.0 (openstreetmap.org/copyright). Die Angaben sind freiwillige Einträge in OpenStreetMap. „nicht erfasst“ heißt nur, dass OpenStreetMap dazu nichts sagt, nicht dass etwas fehlt."

    static let outdatedLines = "Liniendaten veraltet – App aktualisieren"
    static let noLines = "Kein regelmäßiger Linienverkehr bekannt"
    static let liveSource = "Abfahrten: ÖBB-Fahrplanauskunft (live)"

    /// Footer of the stop detail, built from the layers present (§1.10.2) plus the logo line when logos or Wappen show.
    static func footer(attribution: [String], liveShown: Bool, logoOwners: [String], showsWappen: Bool) -> String {
        var parts = attribution
        if liveShown { parts.append(liveSource) }
        var text = parts.joined(separator: " · ")
        if !logoOwners.isEmpty || showsWappen {
            var logo = ""
            if !logoOwners.isEmpty {
                logo += "Logos © \(logoOwners.joined(separator: ", ")) – Marken der jeweiligen Inhaber, nur zur Ortsangabe."
            }
            if showsWappen { logo += (logo.isEmpty ? "" : " ") + "Landeswappen: amtliche Werke, nur zur geografischen Zuordnung." }
            logo += " KlimaBilanz ist kein Angebot der Länder, Skigebiete oder Tourismusverbände."
            text += (text.isEmpty ? "" : "\n") + logo
        } else {
            text += (text.isEmpty ? "" : "\n") + namesNote
        }
        return text
    }
}
