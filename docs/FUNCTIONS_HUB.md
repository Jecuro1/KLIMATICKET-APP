# Funktionen – jede Funktion mit eigenem Schalter, Offline-Modus und Datenschutz-Überblick

Stand: Track „Funktionen“ (November 2026). Eine Seite unter **Einstellungen › Funktionen** beantwortet drei Fragen: *Was kann die App,
was davon ist an, und was sendet sie wohin?* Jede Funktion hat dort ihren Schalter, einen Zustand in Worten und „Was wird gesendet?“.
Ganz oben steht der **Offline-Modus**, darunter der **Datenschutz-Überblick** mit den Live-Zählern dieser Sitzung.

Code: Logik in `Packages/KlimaCore/Sources/KlimaCore/FeatureGate/` (Linux-Tests unter `Tests/KlimaCoreTests/FeatureGate/`,
`swift test --filter FeatureGate`, 19 Tests), die Zähler in `Live/Transport/RequestThrottle.swift`; App in
`App/Sources/Features/Functions/` (Speicher und Regel `FeatureCenter`, Seite, Zeilen, Datenschutz, Demo-Szenen).

## 1. Das Versprechen

- **Jeder Schalter hat eine sichtbare Wirkung.** Was du ausschaltest, verschwindet aus der App – nicht grau, sondern weg.
- **Nichts verschwindet stumm.** Solange etwas ausgeblendet ist, steht in Funktionen eine Zeile dazu
  („Zug-Radar ist aus – der Radar-Knopf im Fahrplan ist ausgeblendet.“), und die Zeile der Funktion sagt, was anders ist.
- **Neue Schalter stehen auf an.** Wer Funktionen nie öffnet, merkt nichts davon.
- **Die Zustimmung zu Live-Daten bleibt, wie du sie gesetzt hast.** Funktionen fügt nur Wege zum Ausschalten hinzu. Ohne deinen Tipp
  und ohne deine Zustimmung geht keine Live-Anfrage hinaus (docs/OEBB_LIVE.md §2) – daran ändert auch das Wieder-Einschalten nichts.

## 2. Die Seite

1. **Kopf mit Mosaik:** „13 von 15 an“ (die Zahl rollt) über 15 kleinen Kacheln – leuchtend = an, gestrichelt in der Gruppenfarbe =
   ausgeblendet (braucht etwas oder Offline-Modus), grau = ausgeschaltet, ein Punkt = an, wartet aber auf Live-Daten. Darunter Pillen
   „Offline-Modus an“ und „2 Einstiege ausgeblendet“.
2. **Offline-Modus** – ein Schalter, darunter genau, was er stoppt und was nicht (§4).
3. **Gerade ausgeblendet** – eine Zeile pro verstecktem Einstieg; ein Tipp springt zur Funktion und lässt ihre Zeile kurz aufleuchten.
4. **Datenschutz-Überblick** (§5).
5. **Die Gruppen** Live-Daten, Karte & Radar, Erfassen, Übersicht, Mitteilungen, Darstellung. Jede Zeile: Symbol, Name, eine Zeile,
   der Zustand als Text („an“, „an · wartet auf Live-Daten“, „aus“, „ausgeblendet · braucht Fahrplan & Echtzeit“, „pausiert ·
   Offline-Modus“), solange sie aus ist der Satz, was dann anders ist, und **„Was wird gesendet?“** (Popover: Empfänger, was, wann).
   Fehlt einer Funktion nur das, was sie braucht, steht direkt in ihrer Zeile „Fahrplan & Echtzeit einschalten“.
   Oben ein Suchfeld („Funktion suchen“).

Für VoiceOver ist jede Zeile **ein** Element: Name, Wert („Schalter an, ausgeblendet · braucht Fahrplan & Echtzeit. Züge in Echtzeit auf
der Karte“), Hinweis (was anders ist), Doppeltipp schaltet; „Was wird gesendet?“ und „… einschalten“ sind Aktionen der Zeile.

## 3. Die Regel (`FeatureGate`)

`FeatureGate.status(id, settings, context)` – in dieser Reihenfolge:

1. **eigener Schalter aus** → aus („aus“; die Erklärung nennt den Schalter),
2. **Offline-Modus an** und die Funktion nutzt Live-Daten (selbst oder über das, was sie braucht) → aus („… · Offline-Modus“),
3. **etwas, das sie braucht, ist aus** → aus („… · braucht Fahrplan & Echtzeit“),
4. sonst **an**; nutzt sie Live-Daten und die sind gerade nicht abrufbar, sagt die Zeile warum: „wartet auf Live-Daten“ (Zustimmung
   offen), „Live-Daten sind abgelehnt“, „ÖBB-Abfrage gerade abgeschaltet“ (Fernabschaltung), „kein Internet“. Die Funktion bleibt
   **an** – ihr Einstieg bleibt sichtbar und zeigt selbst, warum gerade nichts kommt.

| Funktion | Gruppe | Schalter liegt | braucht | ausgeblendet, solange aus |
|---|---|---|---|---|
| Fahrplan & Echtzeit | Live-Daten | Einstellungen › Live-Daten | – | (der Fahrplan zeigt „Live-Daten sind aus“) |
| Live-Ticketpreise | Live-Daten | Einstellungen › Live-Daten | – | (Preise aus den Tarif-Tabellen) |
| Live-Mitteilungen | Live-Daten | Einstellungen › Live-Mitteilungen (eigene Seite) | Fahrplan & Echtzeit | – |
| Zug-Radar | Karte & Radar | **Funktionen** (`features.v1`) | Fahrplan & Echtzeit | der Radar-Knopf im Fahrplan |
| Züge suchen | Karte & Radar | **Funktionen** | Fahrplan & Echtzeit | das Feld „Züge suchen“ im Fahrplan |
| Störungen | Karte & Radar | **Funktionen** | Fahrplan & Echtzeit | der Störungen-Knopf im Fahrplan |
| Hintergrund-Erkennung | Erfassen | Einstellungen › Fahrten erkennen (eigene Seite) | – | – |
| KI auf dem Gerät | Übersicht | Einstellungen › KI auf dem Gerät | – | – (Texte aus Regeln) |
| Vorteile-Karte | Übersicht | **Funktionen** | – | die Vorteile-Karte in Übersicht und Ticket |
| Gipfelbuch-Vorschau | Übersicht | **Funktionen** | – | die Gipfelbuch-Zeile in der Übersicht |
| Diese Woche | Übersicht | **Funktionen** | – | die Karte „Diese Woche“ in der Übersicht |
| Verlängerungs-Erinnerung | Mitteilungen | Einstellungen › Mitteilungen | – | – |
| Wochenrückblick | Mitteilungen | Einstellungen › Mitteilungen | – | – |
| Haptik | Darstellung | Einstellungen › Look & Feel | – | – |
| Offizielle Logos & Wappen | Darstellung | Einstellungen › Darstellung | – | – |

Die Schalter, die es vorher schon gab, sind **eingehüllt, nicht verdoppelt**: Funktionen liest und setzt sie dort, wo sie liegen
(`AppSettings`, Look & Feel, `LogoPackStore`, `TripDetectionService`). Verlängerungs-Erinnerung und Wochenrückblick tun beim Umschalten
dasselbe wie ihre Zeilen unter Mitteilungen (Erlaubnis fragen, Mitteilungen planen oder entfernen, `FeatureNoticeEffects`).
Haptik ist in Funktionen an/aus; „an“ heißt „Voll“, die Stufe „Dezent“ bleibt in Look & Feel. **Live-Mitteilungen** und die
**Hintergrund-Erkennung** brauchen beim Einschalten eine Erlaubnis bzw. eine Erklärung – ihre Zeile zeigt den Zustand und führt auf
ihre eigene Seite („Einrichten ›“), statt sie ohne diese Schritte einzuschalten.

Bei abgelegten Schaltern bleibt immer ein Weg: die Vorteilswelt unter Einstellungen › Vorteile, das Gipfelbuch in der Statistik.

## 4. Offline-Modus

Ein Schalter oben in Funktionen. **Er stoppt:** Fahrplan & Echtzeit, Zug-Radar, Züge suchen, Störungen, Live-Ticketpreise,
Live-Mitteilungen, die automatische Update-Prüfung und den Abruf der Live-Konfiguration (Fernabschaltung). **Er stoppt nicht:**
Konto-Sync, Tarif-Download und Logo-Pakete – die folgen ihren eigenen Schaltern; Karten laden ihre Kacheln weiter bei Apple.
Die Zustimmung zu Live-Daten bleibt unverändert; aus heißt: alles geht wie vorher weiter.

So wirkt er (alles `// MARK: funktionen`):

- `LiveDataService.timetableUnavailable` / `priceUnavailable` → `.switchedOff`. Damit sind `timetable`, `radar`, `trainSearch` und
  `priceProvider` nil, und jede Stelle, die auf diese Zustände hört (Fahrplan, Abfahrten, Pendeln, Widgets-Cache, Live verfolgen auch im
  Hintergrund-Abruf), steht still.
- Die zweite Schicht: `effectiveConfig` schaltet jeden Anbieter ab, wie ohne Zustimmung – auch der Bahnhofs-Abgleich (`StationLinker`)
  fragt dann nicht mehr. Umschalten erhöht `generation` und reicht die Konfiguration an die Clients weiter.
- `refreshConfigIfDue` lädt die Live-Konfiguration nicht.
- `UpdateService.checkIfDue(force: false)` kehrt sofort zurück; „Jetzt prüfen“ (dein Tipp) prüft weiter.
- Der Fahrplan zeigt dann nicht „Live-Daten sind aus“, sondern **„Offline-Modus ist an“** mit dem Knopf „Offline-Modus beenden“.

## 5. Datenschutz-Überblick (Funktionen › Datenschutz)

**Live-Zähler dieser Sitzung** – für ÖBB-Fahrplanauskunft, ÖBB-Ticketshop und VAO: „3 Anfragen in der letzten Minute, 41 seit dem
Start · zuletzt 14:31:12“, dazu die letzte Minute als Balken gegen die Grenze der App (40 / 12 / 20 pro Minute). Die Zahlen kommen aus
dem einen `RequestThrottle` der App (`totalAcquired`, `lastAcquired`, `counters`): gezählt wird eine Anfrage, sobald ihr Platz frei
ist und sie wirklich hinausgeht; eine vom Limit abgewiesene Anfrage zählt nicht. Nur im Arbeitsspeicher, ab dem Start der App, ohne
Inhalt – nur Zeitpunkte. Feste Zeile: „Die Zähler gelten für Live-Daten. Sync, Updates und Logo-Pakete zählen nicht mit.“
Die Seite liest die Zähler jede Sekunde, solange sie offen ist (ein Actor-Aufruf, keine Anfrage).

**Wer was bekommt** – eine Karte je Empfänger, mit dem Zustand jetzt und jeder Funktion oder jedem Dienst, die dorthin senden:

| Empfänger | von | was | wann |
|---|---|---|---|
| ÖBB-Fahrplanauskunft | Fahrplan & Echtzeit, Live-Mitteilungen, Zug-Radar, Züge suchen, Störungen, Hintergrund-Erkennung | Haltestellen, Zeiten, Zugnummern; für „In der Nähe“ der Standort auf rund 100 m gerundet; beim Radar der Kartenausschnitt; die Zugnummer der Suche; der verfolgte Zug; für einen Vorschlag einmal zwei Haltestellen und die Uhrzeit | nur mit Zustimmung: wenn du suchst oder eine Live-Ansicht offen ist, für die Widgets beim Öffnen höchstens alle 15 Minuten, beim Verfolgen auch im Hintergrund; Radar höchstens 24 pro Minute |
| ÖBB-Ticketshop | Live-Ticketpreise | Start, Ziel, Tag, Klasse, Ermäßigung | wenn ein Preis angezeigt wird |
| VAO | Live-Ticketpreise | Start und Ziel im Verbund, Tag | wenn ein Verbundpreis angezeigt wird |
| KlimaBilanz-Server (Cloudflare) | Konto & Sync, Offizielle Logos | Fahrten, Tickets, Favoriten (nur mit Konto); für Logos nichts Persönliches | beim Öffnen und nach Änderungen; Logo-Paket beim ersten Bedarf |
| GitHub | Update-Prüfung, Tarife, Live-Konfiguration | nichts Persönliches – nur der Abruf | höchstens alle 6 h (Updates) bzw. 12 h (Tarife, Live-Konfiguration) |
| Apple Karten | Zug-Radar (und jede Karte) | der Kartenausschnitt | solange eine Karte zu sehen ist |

Am Ende „Bleibt auf dem iPhone“ (KI, Vorteile-Karte, Gipfelbuch-Vorschau, Diese Woche, Erinnerungen, Haptik) und die Zeile:
„Wie bei jeder Internet-Anfrage sieht der Empfänger die IP-Adresse deines Anschlusses.“

## 6. Links und Widget-Knöpfe zu einer ausgeblendeten Funktion

`klimabilanz://radar`, der Radar-Knopf im Kontrollzentrum und „Live verfolgen“ starten (Kontrollzentrum) laufen alle über
`PlannerModel.radarRequested`. Ist der Zug-Radar aus, öffnet sich statt einer leeren Karte **Funktionen als Blatt**, scrollt zur Zeile
„Zug-Radar“ und lässt sie aufleuchten; dazu der Hinweis „Zug-Radar ist ausgeblendet – hier kannst du es wieder einschalten“. Ist gerade
Einstellungen offen, schließt es sich zuerst. Ein Link scheitert so nie stumm.

## 7. Speicher

`features.v1` in den Standard-UserDefaults (nicht in der App Group – die Widgets brauchen es nicht):
`{"version":1,"offlineMode":false,"overrides":{"radar":false}}`. Gespeichert wird nur, was vom Standard abweicht; wer einen Schalter
wieder auf an stellt, hinterlässt nichts. Lesen ist tolerant: kaputtes JSON, eine fehlende oder kleinere Version als 1 → Standard;
unbekannte Namen, Namen von Schaltern, die anderswo liegen, und Werte, die kein Wahrheitswert sind, werden übergangen; eine neuere
Version behält die Schlüssel, die beide kennen. Screenshot- und Perf-Läufe speichern nichts. Kein SwiftData, keine Sync-Daten,
nicht im JSON-Backup.

## 8. Einstiegsstellen (je eine Zeile, `// MARK: funktionen`)

| Datei | Stelle |
|---|---|
| `Features/Planner/PlannerRootView.swift` | Feld „Züge suchen“ · Radar-Knopf · Störungen-Knopf · `radarRequested` (Link/Widget → Funktionen) |
| `Features/Dashboard/DashboardView.swift` | Gipfelbuch-Zeile · „Diese Woche“ · der Block der beiden (kein Leerraum) · Vorteile-Karte |
| `Features/Ticket/TicketView.swift` | Vorteile-Karte |
| `Features/Planner/PlannerStateViews.swift` | „Offline-Modus ist an“ statt „Live-Daten sind aus“ (ein `case`) |
| `Services/Live/LiveDataService.swift` | Offline-Modus in `timetableUnavailable`, `priceUnavailable`, `effectiveConfig`, `refreshConfigIfDue`; `featureSwitchesChanged()`; `requestCounters()` |
| `Services/UpdateService.swift` | keine automatische Prüfung im Offline-Modus |
| `Core/RootView.swift` | `.featureLinkHost()` · Screenshot-Szenen |
| `Features/Settings/SettingsView.swift` | `SetFeaturesSection()` direkt unter dem Konto |

## 9. Abweichungen vom Plan (Plan vom 12.11.2026, geprüft gegen main)

- **„Vorschläge“ hat keinen eigenen Schalter.** `DashSuggestionsSection` gibt es nicht mehr; an ihrer Stelle steht der Eingang der
  Fahrten-Vorschläge (`TripInboxSection`). Den auszublenden würde Vorschläge aus „Fahrt aufzeichnen“ unentschieden verstecken. Statt
  dessen ist die Hintergrund-Erkennung eingehüllt; die Kalender-Vorschläge haben ihren eigenen Schalter (aus, bis du sie einschaltest).
- **„Warum lohnt sich mein Ticket?“ bleibt sichtbar**, auch wenn „KI auf dem Gerät“ aus ist: dann antwortet es aus den Regeln, wie es
  die KI-Seite verspricht. Der Schalter wirkt also auf die Texte, nicht auf den Knopf.
- **Störungen im Zug-Radar:** Die Ebene „Störungen“ der Karte bleibt ein eigener Schalter der Karte (die Radar-Dateien gehören dem
  Radar-Track); ausgeblendet wird der Störungen-Knopf im Fahrplan. Das Störungen-Widget bleibt, solange du es nicht entfernst.
- **Empfänger:** Updates, Tarife und Live-Konfiguration kommen von GitHub, nicht vom Cloudflare-Worker; der Worker bedient Konto, Sync
  und Logo-Pakete. Die Datenschutz-Seite sagt es so.
- **Radar-Budget** 24 pro Minute (nicht 15).
- **Kein `features`-Feld in `AppState`:** `FeatureCenter.shared` (wie `LogoPackStore.shared`, `AutoStore.shared`), damit
  `LiveDataService` und `UpdateService` ohne neue Abhängigkeit fragen können.
- **Live-Mitteilungen und Hintergrund-Erkennung** haben in Funktionen keinen direkten Schalter, sondern „Einrichten ›“ (Erlaubnisse).

## 10. CI-Szenen

`featuresHub`, `featuresRows`, `featuresInfo` („Was wird gesendet?“ des Zug-Radars offen), `featuresOffline`, `featuresPrivacy`, `featuresPrivacyBottom`, `featuresDependency` (Fahrplan & Echtzeit
aus → Radar, Zugsuche, Störungen ausgeblendet, mit Knopf), `featuresAX5`, `featuresAX5Rows`, `featuresPlanner` (Fahrplan im
Offline-Modus: Karte „Offline-Modus ist an“, keine Radar-, Störungs- und Suchknöpfe), `featuresLink` (`klimabilanz://radar` bei
ausgeschaltetem Radar), `featuresSettingsRow`. Demo-Daten, kein Netz, keine Systemabfrage; die Zähler der Szene macht ein echter
`RequestThrottle` mit festgehaltener Uhr. Die Szenen schreiben nichts in die Einstellungen des Screenshot-Laufs.

Was die Screenshot-Läufe zeigten und was daraufhin geändert wurde: Lauf 1 (CI 43491514123) nahm nur leere Bilder auf – der Szenen-Host
hatte ohne Inhalt kein `onAppear`; jetzt liegt eine leere Ebene darunter. Lauf 2 (43496973954): die Zeilen waren zu schmal, weil der
Schalter die ganze Höhe neben dem Text stand – jetzt teilen sich nur Name und Zeile die Breite mit dem Schalter; „Was wird gesendet?“
und die Offline-Liste hatten große Lücken (Label in der Liste) und wurden bei AX5 abgeschnitten; die Kopfzeile und die Pillen stapeln
sich bei großer Schrift. Lauf 3 (43504809657): ein Link und ein Hinweis scrollten zum Hinweis statt zur Zeile (beide trugen die
Funktions-ID) – die Zeilen haben jetzt eine eigene Scroll-ID. Lauf 4 (43514047053): Link und Abhängigkeit landen auf der Zeile
„Zug-Radar“; das dunkle Bild von `featuresLink` blieb leer, weil der Simulator beim ersten Bild 20 s hing (Stichprobe
`stuck-dark-featuresLink.sample.txt`, hängt in `CA::Transaction::commit` vor dem ersten Frame, nicht in der Szene) – in Lauf 2 und 3
war dieselbe Szene dunkel in Ordnung.

## 11. Geräte-Checkliste (nur auf einem iPhone prüfbar)

1. Funktionen › Zug-Radar aus → im Fahrplan fehlt der Radar-Knopf; `klimabilanz://radar` in Safari, der Radar-Knopf im Kontrollzentrum
   und „Live verfolgen“ starten (Kontrollzentrum) öffnen Funktionen an der Zeile „Zug-Radar“ mit Hinweis. Wieder an → der Knopf ist da.
2. Offline-Modus an → Fahrplan zeigt „Offline-Modus ist an“, die Pendel-Karte „Fahrplan live ist ausgeschaltet – die Karte zeigt deinen
   Plan“, die Widgets behalten ihren letzten Stand und altern; Datenschutz: die Zähler bleiben stehen. Aus → alles wie vorher, die
   Zustimmung unverändert.
3. Mit Zustimmung eine Suche und eine Minute Radar → Datenschutz zählt mit (ÖBB-Auskunft), „zuletzt“ springt; nach einem Neustart der App
   stehen alle Zähler auf 0.
4. Verlängerungs-Erinnerung / Wochenrückblick in Funktionen aus und an → unter Mitteilungen derselbe Zustand, „Alle Alarme“ zeigt die
   geplanten Mitteilungen bzw. keine.
5. VoiceOver: jede Zeile ist ein Element, Doppeltipp schaltet, Aktionen „Was wird gesendet?“ und „Fahrplan & Echtzeit einschalten“.

## 12. Grenzen

- Die Zähler gelten für Live-Daten. Sync, Updates, Tarife, Logo-Pakete und Apple-Kartenkacheln zählen nicht mit.
- Was iOS selbst sendet (Karten, Mitteilungen, Apple-Dienste), steht hier nur, soweit die App es auslöst.
- Widgets und das Kontrollzentrum zeigen ihre Knöpfe weiter; Funktionen fängt den Tipp in der App ab (§6).
