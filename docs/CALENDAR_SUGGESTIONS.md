# Kalender-Vorschläge

Stand: Track „Kalender-Vorschläge für Fahrten“ (November 2026). Wer es einschaltet, bekommt in der Übersicht zu Terminen der nächsten
14 Tage, bei denen ein Bahnhof oder eine Stadt mit Hauptbahnhof steht, einen Zugfahrt-Vorschlag mit Ankunftszeit und einem Tipp in den
Fahrplan. Am Tag danach fragt die App, ob du gefahren bist. Alles läuft auf dem iPhone. Dieses Dokument beschreibt, was gebaut ist,
welche Regeln gelten, was nur ein echtes iPhone zeigt (§8) und was bewusst fehlt (§9).

Code: Logik in `Packages/KlimaCore/Sources/KlimaCore/CalendarSuggestions/` (Linux-Tests unter
`Tests/KlimaCoreTests/CalendarSuggestions/`, `swift test --filter CalendarSuggestions`, 32 Tests), App in
`App/Sources/Services/Calendar/` (EventKit, Zustand, Speicher) und `App/Sources/Features/CalendarSuggestions/` (Karten,
Einstellungsseite, Erklärung, Demo-Szenen). EventKit wird nur in `App/Sources/Services/Calendar/EventKitSource.swift` importiert.

## 1. Was die Funktion verspricht – und was nicht

- **Aus, bis du sie einschaltest.** Kein Kalenderzugriff beim Start, keiner im Onboarding. Mit dem Schalter aus öffnet die App die
  Kalenderdatenbank gar nicht (der `EKEventStore` entsteht erst beim ersten Lesen).
- **Erst die Erklärung, dann iOS.** „Einschalten“ zeigt das Blatt „Kalender-Vorschläge“ mit dem Satz *„Wir lesen nur Titel, Ort und Zeit
  deiner Termine, nur auf diesem iPhone, nur während die App offen ist.“* Erst „Verstanden, weiter“ löst die Systemfrage aus
  (`requestFullAccessToEvents`, Vollzugriff zum Lesen).
- **Lieber kein Vorschlag als ein falscher** (§3): nur eindeutige Bahnhofsnamen und Städte mit Hauptbahnhof. Eine Adresse allein,
  „Zoom“, „Büro“ oder ein mehrdeutiger Name bringen keine Karte.
- **Nichts verlässt das iPhone.** Kein Server, keine KI, keine Statistik, keine Synchronisierung. Gespeichert werden keine Titel und
  keine Orte (§4). Die ÖBB werden nur gefragt, wenn du bei einer Karte „Verbindung suchen“ tippst **und** Live-Daten erlaubt hast (§6).

## 2. Bildschirme

**Einstellungen › Kalender › Kalender-Vorschläge** (`SetCalendarSection` → `CalendarSettingsPage`): Schalter (Standard aus), darunter
„Zugriff“ mit eigenem Text je Zustand, „Kalender“ (Auswahl) und „Puffer“, ganz unten „Datenschutz“.

| Zustand (`CalendarSetupState`) | Wann | Was die Seite sagt |
|---|---|---|
| `off` | Schalter aus | „Aus – die App liest keine Termine.“ (Zeile in Einstellungen: „Aus · schlägt Zugfahrten zu deinen Terminen vor“) |
| `needsPermission` | an, iOS hat noch nicht gefragt | „Noch nicht erlaubt“ + „Zugriff erlauben“ (öffnet wieder die Erklärung) |
| `denied` | in iOS abgelehnt oder später entzogen | „Zugriff verweigert“ + „In den iOS-Einstellungen ändern“ |
| `restricted` | Bildschirmzeit / Geräteprofil | „Zugriff eingeschränkt“ – ändern kann das nur, wer die Einschränkung verwaltet (kein Knopf) |
| `writeOnly` | iOS 17+ „Nur hinzufügen“ | „Nur Hinzufügen erlaubt“ – Vorschläge brauchen „Vollzugriff“ + Knopf zu den iOS-Einstellungen |
| `noCalendars` | Vollzugriff, aber kein Kalender, den die App anbietet | „Keine Kalender gefunden“ (Geburtstage und Abos zählen nicht) |
| `noneSelected` | Vollzugriff, nichts angehakt | „Kein Kalender gewählt“ |
| `active` | Vollzugriff und mindestens ein Kalender | „Aktiv – liest 2 Kalender, die nächsten 14 Tage“ |

**Kalenderauswahl**: öffnet sich nach der Erlaubnis als Blatt und steht auch auf der Seite. Angeboten werden alle Kalender außer
Geburtstagen (`EKCalendarType.birthday`) und abonnierten (`.subscription`, `isSubscribed`). Vorgewählt ist nur der Standardkalender für
neue Termine; was du danach an- oder abhakst, gilt.

**Übersicht › „Termine mit Zugfahrt?“** (`CalendarSuggestionsSection`, unter den Fahrten-Vorschlägen): höchstens drei Karten
(`CalendarSuggestionCard`):

- Kalenderblatt mit Wochentag, Tag und Monat; Titel des Termins; „Morgen · 10:00–11:30“;
- das erkannte Ziel als Abzeichen mit Symbol und Wort: **„✓ Ort erkannt: Linz Hbf“** (der Ort nennt den Bahnhof) oder
  **„⌖ Ort: Salzburg (ungefähr)“** (der Ort nennt nur eine Stadt; Ziel ist ihr Hauptbahnhof);
- eine kleine Zeitleiste „an 09:40 Linz Hbf ── 20 min ── Termin 10:00“; der Pufferbalken wächst mit den Chips „Puffer in min
  **10 / 20 / 30 / 45**“ (Standard aus den Einstellungen, 20; auf der Karte nur für diesen Termin);
- **„Verbindung suchen“**, **„Kein Zug“** (merkt sich das, Toast mit „Rückgängig“), **„Später“** (kommt am nächsten Morgen um 07:00 wieder,
  oder drei Stunden vor der Ankunft, wenn das früher ist, nie früher als in einer Stunde; Toast mit „Rückgängig“).

„Anpassen“ im Kopf öffnet die Einstellungsseite als Blatt; dasselbe macht `klimabilanz://calendar`.

**„Warst du gefahren? Innsbruck Hbf“** (`CalendarFollowUpCard`, Stretch, gebaut): am ersten und zweiten Tag nach einem Termin, zu dem eine
Karte gezeigt wurde, wenn an diesem Tag keine Fahrt zu diesem Bahnhof erfasst ist und du nicht „Kein Zug“ gewählt hattest.
„Fahrt erfassen“ öffnet das Formular vorbefüllt (Von = dein üblicher Start, Nach = der Bahnhof, Datum = Tag des Termins zur
vorgeschlagenen Ankunftszeit); gespeichert wird erst im Formular. „Nein“ beendet die Frage.

**Bedienungshilfen**: Jede Karte ist für VoiceOver ein Element mit dem ganzen Satz („Meeting Linz Hbf. Morgen um 10:00. Ort erkannt: Linz
Hbf. Vorgeschlagene Ankunft 09:40, 20 Minuten vor Beginn.“) und den Aktionen „Verbindung suchen“, „Kein Zug“, „Später“ – Ausblenden geht
also ohne Wischgeste. Die Knöpfe bleiben zusätzlich einzeln erreichbar und tragen den Termin im Namen. Bei Bedienungshilfen-Schriftgrößen
stehen Kalenderblatt und Text untereinander, „Kein Zug“ und „Später“ ebenso, „Verbindung suchen“ verliert sein Symbol (die Worte
bekommen die ganze Breite) und „Anpassen“ wandert unter die Karten. Farbe trägt nie allein Bedeutung (Symbol + Wort).

## 3. Vom Ort zum Bahnhof (Präzision vor Trefferquote)

`LocationNormalizer` zerlegt das Ortsfeld an Zeilen, Kommas, Strichpunkten, „|“ und Gedankenstrichen mit Leerzeichen (ein Bindestrich im
Namen bleibt: „Schwarzach-St. Veit“). Er entfernt Klammern, „Gleis 3“ / „Bahnsteig 4a“, Länder („Österreich“, „Deutschland“ …), merkt sich
die Stadt hinter einer Postleitzahl („5020 Salzburg“, „A-6580 St. Anton am Arlberg“) und markiert Straßenzeilen (Wort mit Hausnummer
„Mirabellplatz 4“, oder höchstens zwei Wörter mit Straßenendung „Bahnhofstraße“, „Südtiroler Platz“). Videocalls und Links
(„Zoom“, „Teams“, „Webex“, „https://…“, eine E-Mail-Adresse) und Füllwörter („Büro“, „Home Office“, „tbd“) ergeben nichts.

`CalendarTripMatcher` sucht dann **nur exakte Namen** in der mitgelieferten Bahnhofsliste (`stations.json`, Bahnhöfe, U-Bahn,
Straßenbahn-Knoten), über denselben Vergleichsschlüssel wie die Stationssuche (`StationIndex.normalize`: „Hauptbahnhof“ = „Hbf“,
„Bahnhof“ = „Bf“, „St.“ = „Sankt“, Umlaute gefaltet). Keine unscharfe Suche, keine Präfixe.

1. **Bahnhof genannt** – Name oder Alias eines Bahnhofs („Salzburg Hbf“, „Linz/Donau Hauptbahnhof“), auch umgedreht („Hauptbahnhof
   Salzburg“, „Bahnhof Linz“ → Linz Hbf, „Westbahnhof Wien“) oder mit der Stadt der Postleitzahl („Westbahnhof, 1150 Wien“,
   „Hauptbahnhof, 4020 Linz“). Ergebnis „Ort erkannt“.
2. **Nur eine Stadt** – die Stadt der Postleitzahl oder ein Ortsteil, der nur aus dem Stadtnamen besteht („Wien“, „Wien, Österreich“,
   „Mirabellplatz 4, 5020 Salzburg“). Sie zählt nur, wenn sie einen **Hauptbahnhof** hat, einen Bahnhof **genau ihres Namens**
   („Bregenz“, „Kitzbühel“) oder – sobald die Ortsdatenbank geladen ist – **genau einen** Bahnhof in ihrer Gemeinde („5620 Schwarzach im
   Pongau“ → Schwarzach-St. Veit). Ergebnis „Ort: Wien (ungefähr)“. Hinter einer Postleitzahl wird „Wien-Mariahilf“ zu Wien (nur Städte
   mit Hauptbahnhof).
3. **Sonst nichts.** Ein Name, den zwei weit auseinanderliegende Bahnhöfe tragen („Neumarkt“: am Wallersee und in der Steiermark), ist
   mehrdeutig. Allgemeine Wörter („Hauptbahnhof“, „Westbahnhof“, „Flughafen“, „Mitte“), Linien („U3“) und straßenartige Kurznamen
   („Siemensstraße“) zählen allein nie. „Lech am Arlberg“ hat keinen Bahnhof → keine Karte. „Konzerthaus Wien“ (Veranstaltungsort und
   Stadt in einem Stück) → keine Karte. Dieselbe Station als Bahnhof und U-Bahn-Station („Wien Hauptbahnhof“) zählt einmal, der Bahnhof
   zuerst.

Nur das Ortsfeld zählt, nicht der Titel („Meeting Linz Hbf“ ohne Ort ergibt nichts).

`CalendarSuggestionPlanner` wählt aus den Terminen der angehakten Kalender:

- Beginn in den nächsten **14 Tagen** (danach nichts), noch nicht begonnen (ein mehrtägiger Termin, der gestern begann, nicht mehr; einer,
  der morgen beginnt, einmal, nach seinem Beginn), die Ankunft (Beginn − Puffer) liegt noch in der Zukunft;
- **keine ganztägigen** Termine;
- von einer **Serie nur das nächste Vorkommen** (Schlüssel: `calendarItemIdentifier` bei Terminen mit Wiederholungsregel). „Kein Zug“ für
  das nächste Vorkommen bringt das übernächste nicht nach vorn; es kommt, wenn das nächste vorbei ist;
- nichts, wofür „Kein Zug“ oder ein laufendes „Später“ gilt;
- nichts, was eine erfasste Fahrt an dem Tag schon abdeckt (Ziel = der Bahnhof, nach id oder Name; bei einer Stadt jede Fahrt in diese
  Stadt, z. B. Salzburg Süd für „Salzburg“);
- nichts in der Stadt, in der du startest (der Heimatbahnhof aus den Einstellungen, sonst der häufigste Start der letzten 30 Fahrten):
  ein Termin „1060 Wien“ von Wien Meidling aus braucht keinen Zug; ein genannter Bahnhof („Wien Mitte“) bleibt ein Vorschlag;
- eine Karte je Bahnhof und Tag; höchstens drei, nach Beginn sortiert.

Zeiten: Termine kommen als absolute Zeitpunkte; Tage und Uhrzeiten werden in Europa/Wien gerechnet. Der Puffer ist ein fester Abstand
(über eine Zeitumstellung hinweg stimmt die Ankunft physikalisch: 02:30 MEZ am 25. 10. minus 45 min = 02:45 MESZ). 500 Termine brauchen
im Debug-Build unter Linux etwa 30 ms (Test: unter 50 ms; jeder Ort wird je Durchgang einmal gelesen).

## 4. Was gespeichert wird

`CalendarSuggestionPrefs` als JSON in `UserDefaults.standard` (Schlüssel `calendarSuggestions.prefs.v1`, nicht in der App-Gruppe, nicht im
Backup-Export, nicht synchronisiert):

| Feld | Inhalt |
|---|---|
| `isEnabled` | der Schalter |
| `calendarIDs`, `hasPickedCalendars` | die angehakten Kalender (EventKit-Kennungen) |
| `bufferMinutes` | 10, 20, 30 oder 45 |
| `dismissed` | „Kein Zug“: **SHA-256** aus Termin-Kennung und Beginn → Beginn; gelöscht 60 Tage nach dem Termin |
| `snoozed` | „Später“: derselbe Prüfwert → bis wann; gelöscht, sobald abgelaufen |
| `followUps` | für „Warst du gefahren?“: Prüfwert → Bahnhof-id, Bahnhofsname (aus der App, nicht aus dem Termin), vorgeschlagene Ankunft; gelöscht zwei Tage nach dem Termin |

Titel, Ort, Notizen, Teilnehmer oder Kalendernamen werden **nie** gespeichert, protokolliert (`print`, `os_log`) oder gesendet. Die Termine
selbst leben nur für eine Berechnung im Arbeitsspeicher. Keine SwiftData-Änderung.

## 5. Wann gelesen wird

Nur im Vordergrund und nur mit Schalter an: beim Erscheinen der Übersicht, bei der Rückkehr in die App, wenn sich Fahrten ändern und
wenn iOS meldet, dass sich die Kalenderdatenbank geändert hat (`EKEventStoreChanged`, nur während die App aktiv ist). Kein Hintergrund-
abruf, keine Mitteilungen. Wird der Zugriff in den iOS-Einstellungen entzogen, liest die App den Status bei der nächsten Rückkehr neu:
die Karten verschwinden ohne Fehler, die Einstellungen zeigen „Zugriff verweigert“.

`CalendarEventSource` ist die Schnittstelle: `EventKitSource` (echtes iPhone) und `FakeCalendarSource` (Demo, CI, Tests der Zustände).

## 6. Live-Daten und Rechtsrahmen

Die Vorschläge selbst brauchen **keine** Netzabfrage. „Verbindung suchen“ öffnet den Fahrplan mit Start (Heimatbahnhof oder häufigster
Start; ohne beides der Standard des Fahrplans, „Aktueller Standort“), Ziel und **Ankunft** zur vorgeschlagenen Zeit (der Fahrplan kennt
„Ankunft“, `isArrival`). Die Suche läuft durch den bestehenden Fahrplan: ohne Live-Zustimmung zeigt er seinen eigenen Hinweis und fragt
nichts ab; mit Zustimmung ist es eine gewöhnliche Fahrplanabfrage durch die gemeinsame Drossel (40 Anfragen pro Minute für die ganze App,
docs/OEBB_LIVE.md §2), ausgelöst von deinem Tipp – keine zusätzliche Last, kein Radar-Budget berührt. An die ÖBB gehen zwei Haltestellen
und eine Uhrzeit, nie Titel oder Ort des Termins.

## 7. Berechtigung und Sideload

Nur der Info.plist-Text `NSCalendarsFullAccessUsageDescription` (project.yml), **keine Entitlement**. Die AltStore-Quelle übernimmt den
Text automatisch in `appPermissions.privacy` (`scripts/make_release_metadata.py`). `scripts/check_integration.py` prüft jetzt auch: wer
`requestFullAccessToEvents` aufruft, braucht diesen Text.

Für die Linux-Typprüfung gibt es einen handgeschriebenen EventKit-Stub (`tools/typecheck/Stubs/EventKit`, in `build_stubs.py`
registriert): Status mit `fullAccess`/`writeOnly`, Anfragen (Callback und `async`), Kalender, Quellen, Prädikat, Abfrage,
Änderungsnachricht. Die `null_unspecified`-Eigenschaften sind wie im SDK implizit entpackt; der App-Code bindet sie über explizite
Optionals, damit er mit beiden Schreibweisen übersetzt. Nach dem Neuerzeugen der Stubs liefen die Mutationstests des Harness
(`tools/typecheck/mutation/run_mutations.py --catalog all`) mit 229 von 229 wie erwartet.

## 8. Was nur ein echtes iPhone zeigt (Geräte-Checkliste)

1. Einschalten → Erklärung → Systemfrage erscheint erst nach „Verstanden, weiter“; „Erlauben (Vollzugriff)“ → Kalenderauswahl mit dem
   Standardkalender vorgewählt, ohne Geburtstage und Abos.
2. Einen Kalender mit fünf echten Terminen mit Ort wählen und die Karten prüfen: welche erkannt, welche „ungefähr“, welche zu Recht ohne
   Karte. Besonders: Orte aus Apple Karten (Name + Adresse in zwei Zeilen), Exchange/Outlook, Google; englische Ortsangaben („Vienna“
   wird **nicht** erkannt).
3. Wiederkehrende Termine: nur das nächste Vorkommen; „Kein Zug“ darauf und am Tag danach prüfen, dass das folgende kommt.
4. „Verbindung suchen“ mit und ohne Live-Zustimmung.
5. In iOS-Einstellungen › Apps › KlimaBilanz › Kalender auf „Kein Zugriff“ bzw. „Nur hinzufügen“ stellen, zurück in die App: Karten weg,
   Einstellungen sagen „verweigert“ bzw. „Nur Hinzufügen erlaubt“. Kein Absturz.
6. Einen Termin im Kalender ändern, während KlimaBilanz offen ist: die Karte folgt.
7. Unter einem Sideload-Profil (AltStore/SideStore, kostenlose Apple-ID): die Kalenderfrage funktioniert ohne Entitlement (laut
   Dokumentation; hier nicht getestet).

Nicht in CI prüfbar: die echte Systemfrage und das Verhalten von „Vollzugriff“ gegen „Nur hinzufügen“ unter iOS 26, echte Kalender (iCloud,
Exchange, Google, Sprache der Orte, Kennungen von Serienterminen), EventKit unter einem Sideload-Profil, die Trefferquote mit den echten
Terminen der Besitzerin.

## 9. Bewusst nicht gebaut

- Keine Erkennung aus dem Titel, aus Koordinaten (`structuredLocation`) oder per unscharfer Suche – jede davon brächte falsche Karten.
- Keine Bushaltestellen-Ziele (nur Bahnhöfe, U-Bahn und Straßenbahn-Knoten der mitgelieferten Liste): „Lech“ bleibt ohne Karte.
- Keine englischen Städtenamen („Vienna“, „Salzburg Main Station“).
- Keine Mitteilungen und kein Hintergrundlesen.
- Kein Schreiben in den Kalender.

## 10. Demo und Screenshots

`CalendarDemoEvents` (KlimaCore) ist der erfundene Kalender von Demo, CI und Tests: zwölf Termine um Do., 19. Nov. 2026, 08:12; drei
werden Karten (Meeting Linz Hbf – Bahnhof, Konzert Salzburg – Stadt, Familienbesuch Bregenz – Bahnhof), neun zeigen je einen Grund,
warum nicht (Skitag Lech ohne Bahnhof, Zoom, ganztägig, Serie im Büro, Straße allein, im eigenen Ort, schon begonnen, mehrdeutig).
Der Test `testDemoCalendarYieldsTheThreeExpectedCards` hält das fest.

CI-Szenen (`CalendarScreenshotHost`, `-KBScreenshot <name> -KBDemo YES`, kein EventKit, keine Systemfrage, kein Netz):
`calendarSuggestions`, `calendarAX5`, `calendarAX5Bottom`, `calendarWasYouThere`, `calendarSettings`, `calendarSettingsBottom`,
`calendarDenied`, `calendarRestricted`, `calendarWriteOnly`, `calendarNeedsPermission`, `calendarEmpty`, `calendarExplain`,
`calendarPicker`, `calendarSettingsRow` (die Zeile in Einstellungen zwischen Pendeln und Arbeit & Steuer).
