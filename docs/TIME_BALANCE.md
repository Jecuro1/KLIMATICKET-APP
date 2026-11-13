# „Zeitbilanz“ – wie lange du in Bahn und Bus unterwegs warst

> Wie viele Stunden warst du mit dem KlimaTicket unterwegs, wie lange wärst du dieselben Wege mit dem Auto selbst gefahren, und
> wie viel Zeit haben erfasste Verspätungen gekostet? Jede Minute trägt ihre Herkunft: **eingetragen**, **aus Abfahrt und
> Ankunft** oder **geschätzt**. Kein Netzwerk, kein ÖBB-Zugriff – alles wird auf dem Gerät aus den gespeicherten Fahrten
> gerechnet. Keine Behauptung genauer Fahrzeiten.

Code: `Packages/KlimaCore/Sources/KlimaCore/TimeBalance/` (Rechenkern, Linux-Tests unter
`Packages/KlimaCore/Tests/KlimaCoreTests/TimeBalance/`, `swift test --filter TimeBalance`) und `App/Sources/Features/TimeBalance/`
(Oberfläche), dazu `App/Sources/Features/Trips/Editor/TripEdDurationRow.swift` (Zeile „Dauer“ im Fahrt-Editor).

## 1. Wo man hinkommt

| Einstieg | Wie |
|---|---|
| Statistik | Karte „Zeitbilanz“ unter „Verkehrsmittel“ (Zoom in den Bildschirm, gleiches Ticketjahr wie die Statistik) |
| Deep Link | `klimabilanz://timebalance` (Sheet über dem, was offen ist; aktives Ticketjahr) |
| Fahrt-Editor | Zeile „Dauer“ unter Datum & Uhrzeit (optional, Standard „Unbekannt“) |

Zeitraum oben: **Ticketjahr** oder **Monat** (Pfeile ‹ › durch die Monate des Ticketjahrs, keiner nach heute). Gezählt werden wie
im Auto-Vergleich nur Fahrten im Zeitraum **und bis jetzt** (eine für später heute eingetragene Fahrt zählt erst, wenn ihre Zeit da
ist).

## 2. Woher die Dauer einer Fahrt kommt (`TravelTimeResolver`)

In dieser Reihenfolge, je Fahrt (bzw. Etappe einer „Reise mit Etappen“), immer **eine Richtung** wie km und Preis:

1. **Eingetragen** – `TripEntity.durationMinutes` von 1 bis 1440 Minuten (0 = unbekannt; mehr als ein Tag wird ignoriert).
2. **Abfahrt & Ankunft** – `arrivalAt − date`, wenn beides bekannt ist: Verbindungen aus dem Fahrplan („Fahrt erfassen“ speichert
   die planmäßige Ankunft, `Repository+Journey.swift`) und von „Fahrten erkennen“ übernommene Fahrten (aufgezeichnete Ankunft).
   Bedingungen: das Datum hat eine Uhrzeit (genau Mitternacht gilt als Tag ohne Uhrzeit) und der Abstand liegt zwischen 1 und
   1440 Minuten. Nichts wird dafür geschrieben – die Dauer entsteht beim Lesen.
   *Etappen:* Eine Fahrplan-Reise speichert für jede Etappe dasselbe Datum (die Abfahrt der ersten) und die eigene Ankunft. Eine
   spätere Etappe beginnt deshalb mit der Ankunft der vorigen (ihr Anteil enthält den Umstieg); so ergeben alle Etappen zusammen
   genau erste Abfahrt → letzte Ankunft. Fehlt die Ankunft der vorigen Etappe, wird die spätere geschätzt (sonst zählte die
   erste doppelt). Hat eine Etappe ein eigenes, späteres Datum, beginnt sie dort.
3. **Geschätzt** – Tempomodell (§3).

Hin und zurück zählt doppelt (die Rückfahrt so lang wie die Hinfahrt). Der Weg zur Haltestelle und das Warten am Bahnsteig sind
nicht dabei.

Abweichung vom Plan: Der Plan nannte die Aufteilung „gemessen / geschätzt“. Planmäßige Fahrplanzeiten und eingetragene Dauern sind
nicht gemessen; die App sagt deshalb **„erfasst“** (eingetragen oder aus Abfahrt & Ankunft) gegenüber **„geschätzt“**.

## 3. Das Tempomodell (`TravelTimeModel.standard`)

Grobe Durchschnittsgeschwindigkeit inklusive Halte, je Verkehrsmittel und Strecke; zwischen den Ankerpunkten linear, unter dem
ersten und über dem letzten konstant. Mindestens 2 Minuten pro Fahrt.

| Verkehrsmittel | Ankerpunkte (km → km/h) |
|---|---|
| Zug | 5 → 30 · 20 → 50 · 60 → 70 · 150 → 95 · ab 300 → 125 |
| S-Bahn | 5 → 28 · 15 → 36 · 40 → 48 · ab 80 → 55 |
| U-Bahn | 2 → 25 · ab 10 → 32 |
| Bim | 2 → 14 · ab 10 → 17 |
| Bus, Sonstiges | 3 → 18 · 15 → 28 · 40 → 40 · ab 100 → 50 |
| Schiff | 15 |
| Seilbahn | 15 |

Beispiele: St. Anton → Innsbruck, 101 km Zug: 81 km/h → 74 Minuten (Railjet laut Fahrplan etwa 72, REX etwa 85). Wien Hbf →
Praterstern, 4,5 km U-Bahn: 10 Minuten. Innsbruck → Wien, 476 km: 3 Std. 48 Min. (Railjet etwa 4 Std. 15 Min.).

**Nie kürzer bei längerer Strecke:** Bei linearem Tempo zwischen zwei Ankern ist die Zeit `km ÷ v(km)` genau dann monoton, wenn die
Gerade durch die Anker bei 0 km noch ein positives Tempo hat. `TravelTimeModel.isMonotonic` prüft das für jedes Ankerpaar, ein Test
läuft jedes Verkehrsmittel in 100-m-Schritten bis 700 km ab. Reisen mit Etappen werden Etappe für Etappe geschätzt und addiert.

Die Werte sind gegen typische Fahrpläne plausibel, aber **nicht** gegen echte Fahrpläne vermessen (§10).

## 4. „Dauer“ im Fahrt-Editor

Unter Datum & Uhrzeit, Standard „Unbekannt“. Tippen öffnet ein Rad aus Stunden (0–23) und Minuten in 5-Minuten-Schritten. Solange
nichts eingetragen ist, steht das Rad auf dem Vorschlag – der Dauer der Verbindung (Fahrplan, aufgezeichnet) oder der Schätzung – und
speichert ihn **nicht**; erst Drehen oder „… übernehmen“ setzt eine Dauer, „Unbekannt“ nimmt sie wieder weg. Die Unterzeile sagt,
was ohne Eintrag zählt („Laut Verbindung 1 Std. 12 Min.“ / „Optional – sonst geschätzt ≈ 1 Std. 15 Min.“). Bei Hin und zurück heißt
die Zeile „Dauer pro Richtung“, bei Etappen „Dauer dieser Etappe“ (die Zeile bearbeitet die gewählte Etappe wie Verkehrsmittel und
Preis). VoiceOver: Die Wertkapsel ist einstellbar (Wischen nach oben/unten, 5 Minuten), die Räder sind es ohnehin.

Beim Speichern einer bestehenden Fahrt mit gespeicherter Ankunft (`TripEdDurationHook`): Neue Uhrzeit oder neuer Tag → die Ankunft
wandert mit (die Fahrt dauert so lang wie vorher). Neuer Start, neues Ziel oder andere Stelle in der Reise → die Ankunft wird
gelöscht (die planmäßigen Zeiten gehörten zur alten Strecke); die Fahrt wird dann geschätzt, bis eine Dauer eingetragen ist.

## 5. Daten, Backup, Sync

`TripEntity` (Shared/Models.swift, `MARK: timebalance`) bekommt drei Felder, alle mit Standardwert, ohne Umbenennung oder
Typänderung – ein Speicher von 1.0.8 migriert leichtgewichtig, ohne `VersionedSchema`:

| Feld | Standard | Bedeutung |
|---|---|---|
| `durationMinutes: Int` | 0 | eingetragene Dauer einer Richtung, 0 = unbekannt |
| `delayMinutes: Int` | 0 | Ankunftsverspätung in Minuten, nie negativ |
| `delaySourceRaw: String` | "" | "" = nicht erfasst, "manual", "live" |

Keines der Felder wird in einem `@Query`-Prädikat gelesen. **Nur auf diesem Gerät:** Die Sync-DTOs (`KlimaCloud.TripDTO`),
`schema.ts` und die Backend-Migrationen bleiben unverändert. Sobald das Backend läuft, braucht der Sync eine neue Migration
(drei Spalten, optional wie `via` / `journey_id`, mit Feature-Flag), sonst bleiben die Werte auf dem Gerät, auf dem sie erfasst
wurden. Ein Pull vom Server überschreibt sie nicht (`TripDTO.apply` setzt sie nicht).

**JSON-Backup:** Jede Fahrt-Zeile trägt zusätzlich `duration_minutes`, `delay_minutes`, `delay_source` und – wenn vorhanden –
`arrival_at` (die planmäßige/aufgezeichnete Ankunft; ohne sie würde eine Fahrplan-Fahrt nach dem Wiederherstellen geschätzt) als
flache, optionale Schlüssel neben den Sync-Schlüsseln (`TripTimeBackupRow`). Ein älteres Backup ohne die Schlüssel stellt sich wieder
her: neue Fahrten bekommen die Standardwerte, bestehende behalten ihre Werte. Falsche Typen werden verworfen, Werte außerhalb des
Bereichs bereinigt – das Wiederherstellen scheitert nie an ihnen. Tests: `TimeBalanceBackupTests` (Export einer Fahrt mit allen
Feldern → Import → Vergleich; altes JSON ohne Schlüssel; kaputte Werte). Einmal zusätzlich mit dem echten `TripDTO` (KlimaCloud) auf Linux nachgestellt: Hin- und Rückweg gleich, ein
Backup ohne die Schlüssel liest sich, und eine neue Datei liest sich auch als reines `TripDTO` (eine ältere App ignoriert die Schlüssel). **CSV bleibt unverändert**, damit ältere Exporte
importierbar bleiben.

## 6. Auto-Vergleich und Wortwahl

„Im Auto wärst du Y Std. selbst gefahren“ ist **dieselbe Zahl wie im Auto-Vergleich** (`CarComparisonResult.drivingHours`): je
Fahrt Straßen-km = km × Straßenfaktor (Standard 1,15, Öffis vs. Auto › Berechnung anpassen), Durchschnittstempo nach Länge (bis 10 km 30 km/h, bis
40 km 50, bis 120 km 70, darüber 85), ohne Stau und Parkplatzsuche. Für das Ticketjahr prüft
`testCarMinutesEqualTheAutoVergleichForTheTicketYear` die Gleichheit mit `CarComparison.compare` (drei Auto-Profile); für einen Monat
ist es dieselbe Summe über die Fahrten des Monats.

Urteil (`TimeBalanceCarVerdict`), beide Seiten grob, daher mit Toleranz (5 Minuten oder 5 % der Autozeit, das Größere):

| Fall | Text |
|---|---|
| Öffi länger | „Mehrzeit im Öffi: +N Std.“ – „Dafür Zeit zum Lesen, Arbeiten oder Entspannen – statt selbst am Steuer.“ **Nie „Zeit gespart“.** |
| etwa gleich | „Etwa so lang wie mit dem Auto“ |
| Öffi kürzer | „Zeit gewonnen: N Std.“ |

## 7. Verspätungen

Die Zeile „Verspätungen: Z Std. verloren“ erscheint nur, wenn im Zeitraum mindestens eine Fahrt eine **erfasste** Verspätung hat
(`delaySourceRaw` gesetzt). Gezählt werden nur diese Fahrten (eine Zahl ohne Quelle zählt nicht), einmal pro Fahrt; die Karte nennt,
wie viele von wie vielen Fahrten erfasst sind und wie viele verspätet waren. Verspätungen werden **nicht** zu den Stunden oben
addiert (eine eingetragene Dauer kann sie schon enthalten). In diesem Build gibt es noch keinen Weg, eine Verspätung zu erfassen –
das Verspätungs-Tagebuch (delaydiary) baut auf diesen Feldern auf. Die Demo-Daten haben deshalb keine Verspätungen; die Szene
`timeBalanceDelays` zeigt eine Vorlage.

## 8. Der Bildschirm

- Kopf „Ticketjahr 2026/27 · Zeitbilanz“, Zeitraum-Wahl (Glas-Segmente; ab AX1 zwei volle Knöpfe), im Monat der Monatsschritt.
- **Held:** „128 Std.“ zählt beim ersten Erscheinen einmal hoch (`CountUpText`), darunter Fahrten und Ø pro Woche; Balken
  erfasst (voll, Routenverlauf) / geschätzt (schraffiert) mit Legende in Worten und Prozent – nie nur Farbe.
- **Öffis vs. Auto · Zeit:** zwei Balken, der Satz, das Urteil (§6).
- **Verspätungen** (nur mit erfassten Verspätungen, §7).
- **Pro Woche:** die letzten 12 Wochen (Montag bis Montag, Wien; Sommerzeit-Wochen haben 167 bzw. 169 Stunden), erfasst unten,
  geschätzt schraffiert darüber, Wochen außerhalb des Zeitraums blass, gestrichelte Linie = Schnitt des Zeitraums, Tipp auf eine
  Woche zeigt ihre Zahlen. Selbst gezeichnet (12 Balken), damit die Schraffur zum Held passt.
- **Längste Fahrt** (eine Reise mit Etappen zählt als eine Fahrt, Hin und zurück als eine Richtung; „geschätzt“-Plakette) und
  **Ø pro Woche** (Tage vom Beginn des Zeitraums bis heute ÷ 7, mindestens eine Woche).
- **Nach Verkehrsmittel:** direkt beschriftete Balken mit Symbol und Namen.
- **So rechnen wir:** die drei Quellen, das Auto, was nicht dabei ist.

Bewegung nur über die Motion-Tokens: Reveal gestaffelt, Hero-Count-in einmal, Balken wachsen einmal (`Motion.gentle`, als Maske bzw.
`scaleEffect`), Zahlen rollen beim Zeitraumwechsel, `Motion.smooth` für den Wechsel, Haptik `.selection`. Reduce Motion: alles
sofort, Screenshots im Endzustand.

**Barrierefreiheit:** Held, Auto-Karte, Kacheln und Zeilen sind je ein Element mit gesprochenem Satz („4,5 Stunden in Bahn und Bus
unterwegs, 12 Fahrten. Davon … erfasst, … geschätzt.“); das Wochendiagramm hat einen `accessibilityChartDescriptor` (Audiograph,
zwei Reihen); der Monatsschritt ist einstellbar; ab den Bedienungshilfen-Größen stapeln sich Zeilen und Kacheln.

## 9. Tests und Screenshots

Linux: `swift test --package-path Packages/KlimaCore --no-parallel --filter TimeBalance` – Reihenfolge und Grenzen der Dauer
(0, 1, 1440, 1441 Minuten, Mitternacht in Wien), Etappen (vorige Ankunft, fehlende Ankunft, eigenes Datum, Schätzungen addieren),
Tempomodell (monoton, positiv, Ankerwerte, Stetigkeit), Hin und zurück doppelt, Wochengrenzen (Montag 0:00, Sommerzeit-Anfang 29.3.
und -Ende 25.10.2026), Verspätungssumme nur aus erfassten Fahrten, Urteil länger / gleich / kürzer, Gleichheit mit dem Auto-Vergleich,
Backup-Schlüssel.

CI-Szenen (`[shots:…]`, `-KBDemo YES`, kein Netzwerk): `timeBalance`, `timeBalanceMid`, `timeBalanceBottom`, `timeBalanceMonth`,
`timeBalanceEmpty`, `timeBalanceDelays`, `timeBalanceAX5`, `timeBalanceAX5Mid`, `timeBalanceAX5Bottom`, `timeBalanceCard`,
`tripEditDuration`. Die Demo-Daten (`TimeBalanceDemo.assign`) geben dem Pendelweg St. Anton → Innsbruck bei jeder zweiten Fahrt eine
planmäßige Ankunft (72 Min.), Innsbruck → Salzburg/Wien ebenso, einigen Fahrten eine eingetragene Dauer; Werte und Summen der Demo
bleiben gleich.

Was die Screenshot-Läufe gezeigt haben (CI-Läufe 43468668774 und 43473897047, hell und dunkel) und was danach geändert wurde:
- Die Legende des Helden zeigte 26 + 45 Std. unter „72 Std.“ – jetzt verteilen sich die abgerundeten Stunden nach dem größten Rest
  (und die Prozente auf 100 %), damit die Teile die große Zahl ergeben.
- „Bim · 0 %“ bei 21 Minuten – jetzt „< 1 %“.
- Die Statistik-Karte sagte „Im Auto … gefahren. Davon 37 % erfasst“ (das „davon“ hing am Auto) – jetzt der Auto-Satz und darunter
  „37 % erfasst · 63 % geschätzt“ am Balken.
- AX5: die Kachelzahl blieb 30 pt, während ihre Unterzeile riesig wurde – die Zahl wächst jetzt mit, Unterzeilen stoppen bei AX2;
  Verkehrsmittel-Zeilen stapeln sich; die Kopfzeile und die Zeile unter der großen Zahl stoppen bei AX2.
- Die Verspätungs-Szene zeigte die Karte nicht (sie liegt unter dem Auto-Vergleich) – die Szene scrollt jetzt dorthin.
- Danach gingen die drei Einstiege live (`TimeBalanceRelease.isLive`).

## 10. Nur auf dem Gerät prüfbar / nicht verifiziert

- **Leichtgewichtige Migration eines echten 1.0.8-Speichers.** CI startet mit frischen bzw. In-Memory-Daten; scheitert das Öffnen,
  greift der StoreLoader-Wiederherstellungsbildschirm. Geräte-Check unten.
- **Genauigkeit des Tempomodells** gegen echte Fahrpläne – nur stichprobenartig plausibilisiert (§3).
- **Gefühl des Rads** (Rasten, Haptik) und VoiceOver auf dem echten Gerät.
- Verspätungen: erst mit einem Weg, sie zu erfassen (Verspätungs-Tagebuch), echte Daten.

Geräte-Checkliste:
1. Über eine 1.0.8-Installation mit echten Fahrten installieren (App **nicht** vorher löschen), Fahrten und Statistik öffnen: nichts
   fehlt, die Karte „Zeitbilanz“ erscheint.
2. Eine Fahrt aus dem Fahrplan erfassen, Zeitbilanz öffnen: Ihre Dauer zählt als „Abfahrt & Ankunft“; Uhrzeit im Editor um 10 Minuten
   verschieben → die Dauer bleibt gleich.
3. Im Editor „Dauer“ eintragen, speichern, Backup sichern, Fahrt löschen, Backup wiederherstellen → die Dauer ist wieder da.
4. Ticketjahr der Zeitbilanz mit Statistik › Öffis vs. Auto vergleichen: dieselben Stunden am Steuer.
5. VoiceOver: Held, Wochendiagramm (Audiograph), Monatsschritt, Rad.
