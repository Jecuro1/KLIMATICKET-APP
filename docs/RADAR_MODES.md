# Radar für alle Verkehrsmittel (radarmodes)

Stand 2026-11-13. Teil der zweiten Radar-Welle (radar2). Code: `App/Sources/Features/Radar/Modes/`, `App/Sources/Features/Radar/Radar2/`,
`Packages/KlimaCore/Sources/KlimaCore/Live/Radar/Modes/`, die Spuren-Teile in `RadarScheduler.swift` und `RadarTiles.swift` (jeweils `// MARK: radarmodes`).
Regeln für Live-Daten: `docs/OEBB_LIVE.md` §2, §R11 (hier §R11.4).

## 1. Was es kann

- **Bus, Bim und U-Bahn sind auf dem Radar gleichwertig.** In einer Stadt zeigt die Karte jedes Fahrzeug, das die ÖBB-Auskunft kennt, im selben Budget
  von 24 Anfragen je Minute. Jedes Verkehrsmittel hat sein eigenes Schild (die Wegzeichen der App), eine Legende erklärt Schilder, Ringe und Zeichen.
- **Die Statuskarte zählt je Verkehrsmittel** („Zug 21 · S-Bahn 28 · Bus 180 · Bim 92 · U-Bahn 12“), sobald Bus, Bim oder U-Bahn an sind. Die Zeile
  ergibt immer die Zahl der Pille: Fahrzeuge keiner der fünf Arten (Schienenersatzverkehr, Fernbus, ohne Klasse) stehen als „Andere“ da.
- **Jedes Teilbild sagt, dass es eines ist:** zu weit herausgezoomt, noch nicht alle Gebiete geladen, mehr Fahrzeuge als eine Abfrage liefert, mehr
  Gebiete als das Budget erlaubt, mobile Daten, geschätzte Datenmenge, eine leere Karte („Die Auskunft kennt in diesem Ausschnitt gerade keine Fahrzeuge.“).
- **Der S-Bahn-Chip tut, was er sagt.** Bis radar2 fragte „Züge“ nach `.rail` (4157), und darin steckt die S-Bahn (32): S-Bahnen waren auf der
  Karte, ob der S-Bahn-Chip an war oder nicht. Jetzt ist „Züge“ 4125 und „S-Bahn“ 32; voreingestellt sind beide an, die Anfrage ist dieselbe wie bisher.
- **Filter & Darstellung** (§6): Schnellwahl („Fernverkehr“, „Öffis in der Stadt“ …), Zugart, Linie oder Zugnummer, Betreiber, Verspätung, Echtzeit,
  Region; Beschriftung (Linie, Linie und Ziel, Nur Punkte), Größe, Gruppen, Richtungspfeil, Takt der Stadt-Spur. Ein aktiver Filter steht immer
  sichtbar auf der Karte. Die Suche findet „13A“, „U6“ und „D“.
- **Die Wahl bleibt** je Gerät (`radar.modes.v1`, `radar.filter.v1`, `radar.display.v1`).

## 2. Verkehrsmittel und ihre Bedeutung

| Chip | Produktklassen | Bits | Ebene der Abfrage |
|---|---|---|---|
| Züge | Fernverkehr (RJX, RJ, ICE), IC/EC, Nachtzug, Regionalzug (REX, R, CJX), WESTbahn | 1, 4, 8, 16, 4096 = 4125 | breit |
| S-Bahn | S-Bahn | 32 | breit |
| Bus | Bus, Postbus, O-Bus | 64 | Stadt |
| Bim | Straßenbahn | 512 | Stadt |
| U-Bahn | U-Bahn | 256 | Stadt |

- Voreinstellung {Züge, S-Bahn} = 4157, dieselbe Anfrage wie vor radar2. Mindestens ein Chip bleibt an.
- **Art eines Fahrzeugs = sein Klassen-Bit**, nie `Line.mode`: Der Codec ordnet Schienenersatzverkehr (2) und Fernbusse (1024) `.bus` zu; auf dem
  Radar zählen sie nicht als „Bus“ (`RadarMode.of(productClass:)`), sondern als „Andere“.
- Die **Zeitreise** gibt es nur, solange nur Züge und S-Bahn an sind (`RadarModeSelection.carriesOnlyTrains` speist `RadarFeatureGate.railOnly`). Mit
  Bus, Bim oder U-Bahn steht statt des Uhr-Chips „Zeitreise gibt es nur mit Zügen und S-Bahn.“
- Gespeichert als Komma-Liste unter `radar.modes.v1` („rail,suburban,bus“), wie `map.layers`; unbekannte Wörter fallen weg, eine leere Liste ist die
  Voreinstellung. In der iPhone-Sicherung wie jede App-Einstellung; nicht im Export der App. Screenshot-Starts setzen sie zurück.
- Weitere Arten (Schienenersatzverkehr, Schiff, Seilbahn und Rufbus) bekommen einen Chip nur, wenn eine Messung Positionen zeigt (§8). Gebaut ist
  keiner davon (§11).

## 3. Zwei Ebenen der Abfrage

Ein Scheduler, zwei Spuren (`RadarLane`), ein Budget. Die Spur ist Teil des Kachel-Schlüssels (`RadarTileKey.lane`): Zustände, Teilungen, laufende
Anfragen und Antworten gelten je Kachel und Spur, das Budget bleibt eines.

| | breite Spur | Stadt-Spur |
|---|---|---|
| fragt nach | Züge, S-Bahn (bei eingeschalteter Pünktlichkeit immer alle Züge und S-Bahnen, 4157) | Bus, Bim, U-Bahn (was davon an ist) |
| Gebiet | die Karte, bei Pünktlichkeit ganz Österreich | die Karte, nur bis 0,6° Höhe (etwa 67 km) |
| Startstufe | `level(forLatitudeSpan:)` wie bisher | eine Stufe feiner (`cityLevelOffset` 1): Wien bei 0,12° → Stufe 5, 9,7 × 9 km |
| Teilung bei 1000 | bis Stufe 6 (4,9 × 4,6 km) | bis Stufe 8 (1,2 × 1,1 km) |
| Kacheln je Ansicht | wie bisher | höchstens 16 (`cityMaxTiles`); eine Teilung, die mehr bräuchte, unterbleibt („zu dicht“, gesagt) |
| Takt | 20 s dicht oder nah, 45 s ruhig (wie bisher) | „Automatisch“: 20 s im WLAN, 60 s über mobile Daten oder im Datensparmodus |
| läuft, wenn | Live-Schleife läuft und die Spur etwas abfragt | Live-Schleife läuft, Zug-Ebene an, ein Stadt-Modus an, Karte ≤ 0,6° |

Warum zwei Spuren: (a) eine gemischte Antwort am Limit von 1000 drängte die Züge zugunsten der Busse hinaus (das Limit zählt die ganze Liste);
(b) die Stadt-Spur kann feiner anfangen und tiefer teilen, ohne die zwei Kacheln der Österreich-Ansicht zu ändern; (c) die Pünktlichkeit behält ihre
Österreich-Kacheln mit Schiene, während Busse der Karte folgen; (d) ein Wechsel bei Bus, Bim oder U-Bahn setzt nur die Stadt-Kacheln zurück.

Buchführung (README radar2 F14, F15):
- **Eine Generation je Spur.** Eine Antwort, die vor einem Wechsel ihrer Spur gefragt wurde, fällt weg; eine Antwort der anderen Spur wird
  verbucht und gibt ihre Kachel sofort frei (`RadarLaneSchedulerTests` (l)).
- **Was beim Wechsel geht:** Fahrzeuge, deren Klasse keine der beiden Spuren mehr anfragt (Chips ∪ 4157 bei Pünktlichkeit). Die Pins filtern weiter
  nach den Chips. So bleiben die S-Bahnen der Pünktlichkeit, wenn man den S-Bahn-Chip ausschaltet.
- **Status:** Die bisherigen Felder von `RadarStatus` gelten nur für die breite Spur (Vollständigkeit der Pünktlichkeit, `holdsAllOfAustria` der
  Zeitreise und `RadarStatusText.notes` lesen sie unverändert); die Stadt-Spur hat `status.city`. Gemeinsam nur, wo die Oberfläche eine Zahl zeigt:
  Alter der Pille = ältere Antwort beider Spuren, „Radar pausiert“ = jede Spur mit Kacheln pausiert. Eine Spur ohne Maske hat keine Ansicht: Nur
  Bus an ergibt nie „Außerhalb des Radar-Bereichs“.
- Über 0,6° verlassen Bus, Bim und U-Bahn die Karte sofort, die Chips tragen ein Lupen-Zeichen, VoiceOver sagt „an, erscheint beim Heranzoomen“,
  die Statuskarte sagt „Bus, Bim und U-Bahn erscheinen, wenn du näher heranzoomst.“

## 4. Budget, Datenmenge

Ein Budget für beide Spuren: 24 je Minute, höchstens 4 in 10 s, 1 s Abstand, 3 gleichzeitig (`RadarSchedulerConfig.standard`), über Ansichten hinweg
`RadarBudgetLedger`. Mindestens 16 der 40 Anfragen je Minute der App bleiben für Fahrplan, Abfahrten, „Live verfolgen“ (Test (g)). Wollen die
sichtbaren Kacheln mehr, wird **jede** Kachel um denselben Faktor langsamer, auch die der breiten Spur und der Pünktlichkeit: 16 Stadt- und 4 breite
Kacheln zu je 20 s wollen 60 je Minute, erlaubt sind 24, also alle etwa 50 s. Die Statuskarte sagt es einmal für beide Spuren
(„Dieser Ausschnitt · aktualisiert alle ~50 s“; Tests (i)).

Datenmenge (Schätzung, die App sagt „geschätzt“): Die Antworten von `/gate` sind nicht komprimiert (§A2.1). Ein Bus- oder Bim-Eintrag hat etwa
1,7 KB (§R11.1 c: 1 666 493 B für 1000; Messung §8: 1,6 bis 2,2 KB), ein Zug etwa 2 KB. `RadarDataEstimate` rechnet mit den Fahrzeugen der letzten
Antwort jeder sichtbaren Stadt-Kachel und dem gedehnten Takt der Spur; ab 2 MB je Minute steht es in der Statuskarte.

| Lage | Anfragen je Minute | Daten je Minute (etwa) |
|---|---|---|
| Wien, Stadtansicht, WLAN: 6 Stadt-Kacheln zu je 400 Fahrzeugen, 20 s | 18 + breite Spur, im Budget | 12 MB |
| Wien, Stadtansicht, mobile Daten („Automatisch“ → 60 s) | 6 + breite Spur | 4 MB |
| Österreich mit Pünktlichkeit und Bus an (Bus erst ab 0,6°) | 6 (zwei Kacheln, Schiene) | wie ohne Bus |
| Obergrenze: das ganze Budget, jede Antwort voll | 24 | 24 × 1000 × 1,7 KB ≈ 41 MB |

Auch mit „Automatisch“ über mobile Daten gilt die Obergrenze, sobald die sichtbaren Kacheln trotz 60 s noch 24 Anfragen je Minute wollen. Die Messung
eines Datenzählers auf dem iPhone fehlt (§12).

## 5. Marker und Legende

- **Schild = Wegzeichen.** Der Marker ist das Schild der Linie wie im Fahrplan (`LinePlate`, Größe `.s`): Fernverkehr und Nacht Keil, Regio Rechteck,
  S-Bahn und Bim weich gerundet, U-Bahn Quadrat, Bus Kapsel; Füllung und Schrift aus den Wegzeichen-Tokens. Auf dem Radar trägt das Bim-Schild zusätzlich
  das Bim-Symbol (im Fahrplan steht dort nur die Nummer), damit S-Bahn („S45“) und Bim („D“ mit Symbol) nie nur an der Farbe zu unterscheiden sind.
- **Ring außen**, in der Form des Schilds, mit 1 pt Abstand in Weiß (hell) oder Schwarz (dunkel): grün pünktlich (unter 5 Min), orange ab 5 Min,
  rot fällt aus, grau ohne Echtzeit; gestrichelt, solange die Position zwischen zwei Antworten geschätzt ist. Ein oranger Ring auf dem orangen Bus-Schild
  bliebe ohne den Abstand unsichtbar.
- Pfeil in der Farbe des Verkehrsmittels zum nächsten Halt, ein weicher Schatten, Auswahl 1,18-fach mit `Motion.snappy`; Gruppen wie bisher (Zahl im Kreis).
- **Kontrast der Schilder** (Text auf Füllung, WCAG):

| Schild | hell | dunkel |
|---|---|---|
| Fernverkehr #1B2F57 / #DCE6F5 | 13,2 : 1 | 14,4 : 1 |
| Regio #1F66C1 / #7CC4FF | 5,6 : 1 | 9,7 : 1 |
| S-Bahn #0E7C8A / #5FD6E0 | 4,9 : 1 | 10,5 : 1 |
| Bim #6A55D6 / #B3A6FF | 5,4 : 1 | 8,5 : 1 |
| Bus #C4500C / #FFAE73 | 4,7 : 1 | 10,0 : 1 |
| U-Bahn (U1 bis U6, andere) | 4,9 bis 5,9 : 1 | 8,1 bis 10,3 : 1 |

  Hell weiße Schrift, dunkel #0A1626. Der alte Marker (weiß auf `Theme.modeColor`) lag bei Bus und S-Bahn unter 3 : 1.
- **Legende** (ⓘ in der Statuskarte, Blatt mittel/groß): die fünf Schilder mit Worten für VoiceOver („Bus: Kapsel mit Liniennummer, orange“), die Ringe,
  gestrichelt, Pfeil, Gruppe; Fußzeile „Die Positionen berechnet die ÖBB-Auskunft aus Fahrplan und Echtzeit-Meldungen. Es ist kein GPS.“
- **VoiceOver je Marker:** „Bus 13A, nach Hütteldorf, 6 Minuten verspätet, Position berechnet“; „Position geschätzt“ zwischen zwei Antworten; das
  Hauptwort der Art, wo der Titel keines hat („S-Bahn S 45“, „Straßenbahn D“, „U-Bahn-Linie U6“).
- **Zählzeile** in der Statuskarte, sobald ein Stadt-Modus an ist: Ziffern gleich breit und rollend (`Motion.number`), ab AX-Größen zwei Spalten,
  ab AX3 eine Zeile je Art; eine Stadt-Art außerhalb des Zooms fehlt in der Zeile (die Notiz sagt warum, eine „0“ würde behaupten, die Auskunft kenne keine).

## 6. Filter, Schnellwahl, Darstellung

Das Blatt „Filter & Darstellung“ (Knopf links oben, `RadarFilterSheet`) hat zwei Seiten. Jede Änderung wirkt sofort auf der Karte. **Verkehrsmittel
fragen die Auskunft** (beide Spuren, §3); **alle Filter wirken auf dem iPhone** auf die Fahrzeuge, die das Radar hält, mit einem einzigen Prüfer
(`RadarFilter.matches(_:delay:)`) für die Live-Pins und die Pins der Zeitreise (README radar2 F9).

| Option | Was sie tut | Wo | gespeichert |
|---|---|---|---|
| Schnellwahl „Alles“ | alle fünf Verkehrsmittel, kein Filter | Anfrage + Filter | über Modi und Filter |
| „Fernverkehr“ | Züge; Zugart RJX, RJ, IC/EC, NJ/EN, WB | Anfrage + Filter | dto. |
| „Regional & S-Bahn“ | Züge, S-Bahn; Zugart CJX, REX, R, S | Anfrage + Filter | dto. |
| „Öffis in der Stadt“ | S-Bahn, Bus, Bim, U-Bahn, kein Filter | Anfrage | dto. |
| „Nur Verspätete“ | behält Verkehrsmittel und Region, nur ab 5 Min verspätet | Filter | dto. |
| Verkehrsmittel | Schalter je Art mit „gerade 180“ | Anfrage (§3) | `radar.modes.v1` |
| Zugart | RJX, RJ, IC/EC (auch ICE, IR, D), NJ/EN, WB, CJX, REX, R, S, Andere; gilt nur für Züge und S-Bahnen, nie für Bus, Bim, U-Bahn | Filter | `radar.filter.v1` |
| Linie oder Zugnummer | Feld mit Vorschlägen aus den geladenen Fahrzeugen („Im Ausschnitt:“); verglichen ohne Leerzeichen und Groß-/Kleinschreibung („13a“ = Bus 13A, „u 6“ = U6, „S45“ = S 45), immer die ganze Linie | Filter | dto. |
| Betreiber | Schalter mit Anzahl; „Nahreisezug“ und „OEBB Personenverkehr …“ heißen „ÖBB“, „WESTbahn Management GmbH“ „WESTbahn“; nur sichtbar, wenn die geladenen Fahrzeuge mindestens zwei Betreiber haben | Filter | dto. |
| Nur verspätet (ab 5 Min) | ersetzt „Pünktlich“ und „Fällt aus“ | Filter | dto. |
| Nur mit Echtzeit-Daten | blendet Fahrzeuge ohne Echtzeit aus (ein ausfallendes zählt als mit Echtzeit) | Filter | dto. |
| Pünktlich, Fällt aus | Zustände des Rings | Filter | dto. |
| Region | Bundesland nach Haltestellennamen (Schätzung, wie bisher) | Filter | dto. |
| Beschriftung | „Linie“ (Schild), „Linie und Ziel“ (Ziel unter dem Schild, nur bei höchstens 0,3° und höchstens 80 Einzelmarkern), „Nur Punkte“ (Form und Farbe des Schilds, 9 bis 12 pt, ohne Text, mit Ring) | Marker | `radar.display.v1` |
| Größe | Klein / Normal / Groß = Schild 10 / 11 / 13 pt; der Gruppenraster folgt (44 / 56 / 70 pt), so dass sich Gruppen nie überdecken | Marker, Gruppen | dto. |
| Gruppen zusammenfassen | „Aus“ bis 250 Fahrzeuge im Ausschnitt, darüber wieder Gruppen; ohne Gruppen können sich Marker überdecken | Gruppen | dto. |
| Richtungspfeil | Pfeil zum nächsten Halt an oder aus | Marker | dto. |
| Bus, Bim und U-Bahn aktualisieren | „Automatisch“ (WLAN 20 s, mobile Daten 60 s), „Alle 20 s“, „Alle 60 s“ | Takt der Stadt-Spur | dto. |

- **Aktiver Filter immer sichtbar:** Unter den Chips steht „Filter: RJX, RJ · nur verspätet“ mit „Filter aus“; ein Tipp darauf öffnet das Blatt.
  Eine leere Karte mit Filter sagt „Kein Fahrzeug passt zum Filter. Ohne Filter wären es 84.“
- **Speicherung:** `radar.filter.v1` und `radar.display.v1` als JSON mit `version`, tolerant: unbekannte Schlüssel und Werte fallen weg, Unlesbares
  ist die Voreinstellung; die Kategorien des alten Filters (`categories`, v1) werden zur Zugart, wo sie eine sind. Je Gerät, in der iPhone-Sicherung
  wie jede App-Einstellung, nicht im Export; Screenshot-Starts setzen alle drei zurück.
- **Suche:** findet jetzt auch „13A“, „U6“ und „D“ (die ganze Linie zuerst), „RJX 66“ und „66“ wie bisher; Platzhalter „Linie oder Zugnummer, z. B.
  RJX 66 oder 13A“.
- Das Blatt hat am Ende der Seite „Darstellung“ den Platz für die Abschnitte der anderen radar2-Teile (`Radar2SettingsSections`, „Spuren“ von radartrail).

## 7. Zusammenspiel mit Pünktlichkeit, Zeitreise, Cockpit

- **Pünktlichkeit:** Bei eingeschalteter Ebene fragt die breite Spur Österreich mit mindestens 4157 (was die Chips auch sagen), und die Ebene zählt
  alle Züge und S-Bahnen, die das Radar hält (`refreshHeat` mit `.rail`). Die Zahlen hängen nicht mehr an den Chips; „nur Bus an“ lässt die Ebene
  nicht mehr leer (der Hinweis dazu ist weg); Busse blähen ihre Österreich-Kacheln nicht mehr auf (die offene Frage in `docs/RADAR_HEATMAP.md` §1a ist
  damit beantwortet, ohne etwas abzuschalten). Die Stadt-Spur läuft nur mit eingeschalteter Zug-Ebene, für Marker, nie für die Zahlen.
- **Zeitreise:** Regel unverändert (nur Züge und S-Bahn); ihre Momentaufnahmen fragen weiter 4157, ihre Pins filtern nach den Chips: S-Bahn aus
  blendet die S-Bahnen auch dort aus.
- **Cockpit:** für jedes Fahrzeug wie bisher; der Kasten des Cockpits fragt nach der Klasse des Fahrzeugs. Für Bus, Bim und U-Bahn **nicht geprüft**.
- Zustände wie in §R11.3: Die Stadt-Spur ruht mit der Live-Schleife (Zeitreise abseits von „Jetzt“, Cockpit, Hintergrund, Stromsparmodus mit Ausnahme
  von „Jetzt aktualisieren“) und endet offline, ohne Zustimmung, beim Ausschalten oder Notschalter.

## 8. Messung (einmalig, 4 Anfragen, 2026-11-13, Freitag 21:17 Wien)

`RadarModesLiveTests` (`KB_LIVE_TESTS=1 KB_RADAR_MODES=1`), eigener `HafasClient` mit ehrlichem User-Agent, 2,1 s Abstand, keine Wiederholung. Nur
Zahlen; keine Fahrten, Linien, Namen oder Koordinaten gespeichert. **Abends, außerhalb der Spitze:** Die Zahlen sind kleiner als tagsüber.

| # | Abfrage | Ergebnis |
|---|---|---|
| 1 | Stufe-5-Kachel mit Stephansplatz (9,7 × 9 km), Bus/Bim/U-Bahn (832) | 264 Fahrzeuge (Bus 110, Bim 127, U-Bahn 27), nicht abgeschnitten, 470 KB, 2,4 s, 1,78 KB je Eintrag; alle mit ≥ 2 Halten, 84 % mit Echtzeit, alle mit Betreibernamen, keiner mit `admin`, 4 verschiedene Betreiber |
| 2 | Wien-Kasten aus §R11.1 d, nur U-Bahn (256) | 44 U-Bahn-Positionen, 72 KB, ohne Echtzeit |
| 3 | ganz Österreich, Schienenersatzverkehr/Schiff/Rufbus-Seilbahn (2178) | Schienenersatzverkehr 107, Schiff 0, Rufbus/Seilbahn 10, alle mit ≥ 2 Halten; 10,3 s, 205 KB |
| 4 | Stufe-5-Kachel mit Graz Hbf, 832 (weil 1 nicht abgeschnitten war) | 24 (Bus 19, Bim 5), alle mit Echtzeit |

Entscheidungen:
- **U-Bahn:** JourneyGeoPos liefert U-Bahn-Positionen (README radar2 F6 beantwortet). Die Notiz „Für die U-Bahn liefert die Auskunft keine Positionen.“
  gibt es daher nicht.
- **Grenzen bleiben** (0,6°, Startstufe +1): Eine Stufe-5-Kachel in Wien hatte abends 264; tagsüber ist mit deutlich mehr zu rechnen (§R11.1 d: über 1000
  in 24 × 30 km), eine Messung abends kann eine gröbere Startstufe nicht begründen.
- **Weitere Arten:** Schienenersatzverkehr (107) und Rufbus/Seilbahn (10) liefern Positionen, sind also möglich; Schiff war im November abends
  **nicht messbar** (0 heißt hier nicht „keine Daten“) und bleibt verborgen. Chips dafür sind nicht gebaut (§11, Stretch).
- **Betreiber:** Die Antworten tragen Betreibernamen (nicht `admin`), vier verschiedene in Wien: ein Betreiber-Filter (Teil B) hätte Wirkung.

## 9. Texte

Alle sichtbaren Wörter dieses Tracks stehen in `RadarModesText` (KlimaCore, getestet in `RadarModesTextTests`, `RadarModesLegendTextTests`,
`RadarModesSheetTextTests`): Chips („Züge“, „S-Bahn“, „Bus“, „Bim“, „U-Bahn“; VoiceOver „an“, „aus“, „an, erscheint beim Heranzoomen“), Zählzeile
(„Zug 21 · … · Andere 3“, gesprochen „21 Züge, …, 3 andere Fahrzeuge“), Notizen (Zoom, „4 von 9 Gebieten geladen“, zu dicht, abgeschnitten,
Takt, mobile Daten, Datenmenge, leer, leer mit Filter), Zeitreise-Hinweis, Legende, Blatt, Filterzeile und Suche. Ehrliche Wörter: „berechnet“
(nie GPS), „geschätzt“ (zwischen zwei Antworten), „Die Auskunft kennt in diesem Ausschnitt gerade keine Fahrzeuge.“ (nie „es fährt nichts“).

## 10. Demo und Screenshots

- `Modes/RadarCityDemo.swift`: erfundene Läufe auf erfundenen geraden Linien um die echten Mitten von Wien (600 Busse, 297 Bims, 40 U-Bahnen), Graz,
  Linz und Innsbruck (kleine Mengen), dazu S-Bahnen, Regional- und Fernzüge durch Wien; Liniennamen wie in der Stadt, vier Halte je Lauf, einige
  verspätet, einige ohne Echtzeit, einer von fünfzig fällt aus, Betreiber „Stadtverkehr“, „Regionalbus“, „ÖBB“. Der Dienst antwortet wie der echte: nur
  die gefragten Klassen, nur im Kasten, höchstens `maxVehicles`. In -KBDemo kommen die Stadt-Fahrzeuge auch über `DemoRadarService`.
- Szene „zu dicht“: 1200 Fahrzeuge in **einer** Stufe-8-Kachel am Stephansplatz und drei weitere Knoten zu je 1100, so dass die Teilungen mehr als
  16 Kacheln bräuchten.
- **CI-Takt:** Eine Radar-Szene wird 11 s nach dem Start aufgenommen; mit dem echten Budget wären das etwa 5 Kacheln. Die Stadt-Szenen nehmen daher
  ein Demo-Budget (`RadarSchedulerConfig.forRadar(syntheticCityDemo:sandboxed:)`, 600 je Minute, ohne Abstand), das es nur mit dem synthetischen Dienst
  in einem Sandbox-Start gibt; jeder andere Weg bekommt `.standard` (`RadarLanePlanTests`).
- Szenen (`RadarModesScreenshotHost`): `radarModesCity` (Wien nah, alle fünf Arten, Zählzeile), `radarModesZoomHint` (Österreich mit Bus: Hinweis,
  Lupe am Chip), `radarModesLegend`, `radarModesCrowded` (zu dicht, abgeschnitten, Datenmenge), `radarModesAX5`, `radarModesDots` (Nur Punkte, Groß,
  Gruppen aus), `radarModesFilter` (Blatt oben), `radarModesFilterLines` (Linie, Betreiber, Verspätung), `radarModesDisplay` (Darstellung mit Vorschau),
  `radarModesEmpty` (ein Filter, auf den nichts passt). Die Wien-Szene zeigt 0,02° um Hauptbahnhof und Belvedere statt 0,12°: bei 0,12° (und noch bei 0,045°, erster
  Screenshot-Lauf) waren fast alle Marker Gruppen von 5 bis 25 und die Schilder nicht zu sehen.

## 11. Geprüft / nicht geprüft

Geprüft (Linux, KlimaCore): Masken und Speicherung der Modi (`RadarModeSelectionTests`), Raster mit Spuren (`RadarLaneTilesTests`), Scheduler mit
zwei Spuren (a)–(m) inklusive Budget mit Nebenauftrag, Pünktlichkeit plus Stadt-Spur und der gemeinsamen Dehnung (`RadarLaneSchedulerTests`), was jede
Spur fragt und das Demo-Budget (`RadarLanePlanTests`), Zählzeile (`RadarModeCountsTests`), Datenmenge (`RadarDataEstimateTests`), alle Texte
(`RadarModesTextTests`); alle bisherigen Radar-Tests unverändert grün. App: Linux-Typprüfung.

Dazu Teil B: Zugart, Betreiber, Linien, beide Prüfer gleich auf 20 Fällen, Speicherung v1 → v2 (`RadarFilterCoreTests`), Schnellwahl
(`RadarQuickChoiceTests`), Darstellung (`RadarDisplayTests`), Suche nach „13A“, „U6“, „D“ (`RadarModesSearchTests`), die Demo-Flotte im Scheduler
(`RadarCityDemoFleetTests`).

Nicht geprüft: das Verhalten auf einem iPhone (§12); Positionen von Schiffen; ob `jid`s zwischen Abfahrtstafel und Radar gleich sind; das Cockpit für
Bus, Bim und U-Bahn; die Datenmenge mit einem echten Zähler; ob echte JourneyGeoPos-Antworten außer in Wien und Graz zwei Betreiber haben.
**Nicht gebaut (Stretch):** Chips für Schienenersatzverkehr und Rufbus/Seilbahn (die Messung zeigt Positionen, §8), die Perf-Szene `radarCity`,
Gruppen in der Farbe des häufigsten Verkehrsmittels, „Nur diese zeigen“ als Wischaktion der Suche.

## 12. Geräte-Checkliste

- Wien-Stadtansicht mit allen Arten 5 Minuten: ruckelt die Karte bei 300 bis 600 Markern, Akku.
- Datenzähler (Einstellungen › Mobiles Netz) über 10 Minuten Stadt-Spur gegen die Schätzung der Statuskarte.
- „Automatisch“ über Mobilfunk: kommt die Stadt-Spur alle 60 s?
- VoiceOver über gemischte Marker; Legende bei AX5; Kartenstil „Dunkel“ (Ring-Abstand schwarz, Schilder lesbar).
- Bus an in der Österreich-Ansicht: keine Bus-Anfrage, Lupe am Chip; heranzoomen bis unter 67 km: Busse kommen.
- Filter und Darstellung nach einem Neustart der App noch da; „Filter aus“ in der Zeile auf der Karte; „Nur Punkte“ bei 500 Markern flüssig?
- „Linie und Ziel“: überdecken sich die Ziele in einer dichten Innenstadt (höchstens 80 Einzelmarker)?

## 13. Seam für radarmine/radartrail

Gelandet im ersten Commit dieses Tracks (`Radar2/Radar2Seam.swift`); radarmine und radartrail ersetzen nur die Rümpfe ihrer Stubs.

| Datei | Besitzer danach | Inhalt |
|---|---|---|
| `Radar2/Radar2Seam.swift` | radarmodes | `RadarAnswerEvent`, `RadarEndReason`, `RadarSideJob`, `Radar2Parts`, `Radar2Hooks`, `Radar2TripRows`, `Radar2SettingsSections`, die `RadarView`-Erweiterung |
| `Modes/RadarMarkerDecoration.swift` | radarmodes | `RadarMarkerDecoration` (normal/hervorgehoben/gedimmt, Stern/Zahl, `.plain`), von `RadarMarker` angewandt |
| `Mine/RadarMineModel.swift`, `Mine/RadarView+Mine.swift` | radarmine | Stubs |
| `Trail/RadarTrailModel.swift`, `Trail/RadarView+Trail.swift` | radartrail | Stubs |

Haken in geteilten Dateien (je `// MARK: radar2`): `RadarModel` (`radar2`, `didMerge` nach `store.merge` mit den Produkten der Spur, `didRemove` mit den
ausgeschalteten Klassen, Nebenauftrag vor `scheduler.next` über `claimSlot`, `runSideJob`, Einzelmarker bei `keepsSingle`), `RadarView` (Karteninhalt,
`Radar2Hooks`, Fahrt-Blatt), `RadarView+Heat` (Dekoration, Fahrt-Blatt), `RadarView+Controls` (Chip-Leiste, Panel, Notizen außerhalb des Blocks der
Statuskarte), `RadarTripSheet` (`radar2`, `Radar2TripRows`), `RadarFilterSheet` (`parts`, `Radar2SettingsSections`).
