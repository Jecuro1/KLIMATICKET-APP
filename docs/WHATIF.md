# „Was wäre wenn?“ – Rechenhilfe für die Ticketwahl

> Welches Ticket lohnt sich für mich, und was, wenn ich mehr oder weniger fahre? Der Rechner funktioniert vor dem Kauf (eigene
> Annahmen, keine Fahrten nötig) und mit den echten Fahrten. **Rechenhilfe, keine Beratung:** kein Kauflink, keine
> Kaufempfehlung, keine Ticketvermittlung. Kein Netzwerk, kein ÖBB-Zugriff – alles wird auf dem Gerät aus den gebündelten Tarifen
> gerechnet.

Code: `Packages/KlimaCore/Sources/KlimaCore/WhatIf/` (Rechenkern, Linux-Tests) und `App/Sources/Features/WhatIf/` (Oberfläche).

## 1. Wo man hinkommt

| Einstieg | Wie |
|---|---|
| Ticket-Ratgeber | Zeile „Was wäre wenn?“ direkt unter „Auf einen Blick“ (Push) |
| Onboarding, Schritt „Welches Ticket hast du?“ | Knopf „Erst durchrechnen“ unter der Wahl Österreich / Bundesland / Eigenes (Sheet) |
| Ticket-Tab ohne Ticket | Link „Erst durchrechnen, welches Ticket sich lohnt“ (Sheet) |
| Statistik › „Welches Ticket lohnt sich?“ | Link am Ende der Karte (Sheet) |
| Deep Link | `klimabilanz://whatif` (Sheet) |

## 2. Die zwei Modi

Schalter oben: **Meine Fahrten** (Standard, wenn in den letzten 12 Monaten mindestens 5 Fahrten erfasst sind) und **Eigene
Annahmen** (Standard sonst, und immer vor dem Kauf).

**Eigene Annahmen** – bis zu drei Strecken (Stationssuche wie beim Fahrt erfassen), je mit Stepper (− und +, je mindestens 44 × 44 pt) und Schieber „Fahrten pro
Monat“ (0 bis 60), Klasse (2./1.), dazu Ticketart (Klassik, Jugend, Senior) und Startmonat. Drei Beispiele füllen die Strecken aus
den gebündelten Stationen: Täglich pendeln (Wiener Neustadt ⇄ Wien, 40), Wochenend-Heimfahrt (Graz ⇄ Wien, 4), Gelegentlich
(Salzburg ⇄ Innsbruck, 2). **Eine Fahrt ist eine Strecke in eine Richtung** – Pendeln hin und zurück sind zwei am Tag; das steht
im Bildschirm.

**Meine Fahrten** – die erfassten Fahrten der letzten 12 Monate mit ihren eigenen Preisen; Schieber „Fahrten ×0,5 bis ×2“, Schalter
„Juli und August ohne Fahrten“, „Nur ein Bundesland“ (nur Fahrten, die ganz in einem Bundesland liegen; die Chips zeigen die
Bundesländer deiner Fahrten) und „Mit 1. Klasse“.

Ergebnis in beiden Modi: Rangliste Einzeltickets gegen die passenden KlimaTickets (Ö und regionale), der Satz „Ab 7 Fahrten pro
Monat lohnt sich das KlimaTicket Ö“, der Unterschied pro Jahr („€ 312 weniger im Jahr“ / „kostet € 85 mehr“) und ein
12-Monats-Kostendiagramm (zwei Linien, Break-even als Fahne), das beim Ziehen mitläuft. „Szenario speichern“ (höchstens 5, nur auf
diesem Gerät) und „Teilen“ (reiner Text).

Leerzustände: keine Strecke → Einladung mit den drei Beispielen; 0 Fahrten pro Monat → „Dann lohnt sich kein Ticket“; „Meine
Fahrten“ ohne Fahrten → Hinweis mit Wechsel zu „Eigene Annahmen“; kein Ticket deckt mindestens ein Zehntel der Fahrten ab → „Kein KlimaTicket deckt genug deiner Fahrten ab“; ein Unterschied unter 10 € im
Jahr heißt „kaum ein Unterschied“ (statt einer großen Zahl). Der Katalog ist gebündelt – es gibt keinen Ladezustand.

## 3. Wie gerechnet wird

**Einzeltickets.** Annahmen: pro Strecke und Monat der Preis einer Fahrt aus `FareEstimator` (die exakte ÖBB-Relationstabelle, wo
sie die Strecke kennt, sonst das Entfernungsmodell, in Städten der Stadttarif), mit dem Tarifindex des Monats (`fareIndex`, z. B.
+ 3,5 % ab 13.12.2026: gilt ab dem Monat, in dessen Mitte er greift). Meine Fahrten: der gespeicherte Preis jeder Fahrt, Hin und
Zurück zählt doppelt.

**Tickets.** Die Produkte des Katalogs mit der gewählten Ticketart (ohne Lokal-Tickets, `isLocal`) und – falls vorhanden – das eigene
Ticket. Preis = `TicketProduct.price(forStart:)` für den Starttermin. Abdeckung: KlimaTicket Ö deckt jede Fahrt außer Auslandsfahrten;
ein regionales Ticket nur Fahrten, deren Bundesländer alle seine eigenen sind (`covers(states:)`; Fahrten ohne Bundesland nur Ö, wie
im Ticket-Vergleich der Statistik). Gesamtkosten = Ticketpreis + Normalpreis der nicht abgedeckten Fahrten – **dieselbe Regel wie
`TicketComparator`**.

**Break-even.** „Ab N Fahrten pro Monat“: die Fahrten pro Monat, bei denen das Ticket genauso viel kostet wie Einzeltickets, die
Mischung der Strecken bleibt gleich (aufgerundet). Das Diagramm zeigt dasselbe: das Ticket wird zu Monat 0 bezahlt, Einzeltickets
steigen mit jeder Fahrt; die Linien kreuzen sich innerhalb des Jahres genau dann, wenn das Ticket günstiger ist, und der Satz und der
Kreuzungsmonat stimmen auf einen Monat überein (Test `testBreakEvenSentenceMatchesChartCrossing`).

**1. Klasse.** Einzeltickets × Faktor des Katalogs (1,951); KlimaTicket Ö plus das 1.-Klasse-Upgrade zum Listenpreis (`TicketAddOn`);
regionale Tickets gelten nur in der 2. Klasse, die Fahrten zählen dann als nicht abgedeckt. Das ist ein Modell – ob ein
Klassenwechsel am Schalter anders kostet, rechnen wir nicht.

**Meine Fahrten – Zeitraum.** Die Fahrten der letzten 12 Monate, gezählt ab dem ersten Ticketstart oder der ersten Fahrt. Der Bildschirm
spricht von „pro Jahr“, deshalb werden Fahrten, die weniger als ein Jahr umfassen, immer aufs Jahr hochgerechnet (× 365 ÷ beobachtete
Tage; weniger als 30 Tage Beobachtung zählen als 30, höchstens × 12,2; ab 348 Tagen gilt das Fenster als ganzes Jahr). Der Bildschirm
sagt es: „Grundlage: 79 Fahrten seit 2. Mär., aufs Jahr hochgerechnet (×1,6)“. **Bewusste Abweichung von der Statistik:** der
Ticket-Vergleich dort beantwortet „bisher“ und rechnet erst unter einem Viertel des Jahres hoch; er stellt bei 225 beobachteten
Tagen die Fahrten von 225 Tagen dem Preis eines ganzen Ticketjahres gegenüber („kaum ein Unterschied“, wo die Jahreshochrechnung
mehrere hundert Euro Ersparnis zeigt). Bei einem vollen Jahr Fahrten (Faktor 1) sind die Zahlen die des Ticket-Vergleichs (Test
`testFactorOneEqualsTicketComparatorForTheDemoYear`; die Hochrechnung selbst: `testAnnualizationFactorIsTheComparatorsFactor`).
Der Schieber ×0,5 bis ×2 skaliert die Fahrtwerte (`TicketComparator` selbst klemmt Faktoren unter 1 auf 1, deshalb rechnet der
Rechner mit skalierten Preisen); der Ticketpreis skaliert nicht. Der Break-even „ab N Fahrten“ hängt weder vom Schieber noch von
der Hochrechnung ab. Liegt die eigene Fahrtenzahl schon über dem Break-even, obwohl die aufgerundete Zahl darüber liegt (9,5
Fahrten im Monat, „ab 10“), steht die genaue Schwelle („ab ca. 9,3 Fahrten“).

**Ränge.** Günstigste Gesamtkosten zuerst; bei gleichen Kosten (auf den Cent) das günstigere Ticket, dann die ID – die Reihenfolge
flackert nie. Gezeigt werden Einzeltickets, das eigene Ticket und die besten vier Tickets, die mindestens ein Zehntel der Fahrten abdecken (ein
Ticket eines anderen Bundeslands, das 3 % der Fahrten trifft, ist Rauschen); dieselbe Schwelle gilt für „das beste Ticket“ im
Satz oben.

**Eingaben werden geklemmt:** Fahrten pro Monat 0 bis 60, höchstens drei Strecken, Schieber 0,5 bis 2 (NaN = 1), ungültige Monate
fallen weg, Fahrtwerte, die nicht endlich oder negativ sind, werden ignoriert.

## 4. Ehrlichkeit

- Die Preise sind **Modellwerte für reguläre Einzeltickets** (ÖBB-Standardticket, ohne Sparschiene, Vorteilscard und Aktionen). Der
  Bildschirm sagt das in einer Zeile mit „Tarifstand `<Datum>`“ (`TariffCatalog.updatedAt`).
- Kein Kauflink, kein Shop-Deep-Link, kein `URLSession` im Ordner `Features/WhatIf` (Prüfung per `grep`).
- Bei „Meine Fahrten“ sagt die Fußzeile „Normalpreise deiner erfassten Fahrten“, bei „Eigene Annahmen“ „reguläre Einzeltickets“.
  Ein späterer Startmonat bekommt den Ticketpreis des Tarifstands; der Bildschirm sagt, dass Preisänderungen, die dort nicht
  stehen, nicht eingerechnet sind. Jugend- und Senior-Tickets tragen den Hinweis, dass es sie nur für bestimmte Altersgruppen gibt.
- Ein gespeichertes Szenario zeigt, wann es gerechnet wurde („Gerechnet am 12. Nov. 2026“); beim Öffnen wird neu gerechnet.
- Zahlen nur über `Format.*` (de-AT), Farben und Abstände über `Theme`, Bewegung über `Motion`/`MotionPolicy`.

## 5. Plausibilität der Preise (Stichprobe, 12.11.2026)

Fünf Strecken aus den Demo-Daten gegen die ÖBB-Relationstabelle (`relations.bin`, Tarif ab 14.12.2025, 178.013 Relationen) und das
Entfernungsmodell, das einspringt, wenn die Tabelle die Strecke nicht kennt:

| Strecke | Tabelle | Modell | Abweichung |
|---|---|---|---|
| St. Anton – Innsbruck Hbf | € 23,50 | € 23,70 | + 1 % |
| St. Anton – Bludenz | € 8,60 | € 9,80 | + 14 % |
| Innsbruck Hbf – Wien Hbf | € 92,80 | € 85,50 | − 8 % |
| Innsbruck Hbf – Salzburg Hbf | € 55,20 | € 37,80 | − 31 % |
| Graz Hbf – Klagenfurt Hbf | € 32,00 | € 26,90 | − 16 % |

Die App nimmt, wo es sie gibt, immer die Tabelle (alle Fahrten der Beispiele und der Demo-Daten); die Abweichung des Modells betrifft
nur Strecken ohne Tabellenzeile (vor allem Bus- und Bimhaltestellen). Größte Lücke der Stichprobe: Innsbruck – Salzburg (die
Tabelle rechnet über das Deutsche Eck, das Modell nach Entfernung). Der Bildschirm zeigt je Strecke, woher der Preis kommt
(„ÖBB-Tarif“, „Stadttarif“, „Modell nach Entfernung“).

## 6. Daten, Speicher, Rechte

Kein SwiftData-Feld, keine Migration. Gespeicherte Szenarien: `UserDefaults`, Schlüssel `kb.whatif.scenarios.v1`, versioniertes JSON
(`WhatIfScenarioBook`), höchstens fünf, **nicht synchronisiert**; gespeichert werden die Eingaben, nicht die Zahlen. „Alle Daten löschen“ (Einstellungen) entfernt auch die
gespeicherten Szenarien (`WhatIfStore.clear()`). Eine beschädigte
oder neuere Speicherung ergibt ein leeres Buch, nie einen Absturz. Keine neue Berechtigung, kein Entitlement, kein Netzwerk.

## 7. Tests und Screenshots

- Linux: `swift test --package-path Packages/KlimaCore --filter WhatIf` – Break-even von Hand gerechnet (zwei Fixtures), Kosten steigen
  mit den Fahrten, Jugend/Senior, regionales Ticket deckt nur seine Länder, Startdatum ändert den Preis, Tarifindex im Jahr,
  deterministischer Gleichstand, 0/negativ/riesig geklemmt, Stationen ohne Preis, Gleichheit mit `TicketComparator` für das Demo-Jahr
  (Faktor 1, Hochrechnung, Schieber, Juli/August, Bundesland, 1. Klasse), Beispiele auf den echten Katalog, Szenario-Buch.
- CI-Screenshots (`-KBScreenshot`, Demo-Daten, kein Netzwerk): `whatIf`, `whatIfBottom`, `whatIfFilters`, `whatIfFiltersBottom`,
  `whatIfControls`, `whatIfPrePurchase`, `whatIfPreBottom`, `whatIfRoutes`, `whatIfWeekend`, `whatIfOccasional`, `whatIfEmpty`,
  `whatIfExtreme`, `whatIfAX5`, `whatIfAX5Mid`, `whatIfAX5Bottom`, `whatIfSaved`, `whatIfSheet` – hell und dunkel. Bei
  Accessibility-Schriftgrößen stapeln sich Moduswahl und Klassenwahl als volle Knöpfe, die Zeilen brechen um.

## 8. Nur auf dem Gerät prüfbar / nicht verifiziert

- Gefühl und Haptik der Schieber und Stepper, Lesbarkeit des Diagramms, die Audio-Grafik und die Sprachausgabe der Werte
  („12 Fahrten pro Monat“, „×1,5, ca. 18 Fahrten pro Monat“) mit VoiceOver.
- Die Genauigkeit der geschätzten Preise gegenüber dem ÖBB-Shop: Relationstabelle und Entfernungsmodell sind Modelle, keine
  Shop-Antworten; Sparschiene, Vorteilscard und Aktionen fehlen absichtlich.
- Das 1.-Klasse-Modell (Upgrade-Listenpreis, regionale Tickets nur 2. Klasse) ist eine Vereinfachung.
- Die Ansage des Ergebnisses nach Änderungen (entprellt, 0,9 s Pause) – Verhalten mit VoiceOver am Gerät.
- Ob das Ziehen der Schieber im Perf-Tour flüssig bleibt (Qualitäts-Track) – das Diagramm wird je Bildschirmwert neu gezeichnet
  (26 Punkte, ohne Animation).
