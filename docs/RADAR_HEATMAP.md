# KlimaBilanz · Verspätungs-Heatmap („Pünktlichkeit“ auf dem Zug-Radar)

Owner-Idee: „Eine Karte, wo in Österreich gerade Züge zu spät sind.“ Auf dem Zug-Radar (`docs/OEBB_LIVE.md` §R, §R7, §R10, §R11) gibt es
dafür eine neue Ebene in der Ebenen-Leiste: **Pünktlichkeit**. Sie legt ein Raster aus Sechsecken über Österreich, färbt jedes Feld nach der
mittleren Verspätung der Züge darin und fasst das Land in einem Panel zusammen: Prozent pünktlich, Zahl der Züge mit und ohne Echtzeit-Daten,
die größten Verspätungen jetzt und die Brennpunkte.

Jede Zahl ist nachgerechnet, jedes Wort sagt nur, was stimmt. Wo es ein Gefühl geben könnte, das die Daten nicht tragen (ein Zug ohne
Echtzeit-Daten als „pünktlich“, ein Feld mit zwei Zügen als „rot“), tut die Ebene es nicht.

**Code.** Reine Logik in KlimaCore (`Packages/KlimaCore/Sources/KlimaCore/Live/Radar/Heat/`, Linux-Tests in `Tests/KlimaCoreTests/Live/Radar/Heat/`),
Oberfläche in `App/Sources/Features/Radar/Heat/`. Nichts davon fragt selbst etwas an: Die Ebene benutzt die Anfragen des Radars.

| Datei | Inhalt |
|---|---|
| `HeatGrid.swift` | Sechseckraster, Zell-Ids, Eckpunkte, Schraffur |
| `RadarHeat.swift` | Zug → Klasse, Median, Felder, Landeszahlen, Top-Verspätungen, Brennpunkte, Tippen |
| `HeatPaint.swift` | Farbverlauf, Deckkraft, Obergrenze der gezeichneten Felder, Überblendung |
| `RadarHeatText.swift` | alle deutschen Texte der Ebene (getestet) |
| `HeatHistory.swift` | Verlauf dieser Sitzung für die Sparkline (nur im Speicher) |
| `RadarHeatModel.swift`, `RadarModel+Heat.swift` | Zustand der Ebene, Haken ins Radar-Modell |
| `RadarView+Heat.swift`, `RadarHeatPanel.swift`, `RadarHeatCellSheet.swift`, `RadarHeatMarkers.swift`, `RadarHeatPalette.swift` | Karte, Panel, Feld-Blatt, Punkte, Farben |
| `RadarHeatDemo.swift`, `RadarHeatScreenshotHost.swift` | erfundene Züge und die CI-Szenen |

## 1. Laden: ganz Österreich, ohne eigene Schleife

Ist die Ebene an, bekommt der Scheduler (`RadarScheduler`, §R11.2) als Ansicht das Rechteck des Radar-Gebiets (`RadarTileGrid.coverage`, 2,8° hoch)
statt des Kartenausschnitts. Das sind die zwei Kacheln der Stufe 0, alle 20 s je Kachel (der Scheduler zählt eine Ansicht bis 3° als herangezoomt),
also **6 Anfragen je Minute** im Budget von 24 für das Radar (die übrigen 16 der 40 aus `docs/OEBB_LIVE.md` §2 bleiben für Fahrplan, Abfahrten
und Live verfolgen). Es gibt keine zweite Schleife, keinen eigenen Zeitgeber und keinen Hintergrunddienst: `RadarModel.run` ist dieselbe Schleife,
sie endet mit der Ansicht, sie pausiert im Stromspar-Modus und folgt dem Schutzschalter und der Ratenbegrenzung wie vorher.

- **Keine Abhängigkeit vom Kartenausschnitt.** Schieben und Zoomen ändern keine Anfrage, solange die Ebene an ist (`RadarModel.applyViewport`).
  Wird sie ausgeschaltet, folgt der Scheduler wieder der Karte.
- **Eine Antwort deckt alles.** Gemessen (§R11.1): `maxJny` 1000 liefert alle 923 Schienenfahrzeuge in einer Antwort. Mit den zwei Kacheln der
  Stufe 0 sind es zwei Antworten mit zusammen etwa dieser Zahl; ist eine Kachel abgeschnitten, teilt der Scheduler sie wie sonst.
- **Die Ebene braucht keine Zugpunkte.** Auch mit ausgeschalteter Zug-Ebene lädt das Radar für die Pünktlichkeit; die Zustimmung zu Live-Daten
  (§2) gilt wie vorher: ohne sie lädt nichts und die Ebene zeigt nichts.
- **Modi und Filter.** Die Zahlen gelten für die eingeschalteten Verkehrsmittel (Standard: Schiene), nicht für den Filter: Der Filter betrifft die
  Zugpunkte. Ist er aktiv, sagt das Panel es.

## 2. Das Raster

Sechsecke (Spitze oben), Mittelpunkte benachbarter Felder **0,12° Breite** auseinander (13,3 km); ein Feld hat etwa 154 km² und Seiten von 7,7 km.
Das Raster ist fest: Ursprung in der Mitte Österreichs (47,7° N, 13,35° O), eine Ebene-Projektion mit einem Längengrad-Maß (74,8 km je Grad), Feld-Id
`q|r` als Achsenkoordinaten. **Derselbe Ort hat immer dieselbe Id**, unabhängig von Bildschirm, Zoom und Reihenfolge der Züge. Im Rechteck des Radars
liegen etwa 1 200 Felder. Auf dem Österreich-Zoom eines Hochformat-iPhones ist ein Feld rund 18 pt breit, bei einem Ausschnitt von 1,1° etwa 60 pt.

Sechsecke statt Quadrate, weil sie keine Ecken-Nachbarn haben (jedes Feld hat sechs gleich weit entfernte Nachbarn) und weil Brennpunkte so
zusammenhängend aussehen.

## 3. Die Regeln der Zahlen

**Die Verspätung eines Zuges** ist die Echtzeit-Verspätung am nächsten Halt, den er noch nicht erreicht hat (`RadarDelay.currentDelay`, §R7). Fehlt sie
dort, gilt die des letzten Halts mit Echtzeit-Wert; gibt es gar keinen, hat der Zug keine Echtzeit-Daten. Die Position ist die berechnete, die die
Karte zeigt (`RadarEstimate.shown`).

| Klasse | Grenze (Sekunden) | Farbe |
|---|---|---|
| pünktlich | unter 300 (auch zu früh) | grün |
| 5 bis 15 Min | 300 bis 900 (15:00 gehört noch dazu) | orange |
| über 15 Min | über 900 | rot |
| ausgefallen | `isCncl` | violett (nie rot: Rot heißt „über 15 Min“) |
| ohne Echtzeit | kein Wert | grau |

Die 300 Sekunden sind `RadarDelay.lateThresholdSeconds`, dieselbe Grenze wie der Ring der Zugmarker; ein Test hält beides gleich.

- **Feld.** Alle Züge, deren Position in das Feld fällt. Der **Median** der Verspätungen ist die Mitte (bei gerader Zahl der Mittelwert der zwei mittleren),
  gerechnet **nur über Züge mit Verspätungswert** (Echtzeit, nicht ausgefallen). Ein Feld mit **weniger als 3** solcher Züge bleibt **neutral**: grau,
  gestrichelt, schraffiert, nie gefärbt, ohne Median, auch wenn seine zwei Züge 40 Minuten zu spät sind. Sieben Züge im Feld, davon zwei mit Echtzeit,
  sind ebenfalls neutral (Test).
- **Landeszahlen.** Gezählt wird, was das Radar gerade hält. **„Pünktlich (unter 5 Min)“ ist der Anteil der Züge mit Echtzeit-Daten, die pünktlich
  sind.** Ein ausgefallener Zug hat Echtzeit-Daten und zählt als nicht pünktlich. **Züge ohne Echtzeit-Daten fehlen in den Prozenten und sind nie
  pünktlich**; sie stehen daneben („412 Züge mit Echtzeit-Daten, 38 ohne“). Ohne einen einzigen Zug mit Echtzeit-Daten steht keine Zahl da.
  Gerundet wird so, dass die Zahl nicht mehr sagt als die Daten: nie 100 %, solange ein Zug zu spät ist; nie 0 %, solange einer pünktlich ist.
- **Ø Verspätung** ist der Mittelwert über die Züge mit 5 Minuten oder mehr. Der **Balken** hat vier Teile (pünktlich, 5 bis 15, über 15, ausgefallen), jeder
  ein Anteil der Züge mit Echtzeit-Daten.
- **Größte Verspätungen jetzt.** Die fünf Züge mit der größten Verspätung, nur solche ab 5 Minuten, bei gleicher Verspätung nach Fahrt-Id. Sind es
  weniger als fünf, steht weniger da; ist es keiner, steht das.
- **Brennpunkte.** Die drei Felder mit der größten **Summe der Verspätungsminuten** (zu frühe Züge zählen 0), unter den Feldern, die eine Farbe haben (mindestens 3 Züge mit
  Wert) **und** deren Median mindestens 5 Minuten beträgt (ein Feld mit zwölf Zügen, die vier Minuten zu spät sind, ist kein Brennpunkt, auch wenn die Summe hoch ist).
  Ein Feld neben einem besseren wird übersprungen: drei Brennpunkte sind drei Orte, nicht ein Korridor, der dreimal zählt. Der Name ist der häufigste nächste Halt der Züge
  im Feld („Raum Jenbach“, bei Gleichstand der erste im Alphabet); er sagt, wo das Feld ungefähr liegt, nicht, wo die Störung ist.
- **Gebiet der Zahlen.** Das Rechteck des Radars enthält Teile von Bayern, Südtirol, Westungarn und der Slowakei (§R11.1). „Landesweit“ wäre falsch: Das
  Panel sagt „im Radar-Bereich: Österreich und angrenzende Gebiete“.
- **Unvollständig.** Sind Kacheln noch nicht da, ausgefallen oder abgeschnitten, sagt das Panel es („Die Zahlen gelten für die geladenen Gebiete“).

Der Hinweis unter den Zahlen sagt immer: Die Verspätung ist die Echtzeit-Verspätung, die die ÖBB für den nächsten Halt meldet, die Positionen sind berechnet,
Züge ohne Echtzeit-Daten zählen nie als pünktlich.

## 4. Darstellung

- **Überlagerung.** Jedes Feld ist ein paar `MapPolygon`: farbig drei verschachtelte Sechsecke (Glühen 1,5×, Hof 1,18×, Körper 0,92×) mit steigender Deckkraft, das ergibt
  den weichen Rand; neutral ein gestricheltes Sechseck und ein Zickzack aus drei Diagonalen als eine `MapPolyline`. Die Überlagerungen liegen über den Straßen
  und unter den Beschriftungen der Karte (`mapOverlayLevel(.aboveRoads)`). Es gibt keine View je Zug und keine je Feld.
- **Obergrenze.** Höchstens `HeatLayer.maxDrawnCells` = **300** Felder, höchstens **900** Überlagerungen im Ruhezustand (farbig 3, neutral 2); gewählt werden zuerst die farbigen
  Felder mit den meisten Verspätungsminuten, dann die neutralen mit den meisten Zügen. Sortiert wird nach Id, die Zeichenreihenfolge ändert sich nicht. Ein Test
  mit 700 farbigen Feldern und einer mit 2 000 Zügen prüft die Grenze; die 2 000 Züge werden in unter einer Sekunde gerechnet (auch im Debug-Build).
- **Farbe.** Grün (`Theme.positive`) bis 3 Minuten, Orange (`Theme.summit`) von 7 bis 13, Rot (`Theme.negative`) ab 17, dazwischen linear. Die Übergänge
  liegen auf den Grenzen: bei 5:00 halb grün, halb orange; bei 15:00 halb orange, halb rot. Unter 5 Minuten gewinnt Grün, von 5 bis 15 Orange, darüber Rot (Test über das ganze
  Band). Die Stärke (0,55 bis 1) wächst mit der Zahl der Züge: drei Züge sind eine blasse Farbe, zwölf eine volle. Hell wie dunkel aus denselben Tokens; auf der dunklen Karte (und im
  Kartenstil „Dunkel“) sind es die hellen Dunkelmodus-Töne mit stärkerem Glühen, sie leuchten.
- **Überblendung.** Kommt eine Antwort, laufen die Farben in vier Schritten (alle 90 ms, gut eine Drittelsekunde) vom alten zum neuen Stand; neue Felder blenden ein, weggefallene aus.
  MapKit-Überlagerungen kann SwiftUI nicht animieren, deshalb Schritte statt einer Feder. Mit „Bewegung reduzieren“ und in Screenshots erscheint der neue Stand sofort.
- **Züge als Punkte.** Mit der Ebene sind die Zugmarker kleine Punkte (grün, orange, rot nach Klasse; die Größe wächst mit der Verspätung, ausgefallene und Züge ohne Echtzeit sind
  offene Ringe), Gruppen eine kleine Zahl. Ein Tippen auf einen Punkt öffnet das Fahrt-Blatt wie vorher. Die Zahl der Marker bleibt die des Radars (höchstens etwa 130).
- **Brennpunkte** haben eine Nummer auf der Karte (1 bis 3).
- **Tippen auf ein Feld.** Ein Tippen auf die Karte sucht das Feld unter dem Finger, sonst das nächste mit Zügen innerhalb einer Fingerbreite (24 pt), mindestens ein Feld; es öffnet ein Blatt:
  Ort, mittlere Verspätung (oder warum das Feld keine Farbe hat), worauf es beruht und alle Züge im Feld, der späteste zuerst. Ein Zug öffnet das Fahrt-Blatt darüber. Das Feld hat einen Rahmen.

## 5. Panel, Bedienung, Zugänglichkeit

Ein Glas-Panel unten (über der Ebenen-Leiste), einklappbar. **Zu:** Überschrift „Pünktlich (unter 5 Min)“ mit der großen Zahl, der gestapelte Balken, „412 Züge mit Echtzeit-Daten, 38 ohne“ und
„Stand vor 12 s“ (das Alter der ältesten Antwort, gerechnet ab der Anfrage, wie in §R11.2). **Auf:** Legende mit Zahlen, Ø Verspätung, Verlauf, Größte Verspätungen jetzt (fünf Zeilen), Brennpunkte
(drei Zeilen) und die Hinweise.

- **VoiceOver.** Das Panel liest sich als eine Zusammenfassung (Prozent, Basis, Ø, Teile des Balkens, Stand). Balken und Legende sind für VoiceOver aus (sie würden nur doppeln). Die Zeilen der größten Verspätungen und
  der Brennpunkte sind eigene Schaltflächen („RJX 66 nach Wien Hbf, 18 Minuten verspätet“, „Fahrt öffnen“): So erreicht man Züge und Felder, ohne die Karte zu berühren. Die Felder der Karte sind **keine**
  Zugänglichkeitselemente (Überlagerungen sind es nicht), die Nummern der Brennpunkte sind es.
- **Dynamic Type.** Ab den Zugänglichkeitsgrößen stapeln Überschrift und Zahl, Zeilen laufen auf zwei Zeilen, die Legende ein Eintrag je Zeile; das Panel scrollt, höchstens 60 % der Karte hoch. Die Ebenen-Leiste scrollt
  seitwärts, wenn die fünf Titel nicht nebeneinander passen. Szene `radarHeatAX5`.
- **Bewegung.** Das Aufklappen läuft über `withMotion`, Zahlen rollen (`numericValue`), die Überblendung entfällt mit „Bewegung reduzieren“.
- **Farbe ist nie allein.** Zahlen in jeder Zeile, Legende mit Worten, Punkte mit Größe und Ring, Nummern auf den Brennpunkten.

## 6. Verlauf dieser Sitzung (Zusatz, gebaut)

`HeatHistory`: der Anteil „pünktlich“ im Abstand von mindestens 30 s, höchstens 120 Punkte, **nur im Speicher**, nie auf der Platte, leer bei jedem Start der Karte und beim Ausschalten der Ebene. Ein Verlauf
braucht drei Punkte über mindestens eine Minute und mindestens 20 Züge mit Echtzeit-Daten je Punkt; dann zeigt das offene Panel eine kleine Linie und „Seit 6 Min: 85 % → 87 %“. Geht die Uhr zurück, wird der Punkt verworfen.

„Pünktlichkeitskarte teilen“ als Bild ist **nicht gebaut** (Zusatz, zuerst gestrichen): Das Teilen eines Bildes bräuchte `ImageRenderer` mit einer Karte, die MapKit-Kacheln nicht in ein Bild gibt (die Basiskarte fehlte,
nur die Felder wären zu sehen), und eine Entscheidung, was ein geteiltes Bild über Orte sagen darf.

## 7. Messung (einmalig, vom Owner freigegeben)

**Budget und Ablauf.** Genau **eine** JourneyGeoPos-Anfrage (Österreich, Schiene, `maxJny` 1000), ehrlicher User-Agent (`KlimaBilanz/live-test (iPhone; iOS; private, low-volume)`),
keine Wiederholung, Stopp bei jedem Fehler (`BudgetedTransport` mit Grenze 1, derselbe wie in §R11.1). **Verbraucht: 1, HTTP 200.** Test:
`Tests/KlimaCoreTests/Live/LiveSmoke/RadarHeatLiveTests.swift`, Lauf:
`KB_LIVE_TESTS=1 KB_RADAR_HEAT=1 swift test --package-path Packages/KlimaCore --no-parallel --filter RadarHeatLiveTests`. Zwei Schalter mit Absicht: Ein Lauf mit `--filter LiveSmoke`
verbraucht die Anfrage nicht. Gedruckt werden **nur Zahlen** (Zeilen `RADAR_HEAT …`): keine Fahrzeugliste, keine Fahrt-Ids, keine Namen, keine Positionen. Nichts davon ist im
Repository gespeichert.

**Zeitpunkt und Ort.** Donnerstag 2026-11-12, **22:04 Uhr Wien** (spätabends, nicht Spitze), aus einer Cloud-Sandbox über einen gemeinsamen Ausgangs-Proxy, nicht von einem iPhone. Antwortzeit 2 925 ms.
**Eine** Momentaufnahme: Sie zeigt, wie die Daten aussehen können, nicht, wie sie im Schnitt sind. Die 74 % unten sind **keine** Pünktlichkeitsstatistik der ÖBB.

| Messgröße | Wert |
|---|---|
| Fahrzeuge in der Antwort (`jnyL`) | 568 (am Abend vorher, 17:08, waren es 923: §R11.1) |
| davon mit Echtzeit-Wert (am nächsten Halt, sonst am letzten mit Wert) | **446** (78,5 %) |
| davon **ohne** Echtzeit-Wert | **122** (21,5 %) |
| ausgefallen (`isCncl`) | **0** |
| pünktlich (unter 5 Min) | 331 |
| 5 bis 15 Min | 67 |
| über 15 Min | 48 |
| „Pünktlich (unter 5 Min)“ nach der Regel dieses Dokuments (331 von 446) | **74 %** |
| Ø Verspätung der 115 Züge mit 5 Min oder mehr | 18,9 Min |
| Median aller Verspätungswerte | 60 s |

Verteilung der 446 Werte nach Minuten: unter 3: 297 · 3 bis 4: 34 · 5 bis 9: 50 · 10 bis 14: 15 · 15 bis 29: 26 · 30 und mehr: 24 (keiner unter 0: zu frühe Züge kamen nicht vor).
Zählte man die 122 Züge ohne Echtzeit-Wert als pünktlich, stünde 80 % da (453 von 568); die Regel „ohne Echtzeit nie pünktlich“ macht aus 80 % ehrliche 74 %.
Ein Fahrzeug hat einen Verspätungswert, wenn irgendein Halt seiner Fahrt Echtzeit trägt (`RadarDelay.currentDelay` fällt auf den letzten Halt mit Wert zurück): 446 Fahrzeuge haben irgendwo Echtzeit, und 446 haben einen Wert.

**Das Raster (0,12°) mit diesen Zügen.** 298 Felder mit mindestens einem Zug. **Nur 46 davon (15 %) haben mindestens 3 Züge mit Verspätungswert und damit eine Farbe**, 252 sind neutral. 167 Felder
haben einen Zug, 78 zwei, 45 drei bis fünf, 8 sechs und mehr (das volleste: 30). In den 46 gefärbten Feldern fahren 219 Züge (39 % der 568); davon liegen 36 Felder unter 5 Min, 8 bei 5 bis 15, 2 darüber (Median).
Drei Brennpunkte und fünf größte Verspätungen gab es. Abends mit 568 Zügen ist die Karte also **überwiegend schraffiert**; zur Spitze mit gut 900 Zügen sind es mehr gefärbte Felder (nicht gemessen). Das ist die
Folge der Regel „mindestens 3 Züge“ bei 13-km-Feldern, nicht ein Fehler. Das Panel sagt es in Zahlen („46 von 298 Feldern“), damit die Karte nicht mehr verspricht, als sie hat. Ein gröberes Raster
(`HeatGrid.spacingDegrees`) würde mehr Felder färben und weniger Ort zeigen: Entscheidung des Owners, nicht gemessen.

## 8. Demo-Szenen, Tests, CI

`-KBDemo`, kein Netz (`RadarHeatDemo.swift`): etwa 940 **erfundene** Fahrzeuge auf den erfundenen Korridoren des Radar-Demos (`ScottyDemoDense.swift`), Verspätungen für die Szene gemacht: ein Verspätungs-Cluster über Tirol
(zwischen Arlberg und Kufstein 11 bis 36 Minuten, einige 4 bis 10), der Rest ruhig (fast alles pünktlich, wenige verstreute Verspätungen, einige ohne Echtzeit, einer ausgefallen). Kein echter Zug, keine echte Verspätung, keine echte Position.

| Szene | Zeigt |
|---|---|
| `radarHeat` | die Ebene über Österreich, Panel zu |
| `radarHeatPanel` | das Panel offen |
| `radarHeatCell` | die Karte nah an Tirol, das Blatt des größten Brennpunkts |
| `radarHeatAX5` | das offene Panel in der größten Textgröße |

Tests (Linux, `swift test --package-path Packages/KlimaCore --no-parallel --filter Heat`): `HeatGridTests`, `RadarHeatTests`, `HeatPaintTests`, `RadarHeatTextTests`, `HeatHistoryTests`, dazu `MapLayersTests` (die neue Ebene
ist aus, ein gespeicherter Wert von vorher liest sich wie vorher). Geprüft: Zell-Ids und Randfälle des Rasters, die Grenzen der Klassen gegen `RadarDelay`, Median, Mindestzahl und die Regel „ohne Echtzeit nie pünktlich“, Rundung,
Rangfolge der Brennpunkte, leere und Teil-Antworten, Doppelte und fehlerhafte Positionen, Unabhängigkeit von der Reihenfolge der Züge, die Obergrenze für 2 000 Fahrzeuge, die Überblendung.

## 9. Was nur auf einem iPhone zu prüfen ist

- Wie flüssig die Karte mit bis zu 900 Überlagerungen schiebt und zoomt (die CI-Screenshots zeigen den Stand, nicht die Bildrate); ob die vier Schritte der Überblendung flackern.
- Ob das Tippen auf die Karte das Zoomen mit zwei Fingern oder das Doppeltippen stört (die Geste läuft gleichzeitig mit denen der Karte).
- Wie das Glühen auf der dunklen und der hellen Karte bei Sonnenlicht und bei hoher Helligkeit aussieht.
- Die Laufzeit der Antworten im Mobilfunknetz (§R11) und der Akku bei einer Viertelstunde mit der Ebene an.
- VoiceOver auf dem Gerät: Reihenfolge und Ansagen des Panels.

## 10. Nicht gebaut, Grenzen

- Das Teilen als Bild (§6).
- Ein Verlauf über Sitzungen und eine Karte vergangener Verspätungen: Es gibt keine Historie, nur den Moment.
- Korridore als Zusammenfassung von Feldern: Brennpunkte sind Felder (§3).
- Die Verspätung am nächsten Halt ist nicht die Ankunftsverspätung am Ziel; ein Zug kann sie aufholen oder vergrößern.
- Das Raster ist fest 0,12°. Auf dem Österreich-Zoom sind dünn befahrene Strecken neutral, weil dort weniger als drei Züge je Feld fahren (§7 hat die Zahl).
- Das Rechteck des Radars enthält Grenzgebiete (§3).
