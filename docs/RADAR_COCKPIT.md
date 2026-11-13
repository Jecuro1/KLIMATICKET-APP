# KlimaBilanz · Cockpit-Ansicht („Die Kamera folgt deinem Zug“)

Owner-Idee: „Die Kamera folgt deinem Zug schräg in 3D, mit nächstem Halt, Ankunft und Verspätung.“ Auf dem Zug-Radar (`docs/OEBB_LIVE.md` §R, §R7, §R11)
öffnet das Fahrt-Blatt eines Zuges den Knopf **„Cockpit“**. Er öffnet eine Vollbild-Ansicht: Die Karte steht schräg hinter und über dem Zug, dreht mit der
Fahrtrichtung mit und zeigt die Strecke voraus, gefärbt nach Verspätung. Unten steht ein Glas-Panel mit dem nächsten Halt, der Ankunft, der Verspätung, der
Entfernung, dem Fortschritt der ganzen Fahrt und einer Geschwindigkeits-Schätzung.

**Jede Position ist berechnet, nicht gemessen.** Die ÖBB rechnet die Position aus Fahrplan und Echtzeit-Meldungen (`trainPosMode` CALC, `docs/OEBB_LIVE.md` §R1);
es ist keine GPS-Ortung. Die Geschwindigkeit ist die Geschwindigkeit dieses berechneten Punkts, über etwa eine Minute geglättet, kein Tacho. Das steht im
Cockpit selbst (Info-Knopf im Panel, Wort „geschätzt“ hinter jeder Geschwindigkeit), nicht nur hier.

**Code.** Reine Logik in KlimaCore (`Packages/KlimaCore/Sources/KlimaCore/Live/Cockpit/`, Linux-Tests in `Tests/KlimaCoreTests/Live/Cockpit/`), Oberfläche in
`App/Sources/Features/Radar/Cockpit/`. Die Ansicht hat keine eigene Anfrage-Logik: Sie nutzt `RadarService`, `TimetableService` und das Budget des Radars.

| Datei | Inhalt |
|---|---|
| `CockpitPath.swift` | Winkel (kurze Seite, Mischen), Zielpunkt auf der Kugel, `CockpitPath`: Linienzug mit Kilometern, Punkt bei km, Richtung voraus, Projektion im Fenster, Ausschnitt |
| `CockpitRoute.swift` | die Fahrt als Strecke: Halte entlang der Polylinie (sonst Luftlinie), Lage des Zuges, nächster Halt, Fortschritt, Färbung je Teilstück, Linien zum Zeichnen |
| `CockpitCamera.swift` | Kamera-Planer: Abstand nach Geschwindigkeit, Neigung, Blickpunkt voraus, Richtungsfilter; Regler, der die Kamera gleiten lässt |
| `CockpitSpeed.swift` | Geschwindigkeits-Schätzung aus zwei Antworten, geglättet; „steht“ und „unbekannt“ |
| `CockpitSession.swift` | Zustandsautomat: wartet, folgt, frei, Position verloren, Fahrt beendet |
| `CockpitSummary.swift` | die Zahlen des Panels: nächster Halt, Gleis, Ankunft, Verspätung, Entfernung, Fortschritt, Halte-Striche, Flaggen |
| `CockpitText.swift` | alle deutschen Texte (getestet), auch der VoiceOver-Satz und der Teilen-Text |
| `CockpitFeed.swift` | Zusammenführen von Radar und JourneyDetails, Anfrage-Kasten, Zeitplan der Anfragen, Bild (`CockpitFrame`, `CockpitMarker`) |
| `Cockpit/CockpitModel.swift` | die eine Schleife, Veröffentlichen für die Ansichten, Fluggeräte der Kamera |
| `Cockpit/CockpitView.swift`, `CockpitMap.swift`, `CockpitHUD.swift` | Vollbild, Karte mit Marker und Flaggen, Panel, Schalter, Banner |
| `Cockpit/RadarView+Cockpit.swift` | Haken ins Radar: Start mit dem Zug, den das Radar kennt |
| `Cockpit/CockpitDemo.swift` | erfundener Zug auf erfundener Strecke und die CI-Szenen |

Ins Radar greifen nur wenige Zeilen: der Knopf im Fahrt-Blatt (`RadarTripSheet.swift`), das Vollbild und der angehaltene Radar-Takt (`RadarView.swift`).

## 1. Bedienung

**Einstieg.** Zug auf dem Radar antippen, im Fahrt-Blatt „Cockpit“. Das Blatt schließt, die Vollbild-Ansicht öffnet, die Kamera fliegt von der Karte des Radars
(gleiche Mitte, gleicher Ausschnitt) zum Zug. Unter „Reduce Motion“ und in Screenshots ist die Kamera gleich da. **„Mein Zug“**: Eine Ebene dieses Namens gibt es nicht
(die Ebenen sind Stationen, Züge, Pünktlichkeit, Störungen, Routen). Dafür steht der Einstieg nur im Fahrt-Blatt; ein Einstieg von „Live verfolgen“ aus ist nicht gebaut.

**Drei Kameras** (gläserner Schalter oben, die Auswahl gleitet):

| Ansicht | Kamera |
|---|---|
| **Verfolgen** | hinter und über dem Zug, Neigung 68° (steht) bis 60° (200 km/h und mehr), Blickrichtung aus der Strecke 0,6 km voraus, Abstand `1,5 km + 26 m je km/h` (1,5 bis 8,5 km): ein schneller Zug wird weiter draußen gezeigt. Der Blickpunkt liegt `7 s` Fahrt (0,15 bis 1,4 km) vor dem Zug, damit der Zug im unteren Teil des Bildes sitzt |
| **Vogelperspektive** | senkrecht von oben, Norden oben, Abstand 2,2 × der Verfolgen-Abstand (3,5 bis 16 km) |
| **Frei** | die Kamera gehört dir: schieben, zoomen, drehen. „**Zurück zum Zug**“ erscheint und fliegt zurück (1,4 s) |

Ein Finger auf der Karte macht die Ansicht sofort zu „Frei“ (`MapCameraPosition.positionedByUser`). „Zurück zum Zug“ geht in die Ansicht davor (Verfolgen oder
Vogelperspektive). Bei den größten Schriftgrößen sind die drei Ansichten ein Menü.

**Die Kamera bewegt sich weich.** Die Richtung ist ein Tiefpass: Sie dreht den kurzen Weg zum Ziel, nie schneller als 28° pro Sekunde, mit einer Zeitkonstante von 1,6 s.
Die Richtung kommt aus der Strecke 0,6 km voraus, nicht aus dem Stück unter dem Zug, deshalb dreht die Kamera schon vor der Kurve. Abstand (2,4 s), Neigung (0,8 s) und
Blickpunkt (0,4 s) gleiten ebenso; ein Wechsel der Ansicht ist deshalb ein Schwenk, kein Sprung. Die Kamera wird 20-mal je Sekunde (Stromspar-Modus: 8-mal) gesetzt.

**Was auf der Karte steht.** Der Zug als leuchtende Platte: sein Linien-Zeichen auf Glas, Rahmen und Schein in der Farbe der Verspätung, ein Pfeil in Fahrtrichtung (relativ zur
Kamera: beim Verfolgen nach vorn; drehst du die Karte in „Frei“, dreht der Pfeil mit), ein Haltezeichen, wenn er steht. Der Ring um die Platte atmet nur, solange der Zug fährt;
steht er an einem Halt oder am Ende seiner Fahrt, hält er still. Die Strecke voraus ist je Teilstück zwischen zwei Halten nach der Verspätung am Ende des Teilstücks gefärbt:
**grün** (unter 5 Minuten), **orange** (5 Minuten und mehr), **rot** (ausfallender Halt oder ganze Fahrt), **grau** (keine Echtzeit). Hinter dem Zug ist die Strecke dünn und grau.
Die nächsten vier Halte sind Flaggen mit Name und Ankunftszeit, die übrigen Halte Punkte, passierte gedimmt. Andere Fahrzeuge sind **nicht** zu sehen: Nur der verfolgte Zug bewegt sich.
Hat die Auskunft keine Strecke geliefert oder passt sie nicht zu den Halten (ein Halt weiter als 2 km daneben), sind es gerade Linien zwischen den Halten; ein Hinweis unter dem Schalter
sagt „Luftlinie zwischen den Halten“ (und der Info-Text des Panels, warum).

**Bildausschnitt.** Kopfzeile, Schalter und Banner oben und das Panel unten liegen im sicheren Bereich der Karte (wie beim Radar): MapKit setzt die Mitte der Kamera
in den freien Teil dazwischen, die Karte selbst reicht unter das Glas bis an den Rand. Beim Verfolgen liegt der Blickpunkt voraus, der Zug also etwas unter der Mitte des
freien Teils, nie unter dem Panel, auch bei AX5. (Erste CI-Screenshots, Lauf 43336170151: Die Karte füllte den ganzen Bildschirm, der Zug saß am oberen Rand des Panels und war bei
AX5 ganz darunter.)

**Das Panel (unten).**

- „Nächster Halt“ (oder „Ziel“) groß, das Gleis daneben („Gl. 4“, orange umrandet bei Gleiswechsel). Am Ziel: „Ziel erreicht“ über dem Namen des Halts (`CockpitText.headline`).
- Die Ankunftszeit groß, daneben der Verspätungs-Chip (`pünktlich`, `+4 min`, `−2 min`, `Fällt aus`, `Keine Echtzeit`) und der Countdown („in 12 Min“, „gleich“). Ziffern rollen.
  Hat der nächste Halt **keine eigene Echtzeit**, ist die Zeit die Planzeit. Trägt der Chip dann die Verspätung eines früheren Halts („+7 min“), steht statt des Countdowns
  „laut Fahrplan“ (ein Countdown zur Planzeit wäre um die Verspätung zu kurz), VoiceOver sagt „Ankunft laut Fahrplan 21:02 Uhr, zuletzt 7 Minuten verspätet“, „Teilen“ schreibt
  „Ankunft laut Fahrplan 21:02 (zuletzt +7 min)“ (`CockpitSummary.delayIsCarried`, `CockpitText.arrivalNote`, Review 2). Sonst heißt „21:06 (+4 min)“ immer: erwartet um 21:06, vier Minuten später als geplant.
- Eine Zeile Phase unter dem nächsten Halt: „Unterwegs“, „Hält in X · weiter um 14:07“, „Steht in X · Abfahrt 14:05“, „Dieser Zug fällt aus“. Ohne nächsten Halt steht die Phase
  groß und die Zeile entfällt (keine Wiederholung derselben Wörter, `CockpitText.subline`).
- Der Fortschritt der **ganzen** Fahrt als Leiste: gefüllt bis zum Zug, ein Strich für jeden Halt, an dem der Zug hält, der Zug als leuchtender Punkt.
- „noch 18 km“ (Entfernung entlang der Strecke zum nächsten Halt), „ca. 118 km/h · geschätzt“ (nur wenn der Zug fährt; stehend oder ohne Schätzung steht nichts da),
  „Stand vor 8 s“ (Alter der letzten Antwort mit der Position) und ein Info-Knopf („Woher die Zahlen kommen“: berechnete Position, keine GPS-Ortung; die Marke zeigt, wo der Zug
  vor etwa 20 bis 40 Sekunden war, `CockpitText.markerNote`; wie die Geschwindigkeit entsteht). Eine Zeile, wenn sie passt; sonst Entfernung und Geschwindigkeit
  über dem Alter; sonst jedes für sich. Solange nur die vier Halte des Radars da sind (vor der ersten Antwort von `JourneyDetails`), steht keine Entfernung da: Entlang der
  Kette aus vier Halten wäre sie geraten.
- Drei Aktionen: **Aussteige-Wecker** (öffnet das Wecker-Blatt dieses Zuges, `docs/EXIT_ALARM.md`; der Wecker ist auf main; endet der Zug vorzeitig, beginnt das Blatt mit dem
  Halt, an dem die Fahrt endet, nicht mit dem abgesagten letzten, `CockpitRoute.shortTurnEndID`), **Live verfolgen** (`LiveFollowTracker`, danach „Wird verfolgt“),
  **Teilen** (Text mit Linie, nächstem Halt und Ankunft, **ohne** Koordinaten und ohne Fahrt-ID, z. B. „RJX 66 nach Salzburg Hbf: nächster Halt Linz Hbf, Ankunft 20:13 (+6 min). Live verfolgt mit KlimaBilanz.“;
  am Ziel „RJX 66 hat Salzburg Hbf erreicht.“). Ist der Zug am Ziel, die Fahrt beendet oder abgesagt, entfallen Wecker und „Live verfolgen“: Es bleibt „Teilen“.

**Zustände** (`CockpitSession`, getestet):

```
wartet ──Antwort mit Position──▶ live ──2 Minuten Fragen ohne Position──▶ verloren ──Antwort mit Position──▶ live
wartet / live / verloren ──Zug am letzten Halt, oder Fahrplan seit 5 Minuten zu Ende──▶ beendet (endgültig)
Kamera: Verfolgen ⇄ Vogelperspektive; Finger auf der Karte → Frei; „Zurück zum Zug“ → die Ansicht davor
```

- **Keine Position mehr** (verloren): die Marke bleibt, wo sie war, grau und ohne Schein (der Ort, an dem der Zug zuletzt war, keine Live-Position), ebenso der Punkt auf der Fortschritts-Leiste, ein Banner sagt, warum („Die Auskunft meldet den Zug gerade nicht“, wenn Antworten kommen, oder „Keine Verbindung zu ÖBB“,
  wenn nichts mehr kommt) und seit wann, mit „Erneut versuchen“. Die Anfragen laufen langsamer weiter (alle 30 s), der Zug kann wiederkommen. Die zwei Minuten zählen nur,
  solange das Cockpit fragt (`CockpitSession.pauseLostClock`, Review 2): Zeit im Hintergrund, im Stromspar-Modus oder ohne Live-Daten ist kein Zeichen, dass der Zug fehlt, und
  „Keine Verbindung zu ÖBB“ wäre dann falsch.
- **Alte Position** (Review 2): Ist die letzte Position älter als zwei Minuten, ohne dass der Zug verloren ist (zurück aus dem Hintergrund, Stromspar-Modus, ohne Live-Daten),
  ist die Marke ebenso grau und ohne Schein, „Stand vor 5 Min“ steht im Panel, und die Position wird sofort gefragt; mit der Antwort bekommt die Marke ihre Farbe zurück
  (`CockpitFrame.isStale`). Am Ende der Fahrt bleibt sie farbig: Dort sagt das Banner, was los ist.
- **Fahrt beendet**: Der Zug steht am letzten Halt, oder er fehlt seit 45 s im Radar, war zuletzt in den letzten 6 km seiner Fahrt und die Ankunftszeit am Ziel steht in höchstens zwei Minuten an oder ist
  schon erreicht (ein angekommener Zug wird aus dem Radar genommen). „Fehlt“ heißt: Eine Antwort nach seiner letzten Position hat ihn nicht genannt (`CockpitSession.lastMissingAt`). Die Zeit allein
  reicht nicht (Review 2: Zurück aus dem Hintergrund nach fünf Minuten war die Fahrt sonst endgültig beendet, bevor überhaupt gefragt war). **Letzter Halt** ist der letzte, an dem der Zug hält (`CockpitRoute.endIndex`): Sind die letzten Halte abgesagt
  („Zug endet in Linz“), endet die Fahrt dort. Dieser Halt ist dann „Ziel“, der Fortschritt endet bei ihm, und die abgesagten Halte danach sind nur eine rote Linie, nie „nächster Halt“.
  (Review 1: Vorher war der abgesagte letzte Halt „Ziel“ mit Ankunftszeit und Verspätung, und ein Zug, der am vorgezogenen Endhalt stand, „hielt“ dort und ging nach zwei Minuten verloren.) Banner „Fahrt beendet · Der Zug hat X erreicht“ mit „Schließen“, keine Anfragen mehr. Der Punkt des Halts unter der Marke wird nicht gezeichnet (MapKit
  ordnet Annotationen selbst und legte ihn in einem Screenshot über den Zug); das gilt für jeden Halt, an dem der Zug steht oder gerade vorbeifährt. Ein Zug, der mitten auf der Strecke verschwindet, ist **nicht** beendet, sondern verloren.
- **wartet**: Die erste Antwort steht aus („Suche den Zug …“).

**Bedienungshilfen.** VoiceOver liest das Panel als **ein** Element mit einem Satz („RJX 66 nach Salzburg Hbf. Nächster Halt Linz Hbf, Gleis 4. Ankunft 20:13 Uhr, 6 Minuten verspätet, in 25 Minuten. Noch 37 Kilometer.
50 Prozent der Strecke. Etwa 118 Kilometer pro Stunde, geschätzt. Stand vor 8 Sekunden.“) mit dem Merkmal „aktualisiert sich häufig“ und der Aktion „Woher die Zahlen kommen“ (der Info-Knopf liegt im selben Element); die Aktionen sind eigene Elemente. Solange nur die vier
Halte des Radars da sind, nennt der Satz weder Entfernung noch Prozent der Strecke. Die Karte ist für VoiceOver
ausgeblendet (sie sagt nichts, was das Panel nicht sagt). **Dynamic Type bis AX5**: Das Panel behält den Halt, die Ankunft mit Chip und Countdown (untereinander), die Phase, wenn der Zug steht, und ein Menü „Aktionen“;
„Unterwegs“, Fortschritt, Entfernung, Geschwindigkeit und Alter entfallen im Bild, stehen aber im VoiceOver-Satz; „Woher die Zahlen kommen“ steht im Menü „Aktionen“ und öffnet
sich als Blatt, das scrollt. Der Verspätungs-Chip wächst bis AX2 mit (vorher fest 15 pt: bei AX5 das Kleinste im Panel). Der Schalter wird ein Menü. Die Banner (verloren, beendet,
Stromspar-Modus) wachsen wie Kopfzeile und Schalter bis AX1 mit. Szene `radarCockpitLostAX5` (Lauf 43433688316): Banner und Panel sind ganz lesbar und überdecken sich nicht, von der Karte
bleibt bei AX5 mit Banner aber nur ein Streifen, die graue Marke liegt unter dem Panel. Bewusst so: Bei der größten Schrift hat der Text Vorrang vor der Karte. Kopfzeile (Linie, Ziel auf bis zu zwei Zeilen)
und Schalter wachsen bis zur Größe AX1 mit, wie die Leisten von iOS; der Schließen-Knopf behält sein Symbol in seinem Kreis und zeigt es bei langem Drücken groß (Large Content Viewer). **Reduce Motion**: kein Flug, kein Schwenk, keine pulsierende Marke: eine feste Ansicht von oben
(Norden oben), die Kamera folgt dem Zug einmal je Sekunde ohne Animation. Solange „Verfolgen“ gewählt ist, sagt ein Hinweis unter dem Schalter
„Bewegung reduzieren ist an: Die Kamera schaut fest von oben, Norden oben.“, damit der Schalter nichts verspricht, was die Kamera nicht tut. Farbe ist nie der einzige Träger: Chip-Text, Wörter im Banner, Flaggen-Zeiten. Haptik: ein fester Schlag (`snap`), wenn der nächste Halt wechselt; Auswahl beim Schalter.

## 2. Messung (einmalig, vom Owner freigegeben)

Frage: Hat die Antwort von `JourneyDetails` eine Polylinie, wie groß ist sie, was kostet die Aktualisierung des Cockpits, und was sagen zwei Radar-Antworten über den Takt?

- **Budget:** höchstens 3 Anfragen, mindestens 2 s Abstand (gebaut: 2,1 s), ehrlicher User-Agent (`KlimaBilanz/live-test (iPhone; iOS; private, low-volume)`), keine Wiederholung, Stopp beim ersten Fehler.
  **Verbraucht: genau 3, alle HTTP 200.**
- **Test:** `Tests/KlimaCoreTests/Live/LiveSmoke/RadarCockpitLiveTests.swift`. Lauf:
  `KB_LIVE_TESTS=1 KB_RADAR_COCKPIT=1 swift test --package-path Packages/KlimaCore --no-parallel --filter RadarCockpitLiveTests`. Zwei Schalter mit Absicht: Ein Lauf mit `--filter LiveSmoke` verbraucht
  die Anfragen nicht. Gedruckt werden Zahlen, Größen, Abstände und JSON-Schlüsselnamen: keine Fahrt-ID, keine Linie, kein Haltname, keine Koordinate. Nichts davon ist im Repository gespeichert.
- **Zeitpunkt:** Freitag 2026-11-13, 00:58 Uhr Wien (tiefe Nacht, wenige Züge; Nachtzüge und die letzten Regionalzüge). **Ort:** eine Cloud-Sandbox über einen Ausgangs-Proxy, nicht ein iPhone.

| # | Anfrage | HTTP | Antwort (entpackt) | ms | Inhalt |
|---|---|---|---|---|---|
| 1 | `JourneyGeoPos`, Korridor Wien–Salzburg (48,40 / 13,00 / 47,70 / 16,50), Schiene, `maxJny` 1000 | 200 | 82 920 Byte | 1 629 | 31 Fahrzeuge (2 675 Byte je Fahrzeug); 10 davon unterwegs zwischen zwei Halten, nicht ausfallend, mit mindestens 3 Halten |
| 2 | `JourneyDetails` mit `getPolyline` für eines davon | 200 | 18 429 Byte | 198 | 13 Halte, **alle 13 mit Echtzeit**, **Polylinie mit 617 Punkten** (123,1 km), **`pos` vorhanden**; Alter der Echtzeit-Daten 29 s |
| 3 | `JourneyGeoPos`, Kasten um den Zug (11,1 × 11,2 km), nur seine Produktklasse (16) | 200 | 3 160 Byte | 239 | 1 Fahrzeug (der Zug), 4 Halte, alle 4 mit Echtzeit |

Antwort 2, Schlüssel von `res`: `common`, `fpB`, `fpE`, `journey`, `planrtTS`; Schlüssel von `journey`: `date`, `dirL`, `dirTxt`, `isRchbl`, `jid`, `msgL`, `polyG`, `pos`, `prodL`, `prodX`, `resLDrawStyleX`,
`sDaysL`, `status`, `stopL`, `subscr`, `sumLDrawStyleX`, `trainStartDate`. Zusammen 104 509 Byte.

Was daraus folgt:

1. **Die Polylinie ist da und passt.** Alle 13 Halte liegen auf ihr (`CockpitRoute` lag sie ohne Luftlinie darüber; Länge des Linienzugs 123,1 km = Länge der Fahrt von Halt 1 bis 13). Die Position aus Antwort 1 lag **0 m** neben ihr:
   Der Server legt die berechnete Position auf die Strecke. Deshalb setzt die App die Marke bei höchstens 300 m Abstand auf die Linie (nur Darstellung) und rechnet den Kilometer der Fahrt aus der Projektion.
2. **`JourneyDetails` hat eine eigene Position (`pos`).** Sie wird nur benutzt, wenn der Radar den Zug länger als 40 s nicht gemeldet hat (zwei Quellen für denselben Moment ließen die Marke hin- und herspringen),
   und sie gilt für die Zeit ihrer **Anfrage** (`TripDetails.fetchedAt`): Der Client gibt dieselbe Antwort 60 s lang aus seinem Zwischenspeicher, auch an das Cockpit, das kurz nach dem Fahrt-Blatt fragt (Review 2).
   Ob `pos` und die Radar-Position zur selben Zeit gleich sind, ist **nicht** gemessen.
3. **Der kleine Kasten ist billig.** 3 160 Byte statt 18 429 Byte für `JourneyDetails` (und statt 82 920 Byte für den Korridor). Der Filter auf die eigene Produktklasse lässt andere Züge im Kasten weg
   (im Kasten fuhr nur dieser eine Zug der Klasse; in der ersten Antwort war es derselbe). Die Radar-Antwort bringt dazu die Halte mit den frischesten Verspätungen: vier von vier mit Echtzeit.
   Darum fragt das Cockpit den **kleinen Kasten alle 20 s** und `JourneyDetails` nur am Anfang und danach alle 3 Minuten (bei verlorenem Zug alle 45 s).
4. **Takt.** Zwischen Antwort 1 und 3 (3,9 s) bewegte sich der Zug um 130 m: 120 km/h, der Fahrplan rechnet 113 km/h auf diesem Abschnitt. Die Positionen werden also **für die Zeit der Anfrage gerechnet**, nicht alle 20 s
   eingefroren; eine Aktualisierung alle 20 s liefert jedes Mal eine frische Position. Der Zeitstempel der Echtzeit-Daten (`planrtTS`) war in Antwort 1 28 s alt, in Antwort 3 3 s: Die Echtzeit-Daten ändern sich öfter
   als alle 20 s. **Nicht gemessen:** der Takt über längere Zeit (es sind zwei Antworten, nicht eine Reihe), die Streuung zwischen Zügen und Tageszeiten, ein schneller Fernverkehrszug (der gemessene Zug ist ein Regionalzug), die Größe auf der Leitung.

## 3. Daten und Budget

Solange das Cockpit offen ist, ist der Radar-Takt **für den ganzen Ausschnitt angehalten** (der Radar unter dem Vollbild hört auf, sein Zeitplan und alle seine Anfragen enden mit der Aufgabe; beim Schließen
läuft er wieder an). An seiner Stelle fragt das Cockpit **einen** Zug:

| Anfrage | Wann | Was | Größe (Messung) |
|---|---|---|---|
| Radar, kleiner Kasten | alle 20 s (verloren: 30 s) | Kasten ±5 km um den Zug (breiter, je älter die Position und je schneller der Zug, höchstens ±30 km), nur seine Produktklasse: Position und die vier Halte mit Verspätung | 3 160 Byte |
| `JourneyDetails` | sofort, dann 3 Minuten nach der Antwort (verloren: 60 s) | alle Halte mit Echtzeit, Polylinie, `pos` | 18 429 Byte |

- **Budget:** Beide gehen durch **dasselbe Budget wie der Radar** (`RadarScheduler.claimSlot`: höchstens 24 je Minute, 4 in 10 s, nie zwei innerhalb einer Sekunde). Das Cockpit braucht rund **3,3 Anfragen je Minute**
  (3 Positionen + 0,33 `JourneyDetails`), verloren 3 (2 Positionen + 1 `JourneyDetails`); der Rest des Budgets bleibt frei. Ein Limit (429) oder ein offener Schutzschalter pausiert Cockpit und Radar zusammen.
  Die eine Wiederholung des Clients nach einem Timeout oder einem 502/503/504 (`HafasClient`, nach 1,5 s) zählt **nicht** in diesen 24, aber in den 40 je Minute der ganzen App (`RequestThrottle`): im
  schlimmsten Fall also 6,7 Anfragen je Minute auf der Leitung. Was keine Geste mehr Anfragen macht (Review 2, im Code nachgesehen): Öffnen und Schließen in schneller Folge (jedes Cockpit fragt durch das Budget
  des Radar-Modells darunter, das über `RadarBudgetLedger` auch Schließen und Öffnen des Radars überdauert), Wechsel der Kamera (keine Anfrage), Hintergrund und Vordergrund in schneller Folge (eine abgebrochene
  Anfrage ist im Plan des Cockpits wieder fällig, ihr Platz im Budget bleibt verbraucht, sie kann den Server erreicht haben), „Erneut versuchen“ und „Jetzt aktualisieren“ in Serie (eine Anfrage je Antwort,
  durch das Budget), zwei Cockpits (der Vollbild-Deckel hat Platz für eines). Ein Treffer im 60-s-Zwischenspeicher des Clients (`JourneyDetails`) braucht einen Platz im Budget, aber keine Anfrage.
- **Datenmenge** (entpackt; `/gate` packt nach §R11.1 von `docs/OEBB_LIVE.md` nicht, auf der Leitung ist es also etwa gleich viel, für diese Antworten aber nicht einzeln gemessen):
  - **Normal:** 3 × 3,2 KB + 0,33 × 18,4 KB ≈ **16 KB je Minute**, rund **0,9 MB je Stunde** (3 × 60 × 3,2 KB + 20 × 18,4 KB). Gemessen ist eine Antwort mit einem Fahrzeug.
  - **Schlimmster Fall (Rechnung, keine Messung):** Der Kasten wächst mit dem Alter der Position bis ±30 km (60 × 60 km, nach etwa 5 bis 6 Minuten ohne Position, wenn auch `JourneyDetails` keine
    bringt) und nennt alle Fahrzeuge der eigenen Klasse; hat die Linie keine Klasse, alle Schienenfahrzeuge. Ein solcher Kasten um Wien enthält höchstens so viele Züge wie das ganze Achtel Wien und Umland
    (78 × 145 km, rund 155 Schienenfahrzeuge, gerechnet in §R11.1 von `docs/OEBB_LIVE.md`), bei etwa 2 KB je Fahrzeug also höchstens rund **300 KB je Antwort**; verloren alle 30 s: **höchstens rund
    0,6 MB je Minute** plus 18 KB `JourneyDetails`. Beim Verfolgen ist der Kasten höchstens rund 13 × 13 km (300 km/h, Position 40 s alt), ein kleiner Teil davon. Zum Vergleich: Der ganze Österreich-Radar
    holt 1,8 MB alle 20 s (5,4 MB je Minute), und er steht, solange das Cockpit offen ist.
- **Einwilligung und Schalter:** Ohne Einwilligung, mit ausgeschalteten Live-Daten oder gesetztem Kill-Switch gibt es keine Anfrage (`LiveDataService.radar`/`timetable` sind dann nil); die Ansicht sagt es („Live-Daten sind aus …“).
  Diese drei entscheiden beim Öffnen; ein Kill-Switch, der danach mit der Fern-Konfiguration kommt, erreicht den Client selbst (`LiveError.disabled`, ohne Anfrage). Die **Verbindung** wird vor jeder Anfrage
  neu gefragt (`CockpitModel.Services.live`, Review 2): Offline geöffnet, fragte das Cockpit vorher nie wieder, auch wenn die Verbindung zurückkam. Jetzt scheitert die Anfrage ohne Netz sofort,
  weicht aus (15 s, 30 s, 60 s, 2 Minuten) und kommt mit der Verbindung wieder; „Erneut versuchen“ fragt sofort.
  Stromspar-Modus: keine Anfragen, ein Banner mit „Jetzt aktualisieren“. Nichts läuft im Hintergrund: Verlässt die App den Vordergrund (auch nur kurz, etwa für das Kontrollzentrum), endet die
  Schleife mit allen Anfragen, und die Karte bekommt keine Kamera mehr. Zurück im Vordergrund ist die Position nach mehr als zwei Minuten grau und wird sofort gefragt, einmal, durch das Budget.
- **Langsames Netz:** Eine Anfrage wartet höchstens 20 s auf Daten (`timeout` des HAFAS-Profils, die Zeit zwischen zwei Datenpaketen, nicht die ganze Antwort), höchstens 60 s im Ganzen; danach versucht es
  der Client einmal nach 1,5 s. Die gemessenen 21 s gehören zur Antwort für ganz Österreich (1,8 MB, §R11.1); die Antworten des Cockpits sind 3 bis 18 KB und kamen in 0,2 s. Solange eine Anfrage unterwegs ist,
  fragt das Cockpit dieselbe Art nicht noch einmal, bis 150 s (länger als der Client im schlimmsten Fall braucht: 131,5 s; vorher 90 s, dann fragte es eine langsame Antwort doppelt). Schlägt sie fehl, weicht es aus;
  nach zwei Minuten ohne Position sagt das Banner „Keine Verbindung zu ÖBB“.
- **Antworten zwischen zwei Antworten.** Die Marke läuft **nicht** der Uhr nach, sondern `RadarEstimate` (§R7): Sie zeigt den Zug um das Intervall zwischen den letzten zwei Antworten (mindestens 20 s) zurück und
  bewegt ihn linear von der vorigen zur letzten Position, danach steht sie. Nichts wird vorhergesagt. Daraus folgt: die Marke hinkt der Wirklichkeit um 20 bis 40 s hinterher; „Stand vor X s“ im Panel ist das Alter der
  letzten Antwort, nicht der Marke. Die Marke wird auf die Strecke gesetzt (bei höchstens 300 m Abstand), die Zahlen im Panel (Entfernung, Fortschritt) gehören zur Marke.

## 4. Wie gerechnet wird

**Die Strecke** (`CockpitRoute`). Die Halte von `JourneyDetails` (ohne Koordinate oder ohne Zeit entfallen) werden nacheinander auf die Polylinie projiziert; jeder Halt bekommt einen Kilometer. Liegt ein Halt mehr als 2 km neben
der Polylinie oder in falscher Reihenfolge, wird die Polylinie nicht benutzt und die Strecke ist der Linienzug der Halte (`isStraightLine`). Halte ohne Halt des Zuges (`passesWithoutStop`) und abgesagte Halte
sind nie „nächster Halt“.

**Wo der Zug ist.** Die Lage kommt aus der **Position**, die Zeiten entscheiden nur, ob er steht: Am letzten Halt (höchstens 80 m davor) ist er angekommen; höchstens 350 m neben einem Halt, an dem er hält, ist er dort, wenn die Ankunft
erreicht und die Abfahrt noch nicht erreicht ist (am ersten Halt: bis zur Abfahrt); vor der Ankunftszeit ist er noch im Anflug; sonst ist er zwischen zwei Halten unterwegs.

**Ankunft und Verspätung.** Ankunft = Echtzeit, sonst die Planzeit (nichts wird vorhergesagt). Verspätung = die gemeldete des nächsten Halts, sonst die des letzten Halts davor mit Meldung (Verspätungen laufen die Fahrt entlang weiter, wie im Radar, `RadarDelay.currentDelay`),
sonst keine („Keine Echtzeit“, grau). **5 Minuten und mehr** sind „spät“ (orange), die Regel des Radars (`RadarDelay.lateThresholdSeconds`). Der Chip zeigt die Zahl in Minuten (gerundet), grün bis 4 Minuten.
Der Countdown entfällt, wenn die Ankunftszeit mehr als zwei Minuten zurückliegt (dann stimmen Zeit und Position nicht mehr zusammen; die Zeit bleibt stehen), und wenn die Zeit die Planzeit ist,
die Verspätung aber von einem früheren Halt kommt: Dann steht dort „laut Fahrplan“ (§1). Die Entfernung ist die Strecke entlang der Linie.

**Zusammenführen.** Der Radar liefert die vier Halte (Start, zuletzt verlassen, nächster, Ziel) mit den frischesten Verspätungen alle 20 s, `JourneyDetails` alle Halte alle drei Minuten. Ein Ereignis des Radars ersetzt das der Details, wenn
es für dieselbe Planzeit eine Echtzeit oder eine Absage hat; eine Antwort ohne Echtzeit löscht nie eine Verspätung (`CockpitMerge`). Bis `JourneyDetails` da ist, zeigt das Panel den nächsten Halt und seine Zeit (aus den vier Halten); Strecke und
Fortschritt erscheinen erst mit der vollen Fahrt, weil der Fortschritt mit vier Halten nicht stimmen würde.

**Geschwindigkeit.** Weg zwischen zwei Antworten (entlang der Strecke, wenn bekannt) durch die Zeit dazwischen, bei Antworten ab 3 s Abstand; über 40 s Zeitkonstante geglättet; eine Zeit von mehr als 150 s zwischen zwei Antworten oder über
350 km/h verwirft die Schätzung; ein Halt (unter 2 km/h) zeigt „steht“, und nach einem Halt beginnt die nächste Schätzung neu; ist die letzte Antwort älter als 90 s, ist sie unbekannt. In beiden Fällen zeigt das Panel nichts.

**Anfrage-Kasten und Zeitplan** (`CockpitRequestPlan`, `CockpitScheduler`). Der Kasten ist mindestens 10 × 10 km (der Zug schafft in 20 s bei 250 km/h 1,4 km), wächst mit Alter und Geschwindigkeit und wird auf die Marke und die letzte Antwort
aufgespannt. Der Zeitplan fragt die Position zuerst, dann die Details; Fehler weichen aus (15 s, 30 s, … bis 2 Minuten), ein hängendes Anfrage-Fenster wird nach 150 s frei, ein Abbruch macht die Anfrage sofort wieder fällig.
Die nächsten Details zählen ab der Antwort, nicht ab der Anfrage: So ist die nächste nie die Kopie aus dem 60-s-Zwischenspeicher des Clients (verloren alle 60 s; vorher 45 s ab der Anfrage, und jede zweite war diese Kopie).

## 5. Gestaltung

Panel und Banner: `frostedCard` (Inhalt, `DESIGN.md` §2; beim Banner läuft die Strecke direkt darunter, durch klares Glas kreuzte sie die Wörter), Glas nur für Bedienelemente (Schließen, Schalter, Aktionen, Linien-Chip). Typografie: Halt 30 pt Rounded Bold, Ankunft 36 pt Rounded Bold mit `monospacedDigit` und `numericText`, alles skaliert
(`@ScaledMetric`). Farben nur aus `Theme` (Verspätungs-Töne: `positive`, `summit`, `negative`, grau; kleiner Text in den Text-Varianten `positiveText`, `summitText`, `negativeText`). Bewegung nur über `Motion`-Tokens
(`snappy` für den Schalter, `smooth` für Banner und Rückkehr-Knopf, `number` für Ziffern); der Kamera-Flug ist die eigene Animation von MapKit (2,0 s hin, 1,4 s zurück). Die Marke pulsiert nur über `pulsingHalo`
(`ContinuousMotionReader`: nur sichtbar, nie bei Reduce Motion, Stromspar-Modus oder in Screenshots).

## 6. Tests, Demo, CI

- **Linux-Tests** (`Tests/KlimaCoreTests/Live/Cockpit/`, 152 Fälle): Winkel, Linienzug (Länge, Punkt, Richtung um die Ecke, Projektion im Fenster bei einer Haarnadel, Ausschnitt), Strecke (Halte auf der Polylinie, Luftlinie, Lage:
  vor Abfahrt, zwischen, hält, im Anflug, angekommen, nicht bediente Halte, Färbung, Fortschritt), Kamera (Abstand und Neigung nach Geschwindigkeit, Blickpunkt voraus, Ziel je Ansicht, Reduce Motion, Richtung ohne Strecke,
  Regler: kein Peitschen an der Kurve, kurze Seite über Norden, Konvergenz, Schwenk statt Sprung), Geschwindigkeit (zwei Antworten, Glättung, Halt, Neustart, alt, Lücke, Sprung, doppelte und ältere Antwort, Streckenkilometer), Zustandsautomat
  (verloren nach 2 Minuten, zurück, Grund, beendet, endgültig, frei und zurück), Zahlen und Texte (Verspätungsregeln, Countdown, Entfernung, VoiceOver-Satz, Teilen-Text ohne Koordinaten, große Zeile und Zeile darunter ohne Wiederholung), Zusammenführen, Kasten, Zeitplan (Takt, Budget von 3 bis 3,7 je Minute,
  Ausweichen, Pause, Abbruch, Rückkehr), Feed (Marke zwischen zwei Antworten mit dem Nachlauf des Radars, Geschwindigkeit, Verspätung bis in die Zusammenfassung, ältere Antworten, Ende, Verschwinden nahe dem Ziel oder mitten auf der Strecke),
  Review 1: ein Zug, der vorzeitig endet (Ziel, Fortschritt, Ende am letzten bedienten Halt, rote Linie danach, Halt für den Wecker), die vorläufige Zusammenfassung ohne Entfernung und Prozent.
  Review 2 (13 neue Fälle, §8): Hintergrund und Stromspar-Modus machen den Zug nicht „verloren“, eine Pause beendet „verloren“ nicht, eine Antwort, die den Zug kennt, ist kein Beleg für sein Verschwinden,
  eine Antwort aus dem Zwischenspeicher gilt für die Zeit ihrer Anfrage, eine ältere Position ersetzt nie eine neuere, zurück aus dem Hintergrund nahe dem Ziel endet die Fahrt erst nach einer Antwort,
  graue Marke ab zwei Minuten, Details verloren alle 60 s ab der Antwort, keine doppelte langsame Anfrage, „laut Fahrplan“ und „zuletzt“. Dazu in `HafasErrorTests`: `fetchedAt` auch aus dem Zwischenspeicher.
- **Live-Test** (`RadarCockpitLiveTests`, nicht in der CI): §2.
- **Szenen** (`-KBScreenshot <name> -KBDemo YES`, ein erfundener Zug auf einer erfundenen Strecke zwischen Wien und Salzburg, Zeiten relativ zu „jetzt“, kein Netz): `radarCockpit` (Verfolgen), `radarCockpitBird`, `radarCockpitFree`
  (mit „Zurück zum Zug“), `radarCockpitAX5`, `radarCockpitEnded`, `radarCockpitLost`, `radarCockpitLostAX5` (verloren bei der größten Schrift: Banner und Panel teilen sich den Bildschirm). Die fahrenden Szenen beginnen mit drei Antworten im Abstand von 20 s (wie das Cockpit nach
  40 s), deshalb steht eine Geschwindigkeits-Schätzung im Panel; die Szene „verloren“ hat eine Antwort von vor 2,5 Minuten und keine Schätzung. Die Verspätungen schrumpfen entlang der Fahrt (7, 6, 4, 2 Minuten): voraus erst orange, dann grün.

## 7. Review 1 und was nur ein iPhone zeigt

**Review 1** (Korrektheit, Robustheit, Leistung, Gestaltung, Bedienungshilfen) hat außer den oben genannten Punkten geändert:

- Die Schleife des Cockpits schickt ihre Anfragen in eine Aufgaben-Gruppe, die erledigte Anfragen sofort vergisst (`withDiscardingTaskGroup`); die vorige Gruppe hielt jede erledigte Anfrage bis zum Schließen fest (rund 200 je Stunde).
- Die Kamera wird der Karte nur gegeben, wenn sie sich um mehr als ein Haar bewegt (10 cm, ein Hundertstel Grad): Steht der Zug, zeichnet die Karte nicht mehr 20-mal je Sekunde neu. Ist die Fahrt beendet und die Kamera
  zur Ruhe gekommen, läuft die Schleife nur noch einmal je Sekunde.
- `CockpitFeed.tick` rechnet für die Frage „am Ende?“ nur noch die Lage des Zuges, nicht ein ganzes Bild mit Zusammenfassung und Texten.

**Auf dem iPhone prüfen** (die CI-Screenshots zeigen ein stehendes Bild aus dem Simulator):

- Die Kamera beim Verfolgen: gleitet sie 20-mal je Sekunde ohne Ruckeln, dreht sie vor Kurven weich mit, und zeichnet die Karte die Strecke dabei ohne Flackern (die Inhalte der Karte werden bei jedem Schritt neu ausgewertet)?
- Der Wechsel Verfolgen ⇄ Vogelperspektive (ein Schwenk), der Flug beim Öffnen (2 s) und „Zurück zum Zug“ (1,4 s).
- Ein Finger auf der Karte, während die Kamera fährt: wird die Ansicht sofort „Frei“, ohne dass die Kamera einen Schritt zurückspringt?
- Neigung und Gelände (`elevation: .realistic`) bei 1,5 bis 8,5 km Abstand; Akku und Wärme nach 20 Minuten Verfolgen.
- VoiceOver: wird der Satz des Panels höflich aktualisiert, ohne zu stören, und ist die Aktion „Woher die Zahlen kommen“ erreichbar? Reduce Motion: feste Ansicht von oben, keine Bewegung.

## 8. Review 2: Zugang, Budget, Datenmenge, Ehrlichkeit, Akku

Review 2 hat den Code und diese Datei mit einem anderen Blick gelesen als Review 1: Kommt jede Anfrage durch die Einwilligung, den Kill-Switch und das Budget, kann eine Geste das Budget sprengen,
wie viele Daten fließen, ist jede Zahl und jedes Wort im Cockpit wahr, und läuft etwas, wenn niemand hinschaut. Keine neue Live-Anfrage; die Zahlen in §2 sind gegen das Protokoll des Live-Tests
geprüft (alle gleich: 82 920 / 18 429 / 3 160 Byte, 1 629 / 198 / 239 ms, 31 Fahrzeuge, 13 Halte mit Echtzeit, 617 Punkte, 123,1 km, 0 m, 3,9 s, 130 m, 120 und 113 km/h, 28 s und 3 s). Im Repository liegen keine
Fahrzeugdaten: Die Tests und die Demo nutzen erfundene Züge.

**In Ordnung, ohne Änderung:** Jede Anfrage geht durch `LiveDataService` (Einwilligung, Schalter, Kill-Switch) und zusätzlich durch die wirksame Konfiguration des Clients (`LiveError.disabled` ohne Anfrage);
jede durch einen Platz im Budget des Radars (24 je Minute, 4 in 10 s, eine je Sekunde) und durch `RequestThrottle` (40 je Minute für die App); ein Limit oder ein offener Schutzschalter pausiert Cockpit und Radar;
ehrlicher User-Agent des Clients; keine Koordinaten und keine Fahrt-ID im Teilen-Text; „geschätzt“ hinter jeder Geschwindigkeit, „keine GPS-Ortung“ im Info-Text; „Keine Echtzeit“ statt „pünktlich“ ohne Meldung.
Akku: die Schleife hängt an `.task(id: scenePhase == .active)` und endet mit dem Vordergrund, die Marke atmet nur über `ContinuousMotionReader` (nur sichtbar, nie im Stromspar-Modus); kein Timer, kein Display-Link,
keine `TimelineView`.

**Gefunden und behoben** (Tests in §6):

1. **Eine Antwort aus dem Zwischenspeicher galt als Position von jetzt.** `HafasClient` gibt `JourneyDetails` 60 s lang aus seinem Zwischenspeicher. Das Cockpit fragt beim Öffnen sofort danach, meist wenige
   Sekunden nach dem Fahrt-Blatt, und bekam dessen Antwort. Es stempelte sie mit der Zeit des Aufrufs: War die Radar-Position älter als 40 s, nahm es die `pos` der alten Antwort als Position von jetzt,
   „Stand vor 0 s“ war um bis zu eine Minute falsch, die Geschwindigkeit zu klein, und die frische Radar-Antwort derselben Runde wurde als „älter“ verworfen. Verloren fragte es alle 45 s, jede zweite Antwort
   war diese Kopie, und sie hielt einen verlorenen Zug „live“. Jetzt trägt `TripDetails.fetchedAt` die Zeit der Anfrage, auch aus dem Zwischenspeicher; das Cockpit stempelt damit, zählt die nächsten Details ab der
   Antwort (verloren alle 60 s), und eine ältere Position ersetzt nie eine neuere.
2. **Zeit ohne Fragen machte den Zug „verloren“ und beendete Fahrten.** Zurück aus dem Hintergrund nach Minuten (oder nach zwei Minuten Stromspar-Modus) stand sofort „Keine Position mehr · Keine Verbindung
   zu ÖBB“, obwohl nichts gefragt war, und ein Zug, der zuletzt nahe am Ziel war, galt als angekommen, endgültig, vor der ersten neuen Antwort. Jetzt zählen die zwei Minuten nur, solange das Cockpit fragt,
   „angekommen nach Verschwinden“ braucht eine Antwort ohne den Zug, und eine Position älter als zwei Minuten ist grau, bis die Antwort kommt (einmal, sofort, durch das Budget).
3. **Offline geöffnet, fragte das Cockpit nie wieder.** Die Dienste wurden beim Öffnen festgelegt; ohne Verbindung gab es keine, auch nicht, wenn sie zurückkam. Jetzt wird die Verbindung vor jeder Anfrage gefragt.
4. **Eine langsame Anfrage wurde nach 90 s doppelt gestellt**, obwohl der Client bis 131,5 s antworten kann. Jetzt 150 s, wie beim Radar.
5. **Eine Planzeit mit der Verspätung eines früheren Halts** stand da wie eine erwartete Zeit („21:02 +7 min · in 15 Min“, der Zug kommt aber um etwa 21:09). Jetzt „laut Fahrplan“ statt des Countdowns,
   „zuletzt“ in VoiceOver und im Teilen-Text, „Ankunft laut Fahrplan“ auch ohne jede Echtzeit.
6. **Doku:** Datenmenge je Minute im Normal- und im schlimmsten Fall, Leitung gegen entpackt, die Wiederholung des Clients, langsames Netz, was keine Geste mehr Anfragen macht (§3).

**Nicht geändert, mit Grund:** Der Kasten wächst verloren bis ±30 km (§3, schlimmster Fall rund 0,6 MB je Minute bei Wien): Er findet einen Zug wieder, dessen `JourneyDetails` keine Position bringt, und bleibt weit
unter dem Radar, der in dieser Zeit steht. Die Schleife läuft auch bei stehendem Zug 20-mal je Sekunde (Stromspar-Modus 8-mal); sie rechnet dann nur die Lage, die Karte bekommt keine neue Kamera (Review 1).
Ein Wechsel der Verbindung weckt das Cockpit nicht sofort: Nach dem Ausweichen (bis 2 Minuten) oder mit „Erneut versuchen“ fragt es wieder.

**Auf dem iPhone prüfen** (zusätzlich zu §7):

- Anfragen je Minute: Die App zeigt keine Zählung an. Belegt sind die Grenzen (24 und 40 je Minute) durch Tests und Code; auf dem Gerät nur mit einem Werkzeug am Mac (Xcode-Instrument „Network“
  oder ein Proxy): 10 Minuten Cockpit, erwartet etwa 3 bis 4 Anfragen je Minute an `fahrplan.oebb.at`, nie mehr als 24; mit „Live verfolgen“ zusammen unter 40.
- Mobilfunk-Datenverbrauch der App (iOS Einstellungen › Mobilfunk) vor und nach 30 Minuten Cockpit: Die Anfragen an ÖBB sind rund 0,5 MB (§3, auf der Leitung nicht gemessen). Die Karte lädt ihre
  Kacheln und das Gelände über MapKit selbst; das zählt mit und ist bei der schrägen 3D-Karte wahrscheinlich viel mehr (nicht gemessen).
- Cockpit offen, App 5 Minuten in den Hintergrund, zurück: Marke grau mit „Stand vor 5 Min“, nach etwa einer Sekunde farbig an der neuen Stelle; kein Banner „Keine Position mehr“ dazwischen.
- Stromspar-Modus an, 3 Minuten warten: Banner „Stromspar-Modus“, Marke grau, kein „Keine Verbindung zu ÖBB“; „Jetzt aktualisieren“ holt genau eine Position.
- Flugmodus an, Cockpit aus dem Radar öffnen, Flugmodus aus: spätestens nach 2 Minuten (oder sofort mit „Erneut versuchen“) bewegt sich der Zug wieder.
- Akku und Wärme: 20 Minuten Verfolgen am Akku, danach 20 Minuten Cockpit im Hintergrund: im Hintergrund kein Verbrauch durch die App (iOS Einstellungen › Batterie).
