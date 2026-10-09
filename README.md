# KlimaBilanz

**Hat sich dein KlimaTicket schon rentiert?** KlimaBilanz ist eine native Premium-iOS-App (SwiftUI, iOS 26, Liquid Glass),
die jede deiner Öffi-Fahrten mit dem regulären Ticketpreis bewertet und dir auf einen Blick zeigt, wie weit dein
Ticket schon „amortisiert“ ist – inklusive Prognose, wann du den Break-even-Gipfel erreichst.

## Funktionen

- **Übersicht** – riesige Amortisations-Anzeige mit „Gipfel“-Grafik, Break-even-Prognose, Kennzahlen, Schnellerfassung
- **Fahrten erfassen in Sekunden** – 1.487 Haltestellen (ÖBB-Fahrplandaten, OSM, Wiener Linien), Lieblingsfahrten,
  „Nochmal fahren“, Hin & Retour, Mitfahrende, Notizen
- **Exakte Normalpreise** – offizielle ÖBB-Relationspreise (26.000+ Verbindungen, Tarif ab 14.12.2025), sonst
  kalibrierte Schätzung nach Bahnkilometern; Kernzonen-Tarife in Städten; Vorteilscard & 1. Klasse
- **Alle KlimaTickets** – KlimaTicket Ö (Klassik/Jugend/Senior/Spezial/Familie, Preise 2021–2026 nach Gültigkeitsbeginn)
  und alle regionalen Tickets aller Bundesländer
- **Statistik** – Ersparnis-Verlauf mit Prognose, Monatsbilanz, Verkehrsmittel, Wochentage, Reise-Kalender,
  Top-Strecken, Rekorde, „Welches Ticket lohnt sich?“, Auto-Vergleich, CO₂-Bilanz
- **Digitales Ticket** – Wallet-Karte mit holografischem Schimmer, Gültigkeit, Verlängerungs-Erinnerungen, Ticket-Jahre
- **Erfolge** – 17 Abzeichen von „Eingestiegen“ bis „Ganz Österreich“
- **Automatische Fahrterkennung** (optional) – erkennt Fahrten zwischen deinen Stamm-Bahnhöfen und schlägt sie vor
- **Widgets, Sperrbildschirm, Kontrollzentrum, Siri & Kurzbefehle** – inkl. interaktiver Schnellerfassung
- **Konten** – Anmeldung mit Apple, Google oder Microsoft, Cloud-Sync zwischen Geräten (Supabase)
- **Automatische Updates** – In-App-Update-Hinweis + AltStore/SideStore-Quelle; Ticketpreise aktualisieren sich selbst
- **Datenschutz** – ohne Konto bleibt alles auf dem iPhone; kein Tracking, keine Werbung

## Installieren

Jeder Build auf GitHub erzeugt eine `.ipa`-Datei (Actions › iOS › Artifacts, bzw. unter Releases).
Installation per AltStore, SideStore, Sideloadly oder TestFlight – Details in [docs/SETUP.md](docs/SETUP.md).

## Entwicklung

- Architektur: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · Design: [docs/DESIGN.md](docs/DESIGN.md) ·
  Design-System-API: [docs/DESIGN_SYSTEM_API.md](docs/DESIGN_SYSTEM_API.md)
- Projekt erzeugen: `brew install xcodegen && xcodegen generate`
- Kernlogik testen (macOS oder Linux): `swift test --package-path Packages/KlimaCore`
- Tarifkatalog neu bauen: `python3 scripts/build_tariffs.py` · Preistabelle: `python3 scripts/build_relations.py`

## Datenquellen

Ticketpreise: klimaticket.at & Verkehrsverbünde · Normalpreise: ÖBB Relationspreise · Haltestellen: ÖBB-Personenverkehr
(GTFS, CC BY 4.0), ÖBB-Infrastruktur (CC BY 3.0 AT), © OpenStreetMap-Mitwirkende (ODbL), Stadt Wien – data.wien.gv.at
(CC BY 4.0) · CO₂: Umweltbundesamt.

KlimaBilanz ist ein unabhängiges Projekt und steht in keiner Verbindung zur One Mobility GmbH oder zur ÖBB.
