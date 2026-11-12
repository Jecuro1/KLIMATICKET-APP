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
- **Alles Entscheidende ist reine Logik in KlimaCore** (`Packages/KlimaCore/Sources/KlimaCore/ExitAlarm/`) mit 91 Linux-Tests. Apple-spezifisch sind nur drei dünne Adapter (Standort, Wecker, Speicher) hinter Protokollen.

## 2. Einstiege (alle drei öffnen dasselbe Blatt)

Jeder Einstieg ist ein dünner Knopf. Das gemeinsame Blatt ist `ExitAlarmSheet` (`App/Sources/Features/ExitAlarm/ExitAlarmSheet.swift`); der Einstieg reicht nur eine verfolgbare Fahrt (`ExitAlarmSheetInput`) hinein.

| Einstieg | Wo | Halte |
|---|---|---|
| 1. Live verfolgen | Block „Aussteige-Wecker“ oben im Detail der Verfolgung (`ExitAlarmFollowSection` in `LiveFollowDetailSheet`) | Halte der Verfolgung: vom Einstieg bis zum Ende der Teilstrecke |
| 2. Zug-Radar | „Wecker für diesen Zug“ im Fahrtenblatt (`RadarTripSheet`) | Alle Halte, die der Zug noch nicht erreicht hat |
| 3. Verbindungsdetail | Glocken-Symbol in der Leiste (`ConnectionDetailView`) | Halte der ersten Fahrt-Teilstrecke der Verbindung |

Das Blatt wählt den Halt (Standard: das Ende der Teilstrecke; jeder Halt der Teilstrecke geht, auch ein Umstieg), den Vorlauf, erklärt in zwei Zeilen die beiden Wege mit ihrem Stand (welche Art Wecker, welche Standort-Erlaubnis) und stellt den Wecker. Einstellung „Auch für Umstiege“ (Standard an): ist das Ende der Teilstrecke ein Umstieg, ist es vorgewählt. Ausgeschaltet ist **nichts** vorgewählt und der Nutzer wählt den Halt (der Halt vor dem Umstieg wäre ein Halt, den er nie gewählt hat). „Ändern“ an einer Karte öffnet das Blatt auf dem gestellten Halt mit dem gestellten Vorlauf.

**Der Wecker lebt mit der Verfolgung.** Beim Stellen startet das Blatt die Verfolgung der Fahrt, wenn sie nicht schon läuft; die Verfolgung liefert die Fahrplan-Antworten (`LiveFollowTracker.pollOnce` → `ExitAlarmService.followUpdated`). Endet die Verfolgung (angekommen, Fahrt ersetzt, „Nicht mehr verfolgen“), enden ihre Wecker. Alle Wecker einer Fahrt teilen sich also die Anfragen der Verfolgung; der Wecker erzeugt keine eigenen Anfragen (Rechtsrahmen `OEBB_LIVE` §2: 40 Anfragen je Minute für die ganze App, kein Standort in Anfragen).

**Kein Netz ist nicht „Live-Daten aus“.** Im Tunnel oder Funkloch liefert `LiveDataService.timetable` ebenfalls `nil`; die Verfolgung meldet das als `LiveError.offline` (gewöhnliche gescheiterte Abfrage, die nächste klappt wieder), und der Wecker läuft weiter nach dem zuletzt bekannten Fahrplan. Nur wirklich ausgeschaltete Live-Daten (Schalter, Kill-Switch, keine Zustimmung: `LiveError.disabled`) beenden die Wecker (`killSwitch`), und dann sagt die App es **einmal mit einer Mitteilung** („Aussteige-Wecker ist aus“), damit niemand im Glauben weiterschläft, der Wecker sei scharf. Das Blatt stellt bei ausgeschalteten Live-Daten gar keinen Wecker, statt „Wecker gestellt“ zu melden.

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
- **„Du bist an X vorbeigefahren“:** ein zweiter Hinweis, genau einmal, wenn der Halt vorbei ist und der Wecker nicht quittiert wurde: nach GPS (nächste Annäherung unter 3 km, danach über 3 Fixes mindestens 600 m weiter weg, bei Fahrgeschwindigkeit; nur wenn der Wecker nicht mehr wartet, denn eine Kurve am Anfang einer kurzen Fahrt ist kein Überfahren) oder, wenn kein frischer Fix da ist, nach Fahrplan (90 s nach der Abfahrt des Halts; der letzte Halt kann nicht überfahren werden).
- **Das Echo des Systems:** AlarmKit meldet jeden Wecker, der den klingelnden Zustand verlässt, wie ein „Stopp“ des Nutzers, auch wenn die App ihn selbst gestoppt oder ersetzt hat (Aufschub, Quittieren in der App, „vorbeigefahren“ über einem klingelnden Wecker). Die App hört das nicht als Quittieren: der Adapter (`AlarmKitExitScheduler`) merkt sich, was er selbst beendet, und die Engine nimmt „gestoppt“ nur für einen Wecker im Zustand `fired` an und nicht in den zwei Sekunden nach ihrem eigenen Klingeln. Ohne diese Regel hätte „5 Min später“ sich selbst aufgehoben. Getestet mit einem Fake, der das Echo nachmacht (`echoesStops`).
- **Zustände:** `armed` → `approaching` → `fired` → `acknowledged` oder `snoozed` (→ `fired` nach 5 Min, genau einmal je Aufschub, bis 15 Min, kein Aufschub nach „vorbeigefahren“) → `ended` mit Grund: `completed`, `expired` (Ankunft + 10 Min; kennt der Fahrplan gar keine Ankunft, 6 Stunden nach dem Klingeln oder nach dem Stellen, damit der Standort nie für einen Zeitpunkt läuft, den niemand kennt), `cancelledByUser`, `followEnded`, `killSwitch` (Live-Daten aus).
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
- **Tests** (`Packages/KlimaCore/Tests/KlimaCoreTests/ExitAlarm/`, 91): normale Annäherung (einmal klingeln, im Abstand von einem Fix zum Moment), schnellerer Zug (GPS vor Fahrplan), langsamer Zug mit gemeldeter Verspätung, Verspätung wächst (Wecker rückt, „gleich“ fällt zurück), kleine Änderung verschiebt nichts, Fahrplan rückt vor den Wecker, Tunnel, Stillstand (keine unendliche ETA), wilder Fix, Hysterese, nie doppelt (Kreis, Zeit, GPS, Nachzügler-Ereignis), Geofence-Radius, Kreis-Eintritt (erst absagen, dann klingeln) und unglaubwürdiger Eintritt, Überfahren (einmal, nicht nach Quittieren, nach Fahrplan ohne GPS, nie am Endhalt, nicht beim Weggehen nach Quittieren), Aufschub (einmal, geklemmt, nicht nach „vorbei“), Quittieren, Abbrechen, Ablauf, Ende der Verfolgung, Live-Daten aus, zwei Wecker einer Fahrt unabhängig, **das Echo des Systems** (Aufschub überlebt das Ende des gestoppten Weckers, „vorbeigefahren“ über einem klingelnden Wecker, Quittieren zählt nicht doppelt, ein Stopp des Nutzers quittiert weiter, eine späte „klingelt“-Meldung im Aufschub), Text der Erinnerung nach dem Aufschub, Uhrzeit beim Wechsel Sommer-/Winterzeit, Obergrenze drei, Fenster der Standort-Updates, zweistufige Standort-Erlaubnis, Testwecker, **kein Standort im gespeicherten Zustand**, Neustart stellt Wecker und Kreis wieder her, **Alle Daten löschen** (Wecker, Kreise, gespeichertes Buch), „Genauer Standort aus“, die ehrlichen Sätze je Art des Weckers, und ein Zufallstest (200 Folgen aus Fixes, Takten, Fahrplanänderungen, Kreis-Eintritten, Quittieren, Aufschub und Ende) prüft die Invarianten: höchstens ein Klingeln je Auslösung, nichts nach dem Ende, keine NaN-Zahl auf der Karte, kein Wecker in der Vergangenheit.
- **Demo-Szenen** (CI-Screenshots, `ScreenshotRouter`, Marke `// MARK: exitalarm`): `exitAlarmSheet`, `exitAlarmLocation` (Erklärbildschirm vor der Systemfrage), `exitAlarmArmed`, `exitAlarmApproaching`, `exitAlarmFired`, `exitAlarmPassed`, `exitAlarmSettings`. Die Zustände baut der echte Planner aus einem geskripteten Verlauf der Demo-Fahrt RJX 66 (`ExitAlarmDemo`).

## 6. Datenschutz

Kurz: Der Standort wird **nur auf dem Gerät**, **nur solange ein Wecker scharf ist und die Fahrt läuft**, gelesen und **nie gespeichert oder gesendet**. Es gibt keinen Verlauf: Der Planner hält nur den **letzten Fix im Arbeitsspeicher**.

| Was | Wozu | Wo | Wie lange | Löschen |
|---|---|---|---|---|
| **Standort** (Fixes, Geschwindigkeit, Entfernungen, GPS-Ankunft) | den Zeitpunkt zum Klingeln bestimmen | nur Arbeitsspeicher, ein einziger Fix; `ExitAlarmState.CodingKeys` lässt ihn weg, ein Test prüft, dass keine Koordinate des Nutzers im gespeicherten JSON steht | solange ein Wecker scharf ist und die Fahrt läuft; die App beendet das Lesen beim Quittieren, Abbrechen, Ablauf (Ankunft + 10 Min) und beim Ende der Verfolgung; mit dem Beenden der App ist er weg | nichts zu löschen; „Immer“ kann in den iOS-Einstellungen zurückgenommen werden |
| **Wecker** (Halt mit seinen öffentlichen Koordinaten, Vorlauf, Zeiten, Stand) | ihn nach einem Neustart der App wieder zu stellen | `UserDefaults`-Schlüssel `exitAlarm.book` auf dem Gerät; nicht synchronisiert, nicht gesendet, **Teil des iOS-Backups** (es ist keine Position des Nutzers darin) | solange er aktiv ist, danach höchstens **eine Stunde** (die Karte sagt, was geschehen ist), dann fällt er beim nächsten Start oder Takt heraus | „Wecker ausschalten“ und „Abbrechen“ (eine Stunde Rest), **„Alle Daten löschen“** (Einstellungen › Daten) räumt sofort ab: Wecker, ihre Systemwecker und Kreise, ein wartender Test, das gespeicherte Buch und den Verlauf des Alarme-Bildschirms, auch mit Cloud-Konto |
| Einstellungen (Vorlauf, Ton, „Auch für Umstiege“) | die Voreinstellung | `UserDefaults` | bis zur Änderung | keine personenbezogenen Daten |
| **Ersatz-Mitteilungen** und der Wecker von iOS | klingeln, wenn die App zu ist | beim System (Mitteilungen bzw. AlarmKit); zeigt die App eine Mitteilung bei geöffneter App, steht ihr Text (Halt, Zeit) auch im Verlauf des Alarme-Bildschirms (die letzten 30, `UserDefaults`) | bis sie klingeln; Absagen, Quittieren, Ende und „Alle Daten löschen“ nehmen sie zurück | wie die Wecker |

- **Nichts geht ins Netz:** der Wecker macht keine Anfrage (§2); Anfragen der Verfolgung enthalten nie einen Standort, nur die Fahrt-Kennung (`docs/OEBB_LIVE.md` §2). Das Blatt lädt, wenn die Halte nicht da sind, die Fahrt nach ihrer Kennung.
- Info.plist-Texte (deutsch): `NSLocationWhenInUseUsageDescription` und `NSLocationAlwaysAndWhenInUseUsageDescription` nennen den Wecker und sagen, dass der Standort nicht gespeichert und nicht gesendet wird. `NSAlarmKitUsageDescription` erklärt den Wecker. Die Datenschutz-Seite der App (`Copy.privacy`) nennt den Wecker, und der Erklärbildschirm (`ExitAlarmLocationExplainer`) sagt es **vor** der Systemfrage, mit „Weiter“ und „Nur mit Fahrplan wecken“. Die Einstellungen sagen zusätzlich, dass das Lesen des Standorts Akku kostet und wie lange ein beendeter Wecker bleibt.
- **Erlaubnis in zwei Stufen:** „Beim Verwenden“ zuerst (Systemfrage), dann bietet iOS „Immer“ an (die Engine bittet nach der ersten Antwort darum, nur wenn der Nutzer im Erklärbildschirm „Weiter“ gewählt hat). Nichts wird beim Start oder Stellen gefragt außer der Erlaubnis für den Wecker selbst. Verweigert: Der Wecker läuft nach Fahrplan, die Einstellungen und das Blatt sagen es und führen zu den iOS-Einstellungen.
- **„Genauer Standort“ aus:** iOS liefert dann Positionen mit einigen Kilometern Genauigkeit. Der Planner verwirft sie (Genauigkeit über 300 m), der Kreis kann scheitern (`geofenceFailed`), der Fahrplan trägt. Die App sagt es jetzt: Die Karte zeigt „Standort zu ungenau, nur Fahrplan“, das Blatt und die Einstellungen nennen es und führen zu den iOS-Einstellungen. Eine zeitweilige Erlaubnis (`requestTemporaryFullAccuracyAuthorization`) wird bewusst **nicht** benutzt: sie gilt nur für die laufende Sitzung der App, nicht für eine Nachtfahrt.
- Der blaue Streifen (`showsBackgroundLocationIndicator`) zeigt, dass der Standort in Gebrauch ist.
- Es gibt keinen Server, der etwas davon erhält: weder der Wecker noch die Verfolgung schicken einen Standort oder einen Wecker irgendwohin.

## 7. Sideload: was gebraucht wird, was nicht (Recherche)

Die App wird mit kostenloser Apple-ID neu signiert (AltStore, SideStore). Eine Fähigkeit, die einen bezahlten Account braucht, würde die Installation brechen.

- **AlarmKit** (iOS 26): Framework `AlarmKit`, `AlarmManager.shared.requestAuthorization()`, `schedule(id:configuration:)` mit `Alarm.Schedule.fixed(Date)`, `AlarmAttributes<Metadata>`, `AlarmPresentation.Alert`, Ton über `AlertConfiguration.AlertSound`. Die Schnittstelle steht in der SDK-Datei `AlarmKit.swiftinterface` (iOS 26.4), gegen die das Linux-Prüfwerkzeug (`tools/typecheck`) die App prüft. Nach unserem Stand braucht AlarmKit **nur** den Info.plist-Schlüssel `NSAlarmKitUsageDescription` und die Erlaubnis des Nutzers; eine Entitlement-Zeile gibt es dafür nicht. Das Projekt trägt **kein neues Entitlement** (`App/Supporting/*.entitlements` unverändert: nur die App-Gruppe).
  - AlarmKit zeigt seine Wecker als Live Activity; eine **Widget-Erweiterung** ist für Countdown und Pause nötig. Das Projekt hat die Erweiterung, wir liefern die Darstellung mit (`ExitAlarmLiveActivity`). Unser Wecker ist ein fester Zeitpunkt ohne Countdown.
  - **Nicht auf einem Gerät mit kostenlosem Profil geprüft:** ob `requestAuthorization()` dort `authorized` liefert und der Wecker lautlos klingelt (§9). Fällt AlarmKit aus (nicht erlaubt, Fehler, zu viele Wecker), nimmt die App **automatisch Mitteilungen** (nächster Punkt) und die Einstellungen sagen es.
- **Mitteilungen als Ersatz:** drei lokale Mitteilungen im Abstand von 20 s auf der Stufe `.active`. **Keine zeitkritische und keine kritische Stufe:** sie brauchen Entitlements, die ein Sideload-Build nicht hat. Lautlos-Schalter und Fokus können sie stumm schalten. Die App sagt das in den Einstellungen, im Blatt und in der Fußnote. Aktionen der Mitteilung: „Quittieren“, „5 Min später“ (ohne die App zu öffnen).
- **Standort im Hintergrund:** `UIBackgroundModes` bekommt `location`. Dafür ist **kein Entitlement** nötig; das System verlangt die Nutzer-Erlaubnis. Die App setzt `allowsBackgroundLocationUpdates` nur, wenn der Modus im Bundle steht (sonst wirft iOS eine Ausnahme). Geofence und Wecken per Standort brauchen **„Immer“**.
- **Nicht gebraucht und nicht benutzt:** Push (APNs), Sign in with Apple, CloudKit, Wallet, zeitkritische oder kritische Hinweise, weitere App-Gruppen.
- **Womit die .ipa signiert wird:** `App/Supporting/*-Sideload.entitlements` (nur die App-Gruppe; die `.ipa` wird mit `ldid` damit signiert, `ios.yml` prüft App-Gruppe und fehlendes Sign in with Apple). Das `KlimaBilanz.entitlements` aus `project.yml` (mit Sign in with Apple) gilt nur für signierte Xcode-Builds, nicht für die Sideload-`.ipa`.
- **Das prüft jetzt eine Regel, nicht das Gedächtnis:** `scripts/check_integration.py` (läuft vor jedem Bau) lässt in den Sideload-Entitlements nur die App-Gruppe zu, in `UIBackgroundModes` nur `fetch` und `location`, und verlangt für `import AlarmKit`, `CLLocationManager`, `requestAlwaysAuthorization` den Info.plist-Text und für `allowsBackgroundLocationUpdates` den Modus `location`. Ein neuer Eintrag steht dort nur zusammen mit seiner Begründung (Unit-Tests: `scripts/test_check_integration.py`).
- **`PrivacyInfo.xcprivacy`** gibt es im Repository nicht. Für eine Sideload-Installation wird sie nicht gebraucht; für den App Store wäre sie nötig (Erlaubnis des Eigentümers, welche Datenarten die App angibt, u. a. den auf 100 m gerundeten Standort an die ÖBB). Nicht Teil dieses Tracks, offen.
- **Veraltete Schnittstelle:** `CLLocationManager.startMonitoring(for:)` für Kreise ist seit iOS 17 als veraltet markiert (Nachfolger `CLMonitor`). Sie funktioniert weiter, und die Fahrterkennung nutzt dieselbe. Der Umstieg auf `CLMonitor` ist offen (ohne Mac nicht geprüft).
- **Kreise:** ihre Namen tragen das Präfix `exitalarm.` (die Fahrterkennung teilt sich den Satz der Kreise und fasst nur ihre eigenen an). Ein unveränderter Kreis wird beim Neustart der App **nicht** neu gesetzt: iOS behält Kreise über Starts hinweg, und ein erneutes Setzen könnte den Eintritt verschlucken, wegen dem iOS die App gerade gestartet hat.
- **Geofence-Grenze:** iOS erlaubt 20 überwachte Kreise je App, geteilt mit der Fahrterkennung (`TripDetectionService` nimmt bis zu 20 Lieblingsbahnhöfe). Verweigert das System den Kreis, merkt sich die Engine das (`geofenceFailed`), und die GPS-Schätzung plus der Fahrplan tragen weiter.

## 8. Ehrliche Grenzen

- Der Fahrplan-Wecker folgt Verspätungen nur, wenn die App Daten bekommt (offen, im Hintergrund durch die Standort-Updates, oder durch den Hintergrundlauf der Verfolgung, den iOS nach eigenem Ermessen startet). Ohne Daten klingelt er zur zuletzt bekannten Ankunft.
- Die GPS-Schätzung kennt die Aufenthalte an den Halten zwischen jetzt und dem Ziel nicht und nimmt die jetzige Geschwindigkeit. Weit vor dem Ziel klingelt der Wecker deshalb um die Summe der Aufenthalte früher, je näher der Zug dem Ziel kommt, desto weniger (im Zweifel zu früh, nie zu spät).
- Steht „Genauer Standort“ für die App in iOS auf aus, liefert iOS nur ungefähre Positionen (Genauigkeit über 300 m). Die App verwirft sie, und der Fahrplan trägt den Wecker; Karte, Blatt und Einstellungen sagen es (§6).
- **Akku:** Während ein Wecker scharf ist und die Fahrt läuft (ab 10 Minuten vor der Abfahrt am Einstieg bis zum Ende des Weckers), liest die App den Standort durchgehend (Genauigkeit 100 m, alle 100 m; `pausesLocationUpdatesAutomatically` bleibt aus, damit iOS die Updates nicht mitten in der Fahrt anhält). Das kostet Akku; **wie viel, ist nicht gemessen** (§9 Punkt 11). Eine Nachtfahrt von acht Stunden ist die teuerste Lage. Die App schreibt den gespeicherten Zustand nur, wenn er sich geändert hat, nicht bei jedem Fix und Takt. Ohne den Standort („Nur mit Fahrplan wecken“) liest die App nichts und der Wecker kostet nur den System-Wecker.
- **Das 7-Tage-Profil** einer kostenlosen Apple-ID: Läuft es ab, startet die App nicht mehr. Was ein bereits gestellter Wecker von iOS dann tut, ist ungeprüft (§9 Punkt 14). Die App benutzt keine zusätzliche Erweiterung und keine zusätzliche App-ID für den Wecker: Er nutzt die vorhandene Widget-Erweiterung.
- **Stromsparmodus, Hintergrundaktualisierung aus:** nicht geprüft. Der Wecker von iOS und die Ersatz-Mitteilungen laufen im System; die Nachführung der Verspätung braucht Daten (offene App, Standort-Updates im Hintergrund oder ein Hintergrundlauf, den iOS zuteilt) und kann ausbleiben.
- **Live Activity:** die Zeile „Aussteigen in 4 Min“ zählt von selbst; ändert sich der Wecker (gestellt, geklingelt, abgesagt, Live-Daten aus), aktualisiert die App die Live Activity sofort, solange sie läuft. Schläft die App zur Ankunft, bleibt die Zeile bis zum nächsten Abruf stehen und zählt nach der Ankunft nach oben; die Live Activity wird zehn Minuten nach der erwarteten Ankunft als veraltet markiert.
- Der Wecker beendet sich nicht von selbst, wenn die Verfolgung beim Neustart nicht wieder aufgenommen wird (zum Beispiel ohne Live-Daten-Zustimmung); er läuft dann nach dem zuletzt bekannten Fahrplan bis Ankunft + 10 Minuten. Er macht keine eigenen Anfragen.
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
11. **Akku:** eine Fahrt von etwa einer Stunde mit scharfem Wecker und „Immer“, dazu dieselbe Zeit ohne Wecker als Vergleich: Verbrauch in Einstellungen › Batterie notieren (und bei einer Nachtfahrt über acht Stunden). Es gibt **keinen Messwert**; die Einstellungen sagen nur, dass es Akku kostet. Ist er hoch, ist der Hebel die Genauigkeit und der Abstand der Updates in `CLExitAlarmLocation`.
12. **Tunnel:** durch einen langen Tunnel fahren: klingelt der Wecker trotzdem zur Fahrplanzeit?
13. **Live Activity:** zeigt der Sperrbildschirm „Aussteigen in N Min“, während der Wecker scharf ist, und verschwindet die Zeile nach dem Klingeln?
14. **Profil nach 7 Tagen:** nach einer Neuinstallation (neues Profil) sind die Erlaubnisse (Wecker, Standort) noch da? Gestellte Wecker bleiben erhalten (UserDefaults), AlarmKit-Wecker werden beim Start neu gestellt. **Läuft das Profil am Tag der Fahrt ab** (AltStore/SideStore melden es), startet die App danach nicht mehr: Ob ein vorher gestellter Wecker von iOS dann noch klingelt und seine Darstellung zeigt, ist ungeprüft. Vor einer wichtigen Fahrt neu signieren lassen.
15. **Aufschub mit AlarmKit (Echo):** klingelt der Wecker, „5 Min später“ in der App tippen. Klingelt er nach 5 Minuten wirklich noch einmal, mit dem Text „Deine Erinnerung für …“? (Das System meldet das Ende des gestoppten Weckers; die App darf es nicht als Quittieren verstehen. Auf dem Gerät nie gesehen: Verhalten von `alarmUpdates` nach `stop`.)
16. **Funkloch:** Flugmodus mitten in der Fahrt an und wieder aus. Bleibt der Wecker scharf (Karte, Alarme-Bildschirm), und klingelt er? Danach Live-Daten in den Einstellungen ausschalten: Kommt die Mitteilung „Aussteige-Wecker ist aus“?
17. **Kreis nach Neustart der App:** Wecker mit „Immer“ stellen, App aus dem App-Wechsler wischen, zum Halt fahren. Startet iOS die App für den Kreis (blauer Streifen kurz, Wecker klingelt)? Das Nicht-neu-Setzen eines unveränderten Kreises beim Start ist ungeprüft.

18. **„Genauer Standort“ aus:** in iOS › KlimaBilanz › Standort „Genauer Standort“ ausschalten. Sagen Karte („Standort zu ungenau, nur Fahrplan“), Blatt und Einstellungen es? Klingelt der Wecker trotzdem nach Fahrplan?
19. **Alle Daten löschen:** Wecker stellen (mit AlarmKit und mit Mitteilungen je einmal), dann Einstellungen › Daten › Alle Daten löschen. Verschwinden die Karte, der Eintrag im Alarme-Bildschirm und die Zeile der Live Activity, und klingelt der Wecker **nicht** mehr? Mit und ohne Cloud-Konto.
20. **Live Activity folgt dem Wecker:** Wecker stellen (Zeile „Aussteigen in …“ erscheint), dann in der App abbrechen. Verschwindet die Zeile sofort, nicht erst beim nächsten Abruf? Dasselbe nach dem Klingeln und nach „Live-Daten aus“.
21. **App beendet, „Beim Verwenden“:** Wecker stellen, App aus dem App-Wechsler wischen, nur „Beim Verwenden“ erlaubt. Klingelt der Fahrplan-Wecker (System)? Kommt die Standort-Weckung **nicht** (das ist so gewollt und steht im Erklärbildschirm)?
22. **„Immer“ während der Fahrt zurücknehmen:** in iOS auf „Beim Verwenden“ oder „Nie“ stellen (iOS fragt nach einigen Tagen von selbst, ob „Immer“ bleiben soll). Zeigen Einstellungen und Karte den neuen Stand, hört das Lesen des Standorts auf (kein blauer Streifen mehr), klingelt der Wecker nach Fahrplan?
23. **Stromsparmodus und Hintergrundaktualisierung aus:** Wecker mit Standort stellen und fahren. Klingelt er? Läuft die Nachführung der Verspätung weiter (Karte „geschätzt“ gegen „laut Fahrplan“)?

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
