# Übersicht nach Maß – Karten, Kennzahlen, Ziele

Stand: Track „Übersicht nach Maß“ (November 2026). Du ordnest die Übersicht selbst an: Karten verschieben und ausblenden, bis zu
**vier eigene Kennzahlen** aus einem Katalog von 16 und bis zu **drei Ziele** mit Fortschrittsring („20 Fahrten im Monat“). Fertige
Vorlagen – **Standard · Ruhig · Zahlen · Alles** – sind einen Tipp entfernt. Jede Zahl ist dieselbe, die Statistik zeigt.

Code: Logik in `Packages/KlimaCore/Sources/KlimaCore/Dashboard/` (`DashLayout.swift`, `KpiCatalog.swift`, `Goals.swift`; Linux-Tests
unter `Tests/KlimaCoreTests/Dashboard/`, `swift test --filter 'DashLayout|Kpi|Goals'`, 45 Tests); App in
`App/Sources/Features/Dashboard/Layout/` (Speicher `DashLayoutStore`, die Kartenliste `DashSectionList`, Kennzahlen, Ziele, Editor,
Ziel-Editor, Demo-Szenen). Eingehängt mit `// MARK: uebersicht` in `DashboardView.swift`, `DashSupport.swift` (Woche), `Repository.swift`
(„Alle Daten löschen“), `SetPreferencesSections.swift` (Zeile in Darstellung) und `RootView.swift` (Szenen).

## 1. Was bleibt, wie es war

- **Ohne Änderung sieht die Übersicht aus wie vorher** – bis auf den ruhigen Knopf „Übersicht anpassen“ unter der letzten Karte.
  Jede Karte wird mit genau den Views, Abständen, Eintritts-Reihenfolgen (`reveal`), Funktions-Schaltern und Hooks der anderen Tracks
  (Fahrten erkennen, KI, Jahresrückblick, Pendel-Modus, Kalender-Vorschläge, Funktionen, Vorteile) gebaut wie zuvor in
  `DashboardView`; nur der Abstand über einer Karte, die einen neuen Nachbarn hat, richtet sich nach diesem.
- **Fest oben und nicht verschiebbar:** Kopf, Ticket-Pille, Gipfel, die Kapsel einer laufenden Fahrt und die Update-Kapsel.
- **Eine Karte ohne Inhalt bleibt unsichtbar**, was immer das Layout sagt (keine Vorschläge → keine Vorschlags-Karte; Jahresrückblick nur
  1. Dez. – 31. Jän.).
- **Funktionen gewinnt:** Ist „Nächster Erfolg“, „Diese Woche“ oder „Vorteile“ in Einstellungen › Funktionen aus, bleibt die Karte weg;
  der Editor schreibt dann „Funktion aus · in Einstellungen › Funktionen“ in ihre Zeile.

## 2. Das Layout (`dash.layout.v1`)

Karten (`DashSectionID`, die Strings werden gespeichert und nie umbenannt): `balance` (Bilanz mit „Warum lohnt sich mein Ticket?“ bzw.
die Einladung ohne Fahrt), `yearReview`, `commute`, `quickLog`, `suggestions`, `calendarSuggestions`, `recentTrips`, `goals`, `kpis`,
`achievements`, `week`, `perks` – in dieser Reihenfolge bei einer frischen Installation.

- JSON `{"version":1,"order":[…],"hidden":[…]}` in UserDefaults; **nicht synchronisiert**. Die tägliche Sicherung nimmt es über das
  Präfix `dash.` mit (docs/DATA_HUB.md, `BackupSettingsPolicy`), die Wiederherstellung nennt es „Übersicht“.
- **Tolerant:** Müll, eine unbekannte Version oder nur unbekannte Karten → Standard. Unbekannte Karten werden verworfen, doppelte nur
  einmal genommen, ein falscher Wert nur übersprungen.
- **Neue Karte in einer neuen App-Version:** sie kommt direkt hinter ihren Vorgänger aus der Standard-Reihenfolge (fehlt auch der,
  hinter dessen Vorgänger …, sonst an den Anfang). So erscheinen spätere Karten, ohne die eigene Anordnung zu löschen.
- **Die Bilanz** lässt sich verschieben, aber nicht ausblenden (sie beantwortet die Frage, für die es die App gibt).
- Verschieben folgt exakt `Array.move(fromOffsets:toOffset:)` von SwiftUI (`List.onMove`); Ausblenden ist idempotent.

**Vorlagen** (ersetzen Reihenfolge und Sichtbarkeit; Kennzahlen und Ziele bleiben):

| Vorlage (Untertitel) | Reihenfolge | ausgeblendet | Kennzahlen |
|---|---|---|---|
| Standard („Ab Werk“) | Standard | – | wie gewählt |
| Ruhig („Das Nötigste“) | Standard | Jahresrückblick, Kennzahlen, Nächster Erfolg, Diese Woche, Vorteile | wie gewählt |
| Zahlen („Zahlen zuerst“) | Bilanz, Kennzahlen, Ziele, Diese Woche, dann der Rest | Vorteile | ohne Wahl: die vier Standard-Kacheln |
| Alles („Jede Karte“) | Standard | – | ohne Wahl: die vier Standard-Kacheln |

„Ruhig“ blendet aus, was informiert oder einlädt – nicht, was auf dich wartet (Fahrten-Vorschläge, Pendel-Modus, Termine erscheinen
ohnehin nur, wenn etwas ansteht). Die Standard-Kacheln sind Ersparnis nach Ticketkosten, Fahrten, CO₂ gespart, Kosten pro Tag.

## 3. Kennzahlen (`dash.kpis.v1`)

Bis zu vier Kacheln im 2 × 2-Raster (bei Bedienungshilfen-Schriftgrößen eine Spalte). Jede Kachel: Symbol, der Wert (die Ziffern rollen),
der Titel und wovon sie spricht („Ticketjahr 2026/27“). Für VoiceOver ist eine Kachel ein Element: „Fahrten, 87 Fahrten, Ticketjahr 2026/27“.

**Der Katalog rechnet nichts selbst.** `KpiCatalog.reading(kind, input:)` liest einen Wert aus dem, was die Übersicht ohnehin hat: der
`SavingsSummary` von `Analytics.make` (dieselbe wie Gipfel, Bilanz-Karte und Statistik), `records.longestStreakDays`,
`topRoutes.first`, die Zahl der Karte „Diese Woche“ und der Auto-Vergleich von Statistik › „Öffis vs. Auto“ (`WorkCarCalc`, dieselbe
Zahl wie „Mit dem Auto“ auf der Bilanz-Karte; nur gerechnet, wenn die Kachel gewählt ist). Formatiert wird nur mit `Format.*` und der Rundung des Gipfels (`SummitFigures`).

| Kennzahl | Wert | wie gezeigt |
|---|---|---|
| Wert deiner Fahrten | `totalValue` | ganze Euro wie „€ … von € …“ im Gipfel |
| Ersparnis nach Ticketkosten | `net` | „+ € 412“; vor dem Break-even „€ 354 noch offen“ (dieselbe Zahl wie „Noch € 354 bis zum Break-even“) |
| Fahrten | `tripCount` | eine Reise mit Umstieg zählt einmal |
| Reisetage | `travelDays` | |
| Kilometer | `distanceKm` | unter 10 km mit einer Nachkommastelle, wie Statistik |
| CO₂ gespart | `co2SavedKg` | kg/t nach Look & Feel › Zahlen › CO₂, wie die Bilanz-Karte |
| Ø Wert je Fahrt | `averageValuePerTrip` | „–“ ohne Fahrt |
| Kosten pro Tag | `costPerDay` | |
| Wert pro Tag | `valuePerDay` | |
| Preis pro km | `effectivePricePerKm` | „–“ ohne Kilometer |
| Auto-Vergleich | `CarComparisonResult.carCost` | wie „Öffis vs. Auto“ in Statistik und „Mit dem Auto“ auf der Bilanz-Karte: Straßen-km (Bahn-km × 1,15) × die Autokosten aus Einstellungen › Arbeit & Auto; „–“ ohne Fahrt |
| Tage bis Ablauf | `daysRemaining` | |
| Prognose Endwert | `forecastEndValue` | heißt „Prognose“; nur solange das Ticket läuft und es Fahrten gibt (wie die gepunktete Linie in Statistik) |
| Fahrten diese Woche | die Karte „Diese Woche“ | Wochenstart nach Look & Feel |
| Längste Serie | `longestStreakDays` | |
| Lieblingsstrecke | `topRoutes.first` | „Innsbruck Hbf ↔ Wörgl Hbf“ mit „10 Fahrten“ |

Auswahl im Editor unter „Kennzahlen ändern“: der Katalog mit dem heutigen Wert jeder Zahl, oben die Kacheln als Live-Vorschau; die Zahl
im Kreis ist der Platz der Kachel. Wer eine Kennzahl wählt, während die Karte ausgeblendet ist, blendet sie damit wieder ein.

## 4. Ziele (`goals.v1`, `goals.ledger.v1`)

Höchstens drei. Arten und Stepper:

| Art | Ziel | gezählt |
|---|---|---|
| Fahrten im Monat | 1 – 100 | Fahrten im Wiener Kalendermonat, die im Ticketjahr liegen; eine Reise zählt einmal (wie Statistiks Monatsbalken) |
| Wert im Monat | € 10 – 2.000 in 10er-Schritten | Normalpreis dieser Fahrten |
| CO₂ im Monat | 1 – 500 kg | wie `SavingsCalculator` |
| Break-even bis | ein Tag von heute bis zum letzten Gültigkeitstag | Wert gegen Ticketpreis |

`GoalEvaluator.evaluate` liefert den Fortschritt (darf über 100 % gehen), den Zustand und Texte:

- **Auf Kurs / Hinter Plan** misst am linearen Tempo über die **schon vergangenen Tage** des Monats (Tageszählung, nicht Sekunden – ein
  Monat mit Zeitumstellung hat trotzdem 31 Tage). Am 1. ist noch nichts fällig. Bei Fahrten wird das Soll abgerundet (10,67 → 10).
  Gezählt werden nur die Tage des Monats, die das Ticket abdeckt: Beginnt es am 15., misst das Tempo ab dem 15. („zählt ab 15. Nov.“
  davor), endet es am 11., heißt es „7 Tage bis Ticketende“ und „Prognose: … bis Ticketende“.
- **Geschafft** sobald das Ziel erreicht ist; **Nicht geschafft** bei „Break-even bis“, wenn der Tag vorbei ist, und bei einem
  Monatsziel, wenn das Ticket im Monat geendet hat („Dein Ticket galt bis 11. März · 6 Fahrten fehlten“). **Ruht**, wenn nichts zählen
  kann: das Ticket deckt den Monat nicht ab („Dein Ticket gilt ab 1. Dez. – dann zählt es“) oder der Tag von „Break-even bis“ liegt
  außerhalb dieses Ticketjahrs (ein Ziel vom letzten Ticket). Ein ruhendes Ziel ist nie „Hinter Plan“ und poppt nie.
- „Break-even bis“ folgt der **Prognose der Bilanz-Karte** (`forecastBreakEvenDate`): liegt sie vor dem Tag, ist es „Auf Kurs“. So
  widerspricht der Ring nie der Karte darüber. Ohne Prognose (noch kein Tempo) entscheidet das lineare Tempo. Liegt die Prognose nach
  dem letzten Gültigkeitstag, nennt der Ring kein Datum, sondern „Prognose: kein Break-even bis zum Ablauf“ (wie „Fehlt bei Ablauf“ auf
  der Karte). Hat sich das Ticket erst nach dem Tag rentiert: „Break-even am 2. Juli – nach dem Tag“ (nicht „noch € 0“).
- Was fehlt, mit einem Tempo, das eine Tatsache ist: „noch 4 Fahrten · etwa 1 pro Woche“, „noch € 36 · 5 Tage übrig“, „noch 1 Fahrt ·
  heute ist der letzte Tag“; erreicht „4 Fahrten über dem Ziel“ bzw. „Genau aufs Ziel“ (die Zeile darüber sagt „24 von 20 Fahrten“).
- **Prognose** nur mit dem Wort: „Prognose: etwa 22 Fahrten bis Monatsende“ (ab dem 7. Tag) bzw. „Prognose: Break-even am 14. Dez.“.

Der Ring füllt sich, wenn er ins Bild scrollt; die Prozentzahl steht in der Mitte, der Zustand daneben als Wort mit Symbol – nie nur
Farbe (Gletscher-Verlauf auf Kurs, Morgenrot dahinter, Zirbe geschafft). **Erreichen** spielt einmal pro Ziel und Zeitraum einen kurzen
Pop des Rings mit einer `.success`-Haptik – nur solange die Übersicht sichtbar ist und kein Sheet sie verdeckt; kein Konfetti. Das Buch
dazu (`goals.ledger.v1`, höchstens 48 Einträge) überlebt einen Neustart; ein Ziel, das schon beim Sichern erfüllt ist, poppt in diesem
Zeitraum nicht. „Alle Daten löschen“ löscht die Ziele und ihr Buch; Layout und Kennzahlen-Wahl sind Darstellung und bleiben.

## 5. Der Editor

Erreichbar über den Knopf **„Übersicht anpassen“** am Ende der Übersicht, **„Anpassen“** auf den Karten Kennzahlen und Ziele und
**Einstellungen › Darstellung › Übersicht anpassen** (dort als Seite).

- Als Sheet zuerst halbhoch: Was du änderst, passiert sofort darüber in der Übersicht (`Motion.smooth`). Ganz hoch ziehen zeigt alles.
- **Vorlagen** als vier Kacheln; die zuletzt getippte trägt Ring und Häkchen, solange ihr Layout gilt (sonst die passende; „Alles“ und
  „Standard“ teilen ein Layout). Eigene Anordnung: keine.
- **Karten:** Symbol, Name, wann sie erscheint (oder „Ausgeblendet“, „Funktion aus …“, „4 von 4 gewählt“, „2 Ziele“), das Auge.
  „Sortieren“ im Kopf der Liste zeigt die Griffe zum Ziehen; ein langes Drücken zieht auch so. VoiceOver: eine Zeile ist ein Element,
  Doppeltippen blendet aus oder ein (der Hinweis sagt es), Aktionen „Nach oben“ (nicht an erster Stelle), „Nach unten“ (nicht an
  letzter), „Ausblenden“/„Einblenden“.
- **Kennzahlen** mit Live-Vorschau, **Ziele** mit Stand, **Ziel hinzufügen** (der Ziel-Editor zeigt den echten Ring des Entwurfs an
  den heutigen Fahrten, bevor du sicherst), **Zurücksetzen** (Reihenfolge und Sichtbarkeit; Kennzahlen und Ziele bleiben).

## 6. Demo und Screenshots

Szenen (`DashLayoutScreenshotHost`, Demo-Daten, kein Netz, keine Systemabfrage; Layout, Kennzahlen und Ziele nur im Speicher):
`dashEdit` (Editor halbhoch über der Übersicht), `dashEditFull`, `dashEditSort` (Griffe), `dashEditAX5`, `dashEditSettings` (als Seite),
`dashSettingsRow` (die Zeile in Darstellung), `dashKpis` (Kacheln unter dem Gipfel), `dashKpisAX5` und `dashGoalsAX5` (die Karten
selbst bei der größten Schrift, eine Spalte), `dashStandardAX5` (die Übersicht ohne Änderung bei der größten Schrift), `dashGoals` (drei
Ringe), `dashQuiet`, `dashQuietBottom` (Vorlage Ruhig), `dashKpiPicker`, `dashGoalEditor`; dazu die bestehenden `dashboard`, `dashboardBottom` zum Vergleich.
Aus dem Review: `dashGoalStates`/`dashGoalStatesAX5` (jeder Zustand eines Ziels an den Rändern eines Tickets, feste synthetische Tickets
und Fahrten) und `dashKpisCar` (Bilanz-Karte mit „Mit dem Auto“ über der Kachel „Auto-Vergleich“ – dieselben Euro). Die Ziele der Szenen
richten sich nach den Demo-Fahrten des laufenden Monats (eines erfüllt, eines unterwegs, „Break-even bis“), egal an welchem Tag der Lauf ist.

Angesehen in vier Läufen, hell und dunkel: [693](https://github.com/Jecuro1/KLIMATICKET-APP/actions/runs/44658618686) (alle Szenen,
dazu `dashboard`/`dashboardBottom` ohne Änderung), [697](https://github.com/Jecuro1/KLIMATICKET-APP/actions/runs/44663760622) (nach dem
ersten Feinschliff), [699](https://github.com/Jecuro1/KLIMATICKET-APP/actions/runs/44668459954) (mit dem Knopf am Ende der Übersicht und
der Zeile in Einstellungen) und ein letzter für die kürzeren Untertitel der Vorlagen („Ab Werk“, „Das Nötigste“ – vorher zweizeilig, die
erste Kachelreihe war dadurch höher als die zweite).

## 7. Getestet und nicht

- Linux (`swift test --filter 'DashLayout|Kpi|Goals'`): Zusammenführen mit neuer Karte, unbekannte Karte, `move` gleich `Array.move`,
  Ausblenden idempotent, Bilanz nicht ausblendbar, Vorlagen, Müll → Standard; Kennzahlen gegen eine feste Fahrten-Liste und
  `SavingsCalculator`/`StatsAggregator` (dieselbe Pipeline wie `Analytics.make`); Ziele an Monatsenden (31 Tage, Februar, Zeitumstellung
  29. 3. und 25. 10. 2026), erster Tag ohne Fahrt, 150 % Überschuss, genau im Plan, Einzahl/Mehrzahl, „Break-even bis“ ohne Prognose,
  das Buch feuert einmal pro Zeitraum.
- Typprüfung der App unter Linux (`tools/typecheck`), CI-Build auf macOS, Screenshots hell und dunkel.
- **Leistung** (ein `[perf]`-Lauf nach dem Umbau: [Lauf 44658832501](https://github.com/Jecuro1/KLIMATICKET-APP/actions/runs/44658832501),
  Commit `71161e0`, Artefakt `perf-594`). Der Job stieß wie die Läufe von Look & Feel an das 95-Minuten-Limit (docs/THEMES.md §4); die
  Übersicht war vorher fertig gemessen. Wischen (XCUITest), die Zahl der Planung:

  | Übersicht · Daten | Baseline Lauf 383 | Lauf 387 | dieser Lauf |
  |---|---:|---:|---:|
  | +1 500 Fahrten | 309,0 ms/s | 179,8 ms/s | 299,0 ms/s |
  | Demo-Jahr | 315,3 ms/s | 188,6 ms/s | 308,6 ms/s |

  Also nicht schlechter als die Baseline, aber langsamer als Lauf 387. Der Runner war in diesem Lauf überall langsamer, auch auf
  Bildschirmen ohne Änderung (Gipfelbuch Wischen 13,7 → 42,0, Ticket-Tour 118 → 250, Statistik-Tour 330 → 574 ms/s gegen Lauf 387;
  `sample` brauchte 145 s für ein Fenster von 20 s); der Vergleich trägt nur Unterschiede ab etwa Faktor 2 (docs/PERF_BASELINE.md §6).
  Die Tour-Zeile der Übersicht (459 ms/s) taugt nicht: Gezählt wurde nur einer der sechs Durchgänge, die anderen hatten weniger als die
  nötigen 10 Frames. Ein sauberer Vergleich vorher/nachher auf demselben Runner oder auf einem iPhone steht aus.
- **Nur auf dem iPhone prüfbar:** wie sich Ziehen anfühlt, Umordnen mit VoiceOver, die Pop-Haptik beim Erreichen, die Leistung der
  datengetriebenen Liste beim Scrollen.

## 8. Abweichungen von der Planung

- Katalog mit **16** statt 17 Kennzahlen: „Fehlt bis Break-even“ fiel weg – „Ersparnis nach Ticketkosten“ zeigt vor dem Break-even genau
  diese Zahl („€ 354 noch offen“), die Planung erlaubte höchstens 16.
- `AnalyticsSnapshot` liegt in der App, nicht in KlimaCore; der Katalog liest deshalb eine kleine Eingabe (`KpiInput`), die die App aus
  dem Snapshot füllt.
- „Break-even bis“ misst „Auf Kurs“ an der Prognose der Bilanz-Karte statt am linearen Tempo, damit Ring und Karte nie widersprechen.
- „Diese Woche“ zählt eine Reise mit Umstieg jetzt einmal pro Woche (vorher jede Teilstrecke) – wie Statistik und die Kennzahl.
- Aus Einstellungen öffnet der Editor als Seite statt als Sheet (Einstellungen ist selbst ein Sheet).
- „Nächster Erfolg“ und „Diese Woche“ sind zwei Karten (vorher ein Block); direkt untereinander behalten sie den engen Abstand.

## 9. Review (adversarial, November 2026)

Gefunden und behoben (KlimaCore mit Linux-Tests, `swift test --filter 'DashLayout|Kpi|Goals'`, 45 Tests):

- **Auto-Vergleich widersprach der Bilanz-Karte darüber:** die Kachel rechnete Bahn-km × Kilometergeld (Demo-Jahr etwa ein Achtel
  weniger), Statistik und die Bilanz-Karte rechnen Straßen-km mit den Autokosten aus Einstellungen. Jetzt dieselbe Zahl (`KpiInput.carCost`).
- **Monatsziele bei einem Ticket, das im Monat beginnt oder endet:** Wer am 15. ein Ticket bekommt und am 16. ein Ziel anlegt, las
  „Hinter Plan“ und „Prognose: etwa 4 Fahrten“, weil die 14 Tage ohne Ticket mitzählten; nach dem Ablauf „etwa 5 pro Woche“ für Tage,
  an denen nichts mehr zählt. Jetzt zählen nur die abgedeckten Tage, mit „Ruht“ und „Nicht geschafft“ wie in §4.
- **„Break-even bis“:** ein erst nach dem Tag rentiertes Ticket hieß „Der Tag ist vorbei · noch € 0 bis zum Break-even“; eine Prognose
  nach dem Ablauf stand als Datum da; ein Tag aus dem letzten Ticketjahr galt als „Nicht geschafft“ für das neue.
- Kilometer unter 10 km mit einer Nachkommastelle wie Statistik.
- Ein Tipp auf „Alles“ setzte Ring und Häkchen auf „Standard“.
- VoiceOver: „Nach oben“ an erster Stelle tat nichts; das Auge war in die Zeile verschmolzen (Doppeltippen blendete ohne Hinweis aus).
- Ziel-Editor: eine andere Art spielte zwei Haptiken auf einmal; „Break-even bis“ war nach dem Ablauf wählbar (mit einem Tag nach dem
  Ticket).
- Aus den Screenshots des Reviews: „Schnell erfassen“ unter einer anderen Karte als der Bilanz (Vorlage „Zahlen“: unter „Diese Woche“)
  klebte mit 10 pt an ihr – jetzt der Abstand einer Karte (Szene `dashCardsMoved`); in den Sätzen der Ziele bleibt eine Zahl bei ihrem
  Wort („· 6“ am Zeilenende, „Fahrten fehlten“ darunter); die Kachel „Auto-Vergleich“ sagt nur „Ticketjahr 2026/27“ (zweizeilig machte
  sie ihre Reihe höher).
- Über der Tab-Leiste stand auf jedem Tab eine leere Glas-Kapsel über dem Inhalt: das Zubehör von „Live verfolgen“ (iOS 26.0 zeigt
  `tabViewBottomAccessory` auch leer). Ab iOS 26.1 ist es nur da, während eine Fahrt verfolgt wird (`isEnabled:`; eine Zeile in
  `RootView.swift`, `LiveFollowAccessoryVisibility.swift`). Unter iOS 26.0 bleibt es wie bisher.

## 10. Auf dem Gerät prüfen

1. Übersicht ohne Änderung mit der vorherigen Version vergleichen (bis auf „Übersicht anpassen“ unten).
2. „Vorteile“ ausblenden, „Diese Woche“ nach oben ziehen, App beenden und neu starten – die Anordnung bleibt.
3. Mit VoiceOver eine Karte über „Nach oben“ verschieben und ausblenden.
4. Ein Ziel „Fahrten im Monat“ anlegen und den Ring gegen Statistik › Monatsbilanz prüfen; ein Ziel erreichen – genau ein Pop mit Haptik.
5. Kennzahlen „Fahrten“, „Kilometer“, „CO₂ gespart“ gegen Statistik vergleichen.
