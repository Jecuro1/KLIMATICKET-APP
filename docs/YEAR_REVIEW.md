# Dein Jahr – der Jahresrückblick als Story

Eine antippbare Vollbild-Story mit bis zu neun Seiten (Intro, Ersparnis, Strecke, Lieblingsroute, Rhythmus, Unterwegs, optional
„Wofür“, Klima, Abschluss) und einem Bild zum Teilen. **Nichts davon wird gespeichert und keine Zahl wird neu erfunden:** jede
Zahl kommt aus denselben Rechnern wie Statistik und PDF-Jahresbericht (`SavingsCalculator`, `CategoryStats.honestBalance`,
`StatsAggregator`, `CarComparison`). Kein Netz, keine Logos, keine Markenfarben, keine neue Berechtigung.

Code: `Packages/KlimaCore/Sources/KlimaCore/YearReview/` (Logik, Linux-Tests) und `App/Sources/Features/YearReview/` (Oberfläche).

## 1. Einstiege

| Weg | Wie |
|---|---|
| Statistik | Karte „Dein Jahr“ nach der Ersparnis-Karte (sobald das Ticketjahr mindestens eine Fahrt hat) |
| Übersicht | Saisonkarte vom 1. Dezember bis 31. Jänner, sobald das Jahr Fahrten hat; pro Jahr wegtippbar (UserDefaults-Schlüssel `yearReview.dismissed.<Jahr>`) |
| Deep Link | `klimabilanz://year` (Standardzeitraum) oder `klimabilanz://year/2026` (Kalenderjahr) |
| Widget | Tipp auf das Widget „Jahresrückblick“ öffnet `klimabilanz://year` (nur die `widgetURL`-Zeile geändert) |

Alle vier setzen `AppState.yearReviewRequest`; `RootView` präsentiert genau eine `fullScreenCover` (`.yearReviewHost()`). Die beiden
Karten zoomen (`zoomSource` / `zoomDestination`, Motion-Tokens) in die Story, Links öffnen ohne Zoom. Offene App-Sheets
(Einstellungen, Gipfelbuch, optionales Update) schließen vorher; ein offener Fahrt-Editor und ein Pflicht-Update werden nie überdeckt.

## 2. Zeitraum

Die erste Seite bietet **Ticket-Jahr** (laufendes bzw. letztes Ticket, wie `Analytics.activeTicket`) und **Kalenderjahr YYYY**
(jedes Jahr mit Fahrten). Standard: vom 1. Dezember bis 31. Jänner das Kalenderjahr, das gerade endet bzw. eben geendet hat (wenn es
Fahrten hat), sonst das aktive Ticket-Jahr. Alles in `Calendar.vienna` (`YearReviewPeriods`).

**Ein Kalenderjahr vergleicht mit anteiligen Ticketkosten:** jedes Ticket, das das Jahr berührt, zählt `Preis × Tage im Jahr (bis heute) ÷
Tage des Tickets`. Ohne Ticket im Zeitraum ist der Preis 0 – die Story zeigt dann den Fahrtwert und behauptet keinen Gewinn. Der
Break-even-Tag eines Kalenderjahrs ist der Tag, an dem ein darin berührtes Ticket sich rentiert hat, wenn dieser Tag im Jahr liegt.

## 3. Seiten und Auslassregeln

Eine Seite ohne Daten entfällt; der Fortschrittsbalken und „Seite 3 von 6“ zählen nur die vorhandenen. Ohne Fahrt im Zeitraum gibt es
keine Seite, sondern den freundlichen Leerzustand mit „Fahrt erfassen“.

| Seite | Inhalt | Quelle der Zahlen | Entfällt, wenn |
|---|---|---|---|
| Intro | Zeitraum, Ticketname, Fahrten (zählt einmal hoch), Reisetage | `SavingsCalculator.summary` | keine Fahrt |
| Ersparnis | „Gewinn € X“ oder „noch € X bis zum Break-even“, Wert gegen Ticketpreis, Break-even-Tag (spielt die vorhandene Feier **einmal**) | `HonestBalance`, `SummitFigures` (gleiche Rundung wie Hero und Bericht) | nie (ab einer Fahrt) |
| Strecke | km, verglichen mit einer Referenzstrecke | `summary.distanceKm`, `ReferenceDistances` | 0 km |
| Lieblingsroute | Top-Route, Anzahl, zwei Verfolger (Hin und zurück zählt einmal) | `StatsAggregator.topRoutes` | Top-Route unter 2 Fahrten |
| Rhythmus | stärkster Monat mit Mini-Balkendiagramm, häufigster Wochentag, längste Serie | `months`, `weekdays`, `records` | unter 3 Fahrten |
| Unterwegs | Bundesländer, längste und wertvollste Fahrt | `StatsAggregator.records` | weder Bundesland noch längste Fahrt |
| Wofür | Zwecke nach Fahrten (STRETCH) | `CategoryStats.buckets` | unter 3 Fahrten mit Zweck |
| Klima | CO₂ gespart, Auto gegen Öffis, „Schätzung“ | `CarComparisonResult.co2SavedKg` (= Statistik › „Öffis vs. Auto“) | kein Vergleich oder 0 kg |
| Abschluss | Bild zum Teilen | – | nie |

**Ehrliche Bilanz.** Die Überschrift der Ersparnis-Seite zählt nur Fahrten, die du sonst bezahlt hättest (`HonestBalance.realSavings`,
wie die Statistik-Karte „Ehrliche Bilanz“). „Ohne Ticket wäre ich nicht gefahren“-Fahrten stehen in einer eigenen Zeile als Mehrwert, nie
als gespartes Geld. Der Break-even-Tag zählt ebenfalls nur diese Fahrten.

**Referenzstrecke.** Die Entfernung eines Paares (Wien–Graz, Wien–Linz, Wien–Salzburg, Wien–Villach, Wien–Innsbruck, Bregenz–Wien)
ist die Luftlinie (Haversine, `GeoPoint.distanceKm`) zwischen den Koordinaten der gebündelten Stationen – keine eingetippte Zahl. Gewählt wird
das längste Paar, das nicht länger ist als deine Kilometer („rund 9,0-mal von Bregenz nach Wien“); darunter das kürzeste („40 % der Strecke“).
Die Seite nennt die Luftlinie ausdrücklich. Ein Test löst jede Station des Paares in `stations.json` auf.

**CO₂.** Die Klima-Seite nimmt den Wert aus `CarComparison` (Straßenkilometer = Bahnkilometer × Faktor, wie „Öffis vs. Auto“) und nennt
ihn Schätzung. Die separate Karte „CO₂-Bilanz“ und die KPI im Jahresbericht rechnen mit Bahnkilometern ohne Faktor (`SavingsSummary.co2SavedKg`)
und liegen deshalb etwas niedriger – das ist eine bestehende Eigenheit der App, keine der Story.

## 4. Bedienung

Segmentierte Fortschrittsbalken oben; Tippen rechts (zwei Drittel) = weiter, links (ein Drittel) = zurück, Halten pausiert, nach unten
wischen schließt, 6 Sekunden pro Seite. Immer sichtbar: Schließen, Zurück, Weiter (auf der letzten Seite „Fertig“). Mit VoiceOver,
Schaltersteuerung, „Bewegung reduzieren“ und Bedienungshilfen-Textgrößen läuft nichts von selbst (nur manuell, Überblendung statt
Bewegung, bei Textgrößen ab AX1 auch ohne Tippzonen: die Seite scrollt). Auch in der Hintergrund-App oder beim Halten läuft die Uhr nicht.

Jede Seite ist **ein** Bedienungshilfen-Element mit gesprochener Zusammenfassung („Seite 3 von 8: Du bist 4.812 Kilometer gefahren …“),
der Fortschritt hat `accessibilityValue`, Diagramme tragen Textwerte, keine Information steckt nur in einer Farbe.

## 5. Das Bild zum Teilen

Letzte Seite: Live-Vorschau (`ImageRenderer`, die Vorschau ist der Export), Format **9:16** (1080 × 1920 px) oder **4:5** (1080 × 1350 px),
Stil **Hell**, **Dunkel**, **Gipfel**, Schalter **„Strecken und Namen zeigen“** – standardmäßig **aus**: dann stehen nur Gesamtzahlen im
Bild (Gewinn bzw. Prozent, Fahrten, Kilometer, CO₂, Bundesländer), keine Stationen und kein Name. Ein: Lieblingsroute, längste Fahrt,
Vergleichsstrecke und Name des Ticketinhabers. Geteilt wird mit `ShareLink` und einem PNG-`Transferable` (Muster `StatsSharePayload`); das
Teilen-Menü bietet „Bild sichern“, deshalb ist keine Fotos-Berechtigung nötig. Die PNG-Größe wird nach dem Rendern geprüft und bei Abweichung
auf exakt die Pixelzahl gezeichnet.

## 6. CI, Demo und was ungeprüft bleibt

Screenshot-Routen (`-KBScreenshot`, Demo-Daten, Animationen im Endzustand): `yearReview` (Seite 1), `yearReview2` … `yearReview8`
(Ersparnis, Strecke, Lieblingsroute, Rhythmus, Unterwegs, Klima, Abschluss), `yearReviewPurpose`, `yearReviewShare`, `yearReviewShareNames`,
`yearReviewShareSummit`, `yearReviewSharePortrait`, `yearReviewEmpty`, `yearReviewAX5`, `yearReviewAX5Share`, `yearReviewCards`.

**Nur auf dem Gerät prüfbar** (CI übersetzt den Code und zeigt statische Endzustände): Konflikte zwischen Tippen, Halten und Wischen, das
Timing der Auto-Weiterschaltung, das Gefühl der Animationen und des Zooms, Treue von `ImageRenderer` (Schriften, Verläufe) gegenüber der
Bildschirmansicht, die Ziele im Teilen-Menü, Haptik, das Öffnen aus Safari und aus dem Widget, Echtdaten mit 20 und mehr Fahrten im Vergleich
mit Statistik und Jahresbericht. Siehe die Geräte-Checkliste im Track.

## 7. Tests

`swift test --package-path Packages/KlimaCore --filter YearReview`: Standardzeitraum rund um Dez/Jän und die Zeitumstellungstage
(29. März, 25. Oktober) in Europe/Vienna, anteilige Ticketkosten, Auslassregeln für 0, 1 und 3 Fahrten, Zahlen gleich `StatsAggregator` /
`SavingsCalculator` / `HonestBalance` / `CarComparison` auf Fixtures, deterministischer Gleichstand der Top-Route (mehr Fahrten, dann höherer
Wert, dann Name), Referenzstrecke positiv und symmetrisch und aus den Stationskoordinaten, „Ohne Ticket nicht gefahren“ zählt nicht als Ersparnis.
