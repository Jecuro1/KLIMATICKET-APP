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
| `RadarHeatShare.swift` | Karte als Bild (`ImageRenderer`) |
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
- **Nicht in der Zeitreise.** Zeigt die Zeitreise (`docs/RADAR_TIMETRAVEL.md`) eine andere Zeit als jetzt, ist die Pünktlichkeit ausgeblendet und lädt nichts: Ihre Zahlen gelten für jetzt, und neben einer Karte von heute Abend wären
  sie falsch. Zurück auf „Jetzt“ kommt sie wieder (ohne den Verlauf, der beim Ausblenden endet).
- **Die Ebene braucht keine Zugpunkte.** Auch mit ausgeschalteter Zug-Ebene lädt das Radar für die Pünktlichkeit; die Zustimmung zu Live-Daten
  (§2) gilt wie vorher: ohne sie lädt nichts und die Ebene zeigt nichts.
- **Modi und Filter.** Die Zahlen gelten für **Züge und S-Bahnen** (`ProductMask.rail`), auch wenn Bus, Bim oder U-Bahn bei den Verkehrsmitteln an sind: Die
  Ebene heißt Pünktlichkeit „der Züge“, und eine Busverspätung wäre keine Zugverspätung (Review 1: vorher zählten eingeschaltete Busse und Bims als „Züge“ mit). Die Anfragen
  folgen den Verkehrsmitteln wie beim Radar; mit Bussen an ist die Antwort größer und eine Kachel kann am Limit abgeschnitten sein (das Panel sagt es, der Scheduler teilt sie).
  Ist nur Bus, Bim oder U-Bahn an, steht im Panel, dass die Pünktlichkeit nur Züge zählt. Der Filter betrifft die Zugpunkte, nicht die Zahlen; ist er aktiv, sagt das Panel es.

## 1a. Zugriff, Budget, Datenmenge, Akku (Review 2)

**Tor.** Die Ebene fragt nichts selbst an. Das Radar lädt für sie nur, solange die Ebene an ist, die Live-Daten erlaubt sind
(`LiveDataService.timetableUnavailable` ist `nil`: Zustimmung, Schalter, Notschalter der Fernkonfiguration, online) und die Zeitreise
„Jetzt“ zeigt; sonst endet die Schleife (`RadarView.isRunning`). Jede Anfrage geht durch `HafasClient`: Der prüft den Notschalter vor jeder
Anfrage noch einmal (`LiveError.disabled`, ohne Netz), dann den Schutzschalter (`LiveHealth`: drei Fehler in Folge öffnen ihn für 2 Minuten,
für die ganze App) und die Drossel (`RequestThrottle`: 40 je Minute für die ganze App, mindestens 0,3 s Abstand, ehrlicher User-Agent).

**Budget.** Normal **6 Anfragen je Minute** (zwei Kacheln alle 20 s). Höchstens 24 je Minute, 4 in 10 s und eine je Sekunde, zusammen mit
allem, was das Radar sonst anfragt (Zeitreise, Cockpit): ein Budget im Radar-Modell (`RadarScheduler`). Kein Handgriff kommt darüber
(`HeatBudgetTests`, zehn simulierte Minuten, Antworten nach 3 s, also mehrere Anfragen gleichzeitig unterwegs):

- die Ebene alle 0,75 s ein- und ausschalten (die Ansicht springt zwischen Österreich und Wien: neue Kacheln, Anfragen unterwegs);
- alle 4 s in den Hintergrund und zurück: Laufende Anfragen werden abgebrochen. Ein abgebrochener Lauf gibt die **Kachel** frei (sie ist
  wieder fällig), **nicht den Platz im Budget**: Die Anfrage kann den Server schon erreicht haben. Die Drossel der App rechnet genauso;
- „Jetzt aktualisieren“ (Stromspar-Modus) oder „Erneut versuchen“ zweimal je Sekunde;
- Zeitreise-Momentaufnahmen und die Kacheln der Ebene im selben Lauf.

Das Budget übersteht das Ausschalten der Ebene, den Wechsel der Verkehrsmittel (`reset()` vergisst die Kacheln, nicht das Budget), Zeitreise,
Cockpit und Hintergrund. Zwei Radar-Ansichten mit zwei Budgets gibt es nicht: Die App hat ein Fenster (nur iPhone,
`UIApplicationSupportsMultipleScenes` aus), und Radar und Zugsuche sind Vollbild-Blätter derselben Fahrplan-Ansicht.

**Die Wiederholung des Clients.** Nach einer Zeitüberschreitung oder 502/503/504 fragt `HafasClient` einmal nach 1,5 s nach. Diese zweite
Anfrage zählt in der Drossel (40) und im Schutzschalter, nicht in den 24 des Radars (§R11.2). Im schlechtesten Fall gehen also 12 statt 6
Anfragen je Minute an die ÖBB, aber nicht lange: Drei gescheiterte Anfragen in Folge öffnen den Schutzschalter für 2 Minuten. Ein
Ausweichprofil (nach AUTH, HAMM oder PARSE) wäre eine weitere Anfrage, ebenfalls durch die Drossel.

**Datenmenge.** Gemessen ist nur die Größe **entpackt** (§R11.1): ganz Österreich 1,83 MB in der Abendspitze (923 Züge, Donnerstag 17:08 Uhr),
etwa 1,2 MB um 22 Uhr (`docs/RADAR_TIMETRAVEL.md`, R12), rund 2 KB je Zug, weil jede Fahrt ihre Halte mitbringt. Die zwei Kacheln der Ebene
sind zusammen etwa eine solche Antwort.

| Lage | Antworten je Minute | entpackt je Minute | entpackt je Stunde |
|---|---|---|---|
| Ebene an, Züge (Standard), Abendspitze | 6 (drei Runden) | etwa 5,5 MB | etwa 330 MB |
| dasselbe um 22 Uhr (1,22 MB je Runde, R12) | 6 | etwa 3,7 MB | etwa 220 MB |
| schlimmster Fall nur Züge: „Jetzt aktualisieren“ dauernd getippt | 24 | etwa 22 MB | – |
| schlimmster Fall mit Bus, Bim oder U-Bahn: Kacheln am Limit geteilt | 24, je bis 1000 Fahrzeuge | etwa 40 bis 55 MB | – |

- **Auf der Leitung** ist es weniger: Die App bittet um gzip. Wie viel weniger, ist **nicht gemessen** (der Linux-`URLSession` des Tests
  sieht nur entpackte Bytes).
- **Zoomen spart nichts**, solange die Ebene an ist. Ohne die Ebene lädt das Radar in Wien nur die kleinen Kacheln des Ausschnitts; mit ihr
  immer ganz Österreich. Das ist der Preis von „keine Abhängigkeit vom Kartenausschnitt“ (Auftrag).
- **Die Wahl bleibt.** Ebenen werden je Gerät gespeichert (`map.layers`): Wer die Pünktlichkeit an lässt, lädt bei jedem Öffnen des Radars
  ganz Österreich. Bei geschlossenem Radar und im Hintergrund lädt nichts.
- **Bus, Bim, U-Bahn.** Die Ebene zählt nur Züge, die Anfragen folgen aber den Verkehrsmitteln des Radars (§1). Mit Bussen an ist jede
  Antwort größer (Wien allein: über 1000 Fahrzeuge, 1,67 MB, §R11.1 d), die Kacheln teilen sich, und das Budget von 24 je Minute wird voll
  genutzt: die letzte Zeile der Tabelle. Nicht geändert (die Busse bleiben auf der Karte, wie man sie eingeschaltet hat); ob die Ebene sie
  für ihre Dauer abschalten soll, ist eine Entscheidung des Owners.

**Langsames oder fehlendes Netz.** Das Zeitlimit des Clients sind 20 s **ohne Daten** (`URLRequest.timeoutInterval` ist die Zeit zwischen zwei
Datenpaketen, nicht die der ganzen Antwort; die ganze Antwort darf 60 s dauern, `timeoutIntervalForResource`). Gemessen wurden 0,4 bis 21,5 s
je Antwort; die 21,5 s waren die erste Anfrage mit Verbindungsaufbau und der größten Antwort, Rechenzeit des Servers und Übertragung sind nicht
getrennt gemessen. Ob es reicht, hängt also daran, wann das erste Byte kommt. Kommt es nach mehr als 20 s:

1. Die Anfrage endet mit Zeitüberschreitung, der Client fragt nach 1,5 s einmal nach (zählt in den 40).
2. Scheitert auch das, wartet diese Kachel 15 s, dann 30 s, … höchstens 2 Minuten; die andere läuft weiter. Die Züge der Kachel bleiben 60 s
   auf der Karte und in den Zahlen, das Panel sagt „Für einen Teil des Landes kam keine Antwort. Die Zahlen gelten für die geladenen Gebiete.“
3. Drei gescheiterte Anfragen in Folge öffnen den Schutzschalter: 2 Minuten keine ÖBB-Anfrage der ganzen App (auch Fahrplan und Abfahrten).
   Sind beide Kacheln ausgefallen, sagt das Panel „Das Radar pausiert. Die Zahlen sind vom letzten Stand.“, darunter steht „Radar pausiert“ mit
   „Erneut versuchen“; hat eine Kachel noch ihre Antwort, bleibt es beim Hinweis aus Schritt 2. „Erneut versuchen“ öffnet den Schutzschalter nicht:
   Die Anfrage endet vor der Drossel (`LiveHealth.check`), ohne Netz, und das Radar wartet weiter.

Es staut sich nichts: höchstens 3 Anfragen gleichzeitig, eine Kachel nie zweimal zugleich, eine Anfrage ohne Ausgang gibt ihre Kachel nach 90 s
frei. Ohne Netz ist `timetableUnavailable` `.offline`: Die Schleife endet, die Ebene lädt nichts und sagt, dass sie Live-Daten braucht.

**Akku.** Die Ebene hat keinen eigenen Zeitgeber, keinen `TimelineView`, keinen Display-Link und keine Animation, die von selbst weiterläuft. Was läuft:

- die eine Schleife des Radars (`RadarModel.run`, ein Schritt je Sekunde), nur solange das Radar sichtbar und die App aktiv ist
  (`scenePhase == .active`). Sie endet im Hintergrund, unter dem Cockpit und in der Zeitreise abseits von „Jetzt“; im Stromspar-Modus fragt sie
  nichts an (die Karte steht, das Radar sagt es);
- die Neuberechnung der Zahlen bei jeder Antwort und sonst alle 10 s (2 000 Züge unter 1 s im Linux-Debug-Build; auf dem Gerät nicht gemessen);
- die Überblendung: vier Schritte in 0,35 s nach einer Änderung, eine `Task`, die dann endet; mit „Bewegung reduzieren“ keine;
- das Warten auf ein zweites Tippen (0,28 s).

**Zurück aus dem Hintergrund.** Die Schleife beginnt neu. Beide Kacheln sind überfällig und werden **je einmal** gefragt (die zweite 1 s nach
der ersten); nichts wird nachgeholt oder wiederholt. Züge, deren Antwort älter als ihre Aufbewahrung ist (60 s bei Kacheln, die alle 20 s
kommen), sind weg. Bis Review 2 zählte eine so alte Antwort weiter als „geladen“: Kam nach Minuten die erste neue Antwort, zeigte das Panel die
Zahlen des halben Landes ohne Hinweis, und der Verlauf nahm sie als vollständigen Moment. Jetzt zählt der Scheduler solche Kacheln
(`RadarStatus.staleTiles`, dieselbe Regel wie `RadarFrameStore.prune`). Das Panel sagt „Für einen Teil des Landes ist die letzte Antwort zu alt.
Die Zahlen gelten für die übrigen Gebiete.“ (sind alle zu alt: „Die Daten sind zu alt und zählen nicht mehr. Neue Zahlen kommen mit der nächsten
Antwort.“), der Verlauf lässt den Moment aus, „Pünktlichkeitskarte teilen“ wartet, bis wieder alles frisch ist, und „Stand vor 4 Min“ zeigt das
Alter der ältesten Antwort, bis sie ersetzt ist. Dasselbe gilt nach dem Cockpit und nach dem Stromspar-Modus. Auch die Zeitreise nimmt eine so alte
Antwort nicht mehr als „jetzt“ (`RadarModel.holdsAllOfAustria`).

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
  Eine Position, die nicht auf der Erde liegt (nicht endlich, Breite über ±90°, Länge über ±180°), lässt den Zug aus der Rechnung weg (Review 1; vorher nur nicht endliche).
- **Ø Verspätung** ist der Mittelwert über die Züge mit 5 Minuten oder mehr. Der **Balken** hat vier Teile (pünktlich, 5 bis 15, über 15, ausgefallen), jeder
  ein Anteil der Züge mit Echtzeit-Daten.
- **Größte Verspätungen jetzt.** Die fünf Züge mit der größten Verspätung, nur solche ab 5 Minuten, bei gleicher Verspätung nach Fahrt-Id. Sind es
  weniger als fünf, steht weniger da; ist es keiner, steht das.
- **Brennpunkte.** Die drei Felder mit der größten **Summe der Verspätungsminuten** (zu frühe Züge zählen 0), unter den Feldern, die eine Farbe haben (mindestens 3 Züge mit
  Wert) **und** deren Median mindestens 5 Minuten beträgt (ein Feld mit zwölf Zügen, die vier Minuten zu spät sind, ist kein Brennpunkt, auch wenn die Summe hoch ist).
  Ein Feld höchstens zwei Schritte (etwa 27 km) neben einem besseren wird übersprungen: drei Brennpunkte sind drei Orte, nicht ein Korridor, der dreimal zählt (und ihre Nummern auf der Karte liegen nicht übereinander; mit „nur das Nachbarfeld“ lagen sie im ersten Screenshot übereinander). Der Name ist der häufigste nächste Halt der Züge
  im Feld („Raum Jenbach“, bei Gleichstand der erste im Alphabet); er sagt, wo das Feld ungefähr liegt, nicht, wo die Störung ist.
  Die Zahl neben dem Ort heißt **Median**, nicht Ø (Review 1: „Ø 25 Min“ behauptete einen Mittelwert, gerechnet ist der Median des Feldes); „Ø“ steht nur bei der Landeszahl, die ein Mittelwert ist.
- **Gebiet der Zahlen.** Das Rechteck des Radars enthält Teile von Bayern, Südtirol, Westungarn und der Slowakei (§R11.1). „Landesweit“ wäre falsch: Das
  Panel sagt „im Radar-Bereich: Österreich und angrenzende Gebiete“.
- **Unvollständig.** Sind Kacheln noch nicht da, ausgefallen oder abgeschnitten, sagt das Panel es („Die Zahlen gelten für die geladenen Gebiete“).

Der Hinweis unter den Zahlen sagt immer: Die Verspätung ist die Echtzeit-Verspätung, die die ÖBB für den nächsten Halt meldet (fehlt sie dort, die am letzten
Halt mit Wert), die Positionen sind berechnet, Züge ohne Echtzeit-Daten zählen nie als pünktlich, und die Zahl ist eine Momentaufnahme dieser App, **keine
Pünktlichkeitsstatistik der ÖBB** (Review 2: neben der Zahl, die die ÖBB veröffentlicht, läse sich „74 %“ sonst als Widerspruch oder als deren Zahl).

## 4. Darstellung

- **Überlagerung.** Jedes Feld ist ein paar `MapPolygon`: farbig drei verschachtelte Sechsecke: ein **Untergrund** (1,12×, weiß auf der hellen, Nachtblau auf der dunklen Karte), der Farbe auch auf
  dem grünen Land und den braunen Hügeln der Basiskarte lesbar macht und dem Feld einen schmalen Rand gibt (die ersten Screenshots zeigten grüne Felder auf grünem Land kaum), die Farbe als breiter blasser
  **Hof** (1,45×, der weiche Rand) und der **Körper** (0,92×, mit scharfer Linie); neutral ein Sechseck mit Rand. Ab etwa 28 pt Feldbreite (nah genug, dass man das Muster lesen kann) ist der Rand
  gestrichelt und ein Zickzack aus drei Diagonalen, eine `MapPolyline`, schraffiert ihn; auf dem Österreich-Zoom (18 pt) ist ein neutrales Feld ein blasser Umriss, das Muster wäre dort nur Rauschen. Die Überlagerungen liegen über den Straßen
  und unter den Beschriftungen der Karte (`mapOverlayLevel(.aboveRoads)`). Es gibt keine View je Zug und keine je Feld.
- **Obergrenze.** Höchstens `HeatLayer.maxDrawnCells` = **300** Felder, höchstens **900** Überlagerungen im Ruhezustand (farbig 3, neutral 2); gewählt werden zuerst die farbigen
  Felder mit den meisten Verspätungsminuten, dann die neutralen mit den meisten Zügen. Sortiert wird nach Id, die Zeichenreihenfolge ändert sich nicht. Ein Test
  mit 700 farbigen Feldern und einer mit 2 000 Zügen prüft die Grenze; die 2 000 Züge werden in unter einer Sekunde gerechnet (auch im Debug-Build).
- **Farbe.** Grün (`Theme.positive`) bis 3 Minuten, Orange (`Theme.summit`) von 7 bis 13, Rot (`Theme.negative`) ab 17, dazwischen linear. Die Übergänge
  liegen auf den Grenzen: bei 5:00 halb grün, halb orange; bei 15:00 halb orange, halb rot. Unter 5 Minuten gewinnt Grün, von 5 bis 15 Orange, darüber Rot (Test über das ganze
  Band). Die Stärke (0,55 bis 1) wächst mit der Zahl der Züge: drei Züge sind eine blasse Farbe, zwölf eine volle. Hell wie dunkel aus denselben Tokens; auf der dunklen Karte (und im
  Kartenstil „Dunkel“) sind es die hellen Dunkelmodus-Töne mit stärkerem Glühen, sie leuchten.
- **Überblendung.** Kommt eine Antwort, laufen die Farben in vier Schritten über `Motion.Duration.standard` (0,35 s, je 87,5 ms) vom alten zum neuen Stand; neue Felder blenden ein, weggefallene aus.
  Ein Feld, das grau wird oder eine Farbe bekommt, behält die Farbe seiner farbigen Seite (Review 1: es lief vorher über ein dunkles Zwischenbild, weil „keine Farbe“ Gewichte von 0 hat).
  MapKit-Überlagerungen kann SwiftUI nicht animieren, deshalb Schritte statt einer Feder. Mit „Bewegung reduzieren“ und in Screenshots erscheint der neue Stand sofort.
- **Eckpunkte nachgeschlagen.** Die Sechsecke ändern sich nie: Ihre Eckpunkte (als Kartenkoordinaten, fünf Größen je Feld) stehen in einer begrenzten Ablage (`RadarHeatGeometry.swift`, höchstens 8 000 Ringe und 2 000 Schraffuren, danach von vorn),
  statt bei jedem Neuaufbau der Karte (alle paar Sekunden) für bis zu 900 Ringe neu gerechnet zu werden (Review 1).
- **Züge als Punkte.** Mit der Ebene sind die Zugmarker kleine Punkte (grün, orange, rot nach Klasse; die Größe wächst mit der Verspätung, ausgefallene und Züge ohne Echtzeit sind
  offene Ringe), Gruppen ein kleiner Ring in der Farbe des schlechtesten Zuges (grau, wenn keiner Echtzeit-Daten hat) **ohne Zahl** (eine Zahl wie „265“ über Wien deckte die Felder zu; die Anzahl steht im gesprochenen Text, ein Tippen zoomt). Ein Tippen auf einen Punkt öffnet das Fahrt-Blatt wie vorher. Die Zahl der Marker bleibt die des Radars (höchstens etwa 130).
- **Brennpunkte** haben eine Nummer auf der Karte (1 bis 3), in einem **Sechseck** (Review 1: eine runde Zahl sah aus wie die Zahl einer Stationsgruppe der Stationen-Ebene).
- **Tippen auf ein Feld.** Ein Tippen auf die Karte (es wartet 0,28 s auf ein zweites: Ein Doppeltippen zoomt, und das soll kein Blatt auf- und zumachen; ein Tippen auf einen Zugpunkt, einen Ring oder eine Brennpunkt-Nummer zählt hier nicht, die haben ihre eigene Schaltfläche) sucht das Feld unter dem Finger, sonst das nächste mit Zügen innerhalb einer Fingerbreite (24 pt), mindestens ein Feld; es öffnet ein Blatt:
  Ort, mittlere Verspätung (oder warum das Feld keine Farbe hat), worauf es beruht und alle Züge im Feld, der späteste zuerst. Ein Zug öffnet das Fahrt-Blatt darüber. Das Feld hat einen Rahmen.

## 5. Panel, Bedienung, Zugänglichkeit

Ein Glas-Panel unten (über der Ebenen-Leiste), einklappbar. Es ist so hoch wie sein Inhalt, höchstens 40 % (zu) oder 62 % (auf, in den Zugänglichkeitsgrößen 80 %) der Karte (darunter bleibt Platz für die Ebenen-Leiste und eine Notiz: Review 1, vorher schob das offene Panel die Leiste, mit der man die Ebene wieder ausschaltet, aus dem Bild; der Satz „Zoom näher heran“ der Stationen entfällt, solange das Panel offen ist); was darüber hinausgeht, scrollt in der Karte. Das ist
nötig: In der größten Textgröße ist der Inhalt mehrere Bildschirme hoch, und eine so hohe Glasfläche wird gar nicht gezeichnet (Screenshots `radarHeatAX5`, Lauf 1: der Text lag ohne Karte auf der Karte). **Zu:** Überschrift „Pünktlich (unter 5 Min)“ mit der großen Zahl, der gestapelte Balken, „412 Züge mit Echtzeit-Daten, 38 ohne“ und
„Stand vor 12 s“ (das Alter der ältesten Antwort, gerechnet ab der Anfrage, wie in §R11.2). **Auf:** Legende mit Zahlen, Ø Verspätung, **Größte Verspätungen jetzt** (fünf Zeilen), **Brennpunkte** (drei Zeilen), der Satz zu grauen Feldern („Grau umrandet oder schraffiert“: auf dem Österreich-Zoom ist ein graues Feld nur ein blasser Umriss) und „Farbe in 95 von 154 Feldern mit Zügen“, Verlauf,
„Pünktlichkeitskarte teilen“ und die Hinweise (die Listen stehen vorn, weil sie das sind, wofür man das Panel öffnet).

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

**„Pünktlichkeitskarte teilen“ (Zusatz, gebaut).** Im offenen Panel gibt es „Pünktlichkeitskarte teilen“ (`ShareLink`). Das Bild (`RadarHeatShare`, `ImageRenderer`, 1080 × 1500 px, erst beim Export gerendert wie
`TktSharePass`) zeigt die Zellen auf nachtblauem Grund, ohne Apple-Basiskarte: die Fläche des Radar-Gebiets flach gezeichnet (Längengrad mit dem Kosinus der Breite), ein Glühen unter scharfen Sechsecken, graue Linien für Felder
ohne Farbe, dazu die große Zahl, der Balken, die Teile in Worten, „Stand 12. Nov. 2026, 17:08 Uhr“ und den Hinweis (Radar-Bereich Österreich und Grenzgebiete, Verspätung am nächsten Halt laut ÖBB-Echtzeit, Positionen berechnet, ohne
Echtzeit nie pünktlich, grau = zu wenige Züge, „Eine Momentaufnahme, keine Pünktlichkeitsstatistik der ÖBB“, „KlimaBilanz ist eine unabhängige App“). **Keine persönlichen Daten:** keine Fahrt, kein Zugname, kein Ort der Person, kein Konto, kein Logo. Das Bild ist immer dunkel.
„Stand“ ist die Zeit der ältesten Antwort hinter den Zahlen, nicht der Moment des Teilens (Review 2: vorher stand dort die Uhrzeit, zu der das Panel gezeichnet wurde, auch wenn die
Zahlen Minuten alt waren). Angeboten wird das Bild nur, wenn die Zahlen vollständig sind: jede Kachel hat geantwortet, keine ist ausgefallen, abgeschnitten oder zu alt. Ein Bild vom halben Land
ginge sonst ohne den Hinweis weiter, der das im Panel sagt.

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
| Fahrzeuge in der Antwort (`jnyL`) | 568 (am selben Tag um 17:08, in der Abendspitze, waren es 923: §R11.1) |
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

`-KBDemo`, kein Netz (`RadarHeatDemo.swift`): etwa 940 **erfundene** Fahrzeuge auf den erfundenen Korridoren des Radar-Demos (`ScottyDemoDense.swift`) und 46 dazu entlang des Inntals (das Demo hat dort wenige Züge, ohne sie bliebe der
Cluster grau), Verspätungen für die Szene gemacht: ein Verspätungs-Cluster über Tirol
(zwischen Arlberg und Kufstein 11 bis 36 Minuten, einige 4 bis 10), der Rest ruhig (fast alles pünktlich, wenige verstreute Verspätungen, einige ohne Echtzeit, einer ausgefallen). Kein echter Zug, keine echte Verspätung, keine echte Position.

| Szene | Zeigt |
|---|---|
| `radarHeat` | die Ebene über Österreich, Panel zu |
| `radarHeatPanel` | das Panel offen |
| `radarHeatLists` | das offene Panel, gescrollt zu den größten Verspätungen und den Brennpunkten |
| `radarHeatTrend` | das offene Panel, gescrollt zur Verlaufslinie (erfundene Punkte der letzten 6 Minuten: ein echter Verlauf braucht so lange ein offenes Radar) |
| `radarHeatCell` | die Karte nah an Tirol, das Blatt des größten Brennpunkts |
| `radarHeatAX5` | das offene Panel in der größten Textgröße |
| `radarHeatShare` | das Bild „Pünktlichkeitskarte teilen“ |

Tests (Linux, `swift test --package-path Packages/KlimaCore --no-parallel --filter Heat`): `HeatGridTests`, `RadarHeatTests`, `HeatPaintTests`, `RadarHeatTextTests`, `HeatHistoryTests`, dazu `MapLayersTests` (die neue Ebene
ist aus, ein gespeicherter Wert von vorher liest sich wie vorher). Geprüft: Zell-Ids und Randfälle des Rasters, die Grenzen der Klassen gegen `RadarDelay`, Median, Mindestzahl und die Regel „ohne Echtzeit nie pünktlich“, Rundung,
Rangfolge der Brennpunkte, leere und Teil-Antworten, Doppelte und fehlerhafte Positionen, Unabhängigkeit von der Reihenfolge der Züge, die Obergrenze für 2 000 Fahrzeuge, die Überblendung, und mit `HeatLoadTests`, dass die Ebene den Scheduler bei zwei Kacheln und 6 Anfragen je Minute hält (zehn simulierte Minuten, auch wenn die Karte jede Viertelsekunde dieselbe Ansicht meldet).
`HeatBudgetTests` (Review 2): kein Handgriff über 24 je Minute, 4 in 10 s und eine je Sekunde (Ebene an und aus, Hintergrund, „Jetzt aktualisieren“, Zeitreise), und eine Antwort, die älter als ihre Aufbewahrung ist, zählt als zu alt, bis die nächste kommt.

**Perf-Fall.** `radarHeat` in `PerfFeature` (`PerfFeatureScreens.swift`), `RadarHeatPerfTests` (`PerfTests/FeaturePerfTests.swift`) und die Tour-Liste in `scripts/perf_profile.sh`: dieselbe Karte mit der Ebene an (Demo-Szene `heat`), gepannt wie die anderen Karten. Der CI-Job `perf` läuft nur mit `[perf]` oder von Hand und dauert 55 bis 95 Minuten; er wurde für diese Arbeit **nicht** ausgelöst, es gibt also **keine Messung** und keine Baseline. `scripts/perf_compare.py` führt einen Bildschirm, der nur in einem Lauf vorkommt, als „neu“.

## 9. Geprüft und nicht geprüft

**Gesehen** (CI-Screenshots im Simulator, drei Läufe, hell und dunkel, Demo-Züge): die Ebene über Österreich, das geschlossene und das offene Panel, die gescrollten Listen, das Blatt eines Feldes mit Rahmen und Brennpunkt-Nummern,
das Panel in der größten Textgröße (`accessibility5`) und das Teilen-Bild. Der erste Lauf zeigte vier Fehler, die behoben sind: grüne Felder auf grünem Land (kaum zu sehen, auf der dunklen Karte gar nicht: jetzt Untergrund und Rand), Zahlen-Blasen über
den Feldern (jetzt kleine Ringe), ein Panel ohne Glasfläche in der größten Textgröße (jetzt begrenzte, scrollende Karte) und ein Demo-Hash, der ganze Reihen von Zügen auf einmal ausfallen ließ. Gelegentlich lädt die Basiskarte beim Aufnehmen nicht (beiger Raster ohne Kacheln);
dann fehlen auch die Felder, weil MapKit Überlagerungen kachelweise zeichnet (zweimal gesehen: `light-radarHeatPanel` in Lauf 2 und `light-radarHeatCell` in Lauf 3, jeweils nicht im Code begründet). Nicht gesehen: die Überblendung (Screenshots sind statisch),
der Verlauf (er braucht drei Punkte über eine Minute), das Teilen-Blatt selbst (nur das Bild), VoiceOver, Reduce Motion.

## 9a. Was nur auf einem iPhone zu prüfen ist

- Wie flüssig die Karte mit bis zu 900 Überlagerungen schiebt und zoomt (die CI-Screenshots zeigen den Stand, nicht die Bildrate); ob die vier Schritte der Überblendung flackern.
- Ob das Tippen auf die Karte das Zoomen mit zwei Fingern oder das Doppeltippen stört (die Geste läuft gleichzeitig mit denen der Karte).
- Wie das Glühen auf der dunklen und der hellen Karte bei Sonnenlicht und bei hoher Helligkeit aussieht.
- Die Laufzeit der Antworten im Mobilfunknetz (§R11) und der Akku bei einer Viertelstunde mit der Ebene an (Einstellungen › Batterie: Anteil der App).
- **Datenmenge auf der Leitung** (§1a, nur entpackt gemessen): In Einstellungen › Mobilfunk den Wert bei KlimaBilanz notieren, 10 Minuten das Radar mit
  der Ebene auf dem Österreich-Zoom offen lassen (nur Züge), dann wieder ablesen. Erwartet: deutlich unter 55 MB (entpackt), wie viel darunter,
  sagt gzip. Danach dasselbe einmal in Wien herangezoomt: Mit der Ebene darf es nicht weniger sein (keine Abhängigkeit vom Ausschnitt).
- **Zurück aus dem Hintergrund** nach mehr als einer Minute: Erst steht „Die Daten sind zu alt …“ (oder „Für einen Teil des Landes …“) und „Stand vor
  … Min“, dann kommen beide Kacheln je einmal, die Zahlen wieder vollständig, kein Stoß von Anfragen, kein Sprung im Verlauf.
- **Langsames Netz** (falls in den Entwickler-Einstellungen der Network Link Conditioner zu sehen ist, Profil „Very Bad Network“; sonst ein schwaches
  Mobilfunknetz): die Hinweise in der Reihenfolge von §1a, kein Hängen der Karte; nach dem Schutzschalter funktioniert der Fahrplan nach 2 Minuten wieder.
- **Stromspar-Modus:** keine neuen Zahlen, der Hinweis „Stromspar-Modus“, „Jetzt aktualisieren“ holt einmal beide Kacheln.
- VoiceOver auf dem Gerät: Reihenfolge und Ansagen des Panels.

## 10. Nicht gebaut, Grenzen

- Ein Verlauf über Sitzungen und eine Karte vergangener Verspätungen: Es gibt keine Historie, nur den Moment.
- Korridore als Zusammenfassung von Feldern: Brennpunkte sind Felder (§3).
- Die Verspätung am nächsten Halt ist nicht die Ankunftsverspätung am Ziel; ein Zug kann sie aufholen oder vergrößern.
- Das Raster ist fest 0,12°. Auf dem Österreich-Zoom sind dünn befahrene Strecken neutral, weil dort weniger als drei Züge je Feld fahren (§7 hat die Zahl).
- Das Rechteck des Radars enthält Grenzgebiete (§3).

## 11. Review 1 (Korrektheit, Robustheit, Leistung, Gestaltung, Zugänglichkeit)

Gefunden und behoben:

- **Busse und Bims zählten als „Züge“.** Mit Bus oder Bim bei den Verkehrsmitteln rechnete die Ebene alles mit („412 Züge mit Echtzeit-Daten“ über Busse). Jetzt nur `ProductMask.rail` (Züge und S-Bahnen); der Hinweis im Panel sagt es, und
  ist nur ein Nicht-Zug-Modus an, steht dort, was einzuschalten ist (§1).
- **„Ø 25 Min“ für einen Median.** Bei den Brennpunkten und im Feld-Blatt hieß der Median „Ø“ bzw. „Mittlere Verspätung“; jetzt „Median“ (§3).
- **Ebene an ohne Live-Daten: keine Erklärung.** Ohne Zustimmung (oder offline) passierte beim Einschalten von „Pünktlichkeit“ nichts sichtbar, weil der Hinweis „Züge brauchen Live-Daten“ nur bei der Zug-Ebene stand. Er steht jetzt auch bei der Pünktlichkeit.
- **Ebenen-Leiste aus dem Bild.** Das offene Panel (62 %) plus Satz „Zoom näher heran“ plus Leiste war höher als der Bereich unten (78 %): die Leiste, mit der man die Ebene ausschaltet, lag unter dem Bildschirmrand (CI-Bilder `radarHeatPanel`, `radarHeatLists`). Der Bereich wächst jetzt mit (§5).
- **Verlauf mit halbem Land.** Der Verlauf nahm auch Momente, in denen erst eine der zwei Kacheln geantwortet hatte; der Anteil sprang dann wegen des fehlenden Gebiets, nicht wegen der Pünktlichkeit. Jetzt nur vollständige Antworten (alle Kacheln da, keine ausgefallen, keine abgeschnitten).
- **Dunkler Zwischenschritt in der Überblendung.** Ein Feld, das grau wurde oder eine Farbe bekam, lief über Gewichte der Farben, die zusammen weniger als 1 ergaben (dunkel statt blass). Jetzt behält es die Farbe der farbigen Seite; Test dafür.
- **Positionen außerhalb der Erde.** Eine endliche, aber irrsinnige Breite (1e300) wäre in `Int(rq)` abgestürzt; solche Züge fallen jetzt aus der Rechnung, `HeatGrid.cell(containing:)` gibt für sie nur noch die Ursprungszelle (Tests).
- **Tippen auf einen Zug öffnete vielleicht auch ein Feld.** Die Tipp-Geste der Karte läuft neben den Schaltflächen der Marker; ein Tipp auf einen Zugpunkt, einen Ring oder eine Brennpunkt-Nummer lässt sie jetzt aus. Und: Ein Doppeltippen (Zoom) öffnete mit dem ersten Tipp ein Blatt; die
  Auswahl wartet jetzt 0,28 s auf ein zweites Tippen. Beides nur auf einem iPhone zu bestätigen (§9a).
- **Ein Sechseck-Raster neu gerechnet, alle paar Sekunden.** Siehe §4, „Eckpunkte nachgeschlagen“. Die Karte setzt ihren Inhalt bei jedem Neuaufbau der Ansicht neu zusammen; die Ringe sind jetzt Nachschläge, die Berechnung läuft einmal je Feld.
- **Texte.** „Gezählt wird … Österreich und angrenzende Gebiete“ nennt jetzt Züge und S-Bahnen und sagt, dass Busse, Bims und U-Bahnen nicht zählen; „Grau schraffiert“ (auf dem Österreich-Zoom stimmte es nicht, dort ist ein graues Feld ein Umriss) heißt „Grau umrandet oder schraffiert“; das Teilen-Bild sagt
  „Graue Umrisse“ (es zeichnet keine Schraffur). Die Dauer der Überblendung kommt aus `Motion.Duration.standard`.
- **Brennpunkt-Nummer sah aus wie eine Stationsgruppe.** Auf der dunklen Karte glichen die weißen Kreise der Brennpunkte den Zahlen der Stationsgruppen (CI-Bild `dark-radarHeatCell`); die Nummern sind jetzt Sechsecke.
- **Teilen-Bild.** Die Felder dafür werden einmal je Antwort berechnet (`RadarHeatModel.drawnCells`), nicht in jedem Neuaufbau des Panels.

Geprüft und in Ordnung: die Klassengrenzen gegen `RadarDelay` (5:00 ist verspätet, 15:00 noch „5 bis 15“), Median und Mindestzahl (3 Züge mit Wert, nicht 3 Züge), „ohne Echtzeit nie pünktlich“, die Rundung (nie 100 % bei einem verspäteten Zug, nie 0 % bei
einem pünktlichen), Reihenfolge der Züge ändert nichts, Brennpunkte mindestens drei Schritte auseinander, 6 Anfragen je Minute und keine zweite Schleife (`HeatLoadTests`), `RadarModel.run` endet mit der Ansicht und die Überblendung mit der Ebene,
der Standardbildschirm des Radars (Ebene aus) ist bis auf den fünften Chip der Ebenen-Leiste und eine Tipp-Geste, die nur bei eingeschalteter Ebene etwas tut, unverändert.

Nicht behoben, mit Grund:

- Die Chips der Ebenen-Leiste sind bei fünf Titeln nicht gleich breit (jeder hat die Breite seines Textes plus gleichen Anteil des Rests). Gleiche Breiten bräuchten ein eigenes Layout; die Chips sind lesbar und tippbar.
- Bei der größten Textgröße (`accessibility5`) füllt die obere Leiste des Radars (Suche, Verkehrsmittel: vorhanden vor dieser Ebene) fast die halbe Karte, und die Ebenen-Leiste ist nur durch Scrollen im Bereich unten zu erreichen. Das ist die Gestaltung des Radars, nicht der Ebene.
- Tippen auf die Kompass- oder Standort-Schaltfläche der Karte kann bei eingeschalteter Ebene ein Feld in der Nähe öffnen (die Geste läuft neben den Steuerelementen der Karte). Nur auf einem iPhone zu sehen.

## 12. Review 2 (ÖBB-Regeln, Budget, Datenmenge, Ehrlichkeit, Akku)

Geprüft am Code, nicht am Gerät. Ergebnis in §1a; hier, was sich geändert hat:

- **Halbes Land nach dem Hintergrund.** Eine Antwort, deren Züge die Aufbewahrung schon verlassen hatten, zählte weiter als „geladen“. Nach Minuten im
  Hintergrund (oder unter dem Cockpit, im Stromspar-Modus) zeigte das Panel mit der ersten neuen Antwort die Zahlen einer Hälfte ohne Hinweis, der Verlauf
  nahm sie als vollständig, und die Zeitreise nahm die alte Antwort als „jetzt“. Jetzt `RadarStatus.staleTiles` mit Hinweis, Verlauf, Teilen und Zeitreise
  danach (§1a, Tests `HeatBudgetTests`, `RadarHeatTextTests`). Eingeschaltet nach längerer Pause rechnet die Ebene nicht mehr mit Zügen von vor Minuten
  (`refreshHeat` räumt den Speicher zuerst).
- **„Stand“ im Teilen-Bild** war die Uhrzeit des Zeichnens, nicht die der Daten; jetzt die der ältesten Antwort. Das Bild gibt es nur bei vollständigen Zahlen (§6).
- **Keine ÖBB-Statistik.** Panel, Feld-Blatt und Teilen-Bild sagen, dass die Zahl eine Momentaufnahme dieser App ist; der Hinweis nennt auch den Rückgriff
  auf den letzten Halt mit Echtzeit-Wert (§3).
- **Grüner Ring ohne Echtzeit.** Ein Gruppenring war grün, sobald kein Zug darin verspätet oder ausgefallen war, auch wenn keiner Echtzeit-Daten hatte.
  Jetzt ist er dann grau wie der offene Ring eines einzelnen Zuges ohne Echtzeit; grün nur, wenn mindestens ein Zug pünktlich gemeldet ist.
- **„im Mittel“** im leeren Brennpunkte-Satz behauptete einen Mittelwert; die Regel ist der Median. Jetzt: „Gerade kein Gebiet mit mindestens 3 Zügen mit
  Echtzeit-Daten und einem Median von 5 Minuten Verspätung oder mehr.“
- **Datenmenge, Wiederholungen, langsames Netz, Akku** standen nicht im Dokument: §1a, mit dem schlimmsten Fall je Minute.
- **Messung (§7) gegen das Protokoll des Live-Tests geprüft:** alle Zahlen stimmen (568, 446/122, 331/67/48/0, 74 %, 18,9 Min, 60 s, 298/46/252, 219, 30,
  167/78/45/8, 36/8/2). „Am Abend vorher“ hieß „fünf Stunden vorher am selben Tag“ und ist korrigiert. Im Repository liegen keine Fahrzeugdaten: Der Test
  druckt nur Zahlen, die Demo-Züge sind erfunden.

Geprüft und in Ordnung: Tor, Notschalter und Drossel auf jedem Weg (die Ebene hat keinen eigenen), das Budget bei jedem Handgriff (§1a), abgebrochene
Anfragen geben die Kachel frei und behalten den Platz im Budget, kein Zeitgeber und keine Animation läuft im Hintergrund oder bei geschlossenem Radar,
„Positionen berechnet“ und „ohne Echtzeit nie pünktlich“ in Panel, Feld-Blatt und Bild, keine Behauptung von GPS oder gemessener Position.

Nicht geändert, mit Grund:

- Mit Bus, Bim oder U-Bahn an lädt die Ebene ganz Österreich mit allen Fahrzeugen, obwohl sie nur Züge zählt (bis etwa 40 bis 55 MB je Minute entpackt,
  §1a). Die Busse auf der Karte abzuschalten wäre eine Entscheidung über die Bedienung: Owner.
- Die Überblendung baut bei jeder Änderung bis zu 900 Überlagerungen viermal neu (§4). Ob das auf dem Gerät Akku kostet, zeigt nur ein iPhone (§9a).
- Ein Gruppenring ist orange, wenn ein Zug darin 5 Minuten oder mehr zu spät ist, auch bei 40 Minuten (die Gruppe kennt nur „verspätet“); die Zahlen in
  Panel und Feld-Blatt sagen es genau.
