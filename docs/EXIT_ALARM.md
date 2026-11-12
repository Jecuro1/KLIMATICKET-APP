# Aussteige-Wecker

Stand: Track „Aussteige-Wecker“. Auftrag des Eigentümers: „Die App weckt dich kurz vor deiner Endstation, per Standort, auch im Schlaf.“
Dieses Dokument beschreibt, was gebaut ist, welche Regeln gelten, was nur ein echtes iPhone beweisen kann (§9) und wo die Grenzen liegen (§8).
Live-Regeln bleiben in `docs/OEBB_LIVE.md` (§2 Rechtsrahmen, §R8 Live verfolgen).

## 1. Überblick

- Ein Wecker gehört zu einem **Halt** einer **verfolgten Fahrt** (Live verfolgen, `docs/OEBB_LIVE.md` §R8). Bis zu drei Wecker gleichzeitig, einer je Fahrt und Halt.
- **Zwei Wege zu klingeln, der frühere gewinnt, nie doppelt:**
  1. **Nach Fahrplan** (ohne Standort): ein echter Wecker für die erwartete Ankunft minus den Vorlauf. Er rückt mit, wenn sich die Verspätung ändert.
  2. **Nach Standort** (CLLocationManager): ein Kreis um den Halt (Geofence) und leise Standort-Updates, solange ein Wecker scharf ist und die Fahrt läuft. Er klingelt, wenn der Kreis betreten wird oder die GPS-Schätzung den Zeitpunkt erreicht.
- **Vorlauf:** bei Ankunft, 2, 5 oder 10 Minuten vorher (Standard 5, einstellbar).
- **Alles Entscheidende ist reine Logik in KlimaCore** (`Packages/KlimaCore/Sources/KlimaCore/ExitAlarm/`) mit 69 Linux-Tests. Apple-spezifisch sind nur drei dünne Adapter (Standort, Wecker, Speicher) hinter Protokollen.

## 2. Einstiege (alle drei öffnen dasselbe Blatt)

Jeder Einstieg ist ein dünner Knopf. Das gemeinsame Blatt ist `ExitAlarmSheet` (`App/Sources/Features/ExitAlarm/ExitAlarmSheet.swift`); der Einstieg reicht nur eine verfolgbare Fahrt (`ExitAlarmSheetInput`) hinein.

| Einstieg | Wo | Halte |
|---|---|---|
| 1. Live verfolgen | Block „Aussteige-Wecker“ oben im Detail der Verfolgung (`ExitAlarmFollowSection` in `LiveFollowDetailSheet`) | Halte der Verfolgung: vom Einstieg bis zum Ende der Teilstrecke |
| 2. Zug-Radar | „Wecker für diesen Zug“ im Fahrtenblatt (`RadarTripSheet`) | Alle Halte, die der Zug noch nicht erreicht hat |
| 3. Verbindungsdetail | Glocken-Symbol in der Leiste (`ConnectionDetailView`) | Halte der ersten Fahrt-Teilstrecke der Verbindung |

Das Blatt wählt den Halt (Standard: das Ende der Teilstrecke; jeder Halt der Teilstrecke geht, auch ein Umstieg), den Vorlauf, erklärt in zwei Zeilen die beiden Wege mit ihrem Stand (welche Art Wecker, welche Standort-Erlaubnis) und stellt den Wecker. Einstellung „Auch für Umstiege“ (Standard an): ist das Ende der Teilstrecke ein Umstieg, ist es vorgewählt.

**Der Wecker lebt mit der Verfolgung.** Beim Stellen startet das Blatt die Verfolgung der Fahrt, wenn sie nicht schon läuft; die Verfolgung liefert die Fahrplan-Antworten (`LiveFollowTracker.pollOnce` → `ExitAlarmService.followUpdated`). Endet die Verfolgung (angekommen, Fahrt ersetzt, „Nicht mehr verfolgen“), enden ihre Wecker. Alle Wecker einer Fahrt teilen sich also die Anfragen der Verfolgung; der Wecker erzeugt keine eigenen Anfragen (Rechtsrahmen `OEBB_LIVE` §2: 40 Anfragen je Minute für die ganze App, kein Standort in Anfragen).

## 3. Regeln (ExitAlarmPlanner)

`ExitAlarmPlanner` ist eine reine Zustandsmaschine: Ereignisse und die Uhrzeit hinein, neuer Zustand und eine Liste von Wirkungen heraus. Er liest keine Uhr und kennt keinen Standortdienst.

**Auslösemoment** = das Frühere aus *Fahrplan-Ankunft (mit gemeldeter Verspätung) minus Vorlauf* und *GPS-Ankunft minus Vorlauf*.
- **GPS-Ankunft** = Zeit des Fixes + Restweg ÷ geglättete Geschwindigkeit. Der Restweg wird **entlang der Halte** gemessen (nächster Punkt auf dem Linienzug Einstieg bis Ziel), nicht in Luftlinie; weiter als 6 km vom Linienzug heißt „nicht auf dieser Fahrt“ (Ersatzbus, Auto) und gibt keine GPS-Schätzung. Ohne Linienzug zählt die Luftlinie mit Umwegfaktor 1,15.
- **Geschwindigkeit** wird mit Zeitkonstante 30 s geglättet; Fixes mit Genauigkeit über 300 m oder in falscher Reihenfolge zählen nicht.
- **Stillstand:** unter 3 m/s gibt es **keine** GPS-Ankunft (kein Teilen durch Null, nie „unendlich“); der Fahrplan trägt den Wecker. Steht der Zug wieder, kommt die Schätzung zurück.
- **Tunnel / GPS weg:** ein Fix, der älter als 90 s ist, speist die Schätzung nicht mehr. Der Fahrplan allein klingelt, am Fahrplan-Moment.
- **GPS klingelt nur nach Bestätigung:** zwei Fixes hintereinander müssen „jetzt“ sagen. Ein einzelner wilder Fix klingelt nichts.
- **Geofence:** Kreis um den Halt mit Radius `max(1500 m, Geschwindigkeit × Vorlauf)`, höchstens 20 km (das System kappt zusätzlich). Geschwindigkeit: geglättete, sonst die Durchschnittsgeschwindigkeit der Teilstrecke, sonst 25 m/s. Der Radius folgt einer Geschwindigkeitsänderung ab 25 %. Betritt man den Kreis, obwohl der Fahrplan noch mehr als 30 Minuten bis zum Moment sagt, wird das nicht geglaubt.
- **Hysterese:** die Karte pulsiert („gleich“) ab 3 Minuten vor dem Moment und fällt erst zurück auf „scharf“, wenn der Moment um mehr als 3 + 2 Minuten wegrückt. Eine wackelnde ETA flackert nicht.
- **Verspätung wächst → neu scharf:** der Fahrplan-Wecker wird auf den neuen Moment verschoben (Toleranz 30 s, kleinere Änderungen verschieben nichts). Rückt der Fahrplan *vor* den schon gestellten Wecker, klingelt die App sofort und streicht den späten.
- **Nie doppelt:** Wer zuerst klingelt, setzt `fired`; danach ist alles still. Klingelt der Standort zuerst, wird der gestellte Fahrplan-Wecker erst abgesagt und dann geklingelt („cancel, ring“). Klingelte der Fahrplan-Wecker zuerst (das System macht das auch bei geschlossener App), vermerkt die App es nur.
- **„Du bist an X vorbeigefahren“:** ein zweiter Hinweis, genau einmal, wenn der Halt vorbei ist und der Wecker nicht quittiert wurde: nach GPS (nächste Annäherung unter 3 km, danach über 3 Fixes mindestens 600 m weiter weg, bei Fahrgeschwindigkeit) oder, wenn kein frischer Fix da ist, nach Fahrplan (90 s nach der Abfahrt des Halts; der letzte Halt kann nicht überfahren werden).
- **Zustände:** `armed` → `approaching` → `fired` → `acknowledged` oder `snoozed` (→ `fired` nach 5 Min, genau einmal je Aufschub, bis 15 Min, kein Aufschub nach „vorbeigefahren“) → `ended` mit Grund: `completed`, `expired` (Ankunft + 10 Min), `cancelledByUser`, `followEnded`, `killSwitch` (Live-Daten aus).
- **Standort-Bedarf** (`locationNeed`): vor dem Fenster (10 Min vor der Abfahrt am Einstieg) nur der Kreis; im Fenster leise Updates; nach `fired` Updates, bis quittiert oder „vorbeigefahren“ gemeldet; danach nichts.

## 4. Bedienung

- **Karte** (`ExitAlarmCard`): Ring, der sich zum Zielhalt füllt (Flagge bei 12 Uhr), Minuten in der Mitte (rollende Ziffern), Titel „Aussteigen in Linz Hbf“ („Umsteigen in …“ bei Umstieg), „Weckt dich um 17:42, 5 Min vor der Ankunft“, **„noch 12 Min · ca. 18 km“ mit dem Zusatz „geschätzt“ oder „laut Fahrplan“**. Die Entfernung erscheint nur mit einem frischen Fix auf der Fahrt, sie wird nie erfunden. Ab „gleich“ pulsiert der Ring (Dauerbewegung nur sichtbar und ohne „Bewegung reduzieren“). Drei Fakten darunter: Vorlauf, Art des Weckers, Standort-Stand.
- **Vollbild „Aussteigen!“** (`ExitAlarmFiredView`): Haptik alle 1,6 s, der Halt in großen Buchstaben, Gleis wenn bekannt, Linie, Ankunft mit Verspätung, **Quittieren** und **5 Min später**. Bei „vorbeigefahren“ steht dort „Du bist an X vorbeigefahren“ und „Verstanden“. Das Vollbild liegt in einem **eigenen Fenster** über allem (`ExitAlarmWindow`), auch über Blättern. Hintergrund: der dunkle Farn-Verlauf mit Morgenrot-Glühen, damit weißer Text immer lesbar ist.
- **Live Activity:** solange der Wecker scharf ist, zeigt die bestehende Live Activity (Sperrbildschirm und erweiterte Insel) „Aussteigen in 4 Min“ (`FollowExitAlarmLine`, zählt von selbst). Der Wert kommt aus `FollowLiveState.exitAlarm` (optional, alte Zustände dekodieren als `nil`).
- **Wecker-Ton von iOS (AlarmKit):** die Wecker-Live-Activity der Erweiterung (`ExitAlarmLiveActivity`) zeigt „Aussteigen!“ und den Halt; die Taste „Öffnen“ öffnet die App (`ExitAlarmOpenIntent`).
- **Einstellungen › Aussteige-Wecker:** Vorlauf-Standard, Ton (Standard, Glocke, Signal, Sanft; die drei Töne erzeugt `scripts/gen_exit_alarm_sounds.py`, keine Fremdrechte), „Auch für Umstiege“, **„Wecker testen“** (klingelt in 10 s wie ein echter), **Art des Weckers** (Wecker-Ton, auch lautlos / Mitteilung, lautlos möglich / noch nicht erlaubt), **Standort** (Immer / Nur beim Verwenden / noch nicht gefragt / in iOS aus) und ein Knopf zu den iOS-Einstellungen.

## 5. Testbarkeit

- `ExitAlarmLocationProviding` und `ExitAlarmScheduling` (KlimaCore) sind die Protokolle; dazu `ExitAlarmPersisting`. Echt: `CLExitAlarmLocation`, `SystemExitAlarmScheduler`, `ExitAlarmUserDefaultsStorage`. Falsch: `ScriptedLocationProvider`, `FakeAlarmScheduler`, `MemoryAlarmPersistence` und `ExitAlarmTrack` (ein Fahrverlauf entlang der Halte mit Tempo, Stillstand, Lücke, Überfahren), alle in KlimaCore.
- `ExitAlarmEngine` (KlimaCore) führt die Wirkungen aus und ist mit den Fakes unter Linux testbar. In Screenshot-, Perf- und Demo-Läufen (`-KBDemo`, `LaunchMode.isSandboxed`) läuft `ExitAlarmService` mit den Fakes: **keine Berechtigungsfrage, kein echter Wecker, kein Standort**.
- **Tests** (`Packages/KlimaCore/Tests/KlimaCoreTests/ExitAlarm/`, 69): normale Annäherung (einmal klingeln, im Abstand von einem Fix zum Moment), schnellerer Zug (GPS vor Fahrplan), langsamer Zug mit gemeldeter Verspätung, Verspätung wächst (Wecker rückt, „gleich“ fällt zurück), kleine Änderung verschiebt nichts, Fahrplan rückt vor den Wecker, Tunnel, Stillstand (keine unendliche ETA), wilder Fix, Hysterese, nie doppelt (Kreis, Zeit, GPS, Nachzügler-Ereignis), Geofence-Radius, Kreis-Eintritt (erst absagen, dann klingeln) und unglaubwürdiger Eintritt, Überfahren (einmal, nicht nach Quittieren, nach Fahrplan ohne GPS, nie am Endhalt, nicht beim Weggehen nach Quittieren), Aufschub (einmal, geklemmt, nicht nach „vorbei“), Quittieren, Abbrechen, Ablauf, Ende der Verfolgung, Live-Daten aus, zwei Wecker einer Fahrt unabhängig, Obergrenze drei, Fenster der Standort-Updates, zweistufige Standort-Erlaubnis, Testwecker, **kein Standort im gespeicherten Zustand**, Neustart stellt Wecker und Kreis wieder her.
- **Demo-Szenen** (CI-Screenshots, `ScreenshotRouter`, Marke `// MARK: exitalarm`): `exitAlarmSheet`, `exitAlarmLocation` (Erklärbildschirm vor der Systemfrage), `exitAlarmArmed`, `exitAlarmApproaching`, `exitAlarmFired`, `exitAlarmPassed`, `exitAlarmSettings`. Die Zustände baut der echte Planner aus einem geskripteten Verlauf der Demo-Fahrt RJX 66 (`ExitAlarmDemo`).

## 6. Datenschutz

- Der Standort wird **nur auf dem Gerät** gelesen, **nur solange ein Wecker scharf ist und die Fahrt läuft**, und **nie gespeichert oder gesendet**. Es gibt keinen Verlauf: Der Planner hält nur den **letzten Fix im Arbeitsspeicher**. Der gespeicherte Zustand (`ExitAlarmState`, UserDefaults) lässt Fix, Geschwindigkeit, Entfernungen und GPS-Ankunft aus seinen `CodingKeys` weg; ein Test prüft, dass keine Koordinate des Nutzers im gespeicherten JSON steht. Gespeichert sind der Halt (öffentliche Fahrplan-Koordinaten), der Vorlauf und der Stand des Weckers.
- **Nichts geht ins Netz:** der Wecker macht keine Anfrage (§2); Anfragen der Verfolgung enthalten nie einen Standort.
- Info.plist-Texte (deutsch): `NSLocationWhenInUseUsageDescription` und `NSLocationAlwaysAndWhenInUseUsageDescription` nennen den Wecker und sagen, dass der Standort nicht gespeichert und nicht gesendet wird. `NSAlarmKitUsageDescription` erklärt den Wecker. Die App erklärt den Standort **vor** der Systemfrage auf einem eigenen Bildschirm (`ExitAlarmLocationExplainer`), mit „Weiter“ und „Nur mit Fahrplan wecken“.
- **Erlaubnis in zwei Stufen:** „Beim Verwenden“ zuerst (Systemfrage), dann bietet iOS „Immer“ an (die Engine bittet nach der ersten Antwort darum, nur wenn der Nutzer im Erklärbildschirm „Weiter“ gewählt hat). Nichts wird beim Start oder Stellen gefragt außer der Erlaubnis für den Wecker selbst.
- Der blaue Streifen (`showsBackgroundLocationIndicator`) zeigt, dass der Standort in Gebrauch ist.

## 7. Sideload: was gebraucht wird, was nicht (Recherche)

Die App wird mit kostenloser Apple-ID neu signiert (AltStore, SideStore). Eine Fähigkeit, die einen bezahlten Account braucht, würde die Installation brechen.

- **AlarmKit** (iOS 26): Framework `AlarmKit`, `AlarmManager.shared.requestAuthorization()`, `schedule(id:configuration:)` mit `Alarm.Schedule.fixed(Date)`, `AlarmAttributes<Metadata>`, `AlarmPresentation.Alert`, Ton über `AlertConfiguration.AlertSound`. Die Schnittstelle steht in der SDK-Datei `AlarmKit.swiftinterface` (iOS 26.4), gegen die das Linux-Prüfwerkzeug (`tools/typecheck`) die App prüft. Nach unserem Stand braucht AlarmKit **nur** den Info.plist-Schlüssel `NSAlarmKitUsageDescription` und die Erlaubnis des Nutzers; eine Entitlement-Zeile gibt es dafür nicht. Das Projekt trägt **kein neues Entitlement** (`App/Supporting/*.entitlements` unverändert: nur die App-Gruppe).
  - AlarmKit zeigt seine Wecker als Live Activity; eine **Widget-Erweiterung** ist für Countdown und Pause nötig. Das Projekt hat die Erweiterung, wir liefern die Darstellung mit (`ExitAlarmLiveActivity`). Unser Wecker ist ein fester Zeitpunkt ohne Countdown.
  - **Nicht auf einem Gerät mit kostenlosem Profil geprüft:** ob `requestAuthorization()` dort `authorized` liefert und der Wecker lautlos klingelt (§9). Fällt AlarmKit aus (nicht erlaubt, Fehler, zu viele Wecker), nimmt die App **automatisch Mitteilungen** (nächster Punkt) und die Einstellungen sagen es.
- **Mitteilungen als Ersatz:** drei lokale Mitteilungen im Abstand von 20 s auf der Stufe `.active`. **Keine zeitkritische und keine kritische Stufe:** sie brauchen Entitlements, die ein Sideload-Build nicht hat. Lautlos-Schalter und Fokus können sie stumm schalten. Die App sagt das in den Einstellungen, im Blatt und in der Fußnote. Aktionen der Mitteilung: „Quittieren“, „5 Min später“ (ohne die App zu öffnen).
- **Standort im Hintergrund:** `UIBackgroundModes` bekommt `location`. Dafür ist **kein Entitlement** nötig; das System verlangt die Nutzer-Erlaubnis. Die App setzt `allowsBackgroundLocationUpdates` nur, wenn der Modus im Bundle steht (sonst wirft iOS eine Ausnahme). Geofence und Wecken per Standort brauchen **„Immer“**.
- **Nicht gebraucht und nicht benutzt:** Push (APNs), Sign in with Apple, CloudKit, Wallet, zeitkritische oder kritische Hinweise, weitere App-Gruppen.
- **Geofence-Grenze:** iOS erlaubt 20 überwachte Kreise je App, geteilt mit der Fahrterkennung (`TripDetectionService` nimmt bis zu 20 Lieblingsbahnhöfe). Verweigert das System den Kreis, merkt sich die Engine das (`geofenceFailed`), und die GPS-Schätzung plus der Fahrplan tragen weiter.

## 8. Ehrliche Grenzen

- Der Fahrplan-Wecker folgt Verspätungen nur, wenn die App Daten bekommt (offen, im Hintergrund durch die Standort-Updates, oder durch den Hintergrundlauf der Verfolgung, den iOS nach eigenem Ermessen startet). Ohne Daten klingelt er zur zuletzt bekannten Ankunft.
- Die GPS-Schätzung nimmt die jetzige Geschwindigkeit. Ein Zug, der vor dem Halt bremst, kommt später als geschätzt; der Wecker klingelt dann etwas früher, nicht später. Mit Vorlauf „bei Ankunft“ ist der Kreis 1,5 km groß, das sind je nach Tempo 1 bis 2 Minuten vor dem Halt.
- „Vorbeigefahren“ misst die Luftlinie zum Halt. Auf Schleifen und Serpentinen (Arlberg, Tauern) kann die Luftlinie wachsen, bevor der Zug den Halt erreicht; ein nicht quittierter Wecker könnte dort zu früh „vorbeigefahren“ melden. Quittieren verhindert es.
- Die Art des Weckers in den Einstellungen zeigt den Stand des **letzten Versuchs**: Scheitert AlarmKit beim Stellen, steht dort „Mitteilung, lautlos möglich“, bis ein Versuch wieder klappt.
- Die Verfolgung deckt die **erste Fahrt-Teilstrecke** einer Verbindung ab (`docs/OEBB_LIVE.md` §R8). Weckt der Nutzer für einen späteren Zug, muss er diese Fahrt verfolgen (Zug-Radar) oder die Verfolgung wechseln; ein Wecker einer anderen Fahrt endet, wenn die Verfolgung wechselt.
- Das Vollbild erscheint, wenn die App läuft. Ist sie beendet, klingelt der Fahrplan-Wecker (System) und eine Standort-Weckung startet die App im Hintergrund; das Vollbild folgt, sobald das Gerät entsperrt und die App aktiv ist.
- Ob iOS einen Kreis auch bei „Beim Verwenden“ meldet, wenn die App im Hintergrund läuft, ist **ungeprüft**; die Weckung der beendeten App braucht in jedem Fall „Immer“.
- Der Kreis wird beim Start der Fahrt nicht ausgelöst, wenn der Nutzer schon darin einsteigt (iOS meldet nur das Betreten). Dann tragen die GPS-Updates und der Fahrplan.
- Der Alarme-Bildschirm (`docs/ROUTES_ALARMS.md` §2) listet jeden scharfen Aussteige-Wecker als Zeile (Art `exitAlarm`, aus dem Buch der App, mit dem Moment, den der Planner errechnet hat). „Aus“ und „Löschen“ schalten den Wecker aus; die Verfolgung läuft weiter. Die drei Ersatz-Mitteilungen (`exitalarm.…`) haben keine eigene Zeile.

## 9. GERÄTE-CHECKLISTE (nur ein echtes iPhone kann das beweisen)

Vor jeder Fahrt, auf die du dich verlässt, einmal durchgehen. Notiere Gerät, iOS-Version und Ergebnis.

1. **Wecker testen (Einstellungen › Aussteige-Wecker):** „Art des Weckers“ zeigt „Wecker-Ton, auch lautlos“? Danach: iPhone **auf lautlos** stellen, **Fokus „Nicht stören“** an, Bildschirm **sperren**, „Wecker testen“ tippen. Klingelt es nach 10 s? Zeigt der Sperrbildschirm „Test: Aussteigen!“? Funktioniert „Stopp“? Funktioniert „Öffnen“ und zeigt die App das Vollbild?
2. **AlarmKit mit kostenlosem Apple-ID-Profil (AltStore/SideStore):** fragt iOS beim ersten Stellen nach der Erlaubnis („Wecker“)? Steht danach „Wecker-Ton, auch lautlos“? Wenn nicht: steht „Mitteilung, lautlos möglich“, und kommen die drei Mitteilungen im Abstand von 20 s? (Die Erlaubnis in iOS › KlimaBilanz prüfen.)
3. **Standort-Erlaubnis in zwei Stufen:** Erklärbildschirm → „Weiter“ → Systemfrage „Beim Verwenden“ → danach das Angebot „Immer“. Steht in den Einstellungen „Immer erlaubt“? Das Angebot erscheint nur einmal; nach „Nur beim Verwenden“ hilft der Knopf zu den iOS-Einstellungen.
4. **Blauer Streifen:** läuft der Wecker mit „Beim Verwenden“, zeigt iOS oben den blauen Streifen oder die Pille. Mit „Immer“ auch, solange Updates laufen.
5. **Geofence-Weckung bei gesperrtem iPhone:** Wecker für einen Halt stellen (Vorlauf 5 Min), iPhone sperren, App nicht im Vordergrund, fahren. Klingelt es beim Annähern an den Halt? Wecker **ohne** AlarmKit-Erlaubnis und mit Mitteilungen: kommen sie? Ergebnis mit und ohne laufende App festhalten (aus dem App-Wechsler wischen: Weckt iOS die App für den Kreis wieder auf? Das gilt nur mit „Immer“).
6. **AlarmKit aus dem Hintergrund:** klingelt ein Wecker, der durch den Kreis ausgelöst wird, wenn die App im Hintergrund war? (Die App legt dann einen Wecker 2 s in der Zukunft an; ob iOS das aus dem Hintergrund zulässt, ist ungeprüft.) Sonst fällt sie auf Mitteilungen zurück.
7. **Verspätung:** Wecker stellen, die Verspätung wächst (Live verfolgen zeigt es). Verschiebt sich die Zeit „Weckt dich um …“? Klingelt der alte Moment **nicht** mehr?
8. **Nie doppelt:** klingelt es bei Annäherung genau einmal, auch wenn Fahrplan und Standort fast gleichzeitig dran sind? Nach „Quittieren“ kommt nichts mehr.
9. **Vorbeigefahren:** Wecker stellen, nicht quittieren, am Halt sitzen bleiben. Kommt „Du bist an X vorbeigefahren“ genau einmal, nicht bei Zügen, die am Halt enden?
10. **Aufschub:** „5 Min später“ → klingelt nach 5 Minuten noch einmal, danach nicht mehr.
11. **Akku:** eine Fahrt von etwa einer Stunde mit scharfem Wecker und „Immer“: Verbrauch in Einstellungen › Batterie notieren. Erwartung: gering (Updates alle 100 m, Genauigkeit 100 m); Messwert fehlt bis dahin.
12. **Tunnel:** durch einen langen Tunnel fahren: klingelt der Wecker trotzdem zur Fahrplanzeit?
13. **Live Activity:** zeigt der Sperrbildschirm „Aussteigen in N Min“, während der Wecker scharf ist, und verschwindet die Zeile nach dem Klingeln?
14. **Profil nach 7 Tagen:** nach einer Neuinstallation (neues Profil) sind die Erlaubnisse (Wecker, Standort) noch da? Gestellte Wecker bleiben erhalten (UserDefaults), AlarmKit-Wecker werden beim Start neu gestellt.

## 10. Bewusst nicht gebaut

- Eigene Anfragen des Weckers für eine Fahrt ohne Verfolgung (Rechtsrahmen: 40 Anfragen je Minute für die ganze App): Der Wecker nutzt die Anfragen der Verfolgung.
- Hintergrund-Wecken per Push (kein APNs ohne bezahlten Account, `docs/LIVE_PUSH.md`).
- Wecker für mehrere Fahrten gleichzeitig mit eigenem Polling: bis zu drei Wecker, aber nur für die verfolgte Fahrt.
- Sprachausgabe, Apple Watch, Wallet (außerhalb dessen, was ein Sideload kann).

## 11. Code-Karte

| Was | Wo |
|---|---|
| Werte, Zustand, Konfiguration | `KlimaCore/ExitAlarm/ExitAlarmModels.swift` |
| Geometrie, Restweg, Geschwindigkeit, Geofence-Radius | `KlimaCore/ExitAlarm/ExitAlarmGeometry.swift` |
| Fusion und Zustandsmaschine | `KlimaCore/ExitAlarm/ExitAlarmPlanner.swift` |
| Wecker-Buch (bis zu drei, einer je Halt) | `KlimaCore/ExitAlarm/ExitAlarmBook.swift` |
| Engine mit den Protokollen | `KlimaCore/ExitAlarm/ExitAlarmEngine.swift` |
| Fakes, geskripteter Verlauf | `KlimaCore/ExitAlarm/ExitAlarmFakes.swift` |
| Halte und Spec einer Fahrt | `KlimaCore/ExitAlarm/ExitAlarmStops.swift` |
| Texte, Zahlen der Karte | `KlimaCore/ExitAlarm/ExitAlarmPresentation.swift` |
| Live-Activity-Zeile | `KlimaCore/Live/Follow/FollowLiveState.swift` (`FollowExitAlarmInfo`), `Shared/WidgetViews/FollowActivityViews.swift` |
| App: Dienst, Standort, Wecker, Speicher | `App/Sources/Features/ExitAlarm/` |
| AlarmKit-Metadaten, „Öffnen“-Taste | `Shared/ExitAlarmShared.swift`, `Widgets/Sources/ExitAlarmLiveActivity.swift` |
| Einstellungen | `App/Sources/Features/Settings/SetExitAlarmSection.swift` |
| Töne | `scripts/gen_exit_alarm_sounds.py` → `App/Resources/exitalarm-*.wav` |
