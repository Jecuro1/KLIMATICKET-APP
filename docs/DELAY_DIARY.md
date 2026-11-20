# „Verspätungs-Tagebuch“ – deine Verspätungen, festgehalten

> Du hältst bei jeder Fahrt fest, ob sie pünktlich war – von Hand, mit einem Tipp. Pro Gültigkeitsmonat siehst du deine
> **persönliche** Quote, und für die Monate, die du wählst, gibt es eine Liste als PDF, falls du bei der Bahn nachfragen willst.
> Kein Netzwerk, keine Berechtigung, kein Betrag, kein „Anspruch“: ein Tagebuch, keine Entscheidung über eine Entschädigung.

Code: `Packages/KlimaCore/Sources/KlimaCore/DelayDiary/` (Regeln, Fahrten, Monate, PDF-Zeilen, Texte; Linux-Tests unter
`Packages/KlimaCore/Tests/KlimaCoreTests/DelayDiary/`, `swift test --filter DelayDiary`), `App/Sources/Features/Delays/` (Oberfläche,
PDF) und `App/Sources/Data/Repository+Delay.swift` (Schreiben).

## 1. Wo man hinkommt

| Einstieg | Wie |
|---|---|
| Fahrt-Detail | Zeile „Verspätung“ unter den Kacheln („nicht erfasst“, „pünktlich · von Hand“, „+12 Min. · von Hand“) → Eingabe-Sheet |
| Statistik | Karte „Verspätungs-Tagebuch“ unter der Zeitbilanz (Zoom in den Bildschirm, gleiches Ticketjahr wie die Statistik) |
| Fahrgastrechte | „Mein Verspätungs-Tagebuch“ unter der Schätzung mit den Gültigkeitsmonaten |
| Deep Link | `klimabilanz://delays` (Sheet; dieselben Regeln wie `klimabilanz://timebalance`: Einstellungen, Gipfelbuch, ein optionales Update, Was-wäre-wenn und eine offene Zeitbilanz schließen vorher, ein offener Fahrt-Editor, ein Pflicht-Update und der Jahresrückblick werden nie verdeckt, im Onboarding passiert nichts) |

Alle vier hängen an `DelayDiaryRelease.isLive` (bis die Screenshots angesehen sind: nur in Screenshot-Läufen sichtbar).

## 2. Eine Verspätung eintragen

Das Sheet „Verspätung“: Strecke, Zeit und – falls bekannt – Zug oben; eine große Zahl mit − und + (0 bis 240 Minuten in
1-Minuten-Schritten, Halten wiederholt), Schnellwerte „Pünktlich · +5 · +10 · +15 · +20 · +30 · +45 · +60“, darunter in Worten
und mit Symbol, was die eigene Grenze daraus macht („Zählt als verspätet (ab 5 Min.)“ / „Zählt als pünktlich (unter 5 Min.)“ –
nie nur Farbe). „Speichern“ bzw. „Als pünktlich speichern“; „Entfernen“, sobald etwas eingetragen ist (die Fahrt ist dann wieder
„nicht erfasst“). Beides mit Toast und „Rückgängig“.

- **0 = pünktlich** (Quelle „von Hand“). Nur so zählt eine Fahrt als pünktlich (§4).
- **Etappe einer Reise:** Hinweis „Ankunft dieser Etappe. Für die Reise zählt die letzte erfasste Ankunft – eine Reise ist eine Fahrt.“
- **Hin & Retour** ist ein Eintrag: „trag die größere der beiden Verspätungen ein.“
- **Quelle „live“**: Das Feld kennt sie (Zeitbilanz, Backup). Dieser Build schreibt sie nie (§9). Ändert man einen „live“-Wert, wird
  er „von Hand“; bleibt die Zahl gleich, bleibt die Quelle.
- VoiceOver: Die Zahl ist einstellbar (Wischen hoch/runter = ±1 Minute) und sagt „12 Minuten Verspätung“, „1 Minute Verspätung“,
  „Pünktlich“; die Knöpfe heißen „Eine Minute mehr/weniger“.

## 3. Der Bildschirm

- Kopf „Tagebuch · Ticketjahr 2026/27“, Titel „Verspätungen“.
- **Held „Deine Pünktlichkeit · persönlich“:** die Quote zählt einmal hoch (`CountUpText`), daneben ein Ring (pünktlich voll in
  Zirbe, verspätet gestrichelt in Morgenrot), darunter drei Zahlen mit Wort und Symbol („42 erfasst“, „5 verspätet“, „17 offen“),
  der Vorbehalt in einem Kasten (fett, §7) und die Grenze mit „Ändern“.
- **Pro Gültigkeitsmonat:** ein Balken je begonnenem Monat – pünktlich (voll) unten, verspätet (schraffiert) darüber, die Fahrten
  ohne Eintrag als gestrichelte Kappe oben; Legende in Worten. Ein Tipp öffnet den Monat unten. Selbst gezeichnet (höchstens 12
  Balken), wächst einmal.
- **Monate** (neuester oben): „Gültigkeitsmonat 9“ (+ „läuft“), Titel („November 2026“ bei Ticketstart am 1., sonst „15. Nov. –
  14. Dez.“), „12 Fahrten · 9 erfasst · 2 verspätet“, rechts die Quote oder darunter „zu wenig Fahrten für eine Quote“. Aufgeklappt:
  die verspäteten Fahrten (Datum, Strecke, Zug aus `lineSummary` bzw. Verkehrsmittel, Minuten, Herkunft; Tipp = ändern) und
  „7 Fahrten ohne Eintrag nachtragen“. VoiceOver sagt „Aufgeklappt“ / „Zugeklappt“.
- **Nachweis:** „Nachweis als PDF“ (§6).
- **So führst du das Tagebuch:** sechs Zeilen – Eintragen, ohne Eintrag zählt nichts, die Grenze, Reise = Fahrt, was die AGB messen,
  bleibt auf dem iPhone.
- **Leer** (noch nichts eingetragen): „Noch keine Verspätung eingetragen – tippe bei einer Fahrt auf Verspätung.“ und – wenn es Fahrten
  gibt – „Letzte Fahrten nachtragen“. Vor dem Ticketstart: „Dein Ticket startet bald“.
- **Einstellungen** (Regler-Symbol oben, „Ändern“ im Held): „Verspätet ab“ 3 · 5 · 10 · 15 Min. und „Welche Fahrten“ Alle · Nur Bahn
  (Zug und S-Bahn; bei einer Reise nur ihre Bahn-Etappen), „Auf Standard zurücksetzen“. UserDefaults `delaydiary.options.v1`
  (tolerant gelesen, nicht im Backup – eine Vorliebe, keine Fahrtdaten).

Bewegung nur über die Motion-Tokens (Reveal gestaffelt, Count-in einmal, Ring und Balken wachsen einmal mit `Motion.gentle`,
Auf-/Zuklappen `Motion.smooth`, Werte `Motion.snappy`); Haptik `.increase`/`.decrease` am Stepper, `.selection` bei Schnellwerten,
`.tap` beim Aufklappen, `.success`/`.warning` über den Toast. Reduce Motion und Screenshots: Endzustand.

## 4. Was zählt (KlimaCore, Linux-Tests)

- **Fahrt** wie in Zeitbilanz und Statistik (`DelayDiaryEntries`): eine Reise mit Etappen zählt einmal, mit der Verspätung ihrer
  **letzten erfassten Ankunft** (Review der Zeitbilanz, docs/TIME_BALANCE.md §7). Der Test `testRecordedFahrtenMatchTheZeitbilanz`
  prüft an 120 Zufallsfahrten, dass Tagebuch und Zeitbilanz dieselben Fahrten, dieselben erfassten Fahrten, dieselben „ab 1 Minute“
  und dieselbe Minutensumme zählen.
- **Erfasst** heißt: `delaySourceRaw` ist gesetzt. **Pünktlich** zählt nur, was eingetragen ist (0 oder unter der Grenze). Fahrten
  **ohne Eintrag** sind weder pünktlich noch verspätet: sie stehen als „offen“ / „ohne Eintrag“ da und bleiben aus der Quote
  (Entscheidung laut Plan: sonst hübschte jede vergessene Fahrt die Quote auf).
- **Quote** = pünktlich ÷ erfasst, erst ab **5 erfassten Fahrten** im Monat (bzw. im Jahr für den Held), sonst „zu wenig Fahrten für
  eine Quote“. Prozent werden unter 100 **abgerundet** (1 verspätete von 300 ist „99 %“, nie „100 %“), „< 1 %“ statt „0 %“ für einen
  kleinen Rest.
- **Grenze** standardmäßig 5 Minuten: 4 ist pünktlich, 5 und 6 verspätet (§7). Wählbar 3/5/10/15; nie unter 1 Minute.
- **Monate** sind die **Gültigkeitsmonate** des Tickets (`PerkPassengerRights.validityMonths`: vom Starttag bis vor denselben Tag im
  nächsten Monat, Wien) – die Monate, von denen Punkt 24.2 spricht und die „Fahrgastrechte“ markieren lässt. Halboffen: 23:59:59 am
  letzten Tag gehört zum alten, 00:00 zum neuen Monat. Gezählt werden nur Fahrten im Ticket und **bis jetzt**; Monate, die noch nicht
  begonnen haben, fehlen.
- Werte außerhalb von 0…240 Minuten werden beim Lesen begrenzt.

## 5. Daten

Kein eigenes Modell: das Tagebuch liest und schreibt die Felder der Zeitbilanz (`TripEntity.delayMinutes`, `delaySourceRaw`,
docs/TIME_BALANCE.md §5 – Standardwerte, nur auf dem Gerät, im JSON-Backup als `delay_minutes` / `delay_source`). Geschrieben wird
nur über `Repository+Delay.swift` (`recordDelay`, `recordOnTime`, `removeDelay`, `restoreDelays`) mit dem normalen Commit; jede
Änderung stempelt die Fahrt (`touch()`), daher rechnen Zeitbilanz („verloren“), Statistik-Karte und Tagebuch sofort neu (alle hängen
an `updatedAt`). Der Commit stößt **keinen Sync** an: die Verspätung steht in keiner Sync-Zeile.

## 6. Nachweis als PDF

„Nachweis als PDF“ öffnet ein Sheet: die Gültigkeitsmonate als Schalter (vorgewählt: die mit einer verspäteten Fahrt, sonst die mit
einem Eintrag; „Alle“ / „Keine“), „Name aufs PDF“ (nur wenn am Ticket ein Name steht), die echte Datei in einer PDFKit-Vorschau,
„Teilen“ (Share Sheet – der einzige Weg aus dem Gerät).

Das PDF (A4, `UIGraphicsPDFRenderer`, echter Text, Titel in den Dokument-Infos, kein Logo): Titel „Verspätungs-Tagebuch –
persönliche Aufzeichnung“, Ticket mit Gültigkeit, optional der Name, Erstellungsdatum, ein neutraler Einleitungssatz
(`DelayDiaryText.reportIntro`: mit der App geführt, Fahrten ab der Grenze, „Die Minuten wurden von Hand eingetragen; es sind keine
amtlichen Pünktlichkeitswerte.“ – „Live-Daten“ nur, wenn eine gelistete Zeile von dort käme), der Vorbehalt im Kasten, eine Summe der
gewählten Monate mit persönlicher Quote, dann je Monat „Gültigkeitsmonat 3 · 1. Mai 2026 – 31. Mai 2026“, seine Zahlen und eine
Tabelle **Datum · Strecke · Zug · Verspätung · Quelle** (älteste zuerst, gleiche Minute nach Strecke). Fußzeile auf jeder Seite:
„KlimaBilanz · persönliche Aufzeichnung, keine amtlichen Pünktlichkeitswerte · Seite n“. **Kein Betrag** – weder auf dem Bildschirm
noch im PDF wird aus Verspätungen Geld gerechnet (kein `Format.euro` in `Features/Delays`).

## 7. AGB Punkt 24 – gelesen und so umgesetzt

Gelesen am 20.11.2026 im AGB-PDF des KlimaTicket Ö (Punkt 24 „Fahrgastrechte bei Verspätung und Ausfall“):

- 24.1: Entschädigung, wenn bei den verwendeten Eisenbahnverkehrsunternehmen (ohne Stadtverkehre und nicht vernetzte Nebenbahnen)
  während der Geltungsdauer wiederholt Verspätungen oder Ausfälle auftreten; abgewickelt von den Unternehmen.
- 24.2: garantiert wird ein **Pünktlichkeitsgrad von 93,00 % pro Gültigkeitsmonat** bei allen Eisenbahnverkehrsunternehmen; den
  Pünktlichkeitsgrad veröffentlichen die Unternehmen auf ihren Websites.
- 24.3: liegt er in einem Gültigkeitsmonat darunter, gibt es einmal im Jahr nach Ablauf 10 % des Monatsanteils der Entschädigungsbasis.

**Punkt 24 nennt keine Minute, ab der eine einzelne Ankunft verspätet ist** – maßgeblich ist der Pünktlichkeitsgrad der Bahn, den die
Bahn selbst misst. Darum (Plan: „wenn nicht eindeutig, 5 Minuten und ‚persönlich‘“) gilt im Tagebuch eine **eigene Grenze von 5
Minuten**, und jede Quote heißt „persönlich“. Die ÖBB messen ihren eigenen Wert laut Tarifbestimmungen A.5.4.1.1 ab 5 Minuten 30
Sekunden (`PerkRightsRules.lateFromSeconds`, so steht es auch in „Fahrgastrechte“); mit ganzen Minuten lässt sich das nicht nachbilden,
und es ist eine Regel der Bahn, nicht der AGB. Der Vorbehalt auf dem Bildschirm lautet wörtlich: „Das ist deine persönliche Quote. Für
eine Entschädigung zählt laut AGB die Pünktlichkeit der Bahn im Gültigkeitsmonat (Punkt 24), nicht einzelne Verspätungen.“ Im PDF
steht er ohne „deine“ (`reportCaveat`).

**Menschliche Prüfung (offen):** Wortlaut von Punkt 24 gegen den Kommentar in `DelayDiaryRules.swift` und die beiden Vorbehalte
halten. Ergebnis hier eintragen: _noch nicht geprüft_.

## 8. Tests und Screenshots

Linux: `swift test --package-path Packages/KlimaCore --no-parallel --filter DelayDiary` – Grenze 4/5/6 und wählbare Grenzen,
Begrenzung 0…240, Monatskanten um Mitternacht (31.3. 23:59:59 / 1.4. 00:00, Sommerzeit seit 29.3.) und Starttag 15., nur begonnene
Monate und Fahrten bis jetzt im Ticket, unter 5 erfassten keine Quote, offene Fahrten außerhalb der Quote und „pünktlich“ als
pünktlich, leer ohne NaN, Reise einmal mit letzter erfasster Ankunft, „Nur Bahn“, gleiche Zählung wie die Zeitbilanz, Reihenfolge
und Auswahl des PDF, tolerante Einstellungen, Prozent abgerundet, Texte ohne „Anspruch“ und ohne Geld.

Demo (`DelayDiaryDemo.assign`, nur „von Hand“): vier von fünf Fahrten des Demo-Jahrs tragen eine Ankunft (etwa jede achte verspätet),
jede fünfte keine; die Pendelfahrten aus dem Fahrplan heißen „Railjet Xpress“. Werte und Summen bleiben gleich.

CI-Szenen (`[shots:…]`, `-KBDemo YES`, kein Netzwerk): `delayDiary`, `delayDiaryMid`, `delayDiaryBottom`, `delayDiaryMonth`,
`delayDiaryEmpty`, `delayEntrySheet`, `delayEntryOnTime`, `delayTripRow`, `delayReport`, `delayBackfill`, `delayOptions`,
`delayDiaryCard`, `delayDiaryAX5`, `delayDiaryAX5Mid`, `delayEntrySheetAX5`.

## 9. Nicht gebaut: Live-Übernahme (Stretch)

Geplant war: endet eine verfolgte Fahrt und gibt es eine gespeicherte Fahrt mit derselben `journeyRef`, wird ihre Ankunftsverspätung
als „live“ übernommen. Auf `main` passt das nicht: „Live verfolgen“ kennt die **Fahrt-ID des einen Zugs** (HAFAS, `LiveFollowTarget.tripID`),
eine gespeicherte Fahrt die **Verbindungs-Kennung** des Fahrplans (`journeyRef` = `Journey.refreshToken`) – es gibt keinen gemeinsamen
Schlüssel. Eine Zuordnung über Linie, Uhrzeit und Haltestellennamen könnte die Minuten an die falsche Fahrt schreiben; das wäre in einem
Tagebuch schlimmer als keine Übernahme. Deshalb gestrichen; dafür braucht es zuerst die Fahrt-ID am gespeicherten Trip (eigene
SwiftData-Ergänzung). `DelayDiaryText.capturedToast` und die Quelle „live“ bleiben für diesen späteren Schritt.

## 10. Nur auf dem Gerät prüfbar / nicht verifiziert

- PDF auf anderen Geräten und Programmen (Mail, Dateien, Drucken), Umbruch langer Stationsnamen in der Tabelle.
- Gefühl des Steppers (Halten wiederholt), Haptik, VoiceOver mit der einstellbaren Zahl.
- Ob Punkt 24 richtig gelesen ist (§7, menschliche Prüfung).
- Eintragen → Zeitbilanz „verloren“ ändert sich ohne Neustart: im Code über `updatedAt` gesichert, auf dem Gerät nicht angesehen.

Geräte-Checkliste:
1. Eine Fahrt öffnen, „Verspätung“ → +12 speichern: Zeile zeigt „+12 Min. · von Hand“, Statistik › Zeitbilanz zeigt die Minuten bei
   „Verspätungen“, das Tagebuch den Monat mit der Fahrt. „Rückgängig“ im Toast stellt alles zurück.
2. „Entfernen“: Fahrt wieder „nicht erfasst“, Zeitbilanz ohne die Minuten.
3. Fünf Fahrten eines Monats eintragen (eine davon +7): der Monat zeigt „80 % pünktlich“.
4. „Nachweis als PDF“ → zwei Monate → Teilen → in Dateien sichern und öffnen.
5. `klimabilanz://delays` aus Safari: das Tagebuch öffnet als Sheet.
