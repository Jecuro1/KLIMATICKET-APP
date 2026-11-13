# KlimaBilanz · Radar-Zeitreise („Wo sind die Züge in 1 oder 2 Stunden?“)

Owner-Idee: „Ein Regler zeigt, wo die Züge in 1 oder 2 Stunden sind.“ Auf dem Zug-Radar (`docs/OEBB_LIVE.md` §R, §R7, §R11) sitzt unten ein Uhr-Chip
**„Jetzt“**. Er klappt zu einer Glaskarte auf: ein großer Zeitwert, ein Regler von **30 Minuten zurück bis 3 Stunden voraus** in Fünf-Minuten-Schritten,
„Zurück zu Jetzt“, ein Zeitraffer (1 Sekunde = 5 Minuten, auch doppelt so schnell) und die Zeilen darüber, was an dem Bild stimmt. Solange die Zeit nicht „jetzt“ ist,
steht oben ein Band **„Zeitreise · Prognose aus dem Fahrplan“**.

**Jede Position ist berechnet, nicht gemessen.** Sie kommt aus dem Fahrplan, den Verspätungen, die **jetzt** bekannt sind, und aus Momentaufnahmen, die die Auskunft für andere
Zeiten berechnet hat. Spätere Verspätungen sind nicht vorhergesagt. Der Rückblick (bis 30 Minuten) ist ebenfalls berechnet und keine Aufzeichnung. Das steht in der Karte, nicht nur hier.

**Code.** Reine Logik in KlimaCore (`Packages/KlimaCore/Sources/KlimaCore/Live/Radar/`, Linux-Tests in `Tests/KlimaCoreTests/Live/Radar/`), Oberfläche in
`App/Sources/Features/Radar/Time/`.

| Datei | Inhalt |
|---|---|
| `RadarProjection.swift` | `RadarSchedule` (Halte mit Zeiten und Verspätung), Zusammenführen mehrerer Antworten, `RadarRunPath` (Wegpunkte, Position zur Zeit T), Anker, `RadarRoute` (Polylinie) |
| `RadarTimeline.swift` | Momentaufnahmen je Fahrt, Verdichtung, Speichergrenzen, Pins zur Zeit T, Spur der letzten 10 Minuten, Alter der Verspätungen |
| `RadarTimeScheduler.swift` | Plan der Momentaufnahmen, Reihenfolge, Momentaufnahme für die ruhende Minute, Fehler, Grenzen, Datenmenge |
| `RadarTimeAxis.swift` | Zeitachse, Zeitraffer, Gleiten, alle deutschen Texte, Tageslicht |
| `RadarScheduler.swift` (Haken) | `claimSlot`, `pause`: ein Platz im Budget des Radars für Anfragen, die keine Kachel sind |
| `Time/RadarTimeModel.swift` | Zustand, die eine Schleife, Pins, Spur, Prüfung auf Mobilfunk |
| `Time/RadarTimeScrubber.swift`, `RadarTimePanel.swift` | Regler, Chip und Karte, Band, Himmelstönung |
| `Time/RadarView+Time.swift`, `RadarModel+Time.swift` | Haken in Radar-Ansicht und -Modell |
| `Time/RadarTimeDemo.swift` | erfundene Züge mit Fahrplan und die CI-Szenen |

## 1. Was die Auskunft liefert (R12, einmalige Messung)

Frage: Was antwortet `JourneyGeoPos` für eine andere Zeit, und was steckt in einer Antwort?

- **Budget:** höchstens 6 Anfragen insgesamt, ehrlicher User-Agent, mindestens 2 s Abstand (2,1 s), keine Wiederholung, Stopp bei 403/429. **Verbraucht: 5, alle HTTP 200.**
- **Test:** `Tests/KlimaCoreTests/Live/LiveSmoke/RadarTimeLiveTests.swift`. Lauf:
  `KB_LIVE_TESTS=1 KB_RADAR_TIME=1 swift test --package-path Packages/KlimaCore --no-parallel --filter RadarTimeLiveTests/testMeasureTimeTravel`. Zwei Schalter mit Absicht:
  ein Lauf mit `--filter LiveSmoke` verbraucht diese Anfragen nicht. Gedruckt werden nur Zahlen und Abstände in Kilometern: keine Fahrzeuglisten, keine Fahrt-IDs, keine Namen. Nichts davon ist im Repository
  gespeichert (die Rohantworten lagen außerhalb des Repositorys; `testAnalyseSavedAnswers` wertet so einen Ordner ohne Anfrage aus).
- **Zeitpunkt:** Donnerstag 2026-11-12, 22:05 Uhr Wien (Abend, ruhiger als die Spitze der Messung in §R11.1). **Ort:** eine Cloud-Sandbox über einen Ausgangs-Proxy, nicht ein iPhone.

Alle Anfragen: ganz Österreich (`RadarBox.austria`), Schiene (4157), `maxJny` 1000, `time` und `date` um den Versatz verschoben.

| # | Versatz | HTTP | Fahrzeuge | Bytes (entpackt) | ms | Fahrzeuge mit Echtzeit | Halte mit Echtzeit | Fahrzeuge ≥ 1 Min verspätet |
|---|---|---|---|---|---|---|---|---|
| 1 | jetzt (Vergleich) | 200 | 569 | 1 222 352 | 3 085 | 447 | 1 763 von 2 276 | 339 |
| 2 | +60 Min | 200 | 478 | 1 041 124 | 2 127 | 331 | 1 299 von 1 912 | 146 |
| 3 | +180 Min | 200 | 133 | 309 663 | 2 437 | 76 | 291 von 532 | 30 |
| 4 | **−30 Min** | **200** | 628 | 1 325 863 | 2 391 | 479 | 1 883 von 2 512 | 397 |
| 5 | +720 Min | 200 | 728 | 1 391 048 | 2 560 | 20 | 55 von 2 912 | 4 |

Zusammen 5 290 050 Byte. Je Fahrzeug 1,9 bis 2,3 KB entpackt (wie §R11.1).

Was daraus folgt:

1. **Eine vergangene Zeit wird angenommen.** −30 Min antwortet mit 628 Fahrzeugen. Deshalb bietet der Regler den Rückblick bis 30 Minuten an. Mehr als 30 Minuten zurück wurde nicht gemessen, und −30 nur einmal.
   Es ist **keine Aufzeichnung**: `planrtTS` (der Zeitstempel der Echtzeitdaten) liegt bei jeder Anfrage beim Zeitpunkt der Anfrage, nicht bei der abgefragten Zeit (Alter bei Bildzeit: 32 s, 3 632 s, 10 800 s, −1 799 s, 43 200 s). Die Auskunft rechnet die Vergangenheit aus Fahrplan und den Verspätungen von jetzt.
2. **Verspätungen für spätere Zeiten sind da, aber nicht vorhergesagt.** Für Züge, die jetzt fahren, stehen die Echtzeit-Felder auch in den späteren Antworten (+60: 331 Fahrzeuge). Dieselbe Fahrt in zwei Antworten
   (143 gemeinsame Fahrten +60, 23 bei +180) hat **nie** eine um 2 Minuten oder mehr andere Verspätung am letzten Halt, und es gibt keine Fahrt mit Echtzeit nur in einer der beiden Antworten. Die Auskunft wiederholt, was sie jetzt weiß. Für Züge,
   die erst morgen fahren (+720), gibt es fast keine (20 von 728).
3. **Es kommen nur Züge, die dann fahren.** In den späteren Antworten haben höchstens 2 Fahrzeuge ihre erste Abfahrt nach der Bildzeit (alle am ersten Halt), und höchstens 5 sind schon am Ziel. Gemeinsame Fahrten mit „jetzt“: 329 bei −30, 143 bei +60, 23 bei +180, **0 bei +720**.
   Züge, die später starten, kommen also nur über Antworten für spätere Zeiten ins Bild.
4. **Jede Antwort kennt von einer Fahrt genau vier Halte.** 569 von 569 Fahrzeugen (und alle Fahrzeuge der anderen Antworten) haben `stopL` mit vier Einträgen. In 83 % ist es die Folge **Start (nur Abfahrt), der zuletzt verlassene Halt,
   der nächste Halt, das Ziel (nur Ankunft)** (471 von 569, 400 von 478, 104 von 133, 512 von 628, 622 von 728; der Rest sind Züge am Start oder vor dem ersten Halt). Alles dazwischen ist unbekannt. Die frühere Annahme in §R7 („Haltestellenliste der Fahrt“)
   war für die Karte genug, für eine Berechnung ist sie falsch: Aus einer Antwort ist nur die aktuelle Strecke zwischen zwei Halten genau; danach folgt eine gerade Linie zum Ziel.
   Die `ani`-Bilder der Antwort (4 Punkte der nächsten 30 Sekunden) enthalten keine Strecke.

## 2. Wie gerechnet wird

**Ein Halt** (`RadarScheduleStop`): Ort, Zeit der Ankunft und der Abfahrt mit Verspätung, geplante Zeit (für die Reihenfolge). Die Verspätung eines Halts ist die gemeldete; ein Halt ohne Meldung übernimmt die des letzten Halts mit Meldung (Verspätungen
laufen die Fahrt entlang weiter), vor der ersten Meldung 0. Ein abgesagtes Ereignis trägt keine Verspätung. Zeiten laufen nie rückwärts (eine Ankunft liegt nicht vor der vorigen Abfahrt, eine Abfahrt nicht vor der Ankunft). Nichts wird vorhergesagt.

**Eine Antwort** ist ein Fahrplan aus ihren Halten plus ein **Anker**: die Position, die der Server für die Zeit der Antwort angibt. Der Zug geht zu dieser Zeit durch diesen Punkt, also ist die Projektion zur Zeit der Antwort genau die Position des Servers.
Ein Anker gilt nur, wenn er zu den Halten passt (auf der Strecke zwischen zwei Halten, höchstens 3 km oder ein Drittel der Strecke daneben; oder am ersten Halt vor der Abfahrt). Steht der Zug an einem Halt, gilt der Halt.

**Mehrere Antworten derselben Fahrt** werden zu einer Fahrt zusammengeführt (`RadarSchedule.merged`): die Halte aller Antworten (gleicher Halt = gleiche Koordinate auf 10 m), je Halt die frischeste Antwort mit gemeldeter Verspätung, sortiert nach geplanter Zeit;
zwei verschiedene Halte zur selben geplanten Minute sind eine Umleitung, die frischere Antwort gewinnt. Dazu kommen die Anker, jeder **noch einmal gegen die zusammengeführte Fahrt geprüft**: Meldet eine frischere Antwort eine kleinere Verspätung, steht der Zug zur Zeit einer älteren Position schon am Halt; dieser Anker zog ihn vom Bahnsteig ein paar Kilometer zurück und wieder hin (Review 1, Test `testAnOlderPositionThatTheFresherDelaysContradictDoesNotPullTheTrainOffItsStop`) und fällt jetzt weg. Die Wegpunkte (Ankunft und Abfahrt jedes Halts, jeder Anker) in Zeitreihenfolge sind die Fahrt; die Position zur Zeit T
liegt zwischen den beiden Wegpunkten um T, nach Zeit gewichtet. Für **den ausgewählten Zug** kommen die ganze Haltestellenliste (JourneyDetails) und die Strecke (Polylinie) dazu: Dann sind alle Halte bekannt und der Weg folgt der Strecke
(`RadarPathKind.polyline`); sonst ist er die gerade Linie (`.straight`, im Aufklapptext der Karte gesagt: „Luftlinie“).

**Beginn und Ende.** Vor der ersten Abfahrt ist der Zug nicht auf der Karte, **außer** eine Antwort hat ihn am ersten Halt stehen sehen: Dann bleibt er dort bis zur Abfahrt (die Auskunft hat ihn dort gesehen, der Fahrplan hält ihn bis dahin). Er steht dann **auf** dem Halt, mit dem Pfeil zum nächsten
(die Position der Antwort liegt oft ein paar hundert Meter daneben, am Bahnsteig; früher kroch der Zug von dort zum Halt, den Pfeil rückwärts, Review 1). Nach der Ankunft am Ziel (mit Verspätung) fällt er weg (die Zeit gilt auf die Sekunde).
Fehlt eine Fahrt in einer vollständigen Antwort für eine Zeit, ersetzt das nur, was eine ältere Antwort über **diese Minute** sagte (±150 s); aus ihren anderen Antworten wird sie weiter nach Fahrplan bis zum Ziel gerechnet.

**Zeit.** Alles läuft in absoluten Zeiten. Normal- und Sommerzeit, Mitternacht und der Wechsel in der Nacht sind nur Anzeige: „03:30 MESZ“ erscheint, wenn der Versatz zur Uhr von jetzt ein anderer ist; „morgen“ nach Mitternacht (Wiener Kalendertag), „gestern“ beim Rückblick kurz nach Mitternacht.
Die Plan-Zeiten sind volle 20 Minuten (oder Stunden) der Wiener Uhr; auch über die Zeitumstellung liegen sie 20 echte Minuten auseinander (Test).

**Genauigkeit.** Gemessen (R12, Auswertung `RadarTimeLiveTests.analyse`) an den Fahrten, die in zwei Antworten vorkommen (Abstand der Projektion zur Position der Auskunft, Kilometer):

| Fall | n | Median | 90 % | 99 % | höchstens | in 1 km | in 5 km |
|---|---|---|---|---|---|---|---|
| eine Antwort, 30 Min voraus (−30 → jetzt) | 327 | 5,2 | 15,4 | 31,7 | 35,4 | 9 % | 48 % |
| eine Antwort, 60 Min voraus (jetzt → +60) | 141 | 9,1 | 26,3 | 60,1 | 83,3 | 9 % | 35 % |
| eine Antwort, 180 Min voraus (jetzt → +180) | 23 | 54,4 | 98,4 | 131,8 | 131,8 | 9 % | 9 % |
| zwei Antworten zusammengeführt, die Mitte (jetzt aus −30 und +60) | 80 | 7,0 | 18,5 | 37,0 | 37,3 | 12 % | 41 % |
| zwei Antworten zusammengeführt, die Mitte (+60 aus jetzt und +180) | 23 | 11,4 | 34,0 | 34,8 | 34,8 | 17 % | 22 % |

Die Fahrten dieser Stichprobe sind überwiegend Fernverkehr (lange Strecken zwischen den Halten). Eine getrennte Auswertung der gespeicherten Antworten (kein Teil des Repositorys) fand als Ursache vor allem die **gerade Linie zwischen weit entfernten Halten**:
Abstand quer zur Linie im Median 5,7 km, entlang 3,2 km, Streckenlänge zwischen den Halten im Median 76 km (90 %: 507 km). Die Zeiten selbst stimmen (kein Vorzeichen: entlang gemessen im Median +0,1 km).
Für Regional- und S-Bahn-Fahrten mit kurzen Strecken ist die Abweichung kleiner; das wurde nicht getrennt gemessen.

**Folge für den Entwurf:** Aus einer Antwort allein wird nichts weit in die Zukunft gerechnet. Die Zeitleiste lädt Momentaufnahmen im Abstand von 20 Minuten (damit liegt jede Zeit höchstens 10 Minuten von einer Antwort mit Anker entfernt),
und **wenn der Regler ruht, kommt die Momentaufnahme für genau diese Minute**: Dann ist das Bild die Rechnung der Auskunft selbst (Abweichung 0), nicht unsere. Das Zusammenführen und die Anker sind getestet (Test `testMoreAnswersMakeThePositionsBetweenThemBetter`: mit drei Antworten
unter 1,5 km, mit einer über 3 km auf einer künstlichen Zickzack-Strecke); ob 20 Minuten Abstand auf echten Daten Zehntel-Kilometer oder Kilometer bedeutet, ist **nicht gemessen** (es gab nur Antworten für −30, 0, +60, +180, +720).

## 3. Anfragen, Budget und Datenmenge

Der Regler selbst ist lokal. Anfragen gibt es, **sobald die Zeit nicht „Jetzt“ ist** (nicht schon beim Öffnen der Karte), und nur diese:

- **Plan (`RadarTimeScheduler`).** Eine Momentaufnahme ganz Österreichs (Schiene, `maxJny` 1000, eine Anfrage) zu jeder vollen 20. Minute von 30 Minuten zurück bis 3 Stunden voraus: **10 oder 11 Antworten**, dazu eine für „jetzt“, wenn das Radar nicht ganz Österreich hält (Radar-Ansicht herausgezoomt und alle Kacheln beantwortet:
  dann stammen die Fahrzeuge von dort): bis **12**. Angezeigt als „Zeitreise lädt 3/12“; ab der ersten Antwort ist das Bild nutzbar. Reihenfolge: die Antwort, die dem Regler am nächsten liegt, zuerst, dann nach Abstand; sie folgt dem Regler.
  Eine abgeschnittene Antwort (1 000 Einträge) wird durch ihre zwei Hälften (Kacheln der Stufe 0) ersetzt; die Hälften fügen nur Fahrzeuge hinzu und löschen keine.
  **Lange Zeitreise:** Der Bereich wandert mit der Uhr. Einmal je Minute kommen die Punkte dazu, die rechts in den Bereich gerückt sind (einer je 20 Minuten), und was links herausfällt, wird vergessen (`extendPlan`, `RadarTimeline.prune(forRangeAt:)`);
  Gelungenes wird nicht noch einmal geholt, Gescheitertes nicht noch einmal versucht. **Wieder hinein** innerhalb von zehn Minuten: Die Zeitleiste behält alles, was der Regler erreicht (30 Minuten zurück), denn die Momentaufnahmen gelten so lange als geladen
  (früher wurde „jetzt“ als Grenze genommen, und die Züge der letzten halben Stunde, die schon am Ziel waren, fehlten beim Rückblick, Review 1).
- **Ruhende Minute.** 0,6 s nachdem der Regler stillsteht (nicht beim Ziehen, nicht beim Abspielen), **eine** Anfrage genau für diese Minute; sie ersetzt die Rechnung dort. Nicht, wenn ein Punkt des Plans oder eine Antwort höchstens 150 s daneben liegt oder die Zeit weniger als 60 s von jetzt weg ist.
  Höchstens 12 solche Anfragen von selbst je Zeitreise, danach nur auf „Genau laden“.
- **Budget.** Alles geht durch `RadarScheduler.claimSlot`, den Topf des Radars (§R11.2): **höchstens 24 Anfragen je Minute, 4 in 10 Sekunden, mindestens 1 s Abstand**, zusammen mit der Live-Schleife. Ein Test über 10 simulierte Minuten Ziehen, Spielen und Warten, und einer mit abwechselnder
  Live-Schleife und Zeitreise, prüft alle drei Grenzen. Das Budget gilt für die ganze App, nicht je Radar-Ansicht (Review 2, §3a). Gleichzeitig unterwegs höchstens 2 (über Mobilfunk 1), auch wenn „Fein laden“ den Plan mitten in der Zeitreise neu macht (die Anfragen unterwegs werden abgewartet, nicht doppelt gestellt). Ratenbegrenzung oder offener Schutzschalter pausieren das ganze Radar (`RadarScheduler.pause`). Fehler: nach 15 s, dann 30 s noch einmal, dann bleibt der Zeitpunkt aus und die Karte sagt es.
- **Stromspar-Modus.** Wie das Live-Radar lädt die Zeitreise im Stromspar-Modus nichts; gerechnet wird mit dem, was schon da ist. Die Karte sagt es („Stromspar-Modus. Die Zeitreise lädt nichts nach …“) und bietet „Trotzdem laden“ (gilt, bis das Radar schließt).
- **Pausieren und Beenden.** Die 20-s-Schleife des Radars **pausiert, solange die Zeit nicht Jetzt ist** (nichts wird für „jetzt“ geladen) und läuft nach „Zurück zu Jetzt“ weiter. Verlässt man das Radar oder schaltet die Zug-Ebene aus, endet die eine Schleife der Zeitreise mit allen Anfragen unterwegs.
  Ohne Zustimmung, bei ausgeschaltetem Schalter oder Notschalter gibt es den Chip nicht (derselbe Zugang wie das Radar). Die Zeitreise ist nur für Züge da (Schiene); sind Bus, Bim oder U-Bahn an, oder ist die Pünktlichkeits-Ebene an, ist sie aus.
  Wer eine dieser Ebenen **während** einer Zeitreise einschaltet, beendet sie (früher wartete die Pünktlichkeits-Ebene still hinter der Zeitreise, Review 1).
  **Offline** (Tunnel, Funkloch) endet die Zeitreise wie mit „Zurück zu Jetzt“, das Geladene bleibt aber: Wer innerhalb von zehn Minuten wieder hineingeht, lädt nichts doppelt (Review 2, §3a).
- **Cockpit.** Solange das Cockpit offen ist (`docs/RADAR_COCKPIT.md`), ruht die Schleife der Zeitreise wie die Live-Schleife; danach geht es weiter, wo man war (Momentaufnahmen, die inzwischen älter als zehn Minuten sind, werden einmal neu geholt, §3a). Aus einer Zeitreise öffnet „Cockpit“ nur einen Zug, den das Live-Radar kennt:
  Ein Zug, der erst später losfährt, hat keine Live-Position, und die berechnete darf nicht als eben gesehene weitergegeben werden.
- **Datenmenge, ehrlich.** Gemessen 0,3 bis 1,8 MB je Antwort (1,2 MB um 22 Uhr, 1,83 MB in der Abendspitze, §R11.1). Das ist auch ungefähr, was über das Netz geht: Die Auskunft (`/gate`) **packt ihre Antworten nicht**,
  obwohl die App gzip anbietet (`docs/OEBB_LIVE.md` §A2.1: keine `Content-Encoding` in den aufgezeichneten Antworten von sechs Methoden; `JourneyGeoPos` selbst wurde darauf nicht einzeln angesehen, es ist dieselbe Adresse; nur das Ausweich-Profil `mgate` packt).
  Bis Review 2 sagte die Karte „Auf der Leitung ist es weniger“; das stimmte nicht. Der volle Plan: 12 Antworten, **etwa 14 MB am Abend, bis etwa 22 MB in der Spitze**, jede ruhende Minute dazu 1 bis 2 MB
  (höchstens 12 von selbst: bis etwa 22 MB mehr). Die Karte sagt: „Bis etwa 22 MB für 12 Zeitpunkte, dazu bis etwa 1,8 MB für jede genau geladene Minute. Die Auskunft schickt die Daten ungepackt.“ (aufgeklappt unter „Wie das berechnet wird“; „bis etwa“, weil 1,8 MB die größte gemessene Antwort ist;
  vor Review 2 fehlten dort die ruhenden Minuten). Der schlimmste Fall je Minute steht in §3a.
- **Mobilfunk.** Die App hat keine Einstellung dafür. Beim Start einer Zeitreise fragt sie den Netzwerkpfad einmal ab (`NWPathMonitor`: teuer oder eingeschränkt = Mobilfunk, Hotspot, Datensparmodus; die Karte sagt „Mobile Daten oder Datensparmodus“). Dann gilt der **grobe Plan** (volle Stunden, 3 oder 4 Antworten, eine im Rückblick, wenn die letzte volle Stunde keine halbe Stunde her ist, mit einer für „jetzt“ etwa 5 bis 9 MB entpackt) und es gibt keine
  Anfrage für ruhende Minuten von selbst; die Karte sagt es und bietet „Fein laden“ (voller Plan) und „Genau laden“ (diese Minute). Die Schwelle ist eine Annahme: ob eine Verbindung als „teuer“ gemeldet wird, entscheidet das System; auf einem Mobilfunkvertrag ohne Begrenzung kann man „Fein laden“ tippen.
  Über eine solche Verbindung kommt **eine Antwort nach der anderen** (Review 2): Auf einer langsamen Leitung bekommt eine Antwort von bis zu 1,8 MB die ganze Geschwindigkeit, statt dass zwei sich sie teilen und beide an die 60 s des Clients stoßen.

## 3a. Zugang, Budget, Datenmenge, langsames Netz, Akku (Review 2)

Geprüft am Code und mit Linux-Tests, nicht auf einem iPhone. Keine neue Anfrage an die ÖBB.

**Tor.** Jede Anfrage der Zeitreise geht über `app.live.radar`: Das gibt es nur mit Zustimmung, eingeschaltetem Schalter „Live-Fahrplan“, ohne Notschalter und online
(`LiveDataService.timetableUnavailable`). Der Client (`HafasClient.radar`) prüft den Notschalter vor jeder Anfrage noch einmal (`LiveError.disabled`, ohne Netz), dann den Schutzschalter
(`LiveHealth`: drei Fehler in Folge, 2 Minuten Pause für die ganze App) und die Drossel (`RequestThrottle`: 40 je Minute für die ganze App, ehrlicher User-Agent). Davor steht das Budget des Radars
(`RadarScheduler.claimSlot`, 24 je Minute, 4 in 10 s, 1 s Abstand). Fällt die Zustimmung, der Schalter oder der Notschalter weg, endet die Zeitreise samt allen Anfragen unterwegs und vergisst alles (`reset`).
Ohne `claim` (das Radar-Modell ist weg) wird nichts gesendet; vorher hätte ein fehlendes Modell „frei, sofort senden“ bedeutet (dasselbe im Cockpit).

**Budget unter jeder Geste** (`RadarTimeSchedulerTests`, `HeatBudgetTests`):

- Ziehen, Spielen, VoiceOver-Schritte: Anfragen nur für eine ruhende Minute (0,6 s Ruhe), höchstens 12 von selbst je Zeitreise; alles durch `claimSlot`.
- „Genau laden“, „Fein laden“ dauernd getippt: dieselbe Minute wird nie zweimal gefragt, „Fein laden“ stellt nichts doppelt, was unterwegs ist; jede neue Minute kostet einen Platz im Budget.
- Zug-Ebene aus und ein, Pünktlichkeit an, Bus an: Die Zeitreise vergisst alles und fängt neu an; das **Budget bleibt** (es gehört dem Radar).
- Hintergrund und zurück, Cockpit auf und zu: Anfragen unterwegs werden abgebrochen. Ein Abbruch gibt den **Zeitpunkt** frei (er ist wieder fällig), **nicht den Platz im Budget**: Die Anfrage kann den Server erreicht haben.
- **Radar schließen und wieder öffnen.** Bis Review 2 hatte jede Radar-Ansicht ihr eigenes Budget: Wer das Radar alle paar Sekunden schloss und wieder öffnete und jedes Mal eine Zeitreise begann,
  schickte mehr als 24 Radar-Anfragen je Minute (nur die Drossel der App mit 40 hielt). Jetzt beginnt jede Ansicht mit dem Budget der letzten (`RadarBudgetLedger`: die Sendezeiten der letzten Minute; eine Ratenbegrenzung
  oder einen offenen Schutzschalter hält ohnehin `LiveHealth` für die ganze App). Test `testOpeningTheRadarAgainIsNoFreshBudget`: alle 3 s neu geöffnet, zwei Minuten lang, höchstens 24 je Minute und 4 in 10 s (ohne die Änderung über 24).
  Screenshot- und Perf-Starts (erfundene Züge, kein Netz) behalten je Ansicht ein Budget wie vorher, damit ihre Radar-Szenen in einem Prozess nicht aufeinander warten.
- Zwei Radar-Ansichten **gleichzeitig** gibt es nicht: ein Fenster (nur iPhone), Radar und Zugsuche sind Vollbild-Blätter derselben Fahrplan-Ansicht.

**Die Wiederholung des Clients.** Nach einer Zeitüberschreitung oder 502/503/504 fragt `HafasClient` einmal nach 1,5 s nach. Diese zweite Anfrage zählt in der Drossel (40) und im Schutzschalter,
nicht in den 24 des Radars (§R11.2, wie bei Kacheln). Die Zeitreise selbst versucht einen Zeitpunkt nach 15 s und 30 s noch einmal (diese zählen in den 24). Ein Zeitpunkt kostet also höchstens
6 Anfragen, bevor er als fehlend gilt; drei gescheiterte Anfragen in Folge öffnen aber vorher den Schutzschalter (2 Minuten keine ÖBB-Anfrage der App) und pausieren das Radar.

**Datenmenge je Minute.** Eine Antwort für ganz Österreich: bis 1,83 MB (Abendspitze), 1,2 MB um 22 Uhr, späte Zeitpunkte weniger (0,3 MB für +3 Std um 22 Uhr). Auf dem Netz etwa genauso viel (ungepackt, §3).

| Lage | Antworten | Datenmenge |
|---|---|---|
| Zeitreise beginnt, voller Plan | 12 in etwa 25 s (4 je 10 s) | etwa 14 MB am Abend, bis etwa 22 MB in der Spitze |
| Regler ruht, Plan geladen | alle 20 Minuten eine (der Bereich wandert mit der Uhr) | unter 0,1 MB je Minute |
| an immer neuen Minuten loslassen | bis 12 von selbst je Zeitreise, dann nur auf Tippen | bis etwa 22 MB dazu |
| über Mobilfunk (grober Plan) | 4 oder 5, eine nach der anderen, keine ruhende Minute von selbst | etwa 5 bis 9 MB |
| schlimmster Fall: das Budget voll (z. B. „Genau laden“ an immer neuen Minuten, oder Zug-Ebene aus und ein und neu beginnen) | 24 je Minute | bis etwa 44 MB je Minute |

Mehr als 24 Antworten je Minute holt das Radar nie, Zeitreise und Live-Schleife zusammen (die Live-Schleife ruht, solange die Zeit nicht „Jetzt“ ist). Die letzte Zeile ist eine Obergrenze, kein üblicher Gebrauch.

**Langsames Netz.** Das Zeitlimit des Clients sind 20 s **ohne Daten** (`URLRequest.timeoutInterval`, die Zeit zwischen zwei Datenpaketen) und 60 s für die ganze Anfrage (`timeoutIntervalForResource`).
Die Antworten der Messung R12 brauchten 2,1 bis 3,1 s, die langsamste von §R11.1 21,5 s (die erste Anfrage, mit Verbindungsaufbau). Ob das erste Byte nach mehr als 20 s kommt, hängt an der Rechenzeit des Servers;
gemessen ist das auf einem iPhone nicht. Eine Leitung unter etwa 30 KB/s schafft 1,8 MB nicht in 60 s:

1. Die Anfrage endet mit Zeitüberschreitung; was bis dahin kam, ist verbraucht. Der Client fragt nach 1,5 s einmal nach.
2. Scheitert auch das, versucht die Zeitreise den Zeitpunkt nach 15 s und 30 s noch einmal, dann bleibt er aus („Ein Zeitpunkt konnte nicht geladen werden …“).
3. Drei gescheiterte Anfragen in Folge öffnen den Schutzschalter: 2 Minuten keine Anfrage, die Karte rechnet mit dem, was da ist. Bis dahin können auf einer hoffnungslosen Leitung bis etwa 11 MB
   (3 Anfragen × 2 Versuche × 1,8 MB) angefangen und verworfen worden sein.

Es staut sich nichts: höchstens 2 gleichzeitig (über Mobilfunk 1), und eine Anfrage ohne Ausgang gibt ihren Zeitpunkt erst nach **150 s** frei. Der Client kann für eine Anfrage bis 131,5 s brauchen
(2 × 60 s, 1,5 s dazwischen, je bis 5 s in der Drossel). Mit den früheren 90 s wurde eine langsame Antwort, die noch lud, ein zweites Mal gefragt, genau auf dem langsamen Netz (Review 2; dasselbe für die Kacheln des Live-Radars).

**Offline.** Meldet das System keine Verbindung (Tunnel, Funkloch, Flugmodus), ist `timetableUnavailable` `.offline`: Die Schleife endet mit allen Anfragen unterwegs, die Zeitreise geht zurück zu „Jetzt“
(offline zeigt das Radar keine Züge), **das Geladene bleibt**. Bis Review 2 warf jeder Abbruch der Verbindung alles weg; im Zug durch Tunnel hieß das jedes Mal bis 22 MB neu.

**Zurück aus dem Hintergrund** (oder aus dem Cockpit). Die Schleife beginnt neu und mit ihr die Zeitreise: Der Netzwerkpfad wird neu gefragt, Momentaufnahmen, die älter als zehn Minuten sind,
kommen **einmal** neu (frischere bleiben), „jetzt“ kommt neu, wenn das Live-Radar ganz Österreich nicht frisch hält. Bis sie da sind, steht „Stand der Verspätungen: vor 15 Min“ in der Karte und „Zeitreise lädt 3/12“.
Bis Review 2 kam nichts neu: Nach einer Viertelstunde im Hintergrund blieb das Bild auf alten Verspätungen, nur die Alterszeile sagte es. Ein laufender Zeitraffer behält seinen Platz **von jetzt aus**
(vorher lief er nach langer Pause um diese Zeit hinter dem Bereich des Reglers her). Ein ruhender Regler behält seine Uhrzeit; ist sie aus dem Bereich gefallen, steht er am linken Rand.

**Akku.** Die Zeitreise hat keinen Timer, keinen Display-Link und keine Animation, die von selbst weiterläuft. Was läuft:

- die eine Schleife (`RadarTimeModel.run`), nur solange die Karte offen oder die Zeit nicht „Jetzt“ ist **und** das Radar sichtbar, die App aktiv und kein Cockpit offen ist: viermal je Sekunde, wenn der Regler ruht
  (die Marker werden dann höchstens alle 2 s neu berechnet und nur gesetzt, wenn sich etwas geändert hat), 12-mal je Sekunde, solange die Marker gleiten oder der Zeitraffer läuft. Im Hintergrund endet sie;
- der `TimelineView` der Alterszeile (einmal je Sekunde), nur solange die Karte offen und die Zeit nicht „Jetzt“ ist; im Hintergrund hält das System ihn an;
- das Pulsieren des Uhr-Symbols im Band, nur während der Zeitraffer läuft (mit „Bewegung reduzieren“ keins).

Im Stromspar-Modus lädt die Zeitreise nichts (§3); Gleiten und Zeitraffer laufen, weil man sie selbst startet. Ist die Karte offen und der Regler auf „Jetzt“, läuft die Schleife ohne Arbeit weiter (viermal je Sekunde,
damit das erste Ziehen sofort antwortet); geschlossen und auf „Jetzt“ läuft nichts.

## 4. Oberfläche

- **Chip und Karte.** Der Chip („Jetzt“, oder die Zeit, wenn weg von jetzt, mit einem Knopf „Zurück zu Jetzt“ daneben) und die Karte sind ein Glas, das ineinander übergeht (`GlassMorphGroup`, `Motion.smooth`). Die Karte hat innen kein Glas (Glas auf Glas gibt es nicht): Kopf mit großer
  Zeit (rollende Ziffern), Regler, Knöpfe, Status.
- **Regler** (`RadarTimeScrubber`): Spur von −30 Min bis +3 Std, Striche alle 15 Minuten (hoch zu jeder Stunde und bei „Jetzt“), Beschriftung „−30, Jetzt, +1, +2, +3 Std“, Griff rastet auf Fünf-Minuten-Schritten ein (Auswahl-Haptik; beim Abspielen keine, einmal beim Start und Ende). Über „Jetzt“ **gezogen** zeigt die Karte jetzt, die Zeitreise endet aber erst, wenn der Finger dort loslässt (vorher startete und stoppte jedes Überstreichen das Live-Radar, seine Statuskarte sprang auf und zu, Review 1).
  **VoiceOver:** einstellbar (nach oben oder unten = ein Schritt), spricht „22 Uhr 32, in 45 Minuten“ (`RadarTimeText.spokenValue`, getestet; vor Review 1 sagte es „22 Uhr 32 Uhr“). Die Auswahl-Haptik folgt dem Schritt, den man wählt, nicht der Uhr: Ein ruhender Regler tickt nicht, wenn die Uhr eine Fünf-Minuten-Marke überschreitet. **Dynamic Type:** Zeit und Zeilen skalieren, die Knöpfe stapeln sich bei großen Schriften. Der Chip auf der Karte wächst bis AX2 (größer passten Zeit, „vor 15 Min“ und der Knopf daneben nicht mehr in die Breite); langes Drücken zeigt ihn groß.
- **Bewegung** (nur Tokens): Die Marker **gleiten**, wenn der Griff springt oder der Zeitraffer läuft: Die gezeigte Zeit folgt der gewählten mit `RadarTimeGlide` (Zeitkonstante 0,14 s, 12 Bilder je Sekunde, nur solange sie sich bewegt). Spur: die letzten 10 Minuten des **gewählten** Zuges, eine Linie auf einem hellen Unterstrich, die ältere Hälfte blass,
  die neuere kräftig. Review 1: Vorher waren es zehn Stücke ohne Unterstrich, das älteste mit 18 % Deckkraft; die ältere Hälfte war auf der Karte nicht zu sehen, und beim Zeitraffer
  (elf Überlagerungen, 12-mal je Sekunde ersetzt) zeigte die CI-Aufnahme nur ein Stück, ein bis zwei Sekunden hinter dem Zug. Mit zwei hielt sie Schritt; ein Farbverlauf als Strich wurde im Simulator gar nicht gezeichnet (nur der Unterstrich), daher jetzt drei Überlagerungen: Unterstrich, ältere Hälfte blass, neuere kräftig. Himmel: eine weiche Tönung über der Karte (Dämmerung warm, Nacht violett, `RadarDaylight`: Sonnenhöhe für 47,6° N ohne Zeitgleichung, auf etwa 15 Minuten genau; **Anmutung, nichts wird damit behauptet**).
  **Reduce Motion:** kein Gleiten (die gezeigte Zeit folgt sofort), keine Symbol-Effekte; Abspielen funktioniert weiter. Screenshot-Modus: Endzustand sofort.
- **Marker.** Wie im Radar. Der gestrichelte Ring heißt hier „berechnet“ (alle Positionen außer der Antwort der Auskunft für diese Minute, auf 30 s); die Farbe des Rings ist die Verspätung, die der Zug zu dieser Zeit trägt (grün unter 5 Minuten, orange ab 5, rot abgesagt, grau ohne Echtzeit-Daten). Filter und Suche gelten.

## 5. Die Texte (alle getestet, `RadarTimeText`)

| Wo | Text |
|---|---|
| Band, Zukunft | „Zeitreise · Prognose aus dem Fahrplan“ |
| Band, Rückblick | „Zeitreise · Rückblick aus dem Fahrplan“ |
| Zeile in der Karte | „812 Züge · berechnet für 22:32“, „Stand der Verspätungen: vor 42 s“ (tickt jede Sekunde) |
| Wahrheit, Zukunft | „Berechnet aus dem Fahrplan und den Verspätungen von jetzt. Spätere Verspätungen sind nicht vorhergesagt.“ |
| Wahrheit, Rückblick | „Berechnet aus dem Fahrplan und den Verspätungen von jetzt. Das ist keine Aufzeichnung.“ |
| Laden | „Zeitreise lädt 3/12“ mit Balken |
| Weg | „Zwischen den Halten fahren die Züge auf der Luftlinie. Nur beim gewählten Zug folgt die Spur der Strecke.“ |
| Ausfall | „Ein Zeitpunkt konnte nicht geladen werden. Zügen, die erst später losfahren, fehlen dort Daten.“ |
| Genaue Minute | „Für diese Minute hat die Auskunft die Positionen selbst berechnet.“ (nur, wenn ihre Antwort höchstens 30 s neben der gewählten Zeit liegt: dann sind die Marker durchgezogen) |
| Antwort daneben | „Für 22:20 hat die Auskunft die Positionen selbst berechnet, für 22:19 rechnet die App von dort aus.“ (eine Antwort bis 150 s daneben; vor Review 1 hieß das ebenfalls „für diese Minute“, während alle Marker gestrichelt waren) |
| Stromspar-Modus | „Die Zeitreise lädt nichts nach, solange der Stromspar-Modus an ist. Gerechnet wird mit dem, was schon geladen ist.“ |

## 6. Demo und Screenshots

`-KBDemo` und die Hosts `radarTime` (Regler bei +45 Minuten), `radarTimePlaying` (Zeitraffer läuft ab −30 Minuten und beginnt in der Szene am Ende von vorn, Westbahn nah, ein Zug gewählt mit Spur), `radarTimeLoading` („Zeitreise lädt 3/12“, bleibt stehen), `radarTimeAX5` (größte Schrift), `radarTimeChip` (15 Minuten zurück, die Karte zum Chip eingeklappt: „Rückblick“ im Band, die Zeit und der Weg zurück im Chip). Kein Netz, keine Berechtigung.
Die Züge sind **erfunden** (`RadarTimeDemo.swift`: 14 Linien auf den echten Hauptstrecken mit erfundenen Fahrplänen, je Antwort vier Halte wie die echte Auskunft); kein echter Zug, Fahrplan oder Standort.

## 7. Geprüft und nicht geprüft

**Auf echten ÖBB-Daten geprüft (R12, 5 Anfragen):** Vergangenheit und Zukunft werden angenommen; Echtzeit-Felder stehen in späteren Antworten und werden dort nicht vorhergesagt; vier Halte je Fahrt; Zahlen und Größen der Antworten; die Genauigkeit der Projektion
(Tabelle oben). **Mit erfundenen Daten (Linux-Tests):** Projektion, Anker, Zusammenführen, Beginn und Ende, Halten am Start, Zeitzone, Mitternacht und Zeitumstellung, Zeitleiste, Speichergrenzen, Plan und Reihenfolge, das Budget über simulierte Sitzungen, Texte.

**Nur auf einem iPhone zu prüfen:** das Gleiten der Marker bei 120 Hz und die Last bei 1 000 Markern (der Entwurf begrenzt auf 12 Bilder je Sekunde und höchstens etwa 130 Gruppen, gemessen ist es nicht), die Haptik, VoiceOver, die Antwortzeit und Größe im Mobilfunknetz (gemessen wurde aus einer Cloud-Sandbox, 21,5 s
war die langsamste Antwort von §R11.1), ob die Erkennung „Mobilfunk“ im Alltag richtig liegt, die Genauigkeit bei 20 Minuten Abstand der Antworten, tagsüber und in der Spitze (gemessen: Abend, 22 Uhr).
Dazu (Review 1): ob das Ziehen am Regler bei großen Schriften, wenn der Bereich unten scrollt, nicht mit dem Scrollen kämpft; ob die Spur (drei Überlagerungen, beim Gleiten 12-mal je Sekunde neu gesetzt) auf MapKit flackert und beim Zeitraffer mit dem Zug Schritt hält; der Stromspar-Modus und „Trotzdem laden“ im Alltag. **Offen:** Der gewählte Zug ist ein eigener Marker, kann aber unter der Gruppe seiner Nachbarn liegen: MapKit legt Marker nach ihrer Lage übereinander (der südlichere oben), und die SwiftUI-Karte bietet dafür keine Reihenfolge (dasselbe gilt im Live-Radar).

**Geräte-Checkliste (nur ein iPhone kann das zeigen):**

1. **Datenmenge auf dem Netz.** Einstellungen › Mobilfunk › KlimaBilanz: Zähler notieren, über Mobilfunk mit „Fein laden“ eine volle Zeitreise laden (bis „Zeitreise lädt 12/12“), Zähler wieder lesen. Erwartet: bis etwa 22 MB (die Auskunft packt nicht). Weniger als etwa 15 MB hieße, `JourneyGeoPos` wird doch gepackt: dann den Kartentext anpassen.
2. **Mobilfunk erkannt.** Über Mobilfunk erscheint „Mobile Daten oder Datensparmodus“, der Plan hat 4 oder 5 Punkte und lädt einen nach dem anderen; im WLAN nicht. Persönlicher Hotspot eines anderen iPhones: ebenfalls „teuer“?
3. **Tunnel.** Mitten in einer Zeitreise den Flugmodus an und nach 30 s wieder aus: Die Karte klappt zu, das Radar steht auf „Jetzt“. Wieder in die Zeitreise: kein „Zeitreise lädt 0/12“ von vorn (nur die ruhende Minute kommt).
4. **Hintergrund.** Zeitreise bei +45 Min, App 15 Minuten in den Hintergrund. Zurück: zuerst „Stand der Verspätungen: vor 15 Min“, dann „Zeitreise lädt …“, danach ein Alter unter einer Minute. Ein laufender Zeitraffer läuft im Bereich weiter.
5. **Schnell auf und zu.** Das Radar zehnmal hintereinander öffnen, in die Zeitreise ziehen und schließen. Danach sofort eine Verbindung im Fahrplan suchen: Sie kommt, ohne „Kurz zu viele Anfragen“ (die Drossel der App hat Platz, weil das Radar bei 24 je Minute bleibt); im Radar erscheint kein „ÖBB bittet um eine kurze Pause“.
6. **Langsames Netz.** Entwickler › Network Link Conditioner „3G“ oder „Edge“: Die Karte zeigt „Zeitreise lädt“, auf Edge Fehlerzeilen statt eines hängenden Balkens; nach drei Fehlern pausiert das Radar und sagt es.
7. **Akku.** Zeitreise offen, Regler ruht, 10 Minuten: Einstellungen › Batterie zeigt für KlimaBilanz keinen auffälligen Verbrauch im Hintergrund (es sollte keiner sein).

**Nicht gebaut / gekürzt:** Rückblick über 30 Minuten; Verspätungs-Vorhersage (die Auskunft liefert keine, wir erfinden keine); mehr als vier Halte je Fahrt für alle Züge (das wären 1 000 Anfragen für JourneyDetails, nur für den gewählten Zug); Bus, Bim und U-Bahn (in einer Großstadt ist schon eine Kachel am Limit von 1 000 Fahrzeugen, §R11.1 d; die Datenmenge einer solchen Zeitreise wurde nicht gemessen); eine Fortsetzung nach dem Ende des Zeitraffers (er stoppt bei +3 Std; „Abspielen“ am Ende beginnt bei „Jetzt“).
