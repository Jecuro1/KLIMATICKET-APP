# Datenquellen und Lizenzen der gebündelten Daten

Status: 2026-10-09 (Haltestellen-Daten Format v2, docs/ENRICH_SPEC.md). Gilt für alle Dateien in `App/Resources/` und
`data/`. Die Texte, die die App unter Einstellungen › Über › Datenquellen zeigen muss, stehen in
[§5](#5-text-für-die-app-datenquellen).

## 1. Überblick

| Datei | Inhalt | Erzeugt von | Lizenz der Datei |
|---|---|---|---|
| `App/Resources/places.bin` (KBPL v2, ≈ 1.19 MB) | **amtliche Ebene:** alle 39,711 Haltestellen Österreichs (alle Verkehrsverbünde) + 118 Grenz-/Auslandsbahnhöfe; Linienkatalog (2,789 Linien), Linien je Haltestelle mit Richtungen und nächsten Halten, Zuggattungen der Bahnhöfe, amtliche Merkmale (Ortstyp, Region, KlimaTicket, Umstieg zur Bahn), Nachschlagetabellen (Regionen, Skigebiete *als eigene Zusammenstellung*, Betreiber, Bezirke, KlimaTicket-Produkte) | `scripts/build_places.py --stage v2` | Mobilitätsverbünde-Daten (siehe §3 – **offen**) + CC BY 4.0 / CC BY 3.0 AT + eigene Arbeit; **keine OSM-Daten** |
| `App/Resources/stops_osm.bin` (KBPL v2, ≈ 0.22 MB, **neu**) | **OSM-Ebene:** Linien, die nur OSM kennt (Skibusse, Ortsbusse, Saisonlinien), Ergänzungen zu amtlichen Linien (Betreiber, Name, Endhalte, Saison-/Ski-Flags, Umnummerierungen), Haltestelle↔Linie-Paare, die der amtlichen Ebene fehlen, OSM-Merkmale (Skigebiet, Lift/Talstation, Barrierefreiheit, P+R, B+R, Flughafen, Hütte, Gletscher, Nationalpark, Landschaften), Lift-Tabelle, Skigebiete nur aus OSM, Flächen/Lift-/Haltestellenzahlen der Skigebiete | `scripts/build_places.py --stage v2` | **ODbL 1.0** (abgeleitete Datenbank aus OpenStreetMap) |
| `App/Resources/localities.bin` (KBPL v2, ≈ 0.64 MB) | 21,050 Orte (Städte, Gemeinden, Dörfer, Ortsteile) mit Hauptbahnhof/-haltestelle | `scripts/build_places.py` | **ODbL 1.0** |
| `App/Resources/stations.json` | die bisherige Stationsliste (1,487 Einträge). **Eingefroren**: bestehende Fahrten referenzieren diese IDs; jede ID ist in `places.bin` als `legacy`-ID hinterlegt | früherer Recherche-Lauf | ÖBB GTFS (CC BY 4.0), ÖBB-Infrastruktur (CC BY 3.0 AT), OSM (ODbL), Stadt Wien (CC BY 4.0) |
| `App/Resources/relations.bin`, `relations-points.json` | ÖBB-Relationspreise | `scripts/build_relations.py` | siehe dort |
| `App/Resources/tariffs.json`, `data/*.json` | Ticketpreise, Tarifmodell | `scripts/build_tariffs.py` | Fakten von klimaticket.at / Verbünden |
| `data/places_report.json` | Prüfsummen der Eingaben, Zählungen je Bundesland/Verkehrsmittel, Abschnittsgrößen/CRCs, Abdeckung, Ergebnis der Abnahmeprüfung | `scripts/build_places.py` | – |
| `data/places_spot_checks.json` | 51 Stichproben der Merkmale (Warth, Lech, St. Anton, Obergurgl, Innsbruck …) | eigene Arbeit | – |

Format: KBPL v2 = Abschnitts-Container mit Verzeichnis, Rohes DEFLATE je Abschnitt und CRC-32 (docs/ENRICH_SPEC.md §1).
Referenzleser: `scripts/check_places_v2.py` (inkl. der Laufzeit-Zusammenführung M1–M8), `read_bin()` in
`scripts/build_places.py` für die Datensätze; Swift: `Packages/KlimaCore/Sources/KlimaCore/Places/` (`PlaceDataset`,
`Format/KBPLContainer.swift`). Die App führt die Ebenen zur Laufzeit zusammen; fehlt `stops_osm.bin` oder gehört sie zu
einem anderen Build (`BASE`-Prüfsumme), läuft die App mit der amtlichen Ebene allein.

## 2. Quellen

### 2.1 Haltestellen (`places.bin` Datensätze, `localities.bin`)

| Quelle | Lizenz | Beitrag |
|---|---|---|
| **ÖV-Güteklassen 2025_revised** (ÖROK / BMIMI / AustriaTech; enthält den Haltestellen-WFS der Mobilitätsverbünde Österreich, Stand 10/2025) – `01_Haltestellenkategorien_20251022` | **keine explizite Lizenz** („Kein(e) Lizenz und kein Vertrag“ auf mobilitydata.gv.at) → §3 | Basisliste: 39,541 Haltestellen mit IFOPT-ID (`St_Nummer` 470118700 → `at:47:1187`), Abfahrten am Mi 22.10.2025, Linien, Verkehrsmittel-Klasse |
| data.mobilitaetsverbuende.at Datensatz 46 „Haltestellen (CSV)“ (optional, `--mvo`) | Datenlizenz Mobilitätsverbünde Österreich v1.1 | ersetzt/ergänzt die Basisliste (Login nötig) |
| ÖBB-Personenverkehr AG, Soll-Fahrplan GTFS 2026 (data.oebb.at) | CC BY 4.0 | 1,138 Bahnhöfe: Bahn-Verkehrsmittel, Abfahrten; 92 Auslandsbahnhöfe ergänzt, 11 Tarifpunkte verworfen |
| Wiener Linien GTFS (Stadt Wien – data.wien.gv.at) | CC BY 4.0 | 1,781 Haltestellen zugeordnet (Kurznamen als Alias), 15 ergänzt |
| Land Steiermark – Haltestellen des Verkehrsverbundes Steiermark (data.steiermark.gv.at) | CC BY 4.0 | 7,108 zugeordnet, 61 bediente Haltestellen ergänzt, 1,047 unbediente übersprungen |
| Statistik Austria – Gemeindegrenzen 01.01.2026 (data.statistik.gv.at) | CC BY 4.0 | Gemeinde, Bezirk und Bundesland je Haltestelle (Punkt-in-Polygon; 39,591 in Österreich, 118 im Ausland) |
| ÖBB-Infrastruktur AG – Verzeichnis der Verkehrsstationen (über `data/stations_meta.json`) | CC BY 3.0 AT | EVA-Nummern (= ÖBB-HAFAS-extId) für 1,015 Bahnhöfe |
| OpenStreetMap Austria (Geofabrik-Extrakt) | ODbL 1.0 | **nur** `localities.bin` (Orte), `stops_osm.bin` und die Lückenanalyse (`osm_only_clusters.tsv`, nicht ausgeliefert) |

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

### 2.2 Linien (`scripts/build_lines.py`)

| Quelle | Lizenz | Ebene | Beitrag |
|---|---|---|---|
| ÖV-Güteklassen 2025 – Feld „Linien“ an beiden Stichtagen (22.10.2025 Werktag, 29.10.2025 Herbstferien) | keine explizite Lizenz → §3 | `places.bin` | Liniennummern je Haltestelle (nur am Werktag = „Schultage?“, wird nicht angezeigt) |
| ÖBB-PV Soll-Fahrplan GTFS 2026 | CC BY 4.0 | `places.bin` | Bahnlinien (REX, R, S, CJX …) mit Haltfolgen, Richtungen, Betreiber; Zuggattungen je Bahnhof (RJX, RJ, ICE, EC, IC, NJ, EN …) |
| Wiener Linien GTFS | CC BY 4.0 | `places.bin` | U-Bahn, Straßenbahn, Bus, Nachtbus mit Haltfolgen und Richtungen |
| Land Steiermark – Linienverkehr des Verkehrsverbundes Steiermark | CC BY 4.0 | `places.bin` | öffentliche Liniennummer, Art, Kategorie Schüler/Saison je Haltestelle |
| Verbund-GTFS von data.mobilitaetsverbuende.at (optional, `build/places-dl/mvo/*.zip`) | MVO v1.1 | `places.bin` | ersetzt ÖV-GK für Linien (ganzes Fahrplanjahr inkl. Winter/Ski) |
| OpenStreetMap-Routenrelationen (`extract_osm_routes.py`) | ODbL 1.0 | `stops_osm.bin` | Linienverläufe, Betreiber, Endhalte, Ski-/Saison-/Nacht-Flags, Linien, die nur OSM kennt, Umnummerierungen 12/2025 |

Linienidentität (E1): eine Linie ist eine zusammenhängende Komponente ihres Haltestellen-Graphen. „R1“ in Oberösterreich
und „R1“ im VOR-Gebiet sind zwei Linien mit eigenen Endhalten (Wien Floridsdorf zeigt nicht mehr „Kleinreifling –
Linz“). Endhalte werden, wo möglich, als Haltestelle der Linie gespeichert (E2: Tippfehler in OSM wie „Schlosswopf“
erscheinen nicht). Das Netz einer Linie ist der Verbund der Mehrheit ihrer Haltestellen (E3: 110 Reutte – Warth = VVT).

### 2.3 Merkmale (`scripts/build_tags.py`)

| Quelle | Lizenz | Ebene | Beitrag |
|---|---|---|---|
| Haltestellen-Datensatz (Verkehrsmittel, Namen, ÖV-GK-Linien) | wie §2.1 | `places.bin` | Ortstyp (Bahnhof, Hauptbahnhof, Fernverkehr, Nachtzug, S-/U-Bahn, Straßenbahn, Busbahnhof, Schiff, Seilbahn, Krankenhaus), Nachtbus, Umstieg zur Bahn, KlimaTicket-Hinweis (nur mit amtlichen Belegen bestimmt) |
| Statistik Austria Gemeinden | CC BY 4.0 | `places.bin` | Gemeinde, Bezirk, Wiener Gemeindebezirk; Tourismusregionen über kuratierte Gemeindelisten |
| Eigene Zusammenstellung (`scripts/places_curated.py`) | eigene Arbeit | `places.bin` | 146 Skigebiete + 7 Sektoren (Namen, Orte, Glyphe, Monogramm, eigene Gipfelfarbe `SummitHue`), 9 Skiverbünde (`verified: false`, werden in der App bis zur Prüfung nicht gezeigt – E5), Tourismusregionen, KlimaTicket-Regeln, Betreiber-Anzeigenamen (E4: „Österreichische Postbus AG“ → „Postbus“) |
| OpenStreetMap (`extract_osm_tags.py`: winter_sports-Flächen, Aerialways, Pisten, Routen, POIs, wheelchair, Regionen/Viertel, Nationalparks) | ODbL 1.0 | `stops_osm.bin` | Skigebiet je Haltestelle (mit Entfernung), Lift/Talstation, 56 Skigebiete nur aus OSM, Ski-/Wanderbus, Rufbus, Saison- und Flughafenlinien laut OSM, P+R, B+R, Flughafen, Universität, Einkaufszentrum, Hütte, Gletscher, Nationalpark, Landschaften (Viertel), Barrierefreiheit |

Jeder Merkmalseintrag trägt in `build/tags/tags.json` die Herkunft (`"osm": true|false`); nur Einträge mit
`osm: false` gelangen in `places.bin`. Die Abnahmeprüfung (AT-D7) bricht den Build ab, wenn ein OSM-Merkmal,
ein OSM-Betreibername oder eine OSM-Quelle in `places.bin` auftaucht.

## 3. Lizenzstatus – **Freigabe vor dem Release nötig**

Die Basisliste und die Liniennummern je Haltestelle stammen aus „ÖV-Güteklassen 2025“, dem einzigen Weg, die Daten der
Mobilitätsverbünde ohne Konto herunterzuladen. mobilitydata.gv.at nennt für diesen Datensatz **keine Lizenz**. Ohne
ausdrückliche Lizenz ist die Weitergabe in der App nicht abgesichert. Zwei Wege, das vor dem Release zu lösen:

1. **Bevorzugt:** kostenlos bei data.mobilitaetsverbuende.at registrieren, die *Datenlizenz Mobilitätsverbünde
   Österreich v1.1* akzeptieren, Datensatz 46 „Haltestellen (CSV)“ laden und mit `--mvo <haltestellen.csv>` bauen
   (der CSV-Leser ist mit einer synthetischen Datei getestet; die echte Datei liefert die API nur nach Login); die
   Verbund-GTFS (52–58, 69) nach `build/places-dl/mvo/<label>.zip` legen – `build_places_all.sh` übergibt sie an
   `build_lines.py --gtfs`.
2. **Alternative:** schriftliche Erlaubnis von AustriaTech (data.stewards@austriatech.at), die Haltestellenpunkte und
   Linienlisten aus ÖV-Güteklassen zu bündeln.

Bedingungen der MVO-Lizenz v1.1 (Lizenztext: `Lizenzvereinbarung_DBP_v1.1.pdf` auf data.mobilitaetsverbuende.at):

- Kopieren, Weitergeben und Verändern ist erlaubt; **keine Unterlizenzierung** (darum nie mit ODbL-Daten in einer Datei).
- **Namensnennung** mit Hinweis auf die Lizenz und darauf, **dass die Daten verändert wurden** (§5 enthält den Text).
- **Kein Fahrkartenvertrieb** auf Basis der Daten (Abschnitt 2(a)(5)). Die App verkauft keine Tickets; ein späterer
  „Im ÖBB-Shop kaufen“-Absprung (OEBB_LIVE §B3.7) übergibt nur an den ÖBB-Shop – vor Einführung prüfen.
- **Aktualität:** Daten dürfen in öffentlich zugänglichen Auskunftssystemen nicht über ihren Gültigkeitszeitraum hinaus
  verwendet werden; bei kommerzieller Nutzung beträgt die Vertragsstrafe EUR 20,000 je Verstoß (Abschnitt 7).
  → **jedes Jahr zum Fahrplanwechsel im Dezember neu bauen** (§4). `places.bin` META `build.gtfsValidity` /
  `build.validUntil` tragen den Gültigkeitszeitraum; die App blendet Linien danach aus („Liniendaten veraltet“).

**ODbL-Dateien:** `stops_osm.bin` und `localities.bin` sind abgeleitete Datenbanken aus OpenStreetMap unter
**ODbL 1.0**: Namensnennung „© OpenStreetMap-Mitwirkende“ und Angebot der Datenbank unter ODbL (erfüllt durch dieses
öffentliche Repository: Dateien + Pipeline `scripts/build_places_all.sh`). `places.bin` enthält bewusst **keine**
OSM-Daten (auch keine Flächen, Liftzahlen oder Haltestellenzahlen der Skigebiete – die stehen in `stops_osm.bin`
META `skiAreaStats`), damit es nicht unter ODbL fällt und mit MVO-Daten vereinbar bleibt (`--osm-policy separate`).

**Zeichen, Logos, Wappen:** Die Daten enthalten nur Namen als Text (Skigebiete, Regionen, Verbünde, Betreiber) und die
eigene Gestaltung (Glyphe, Monogramm, `SummitHue`-Name; die Farbvorschläge in `places_curated.py` werden nie
ausgeliefert, AT-D9). Originallogos von Skigebieten und Regionen kommen ausschließlich über das Logo-Paket von
Cloudflare, Landeswappen (ohne Niederösterreich) über das App-Bundle – beides geregelt in `docs/LOGO_SPEC.md`, nichts
davon gehört in die Places-Daten oder in dieses Skript-Verzeichnis.

ÖBB-HAFAS-extIds von Bushaltestellen werden **nicht** gebündelt (Scotty-Daten sind keine offenen Daten); die App lernt
sie zur Laufzeit beim Zusammenführen mit Live-Ergebnissen.

## 4. Neu bauen (jährlich zum Fahrplanwechsel, oder bei neuen Quelldaten)

```sh
sh scripts/fetch_places_sources.sh build/places-dl     # ≈ 1.4 GB; ÖBB-GTFS manuell (Nutzungsbedingungen)
python3 -m venv build/venv && build/venv/bin/pip install -r scripts/requirements-enrich.txt
PYTHON=build/venv/bin/python sh scripts/build_places_all.sh --extract --twice
#   1 OSM-Extrakte (Orte, Routen, Merkmale; ≈ 10 min)   2 Haltestellenliste (--stage base, ≈ 45 s)
#   3 Linien zweimal (amtlich ohne OSM, voll mit OSM)   4 Merkmale   5 v2-Dateien + Selbsttest   6 Goldens + swift test
SCOTTY_FIXTURES=<LocMatch-Fixtures> OEBB_FIXTURES=<OEBB_LIVE-Fixtures> PYTHON=… sh scripts/build_places_all.sh
python3 -I scripts/check_places_v2.py check            # Abnahmeprüfung AT-D1…D9 der ausgelieferten Dateien
python3 -I scripts/check_places_v2.py show at:48:344   # was Place.lines / Place.tags für eine Haltestelle enthalten
```

- Nur die Python-Standardbibliothek; Ausnahmen (gepinnt in `scripts/requirements-enrich.txt`): pyosmium für die drei
  OSM-Extrakte, shapely + numpy für `build_tags.py`.
- Reproduzierbar: gleiche Eingaben → bitgleiche `.bin`-Dateien (`--twice` baut die v2-Dateien ein zweites Mal und
  vergleicht die SHA-256; `SOURCE_DATE_EPOCH` legt `build.date` fest). Eingabe-Prüfsummen, zlib-Version,
  Abschnittsgrößen und CRCs stehen in `data/places_report.json`.
- `stations.json` und `data/stations_meta.json` sind Eingaben (alte IDs → neue Einträge), werden aber nie überschrieben.
- Der v2-Schritt schreibt erst nach bestandenem Selbsttest (`scripts/check_places_v2.py`: Dekodierung, CRC, BASE,
  Budget ≤ 5 MB, Abdeckung, Warth-Referenzfall, 51 Stichproben, Endhalte, Lizenz-Trennung, Umnummerierungen,
  Gestaltungsdaten) nach `App/Resources`; die v1-Dateien bleiben als Rückfall in `build/places/v1/`
  (`--stage v1` schreibt sie direkt nach `App/Resources`).
- Die Erwartungswerte der Suche (`Fixtures/places/golden_places.json`) bleiben mit v2 unverändert, bis auf die
  Prüfsummen der Dateien.

## 5. Text für die App („Datenquellen“)

`App/Sources/Core/Copy+Places.swift` (ENRICH_SPEC §1.10.2), Einstellungen › Über › Datenquellen:

- **„Haltestellen“** – „Mobilitätsverbünde Österreich OG, Haltestellenverzeichnis (Stand 10/2025, über ÖV-Güteklassen
  2025 von ÖROK/BMIMI/AustriaTech), verändert (zusammengeführt, gekürzt, Koordinaten umgerechnet) · ÖBB-Personenverkehr AG
  Soll-Fahrplan GTFS 2026 (CC BY 4.0) · ÖBB-Infrastruktur AG Verkehrsstationen (CC BY 3.0 AT) · Stadt Wien –
  data.wien.gv.at (CC BY 4.0) · Land Steiermark – data.steiermark.gv.at (CC BY 4.0) · Statistik Austria – Gemeindegrenzen
  2026 (CC BY 4.0)“
- **„Linien“** – „ÖBB-Personenverkehr AG Soll-Fahrplan GTFS 2026 (CC BY 4.0) · Stadt Wien – data.wien.gv.at, Wiener
  Linien Fahrplandaten (CC BY 4.0) · Land Steiermark – data.steiermark.gv.at, Haltestellen und Linienverkehr des
  Verkehrsverbundes Steiermark (CC BY 4.0) · Linien je Haltestelle: ÖV-Güteklassen 2025 (ÖROK/BMIMI/AustriaTech; Daten
  der Mobilitätsverbünde Österreich OG), verändert (zusammengeführt).“
- **„Linienverläufe, Skigebiete, Lifte, Barrierefreiheit, Orte“** – „© OpenStreetMap-Mitwirkende, ODbL 1.0
  (openstreetmap.org/copyright)“
- **„Gemeinden und Bezirke“** – „Statistik Austria, Gemeinden 01.01.2026 (CC BY 4.0)“
- **„Zeichen und Namen“** – Text nach `docs/LOGO_SPEC.md` §4.4/§5 (Originallogos © der jeweiligen Inhaber, nur zur
  Ortsangabe; Landeswappen als amtliche Werke nur zur geografischen Zuordnung; KlimaBilanz ist kein Angebot der Länder,
  Skigebiete oder Tourismusverbände). Ohne Logo-Paket gilt der Text aus ENRICH_SPEC §1.10.2 („keine offiziellen Logos“).

Sobald die MVO-Lizenz (§3, Weg 1) genutzt wird, lautet der erste Teil von „Haltestellen“ und der letzte Teil von
„Linien“: „Datenquelle: Mobilitätsverbünde Österreich OG, Datenlizenz Mobilitätsverbünde Österreich v1.1
(data.mobilitaetsverbuende.at); verändert (zusammengeführt, gekürzt, Koordinaten umgerechnet)“. Live-Vorschläge
(Adressen, POIs) und Live-Abfahrten kommen von der ÖBB-Fahrplanauskunft (OEBB_LIVE §2).

Die README-Zeile „Datenquellen“ ist entsprechend angepasst.
