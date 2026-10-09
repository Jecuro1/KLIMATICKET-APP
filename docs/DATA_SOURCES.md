# Datenquellen und Lizenzen der gebündelten Daten

Status: 2026-10-09. Gilt für alle Dateien in `App/Resources/` und `data/`. Die Texte, die die App unter
Einstellungen › Über › Datenquellen zeigen muss, stehen in [§5](#5-text-für-die-app-datenquellen).

## 1. Überblick

| Datei | Inhalt | Erzeugt von | Lizenz der Datei |
|---|---|---|---|
| `App/Resources/places.bin` (3.06 MB, 1.19 MB gzip) | alle 39,711 Haltestellen Österreichs (alle Verkehrsverbünde: Bahn, S-Bahn, U-Bahn, Straßenbahn, Bus inkl. Postbus/Regionalbus, Schiff, Seilbahn/Rufbus) + 118 Grenz-/Auslandsbahnhöfe | `scripts/build_places.py` | Mobilitätsverbünde-Daten (siehe §3 – **offen**) + CC BY 4.0 / CC BY 3.0 AT; **keine OSM-Daten** |
| `App/Resources/localities.bin` (1.48 MB, 0.64 MB gzip) | 21,050 Orte (Städte, Gemeinden, Dörfer, Ortsteile) mit Hauptbahnhof/-haltestelle | `scripts/build_places.py` | **ODbL 1.0** (abgeleitete Datenbank aus OpenStreetMap) |
| `App/Resources/stations.json` | die bisherige Stationsliste (1,487 Einträge). **Eingefroren**: bestehende Fahrten referenzieren diese IDs; jede ID ist in `places.bin` als `legacy`-ID hinterlegt | früherer Recherche-Lauf | ÖBB GTFS (CC BY 4.0), ÖBB-Infrastruktur (CC BY 3.0 AT), OSM (ODbL), Stadt Wien (CC BY 4.0) |
| `App/Resources/relations.bin`, `relations-points.json` | ÖBB-Relationspreise | `scripts/build_relations.py` | siehe dort |
| `App/Resources/tariffs.json`, `data/*.json` | Ticketpreise, Tarifmodell | `scripts/build_tariffs.py` | Fakten von klimaticket.at / Verbünden |
| `data/places_report.json` | Prüfsummen der Eingaben, Zählungen je Bundesland/Verkehrsmittel | `scripts/build_places.py` | – |

Das Binärformat beider `.bin`-Dateien ist im Docstring von `scripts/build_places.py` beschrieben (`read_bin()` ist der
Referenz-Decoder, der Swift-Leser ist `Packages/KlimaCore/Sources/KlimaCore/Places/PlaceDataset.swift`).

## 2. Quellen von `places.bin` und `localities.bin`

| Quelle | Lizenz | Beitrag |
|---|---|---|
| **ÖV-Güteklassen 2025_revised** (ÖROK / BMIMI / AustriaTech; enthält den Haltestellen-WFS der Mobilitätsverbünde Österreich, Stand 10/2025) – `01_Haltestellenkategorien_20251022` | **keine explizite Lizenz** („Kein(e) Lizenz und kein Vertrag“ auf mobilitydata.gv.at) → §3 | Basisliste: 39,541 Haltestellen mit IFOPT-ID (`St_Nummer` 470118700 → `at:47:1187`), Abfahrten am Mi 22.10.2025, Linien, Verkehrsmittel-Klasse |
| data.mobilitaetsverbuende.at Datensatz 46 „Haltestellen (CSV)“ (optional, `--mvo`) | Datenlizenz Mobilitätsverbünde Österreich v1.1 | ersetzt/ergänzt die Basisliste (Login nötig) |
| ÖBB-Personenverkehr AG, Soll-Fahrplan GTFS 2026 (data.oebb.at) | CC BY 4.0 | 1,138 Bahnhöfe: Bahn-Verkehrsmittel, Abfahrten; 92 Auslandsbahnhöfe ergänzt, 11 Tarifpunkte verworfen |
| Wiener Linien GTFS (Stadt Wien – data.wien.gv.at) | CC BY 4.0 | 1,781 Haltestellen zugeordnet (Kurznamen als Alias), 15 ergänzt |
| Land Steiermark – Haltestellen des Verkehrsverbundes Steiermark (data.steiermark.gv.at) | CC BY 4.0 | 7,108 zugeordnet, 61 bediente Haltestellen ergänzt, 1,047 unbediente übersprungen |
| Statistik Austria – Gemeindegrenzen 01.01.2026 (data.statistik.gv.at) | CC BY 4.0 | Gemeinde und Bundesland je Haltestelle (Punkt-in-Polygon; 39,591 in Österreich, 118 im Ausland) |
| ÖBB-Infrastruktur AG – Verzeichnis der Verkehrsstationen (über `data/stations_meta.json`) | CC BY 3.0 AT | EVA-Nummern (= ÖBB-HAFAS-extId) für 1,015 Bahnhöfe |
| OpenStreetMap Austria (Geofabrik-Extrakt) | ODbL 1.0 | **nur** `localities.bin` (Orte) und die Lückenanalyse (`osm_only_clusters.tsv`, nicht ausgeliefert) |

Kuratierte Suchaliasse (Codes wie „VIE“, „GRZ“, „Wien West“) sind im Skript (`CURATED_ALIASES`) hinterlegt, eigene Arbeit.

**Zählungen** (eine Haltestelle kann mehrere Verkehrsmittel haben; „ohne Abfahrt“ = keine Abfahrt am Referenz-Mittwoch,
z. B. Saison-, Schul- und Rufbushaltestellen):

| Bundesland | gesamt | Bahn | Bim | U-Bahn | Bus | Schiff | Seilbahn/Rufbus | ohne Abfahrt |
|---|---|---|---|---|---|---|---|---|
| Wien | 1,958 | 52 | 406 | 98 | 1,731 | 0 | 21 | 223 |
| Niederösterreich | 8,984 | 450 | 1 | 0 | 8,671 | 12 | 68 | 1,544 |
| Burgenland | 1,634 | 44 | 0 | 0 | 1,613 | 0 | 0 | 228 |
| Oberösterreich | 5,828 | 310 | 63 | 0 | 5,599 | 27 | 4 | 861 |
| Salzburg | 2,712 | 130 | 0 | 0 | 2,587 | 4 | 57 | 475 |
| Steiermark | 8,996 | 230 | 107 | 0 | 8,737 | 10 | 96 | 2,213 |
| Kärnten | 3,419 | 196 | 0 | 0 | 3,293 | 34 | 38 | 706 |
| Tirol | 3,922 | 231 | 57 | 0 | 3,791 | 8 | 71 | 924 |
| Vorarlberg | 2,140 | 41 | 0 | 0 | 2,127 | 1 | 2 | 419 |
| Ausland | 118 | 93 | 0 | 1 | 27 | 0 | 0 | 24 |
| **Summe** | **39,711** | 1,777 | 634 | 99 | 38,176 | 96 | 357 | 7,617 |

Dazu 127 Haltestellen mit Schienenersatzverkehr. Orte: 6 Städte (city), 223 Städte/Märkte (town), 5,826 Dörfer,
366 Stadtteile, 13,620 Weiler, 947 Viertel, 62 Quartiere.

Abgleich mit Scotty (10 LocMatch-Anfragen, Oktober 2026): 99.3 % der von Scotty vorgeschlagenen österreichischen
Haltestellen mit Fahrplan sind offline vorhanden. Fehlend: Rufbus-Sammelpunkte (nur in den MVO-„GTFS Flex“-Daten bzw.
live), Adressen und POIs (nur live über ÖBB LocMatch).

## 3. Lizenzstatus – **Freigabe vor dem Release nötig**

Die Basisliste stammt aus „ÖV-Güteklassen 2025“, dem einzigen Weg, die Haltestellenliste der Mobilitätsverbünde ohne
Konto herunterzuladen. mobilitydata.gv.at nennt für diesen Datensatz **keine Lizenz**. Ohne ausdrückliche Lizenz ist die
Weitergabe in der App nicht abgesichert. Zwei Wege, das vor dem Release zu lösen:

1. **Bevorzugt:** kostenlos bei data.mobilitaetsverbuende.at registrieren, die *Datenlizenz Mobilitätsverbünde
   Österreich v1.1* akzeptieren, Datensatz 46 „Haltestellen (CSV)“ laden und mit
   `python3 -I scripts/build_places.py --mvo <haltestellen.csv>` bauen (der CSV-Leser ist mit einer synthetischen
   Datei getestet; die echte Datei liefert die API nur nach Login).
2. **Alternative:** schriftliche Erlaubnis von AustriaTech (data.stewards@austriatech.at), die Haltestellenpunkte aus
   ÖV-Güteklassen zu bündeln.

Bedingungen der MVO-Lizenz v1.1 (Lizenztext: `Lizenzvereinbarung_DBP_v1.1.pdf` auf data.mobilitaetsverbuende.at):

- Kopieren, Weitergeben und Verändern ist erlaubt.
- **Namensnennung** mit Hinweis auf die Lizenz und darauf, **dass die Daten verändert wurden** (§5 enthält den Text).
- **Kein Fahrkartenvertrieb** auf Basis der Daten (Abschnitt 2(a)(5)). Die App verkauft keine Tickets; ein späterer
  „Im ÖBB-Shop kaufen“-Absprung (OEBB_LIVE §B3.7) übergibt nur an den ÖBB-Shop – vor Einführung prüfen.
- **Aktualität:** Daten dürfen in öffentlich zugänglichen Auskunftssystemen nicht über ihren Gültigkeitszeitraum hinaus
  verwendet werden; bei kommerzieller Nutzung beträgt die Vertragsstrafe EUR 20,000 je Verstoß (Abschnitt 7).
  → **jedes Jahr zum Fahrplanwechsel im Dezember neu bauen** (§4).

`localities.bin` ist eine abgeleitete Datenbank aus OpenStreetMap unter **ODbL 1.0**: Namensnennung „© OpenStreetMap-
Mitwirkende“ und Angebot der Datenbank unter ODbL (erfüllt durch dieses öffentliche Repository: Datei + Pipeline).
`places.bin` enthält bewusst **keine** OSM-Daten (`--osm-policy separate`, Standard), damit es nicht unter ODbL fällt;
`--osm-policy merge` würde OSM-Namensvarianten und Verkehrsmittel einmischen und `places.bin` als Ganzes zu ODbL machen.

ÖBB-HAFAS-extIds von Bushaltestellen werden **nicht** gebündelt (Scotty-Daten sind keine offenen Daten); die App lernt
sie zur Laufzeit beim Zusammenführen mit Live-Ergebnissen.

## 4. Neu bauen (jährlich zum Fahrplanwechsel, oder bei neuen Quelldaten)

```sh
sh scripts/fetch_places_sources.sh build/places-dl            # ≈ 1.3 GB; ÖBB-GTFS manuell (Nutzungsbedingungen)
python3 -I scripts/build_places.py --dl build/places-dl       # → App/Resources/places.bin, localities.bin (~45–70 s)
cp build/places/places_report.json data/places_report.json
SCOTTY_FIXTURES=<LocMatch-Fixtures> OEBB_FIXTURES=<OEBB_LIVE-Fixtures> \
  python3 -I scripts/places_reference.py golden App/Resources/places.bin App/Resources/localities.bin \
  Packages/KlimaCore/Tests/KlimaCoreTests/Fixtures/places      # Erwartungswerte der Suche neu erzeugen, Diff prüfen
swift test --package-path Packages/KlimaCore --no-parallel
```

- Nur die Python-Standardbibliothek; Ausnahme: `scripts/extract_osm_places.py` braucht pyosmium (die gleichwertige
  Overpass-Abfrage steht im Docstring).
- Reproduzierbar: gleiche Eingaben → bitgleiche `.bin`-Dateien (zweimal gebaut, SHA-256 identisch; `places.bin`
  `ba824851cc1a…`, `localities.bin` `e9614337c81f…`). Eingabe-Prüfsummen stehen in `data/places_report.json`.
- `stations.json` und `data/stations_meta.json` sind Eingaben (alte IDs → neue Einträge), werden aber nie überschrieben.
- Ein Round-Trip-Selbsttest (`read_bin`) läuft am Ende jedes Builds.

## 5. Text für die App („Datenquellen“)

Den Eintrag „Haltestellen“ in `App/Sources/Core/Copy.swift` (`dataSources`) ersetzen durch diese zwei Einträge:

- **„Haltestellen“** – „Mobilitätsverbünde Österreich OG, Haltestellenverzeichnis (Stand 10/2025, über ÖV-Güteklassen
  2025 von ÖROK/BMIMI/AustriaTech), verändert (zusammengeführt, gekürzt, Koordinaten umgerechnet) · ÖBB-Personenverkehr AG
  Soll-Fahrplan GTFS 2026 (CC BY 4.0) · ÖBB-Infrastruktur AG Verkehrsstationen (CC BY 3.0 AT) · Stadt Wien –
  data.wien.gv.at (CC BY 4.0) · Land Steiermark – data.steiermark.gv.at (CC BY 4.0) · Statistik Austria – Gemeindegrenzen
  2026 (CC BY 4.0)“
- **„Orte“** – „© OpenStreetMap-Mitwirkende, ODbL 1.0 (openstreetmap.org/copyright)“

Sobald die MVO-Lizenz (§3, Weg 1) genutzt wird, lautet der erste Teil: „Datenquelle: Mobilitätsverbünde Österreich OG,
Datenlizenz Mobilitätsverbünde Österreich v1.1 (data.mobilitaetsverbuende.at); verändert (zusammengeführt, gekürzt,
Koordinaten umgerechnet)“. Live-Vorschläge (Adressen, POIs) kommen von der ÖBB-Fahrplanauskunft (OEBB_LIVE §2).

Die README-Zeile „Datenquellen“ ist entsprechend angepasst.
