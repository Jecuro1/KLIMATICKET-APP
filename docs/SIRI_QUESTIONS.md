# Fragen an KlimaBilanz – Siri und Kurzbefehle

> „Wie viele Fahrten diesen Monat in KlimaBilanz?“ – Siri antwortet mit einem Satz und der Zahl, ohne dass die App aufgeht. In der
> Kurzbefehle-App heißt dieselbe Abfrage „Frag KlimaBilanz“ und gibt die Zahl als Text an den nächsten Schritt weiter.
> Code: `Packages/KlimaCore/Sources/KlimaCore/Siri/` (Tabelle, Antworten, Tests in `Tests/KlimaCoreTests/Siri/`),
> `Shared/KpiDailyTable.swift` (die Datei), `App/Sources/Features/Siri/` (Schreiber, Intent, Snippet, Seite, Screenshots).

## 1. Was es ist

- **Acht Fragen**: Fahrten · Wert deiner Fahrten · Kilometer · CO₂ gespart · Ersparnis nach Ticketkosten · Tage bis Ablauf ·
  Fehlt bis Break-even · Kosten pro Tag. Die Titel sind die Titel der Kennzahl-Kacheln der Übersicht (`KpiKind.title`), damit
  eine Frage heißt wie die Kachel. „Lieblingsstrecke“ gibt es absichtlich nicht: Stationsnamen und Orte bleiben aus Sprachantworten
  draußen.
- **Fünf Zeiträume**: Diese Woche · Dieser Monat · Letzter Monat · Ticketjahr · Kalenderjahr.
- Die vier Ticket-Fragen (Ersparnis, Tage bis Ablauf, Fehlt bis Break-even, Kosten pro Tag) gelten immer fürs Ticketjahr. Wird
  in einem Kurzbefehl ein anderer Zeitraum gewählt, beginnt die Antwort bei Ersparnis und Break-even mit „Das gibt es nur fürs
  ganze Ticketjahr.“; Tage bis Ablauf und Kosten pro Tag hängen von keinem Zeitraum ab und sagen nichts dazu.

## 2. Die Tabelle (`kpi-daily.v1.json`)

Siri und die Kurzbefehle-App öffnen den SwiftData-Speicher nie. Die App legt nach jedem Speichern eine kleine JSON-Datei in den
App-Group-Container (ohne App Group: Application Support; der Intent läuft im Prozess der App und findet sie dort auch):

| Feld | Inhalt |
|---|---|
| `version`, `generatedAt` | Format 1; wann geschrieben (ohne Zeitstempel ist die Datei ungültig) |
| `format` | Look & Feel › Zahlen: Wochenstart für „diese Woche“, Beträge und CO₂-Einheit der geschriebenen Zahl |
| `ticket` | das aktive Ticket der Übersicht: Name, Beginn, Ende, eigener Anteil am Preis und aus seiner `SavingsSummary` Fahrten, Wert, km, CO₂, Rentiert-Tag, Break-even-Prognose |
| `days` | eine Zeile je Wiener Kalendertag mit mindestens einer Fahrt in den letzten 400 Tagen: `day` („2026-10-25“), `journeys`, `value`, `km`, `co2` |

- **Dieselben Zahlen wie Statistik**: Das Ticketjahr ist die `SavingsSummary` aus `Analytics.make` (dieselbe, memoisierte
  Rechnung wie Übersicht, Statistik und Widgets). Die Tage verwenden die Bausteine dieser Summary – `totalValue`,
  `totalDistanceKm`, `EmissionFactors.savedKg` des Tarifkatalogs und „eine Reise mit Umstieg zählt einmal“. Der Test
  `SiriKpiTableTests.testDaysOfTheTicketPeriodAddUpToTheSummary` prüft für vier Fixture-Sätze (gemischte Verkehrsmittel,
  Hin & retour, eine Reise aus drei Teilstrecken, beide Zeitumstellungen, erster und letzter Moment des Tickets, ein ganzes Jahr), dass
  die Summe der Tage im Ticketzeitraum Fahrten, Wert, km und CO₂ der Summary ergibt; `testMonthsMatchStatistik` vergleicht mit den
  Monatsbalken von Statistik.
- Eine Reise zählt am Tag ihrer ersten Teilstrecke; Wert, km und CO₂ jeder Teilstrecke an deren eigenem Tag. Eine Reise über
  Mitternacht an einer Monats- oder Wochengrenze zählt also einmal (Statistik zählt sie in beiden Monaten) – selten, und die
  Ticketjahr-Antworten kommen ohnehin aus der Summary.
- **Wann geschrieben**: `SiriKpiWriter.refresh` hängt mit einer markierten Zeile an `Repository.refreshWidgets()` – nach jedem
  Speichern (gebündelt mit dem Widget-Update), beim Start, nach einer Synchronisierung, an einem neuen Tag, nach einem Ticketwechsel,
  nach „Alle Daten löschen“. Gleiche Zahlen werden erst nach einer Stunde neu geschrieben (der Zeitstempel trägt den „Stand“).
  Nicht in Screenshot- und Performance-Läufen. Atomar geschrieben: ein Leser sieht die alte oder die neue Datei.
- **Größe**: 400 Tage mit je einer Fahrt sind unter 60 KB (Test), ein typisches Jahr deutlich darunter (nur Tage mit Fahrten).
- **Robust**: Müll, eine leere Datei oder ein fehlender Zeitstempel ergeben „keine Tabelle“; ein kaputtes Feld seinen Standard, eine
  kaputte Tageszeile fällt weg (`SiriKpiTableTests.testGarbageAndBadRows`).

## 3. Zeiträume (Wiener Zeit)

| Zeitraum | Tage | im Satz | unter der Zahl |
|---|---|---|---|
| Diese Woche | Montag – Sonntag, oder Sonntag – Samstag mit Look & Feel › Zahlen › „Woche beginnt am Sonntag“ | „diese Woche“ | Diese Woche |
| Dieser Monat | 1. – letzter Tag | „im November“ | November 2026 |
| Letzter Monat | der Monat davor; im Jänner mit Jahr | „im Oktober“, „im Dezember 2026“ | Oktober 2026 |
| Ticketjahr | die Zahlen des Tickets (Summary) | „im Ticketjahr“ | Ticketjahr 2026/27 |
| Kalenderjahr | 1. Jänner – 31. Dezember | „im Jahr 2026“ | 2026 |

Grenzen in Wiener Zeit, auch um 0:30 am Monatsersten und in beiden Umstellungswochen (Tests `testBoundariesInViennaTime`,
`testWeekStartsOnMondayOrSunday`, `SiriKpiTableTests.testDayKeysAreViennaDays`).

## 4. Antworten (`KpiAnswer.make(question, period, table, now)`)

Gesprochene Zahlen (`KpiSpoken`): „212 Euro 40“, „186 Euro“, „40 Cent“, ab 1.000 € ganze Euro („1.044 Euro“) · „1 Fahrt“,
„14 Fahrten“ · „3,4 Kilometer“ (eine Kommastelle unter 10) · „3,4 Kilogramm“, „58 Kilogramm“, ab 1.000 kg „1,4 Tonnen“ (außer
„Immer kg“) · „1 Tag“, „45 Tage“ · Datum „14. Dezember“, mit Jahr, wenn es nicht das laufende ist. Siri liest „€ 212,40“ sonst als
„212 Komma 40 Euro“, deshalb steht im Satz nie ein €-Zeichen (Test). Die **geschriebene** Zahl (Snippet, Rückgabe an Kurzbefehle)
folgt Look & Feel › Zahlen: „€ 186,40“, „412 km“, „1,4 t“.

| Frage | Beispielsatz |
|---|---|
| Fahrten | „Im Oktober hast du 14 Fahrten erfasst.“ · „Diese Woche hast du 1 Fahrt erfasst.“ |
| Wert deiner Fahrten | „Der Wert deiner Fahrten im Oktober: 186 Euro 40. So viel hätten sie einzeln gekostet.“ |
| Kilometer | „Im November bist du 3,4 Kilometer gefahren.“ |
| CO₂ gespart | „Im Oktober hast du gegenüber dem Auto etwa 58 Kilogramm CO₂ gespart.“ |
| Ersparnis nach Ticketkosten | „Dein Ticket hat sich rentiert: Du bist 80 Euro 40 im Plus.“ · „Du bist noch 120 Euro im Minus. So viel fehlt bis zum Break-even.“ · nach Ablauf „Du warst …“ |
| Tage bis Ablauf | „Dein Ticket gilt noch 100 Tage, bis 28. Februar 2027.“ · „Heute ist der letzte Tag deines Tickets.“ · „Dein Ticket ist am 28. Februar abgelaufen.“ · vor Beginn „Dein Ticket beginnt am … und gilt bis …“ |
| Fehlt bis Break-even | „Bis zum Break-even fehlen noch 120 Euro. Prognose bei deinem Tempo: am 14. Dezember.“ · „… reicht es laut Prognose nicht bis zum Ablauf.“ · „Nichts mehr: Dein Ticket hat sich am 3. Oktober rentiert.“ |
| Kosten pro Tag | „Dein Ticket kostet dich 3 Euro 23 pro Tag: 1.179 Euro für 365 Tage.“ |

- **Leerer Zeitraum**: „Im Oktober hast du keine Fahrt erfasst.“ (bei jeder der vier Zeitraum-Fragen; im laufenden Ticketjahr
  „… noch keine Fahrt …“).
- **Älter als 24 Stunden**: angehängt „Stand 12. November. Öffne die App, um zu aktualisieren.“
- **Keine Tabelle**: „Öffne KlimaBilanz einmal – dann kennt Siri deine Zahlen.“ **Kein Ticket** (Ticketjahr, Ticket-Fragen):
  „Öffne KlimaBilanz und lege zuerst dein Ticket an.“ Zeitraum-Fragen für Woche, Monat und Jahr gehen auch ohne Ticket.
- Prognosen heißen „Prognose“; Tage und Kosten pro Tag rechnet `SavingsCalculator.summary` mit den Ticketdaten (dieselbe Formel
  wie die Übersicht), nicht eine eigene.
- Jede Kombination aus Frage, Zeitraum und Tabellenzustand ergibt einen Satz mit Punkt, ohne €-Zeichen, ohne „nan“
  (`SiriKpiAnswerTests.testEveryQuestionAndPeriodGivesASentence`).

## 5. Siri und Kurzbefehle

- `AskKlimaIntent` („Frag KlimaBilanz“, Kategorie „Zahlen“) mit zwei `AppEnum`-Parametern: `AskKlimaQuestion` (Standard Fahrten)
  und `AskKlimaPeriod` (Standard Ticketjahr), deutsche Titel und Synonyme („Wie viel CO₂ habe ich gespart“, „Wann läuft mein Ticket
  ab“, „diesen Monat“, „heuer“ …). Ergebnis: Dialog (der Satz), Snippet (`AskKlimaSnippet`) und die geschriebene Zahl als `String`
  („€ 186,40“; ohne Zahl der Satz) für den nächsten Schritt eines Kurzbefehls (`resultValueName` „Antwort“).
- **Ein** App Shortcut in `Shortcuts.swift` (MARK: siri), der 9. von höchstens 10 – der 10. bleibt frei
  (`scripts/test_app_shortcuts.py` zählt und prüft, dass jede Phrase die App nennt und höchstens einen Parameter hat). Phrasen:
  „\(question) in KlimaBilanz“, „Frag KlimaBilanz nach \(question)“, „KlimaBilanz \(question)“, „Wie viele Fahrten \(period) in
  KlimaBilanz“, „Fahrten \(period) in KlimaBilanz“. Eine App-Shortcut-Phrase trägt nur **einen** Parameter (iOS-26-Header:
  `AppShortcutPhrase.StringInterpolation.appendInterpolation(_: KeyPath<Intent, IntentParameter<Value>>)` mit `Value: _IntentValue`,
  einmal gelesen); der andere behält seinen Standard, Siri fragt nie nach. Deshalb gehen per Sprache: jede Frage fürs Ticketjahr
  und Fahrten für jeden Zeitraum; jede andere Kombination nur im Kurzbefehl (die Seite sagt das beim Ausprobieren).
- Der Intent liest nur die Datei; kein SwiftData, kein Netz. Er läuft im Prozess der App (es gibt keine Intents-Erweiterung).
- Kein Spotlight-Eintrag (bewusst, Plan „rejected“), keine Ticket-Frist-Aktion (Stretch, gestrichen: „Tage bis Ablauf“ deckt sie ab).

## 6. In der App

Einstellungen › KI & Siri › **Fragen an KlimaBilanz** (`SiriQuestionsView`):

1. Eröffnung mit der Siri-Kugel im Routenverlauf und einem Beispielsatz.
2. **Probier es aus**: Frage und Zeitraum als beschriftete Menüs (bei großen Schriften untereinander), darunter Siris Tafel – was
   man sagt (oder „Nur im Kurzbefehl …“), Siris Satz und das Snippet mit Zahl und Balken (Tage der Woche oder des Monats, Monate
   des Jahres; der heutige Tag bzw. Monat in der Akzentfarbe) oder, bei Ticket-Fragen, dem Anteil der Gültigkeit bzw. des
   Ticketpreises. Die Tabelle dafür baut die Seite beim Öffnen aus denselben Daten wie die Datei (`SiriKpiWriter.makeTable`), mit
   demselben `KpiAnswer` – die Seite zeigt also genau den Satz, den Siri sagt. Die Balken wachsen beim Wechsel (`Motion.smooth`,
   Skalierung statt Layout; Reduce Motion: Überblendung; Screenshots: Endzustand).
3. **So fragst du**: alle acht Fragen mit Beispiel; ein Tipp wählt die Frage oben aus und scrollt hin.
4. **Kurzbefehle**: was die Aktion zurückgibt, `ShortcutsLink` zur Kurzbefehle-App.
5. **Datenschutz** (§7).

## 7. Datenschutz

Alles bleibt auf dem iPhone. Die Datei enthält Summen pro Tag und die Zahlen des Ticketjahrs – keine einzelnen Fahrten, keine
Haltestellen, keine Orte. Antworten nennen keine Stationen. Wer die Antwort in einem Kurzbefehl weitergibt, entscheidet selbst
wohin; das steht in der Beschreibung der Aktion und auf der Seite. Kein Netz, kein Server, keine Berechtigung, keine Entitlements
(Sideload-tauglich, `scripts/check_integration.py`).

## 8. Freigabe, Demo, Screenshots

`SiriQuestionsRelease.isLive` (SiriScreenshotHost.swift) schaltet die Einstellungs-Zeile. Bis zur Freigabe war der Intent
`isDiscoverable = false` und ohne App Shortcut; freigegeben nach zwei Screenshot-Läufen (723, 724), in denen Seite und Snippet in
hell, dunkel und AX5 angesehen wurden. Screenshot-Szenen (`-KBScreenshot <name> -KBDemo YES`, Demo-Jahr, kein Netz):
`siriQuestions` (die Seite), `siriAnswer` (Wert · Letzter Monat, zum Ausprobieren gescrollt), `siriExamples` („So fragst du“),
`siriBottom` (Kurzbefehle, Datenschutz), `siriAX5` / `siriAX5Mid` (größte Schrift: Eröffnung, Ausprobieren mit Tage bis Ablauf),
`siriSnippets` / `siriSnippetsEnd` (Siris Tafel für fünf Antworten: Tage eines Monats, Monate eines Jahres, Tage bis Ablauf,
Break-even, keine Tabelle) und `siriSettings` (der Abschnitt „KI & Siri“ in Einstellungen).

Angesehen in hell und dunkel: Lauf 723 (erste Fassung), 724 (Zahl und Einheit trennen nie, Balken-Beschriftung unter dem eigenen
Balken, Eröffnung bis AX3), 725 (freigegeben: „KlimaBilanz“ trennt nicht, Prozent wie die Widgets), 726 (die Einstellungs-Zeile).
Die jeweils erste helle Aufnahme eines Laufs (`siriSnippets` in 723 und 724) blieb leer: der Simulator hing beim ersten Bild im
Farbraum-Aufbau von CoreGraphics (`stuck-light-siriSnippets.sample.txt`), dieselbe Szene in dunkel und `siriSnippetsEnd` in hell
sind vollständig.

## 9. Getestet und nicht getestet

- Linux: `swift test --package-path Packages/KlimaCore --no-parallel --filter Siri` (Tabelle, Kreuzprobe mit der Summary,
  Statistik-Monate, Reisen, Wiener Tage und Umstellungen, Fenster, JSON, Müll, Stand, alle Kombinationen, Sätze, Einzahl/Mehrzahl,
  Zeiträume, Wochenstart, Balken, Ticket-Fragen, Fortschritt, gesprochene Zahlen); Typprüfung von App und Widget
  (`tools/typecheck`), `scripts/test_app_shortcuts.py`.
- CI (macOS): Build und die Screenshots in hell und dunkel.
- **Nur auf einem iPhone prüfbar**: ob Siri die deutschen Phrasen und Synonyme erkennt; der Intent im Hintergrund (App nicht
  offen); das Auslesen der App-Group-Datei, während die App ruht; die Metadaten-Extraktion der App Intents (die Linux-Prüfung kennt
  nur die Signaturen); wie Siri das Snippet auf der Tafel darstellt.
- Gerät-Checkliste: „Wie viele Fahrten diesen Monat in KlimaBilanz“, „Wie viel CO₂ habe ich gespart in KlimaBilanz“, „Wann läuft
  mein Ticket ab in KlimaBilanz“ sagen; „Frag KlimaBilanz“ in der Kurzbefehle-App mit „Wert deiner Fahrten · Letzter Monat“ laufen
  lassen und die Zahl mit Statistik vergleichen; eine Fahrt erfassen und sofort wieder fragen; Flugmodus – die Antwort kommt
  trotzdem.
