# Meine Fahrzeuge auf dem Radar (radarmine)

Stand 2026-11-20. Teil der zweiten Radar-Welle (radar2). Code: `App/Sources/Features/Radar/Mine/`,
`Packages/KlimaCore/Sources/KlimaCore/Live/Radar/Mine/`, Tests in `Packages/KlimaCore/Tests/KlimaCoreTests/Live/Radar/Mine/`. Eingebunden nur über die
Naht der zweiten Welle (`Radar2/Radar2Seam.swift`, `docs/RADAR_MODES.md` §13) und je eine markierte Zeile in `ScreenshotRouter` (`RootView.swift`),
`Heat/RadarView+Heat.swift` (Höhe des offenen Panels), `Repository.deleteAllData` („Alle Daten löschen“), `StopBoardDepartures.isAhead` (gemeinsame
Regel), `RadarFeatureGateTests`, `FeatureRegistry` und `project.yml` (Standort-Text). Regeln für Live-Daten: `docs/OEBB_LIVE.md` §2, §R11 (hier §R11.5).

## 1. Was es kann

Der Chip **„Meine“** am Anfang der Verkehrsmittel-Chips öffnet über der Statuskarte das Panel **Meine Fahrzeuge** mit drei Seiten:

1. **Linien** – Linien, die du dir gemerkt hast, mit dem, was das Radar gerade von ihnen weiß; auf Wunsch hervorgehoben (Stern, der Rest tritt zurück).
2. **In der Nähe** – nach deinem Tipp die Fahrzeuge im Umkreis von 1,5 km mit den Minuten bis zu ihrem nächsten Halt.
3. **Haltestelle – „Wo bleibt mein Bus?“** – die nächsten Abfahrten einer Haltestelle, jede mit Ankunftszeit, Verspätung, Steig oder Gleis und dem
   Ort, an dem das Fahrzeug gerade ist; die ersten fünf mit Position bekommen eine Nummer, in der Liste und auf der Karte.

Es öffnet sich immer nur ein Panel unten: Öffnet sich die Zeitreise, schließt sich „Meine“ (`Radar2Parts.timeCardOpened`), und „Meine“ schließt die
Zeitreise-Karte. Während das Panel offen ist, weicht die Ebenenleiste (wie bei der Zeitreise). Das Panel ist so hoch wie sein Inhalt, höchstens 36 % des
Bildschirms (ab AX1 40 %, die Statuskarte rückt dann unter das Panel und wird mit ihm gescrollt, damit die Karte Platz behält); der Rest scrollt im
Panel. Gemessen am Bildschirm, nicht an der Karte: die Karte wird kleiner, während das Panel unten Platz
nimmt, und ein Panel, das sich an ihr maß, schrumpfte mit (CI-Screenshots, zweiter Lauf). So bleiben Haltestelle und nummerierte Fahrzeuge darüber
sichtbar.

## 2. Linien

- **Merken:** im Fahrtblatt eines Fahrzeugs „Linie merken“ (Stern), noch einmal tippen: „Gemerkt“ wird wieder vergessen. VoiceOver sagt „Bus 13A
  gemerkt“. Höchstens **20 Linien**; die 21. wird abgelehnt („Du kannst bis zu 20 Linien merken. Entferne zuerst eine.“), nie wird still eine alte
  verdrängt. Unter Zügen steht: „Die gleiche Zugnummer kann an anderen Tagen anders fahren.“
- **Was gemerkt wird (`RadarLineKey`):** das Verkehrsmittel aus dem Klassen-Bit (`RadarMode.of(productClass:)`, nie `Line.mode`, das Schienenersatz
  „Bus“ nennt), der Linientitel („Bus 13A“, „S 45“, „U6“, „Tram D“, „RJX 66“) und kompakt („BUS13A“) zum Vergleichen, optional eine Richtung, und grob
  die Gegend: die Mitte der Radar-Kachel der Stufe 3 (etwa 39 × 36 km), auf zwei Kommastellen gerundet. **Nie** eine Fahrt-ID, nie ein Standort von
  dir. Schienenersatz, Fernbusse, Schiffe und Fahrzeuge ohne Linie lassen sich nicht merken (kein Knopf).
- **Vergleich:** gleiches Verkehrsmittel und gleicher kompakter Titel, Groß- und Kleinschreibung und Leerzeichen egal; „S 1“ ist nie „Bus 1“.
- **Zeile:** „3 unterwegs in den geladenen Gebieten“ und „Nächster: Richtung Hütteldorf · Westbahnhof in 3 Min (+1)“ (das Fahrzeug der Linie, das der
  Kartenmitte am nächsten ist; ohne Echtzeit „… laut Fahrplan“, ausgefallen „… fällt aus“). Ohne Fahrzeug: „Gerade keine in den geladenen Gebieten.
  Die Auskunft kennt nur, was in den geladenen Gebieten fährt.“ mit **„Zur gemerkten Gegend“** (die Karte geht dorthin, keine Anfrage). Ist der Chip
  der Linie aus: „„Bus“ ist oben ausgeschaltet …“ mit „Einschalten“; ist die Karte für Bus, Bim und U-Bahn zu weit, sagt es der Zoom-Hinweis der
  Stadt-Spur. Die Liste wird alle 5 s neu berechnet, nicht bei jeder Markerbewegung. Ein Tipp auf die Zeile wählt das Fahrzeug auf der Karte aus
  (kein zweites Blatt über dem Panel); „Nicht mehr merken“ im Menü und als VoiceOver-Aktion.
- **„Nur meine Linien hervorheben“:** deine Fahrzeuge bekommen einen goldenen Stern auf weißem Grund und einen goldenen Rand, alle anderen werden auf
  35 % gedimmt und verlieren den Pfeil (der Verspätungsring bleibt). Hervorgehobene Fahrzeuge werden **nie in Gruppen gefasst** – bis zu **60** als
  einzelne Marker, die der Kartenmitte am nächsten zuerst (`RadarMineHighlight`); mehr gruppieren sich wie gewohnt (20 Buslinien in Wien wären sonst
  Hunderte Einzelmarker, gegen die 250er-Regel von radarmodes). Der Chip „Meine“ ist dann golden.
- **Spuren:** „Ausgewählte und meine“ (`docs/RADAR_TRAILS.md`) zeichnet jetzt auch die Spuren deiner gemerkten Linien (`remembers(_:)`).

## 3. In der Nähe

- **Standort nur auf deinen Tipp** auf „In meiner Nähe zeigen“ (oder „Neu orten“): ein einziger Fix über `LocationService` (Freigabe „Beim Verwenden“,
  die Systemfrage kommt nur, wenn sie nie beantwortet wurde). Kein anderer Weg zur Standortfrage in diesem Ordner (`RadarMineSourceGuardTests`).
- Der Fix bleibt **im Arbeitsspeicher**, solange das Panel offen ist; nie gespeichert, protokolliert oder gesendet. Der blaue Punkt
  (`UserAnnotation`) erscheint erst nach dem Tipp, solange der Fix gehalten wird – nicht schon, weil die Seite offen ist (sonst würde eine frühere
  Freigabe, etwa vom Aussteige-Wecker, deinen Ort beim bloßen Öffnen zeigen).
- Die Karte geht auf etwa 3 km um den Fix, ein Kreis zeigt den Umkreis von 1,5 km. Die Liste kommt aus den Markern, die das Radar ohnehin hat
  (`RadarNearby.rows`): Entfernung, nächster Halt, Minuten (Echtzeit vor Fahrplan, 59 s sind „in 1 Min“, 0 oder weniger „jetzt“), Verspätung; ohne
  nächsten Halt fällt ein Fahrzeug weg; nächstes zuerst.
- **Ehrlich:** Die Position wird nicht gesendet, aber das Radar fragt danach die Kartenausschnitte rund um dich, wie beim Verschieben der Karte – daran
  sieht die ÖBB-Auskunft grob die Gegend. Die Seite sagt das vor dem Tipp, ebenso der Standort-Text in `project.yml`.
- Zustände: „Suche deinen Standort …“, „Lade Fahrzeuge in deiner Nähe …“, keine Freigabe („Ohne Standort geht das nicht …“ mit „Einstellungen
  öffnen“, keine erneute Frage), kein Fix in 8 s („Dein Standort kam gerade nicht …“ mit „Erneut versuchen“), Bus/Bim/U-Bahn aus (mit „Einschalten“),
  leer („Die Auskunft kennt im Umkreis von 1,5 km gerade kein Fahrzeug.“, mit Filter „… keines, das zum Filter passt.“).

## 4. Haltestelle – „Wo bleibt mein Bus?“

- **Warum eine Abfahrtstafel:** Eine Radar-Antwort kennt je Fahrzeug nur vier Halte (Start, zuletzt verlassen, nächster, Ziel). Welche Busse zu *deiner*
  Haltestelle kommen, weiß nur die Abfahrtstafel (StationBoard). Ihre Einträge tragen für laufende Fahrten die Position, die die Auskunft berechnet hat
  (`BoardEntry.currentPosition`); in den aufgezeichneten Tafeln auch für Bus, Bim und U-Bahn (`docs/OEBB_LIVE.md` §R11.5).
- **Auswahl:** Suche im eigenen Stationsverzeichnis (keine Anfrage), „Kartenmitte: …“ (die Haltestelle der Kartenmitte, bis 1 km), „In der Nähe: …“
  (nur nach einem Fix) und „Zuletzt“ (die letzten fünf). Das kleine „Ändern“ neben dem Namen (ab AX1 nur sein Symbol, damit der Name umbricht statt abgeschnitten
zu werden; VoiceOver: „Andere Haltestelle“) führt zurück.
- **Abfrage:** eine StationBoard-Anfrage für 30 Minuten, höchstens 12 Einträge, **Züge, S-Bahn, Bus, Bim und U-Bahn (4989), egal welche Chips an sind**
  – mit den voreingestellten Chips (Züge, S-Bahn) wäre eine Bushaltestelle sonst leer und „Die Auskunft kennt keine Abfahrt“ wäre falsch. Beim ersten
  Mal für eine Haltestelle vorher eine LocMatch-Anfrage (keine bei `uic:`-Stationen; der Linker merkt sie sich 30 Tage auf dem Gerät).
- **Takt (`RadarStopWatchPlan`):** sofort beim Wählen (zuerst die Verknüpfung, dann die Tafel, jede in einem eigenen Platz), danach 60 s nach der
  letzten Antwort; nie zwei gleichzeitig; nach Fehlern 15/30/60/120 s; nach 30 Minuten ohne Tipp Pause („Pausiert. Tippe zum Aktualisieren.“).
- **Zeilen (`RadarStopArrivals`):** die nächsten acht, die noch vor dir liegen (die Regel der „Nächsten Abfahrten“ des Pendel-Modus,
  `StopBoardDepartures.isAhead`: bis eine Minute nach der Abfahrt, ausgefallen bis zur Plan-Zeit), in der Reihenfolge der Tafel: Schild,
  „→ Hauptbahnhof“ neben dem Schild „13A“, „in 4 Min“ mit „+1“ / „pünktlich“ / „laut Fahrplan“ / „fällt aus“ (durchgestrichen) und in einer zweiten
  Zeile „ab 14:36 · Steig 2“ (Bahn: „Gleis 4“) mit der Position: „noch 1,2 km“ (Luftlinie), „an der Haltestelle“ (bis 100 m) oder „Position
  unbekannt“; älter als 2 Minuten grau mit „Position von vor 3 Min“. Nie hochgerechnet.
- **Position:** hält das Radar dieselbe Fahrt-ID mit einer **neueren** Antwort als die Tafel (oder hat die Tafel keine Position), ist der Radar-Marker
  die Position: er bekommt die Nummer und bleibt Einzelmarker. Sonst zeigt eine eigene Nadel mit Nummer (gestrichelter Rand) die Position der Tafel.
  Eine gestrichelte Luftlinie verbindet jedes nummerierte Fahrzeug mit der Haltestelle; ein Tipp auf Zeile oder Nadel zeigt beide auf der Karte.
  Während die Seite Nummern zeigt, treten die anderen Marker zurück.
- **Chips aus:** eine Abfahrt eines Verkehrsmittels, dessen Chip aus ist (oder das die Stadt-Spur gerade nicht zeichnet), steht in der Liste ohne
  Nummer; darunter „Bim ist aus – diese Abfahrten stehen in der Liste, aber nicht auf der Karte.“ mit „Einschalten“.
- **Pausen (`RadarFeatureGate.stopPanelAsks`):** gefragt wird nur, solange die Live-Schleife läuft, die Ebene „Züge“ an ist, die Seite offen ist und
  der Stromsparmodus aus ist. Die Seite sagt jede Pause: Zeitreise weg von „Jetzt“, Cockpit offen, Stromsparmodus (mit „Jetzt aktualisieren“, das die
  Abfrage in die manuelle Runde des Radars legt), Ebene „Züge“ aus (mit „Einschalten“), keine Live-Daten (mit „Einstellungen“), offline, und die
  Pause nach 30 Minuten. Fehler: die Sätze von `LiveMessage.text(for:)`; eine Haltestelle ohne ÖBB-Station: „Diese Haltestelle findet die Auskunft
  nicht.“
- **„Alle Abfahrten“** öffnet die Abfahrtstafel des Fahrplans (über `showBoard` des Radars).

## 5. Budget und Datenmenge

- **Linien** und **In der Nähe** fragen nichts selbst; sie lesen, was die Kacheln des Radars ohnehin liefern.
- **Haltestelle** ist eine **Nebenaufgabe der einen Live-Schleife** (`Radar2Parts.dueSideJob`, `RadarModel.run`): jede Anfrage (Verknüpfung oder
  Tafel) nimmt **einen eigenen Platz** desselben Budgets von 24 je Minute (`RadarScheduler.claimSlot`, höchstens 4 in 10 s, 1 s Abstand), nie zwei hinter
  einem Platz, höchstens eine unterwegs. Sie pausiert mit der Schleife (Hintergrund, Zeitreise weg, Cockpit, Stromsparmodus) und endet, wenn das Panel
  schließt, die Seite wechselt oder die Ebene „Züge“ ausgeht. 429, offener Schalter und Notschalter pausieren das ganze Radar wie eine Kachel.
- **Beweis:** `RadarMineGateTests.testTheWorstCityViewWithTheBoardStaysWithinTheBudget` – Wien mit 16 Stadt- und den breiten Kacheln plus Tafel zehn
  Minuten lang: höchstens 24 je Minute, 4 in 10 s, 1 s Abstand, mindestens 16 der 40 je Minute frei, etwa eine Tafel je Minute.
- **Daten:** eine Tafel von 12 Einträgen ist in den aufgezeichneten Antworten etwa 20–40 KB (1,8 KB je Eintrag in Innsbruck, meist Busse; 3 KB je
  Eintrag in Wien Hbf, Bahn) – also höchstens rund 40 KB je Minute, klein gegen die Kacheln der Stadt-Spur.

## 6. Datenschutz

| Was | Wo | Wie lange |
|---|---|---|
| Gemerkte Linien (Titel, Verkehrsmittel, grob die Gegend), die letzten fünf Haltestellen, „Hervorheben“ an/aus | `Application Support/RadarMine/mine.json`, **nicht** in der iPhone-Sicherung (`isExcludedFromBackup`), lesbar nach dem ersten Entsperren | bis du sie im Panel-Menü löschst oder „Alle Daten löschen“ |
| Dein Standort für „In der Nähe“ | nur im Arbeitsspeicher | bis das Panel schließt oder der Zugriff endet |
| Abfahrtstafel, Positionen, Nummern | nur im Arbeitsspeicher | bis Panel/Seite schließt oder der Zugriff endet |
| An die ÖBB-Auskunft | die gewählte Haltestelle (Tafel, ggf. einmal LocMatch) | einmal pro Minute, solange die Seite offen ist |

Nicht in UserDefaults (die gehören zur iPhone-Sicherung, und die letzten Haltestellen sagen, wo du wartest), nicht im Export, nicht in Sync.
Screenshot- und Perf-Starts lesen und schreiben die Datei nie (Speicher im Arbeitsspeicher). Zustimmung weg, Live-Fahrplan aus, Notschalter oder
Funktionen-„Offline-Modus“ beenden Tafel und Fix sofort (`end(.accessClosed)`); die gemerkten Linien bleiben (Einstellungen, keine Live-Daten). Die
Funktionen-Zentrale nennt beides beim Zug-Radar.

## 7. Messung

**Nicht gemessen.** Die Messung liegt als Live-Test bereit (`RadarMineLiveTests`, zwei Anfragen: die Tafel von Wien Hbf für Bus, Bim und U-Bahn und
das Radar rund um den Bahnhof; nur Zahlen und Ja/Nein; `KB_LIVE_TESTS=1 KB_RADAR_MINE=1`, nur werktags 9–19 Uhr Wiener Zeit, weil nachts kaum Busse
fahren). Sie lief nicht: als der Teil fertig wurde, war es in Wien nachts. Die aufgezeichneten Tafeln vom 2026-10-09 (`Fixtures/OEBB/hafas/`) tragen `pos` für Bus, Bim und U-Bahn (Innsbruck Hbf
Abfahrten: Bus 11 von 19, Bim 5 von 7, Median 1,1–1,2 km von der Haltestelle; Wien Hbf Ankünfte: Bus 7 von 7, Bim 15 von 17, U-Bahn 6 von 8). Ob die
Fahrt-IDs der Tafel denen des Radars gleichen, ist **nicht geprüft**. Deshalb steht der Satz „Ein Fahrzeug kann zweimal erscheinen: einmal vom Radar,
einmal von der Abfahrtstafel.“ von Anfang an unter jeder Tafel; stimmen die IDs nicht überein, ersetzt der Radar-Marker nie eine Nadel und dasselbe
Fahrzeug kann doppelt auf der Karte sein. Wie alt eine `pos` der Tafel im Moment der Antwort ist, ist ebenfalls offen: sie wird mit dem Alter der Tafel
gezeigt und nie hochgerechnet.

## 8. Linie per Suche orten: nicht gebaut

Die Zugsuche (JourneyMatch) liefert pro Lauf ein `pos`, aber `HafasCodec.trainSearch` verwirft es, die Abfrage umfasst alle Verkehrstage der
Fahrplanperiode (`onlyCR` aus), die Gleichheit ihrer `jid` mit dem Radar ist ungeprüft und Buslinien („13A“) wurden nie gesucht. Das bräuchte eine
eigene Messung. „Linien“ nutzt deshalb nur, was die Kacheln halten; außerhalb der geladenen Gebiete führt „Zur gemerkten Gegend“ dorthin.

## 9. Texte

Alle Sätze stehen in `RadarMineText` (KlimaCore) und sind getestet (`RadarMineTextTests`): „berechnet“, nie GPS; leere Listen sagen, was die Auskunft
kennt, nie „es fährt nichts“; „Min“ in Zeilen, „Minuten“ für VoiceOver; „240 m“, „1,2 km“; du-Form. VoiceOver liest jede Zeile als einen Satz
(„Bus 13A nach Hauptbahnhof, ab 14 Uhr 36, in 4 Minuten, 1 Minute verspätet, Steig 2, noch 1,2 Kilometer entfernt, Position berechnet, Nummer 1 auf der
Karte“), mit Aktionen „Auf der Karte zeigen“ und „Nicht mehr merken“. Textgrößen: die Titelzeile („Meine Fahrzeuge“ mit zwei Knöpfen) wächst bis
xxxLarge, die Seite bis AX2 – wie Statuskarte und Leisten des Radars über der Karte (bei AX5 war sonst keine Zeile mehr zu sehen); ab AX3 werden die
Segmente ein Menü mit der Seite als Titel, einzeilig („Haltestelle“ wurde bei AX5 getrennt); Zeilen stapeln sich, die Zeit wird nie abgeschnitten.

## 10. Demo und Screenshots

`RadarMineDemo`: gemerkt sind Bus 13A, S 45 und Tram D (Stadtflotten von radarmodes, in Wien gemerkt) und RJX 66 (Korridor-Demo, bei St. Pölten
gemerkt – in der Wien-Ansicht „nicht geladen“); die erfundene Haltestelle „Neubaugasse (Demo)“ mit acht Abfahrten relativ zu jetzt (die erste ist ein
Bus, den das Demo-Radar hält – gleiche Fahrt-ID, er bekommt die Nummer –, zwei ohne Position, eine ausgefallen); der erfundene Ort Wien Neubau
(48,2015 / 16,3480) für „In der Nähe“, als eigener Punkt gezeichnet (keine Standortfrage, kein Simulator-Ort). Szenen (`RadarMineScene`):
`radarMineLines`, `radarMineLinesAX5`, `radarMineHighlight`, `radarMineNear`, `radarMineNearIntro`, `radarMineDenied` (simuliert), `radarMineStop`,
`radarMinePicker`, `radarMineEmpty`, `radarMineTripSheet`, `radarMineAX5`. Sie nutzen das Demo-Budget der Stadtflotten (`RadarView(preset: .modesCity)`).

## 11. Geprüft / nicht geprüft

Geprüft (Linux, `swift test --filter RadarMine`): Schlüssel und Vergleich, 20er-Grenze, Datei-Format v1 mit Toleranz, Umkreis-Kante 1,499/1,501 km,
Reihenfolge, Minuten, Tafel-Zeilen (Reihenfolge, vergangene, 8er-Grenze, 100 m, Steig/Gleis, Alter), Radar-Abgleich nur bei gleicher ID und neuerer
Antwort, Nummern, Gate in jedem Zustand (auch in `RadarFeatureGateTests`), Takt und Backoff, Budget-Simulation, Hervorhebungs-Grenze 60, alle Texte,
Quell-Wächter (keine UserDefaults, kein zweiter Standortweg, keine Position in einer Anfrage, Tafel nur über die Quelle der Nebenaufgabe), die Zeilen
der Funktionen-Zentrale. Linux-Typecheck der App. CI-Screenshots hell, dunkel und AX5 in vier Läufen (Builds 677, 680, 685, 689: Panelhöhe, AX5-Kappen,
Kopfzeile der Haltestelle, eine Zeile für Zeit, Steig und Position, Fahrtblatt-Szene); danach wurden Chip „Meine“ und „Linie merken“ für alle
sichtbar (`RadarMineEntry.isReleased`, vorher nur in Screenshot-Starts). Das Symbol statt „Ändern“ ab AX1 kam nach dem vierten Lauf und ist in
keinem Screenshot zu sehen.

Nicht geprüft: alles mit echten Daten (Messung §7), MapKit-Leistung mit vielen hervorgehobenen Markern, der echte Standort-Dialog, VoiceOver auf dem Gerät.

## 12. Geräte-Checkliste

1. Echte Haltestelle in Wien (z. B. eine Bushaltestelle): die ersten drei Zeilen mit der Anzeige an der Haltestelle vergleichen; nach 60 s neue „Stand“.
2. „In meiner Nähe zeigen“ fragt genau einmal nach dem Standort; danach nie wieder beim bloßen Öffnen; der blaue Punkt erst nach dem Tipp.
3. Stromsparmodus: „Stromspar-Modus: Die Abfahrten werden nicht aktualisiert.“, „Jetzt aktualisieren“ holt eine Tafel.
4. Zeitreise weg von „Jetzt“ und Cockpit: die Seite pausiert und sagt es; zurück: es geht weiter.
5. Ebene „Züge“ aus: Pause mit „Einschalten“.
6. „Nur meine Linien hervorheben“ mit vielen Buslinien in Wien: Sterne, gedimmter Rest, flüssiges Scrollen.
7. VoiceOver: Zeilen als ein Satz, Aktionen „Auf der Karte zeigen“ und „Nicht mehr merken“.
8. Zeigt dasselbe Fahrzeug zweimal (Radar-Marker und Nadel)? Dann gleichen die IDs nicht – in §7 und §R11.5 eintragen.
