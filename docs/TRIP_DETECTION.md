# KlimaBilanz – Fahrten erkennen

> „Du hast einen Zug genommen, die App schlägt die Fahrt vor, du bestätigst, und die Ersparnis wächst ohne Eintippen.“

Zwei Wege, eine Regel: **Eine Fahrt wird nie ohne Tippen erfasst.** Jeder Vorschlag landet im Postfach „Fahrten-Vorschläge“
auf der Übersicht und fragt: Übernehmen, Bearbeiten oder Verwerfen. Das Ergebnis ist die ganz normale Fahrt (`TripEntity`) –
Statistik, Jahresrückblick und Widgets zählen sie ohne neuen Codepfad mit.

Was sich **in CI und unter Linux prüfen lässt** und was **nur auf einem echten iPhone**, steht in §10 und §11. Kurz: Die
Regeln, Zahlen, Texte und Oberflächen sind getestet; Treffsicherheit, Akkuverbrauch und das Aufwachen im Hintergrund nicht.

## 1. Die zwei Modi

| | Modus A „Fahrt aufzeichnen“ | Modus B „Hintergrund-Erkennung (Beta)“ |
|---|---|---|
| Wer startet | du, mit einem Knopf (Fahrten-Tab › Aufzeichnen) | niemand – läuft still, wenn du es eingeschaltet hast |
| Standort | genau (GPS), **nur solange die Aufzeichnung läuft**, auch im Hintergrund (blaue Anzeige) | grob (Mobilfunk-Ebene), Zugriff „Immer“ |
| Erlaubnis | „Beim Verwenden der App“ | „Immer“, erst nach der Erklärung |
| Zuverlässigkeit | hoch: Start, Ziel, Zeit, Halte kommen aus deinem Weg | begrenzt, siehe §4 und §9 |
| Standard | immer verfügbar | **aus**, Einschalten nur über den Erklärungsbildschirm |
| Live Activity | „Aufzeichnung läuft“ (Sperrbildschirm, Dynamic Island) | – |

## 2. Modus A – Fahrt aufzeichnen

Bildschirm (`TripRecordView`): eine eigene Karte ohne Kartenkacheln (kein Netz, nie leer) – die Strecke zeichnet sich beim
Fahren selbst, die Bahnhöfe ringsum stehen als Punkte, der Kopf pulsiert („du bist hier“); darunter Fahrzeit, Strecke, Tempo und
„Du bist am Bahnhof X“ / „Zuletzt Y“. **Beenden** schlägt die Fahrt vor (Von, Nach, Verkehrsmittel, Wert) – danach Übernehmen,
Bearbeiten, Verwerfen. Ohne Entscheidung wartet der Vorschlag im Postfach.

Die Zahlen (`RecordingSession`, KlimaCore):
- Fixes mit mehr als 100 m Ungenauigkeit, Sprünge über 360 km/h und Fixes vor dem Start zählen nicht.
- Schritte unter ~6 m (Zittern eines stehenden Handys) addieren keine Strecke.
- Das Tempo ist das des Systems, sonst Schritt ÷ Zeit, geglättet.
- Start und Ziel werden Bahnhöfen im Umkreis von 800 m zugeordnet; gibt es keinen, fragt die Bearbeiten-Ansicht danach.
- Ein Halt an einem Bahnhof zählt ab 15 s unter 7 km/h. Halte sind ein Hinweis, keine Zwischenstationen der Fahrt.
- Unter 500 m oder 60 s ist es keine Fahrt (versehentlicher Start): nichts wird gespeichert.

Der **Wert** kommt nicht aus der aufgezeichneten Strecke, sondern genau wie bei einer getippten Fahrt aus Start, Ziel und Mittel
(§5) – sonst wäre dieselbe Fahrt je nach Erfassungsweg unterschiedlich viel wert.

## 3. Modus B – Hintergrund-Erkennung (Beta)

### Quellen (`TripDetectionService`)
- **Bedeutende Ortswechsel** (`startMonitoringSignificantLocationChanges`): grobe Punkte, wenige pro Fahrt.
- **Aufenthalte** (`CLVisit`): iOS meldet, wo und von wann bis wann du geblieben bist.
- **Geofences** an deinen bis zu 15 häufigsten Bahnhöfen (250 m; iOS erlaubt 20 je App, der Rest bleibt dem Aussteige-Wecker): Betreten und Verlassen ergeben Aufenthalte mit genauer Zeit –
  die beste Quelle für den Halt am Bahnsteig.

Alles landet im **rollenden Puffer** (§6). Nach jedem Ereignis (und beim Öffnen der App) läuft der reine Detektor
(`TripDetector`, KlimaCore) über den Puffer.

### Regeln – alle müssen gelten (`DetectorConfig`)
1. Start und Ziel liegen **höchstens 500 m** von einem bekannten Bahnhof oder einer Haltestelle der gebündelten Daten entfernt
   (`stations.json` und die komplette Ortsdatenbank). Ein Bahnhof gewinnt gegen eine nähere Bushaltestelle.
2. Luftlinie zwischen den beiden Haltestellen **mindestens 5 km**.
3. Durchschnittstempo vom Verlassen des Starts bis zum Ankommen am Ziel **35 bis 250 km/h**.
4. **Aufenthalt an beiden Enden** (mindestens 3 Minuten; ein Aufenthalt ohne bekanntes Ende muss 5 Minuten gedauert haben – das
   verhindert, dass ein Halt des Zuges für das Ziel gehalten wird).
5. Der Weg dazwischen geht nicht hin und her (Weglänge ≤ 3 × Luftlinie), die Dauer ist höchstens 12 Stunden.
6. Ein **Umstieg** (Aufenthalt am Umsteigeort bis 25 Minuten, beide Teilstrecken und die Gesamtstrecke bestehen die Regeln) wird zu
   **einer** Fahrt „über Umsteigeort“ (die App kennt Via-Halte und rechnet den Preis dafür richtig).
7. Fahrten, die schon als Fahrt eingetragen sind, kommen nicht noch einmal (§5).

Rechnerisch ausgeschlossen: Gehen (5 km/h), Radfahren (20 km/h), die Bim in der Stadt (unter 5 km), ein Kaffee am Bahnhof (kein
zweites Ende). Alle diese Fälle sind als synthetische Spuren getestet.

### Zeit
Alle Zeiten sind absolute Zeitpunkte. Eine Fahrt über Mitternacht und über die Zeitumstellung (Europe/Vienna) rechnet mit der
echten Dauer, nicht mit der Uhr an der Wand (Test: 01:40 → 03:10 am 29.3. sind 30 Minuten, nicht 90).

## 4. Bewertung, Etiketten und die Autofahrt

Die Regeln entscheiden, **ob** vorgeschlagen wird; die Bewertung (`CandidateRanking`) entscheidet das **Etikett**. Es behauptet nie
mehr, als die Daten hergeben:

| Etikett | Bedeutung | Voraussetzung |
|---|---|---|
| **Vielleicht** | besteht die Regeln, könnte auch ein Auto sein | Punktzahl ab 0,30 |
| **Wahrscheinlich** | Bahnhöfe am Bahnsteig, bekannte Verbindung | ab 0,60 – **mehr kann eine Spur allein nicht erreichen** |
| **Sicher** | der Fahrplan hat die Verbindung zu dieser Zeit **und** beide Enden sind Bahnhöfe ≤ 250 m | ab 1,00, nur mit Fahrplan-Abgleich (§7) |

Punkte: Regeln erfüllt +0,30 · Bahnhof ≤ 150 m +0,15 je Ende (≤ 300 m +0,08; > 400 m −0,10) · nur Haltestelle (> 100 m) −0,08
je Ende · Verbindung in der ÖBB-Preistabelle +0,15 · beide Enden Bahnhöfe +0,10 · ab 15 km +0,10 · Halt an einem Bahnhof
unterwegs (dichte Spur) +0,15, höchstens zwei · Fahrplan bestätigt +0,35 / keine Verbindung −0,25 · schon verworfen −0,20 je
Mal (höchstens −0,60) · schon einmal erfasst +0,10. Unter 0,30 wird nichts vorgeschlagen (im Protokoll: „zu unsicher“).

**Hauptrisiko Autofahrt.** Eine Fahrt mit dem Auto von Ort zu Ort, beide mit Bahnhof, besteht jede Regel. Der Detektor kann sie
nicht sicher erkennen. Was er tut: Wer 450 m vom Bahnhof startet (Zuhause, Büro) bekommt Abzüge; wer nur Bushaltestellen in der
Nähe hat, fällt meist durch; ein Etikett über „Wahrscheinlich“ gibt es nur mit Fahrplan. **Was er nicht kann:** ein Auto, das am
Bahnhof startet (Park & Ride) und dort endet, ist von einer Zugfahrt in den groben Daten nicht zu unterscheiden. Deshalb steht
auf jeder Karte, solange das Etikett unter „Sicher“ liegt: „Aus den Standortdaten allein lässt sich eine Autofahrt nicht
ausschließen. Bitte prüfen.“ – und auch bei „Sicher“ heißt es nur „Ein Auto ist unwahrscheinlich, aber nicht ausgeschlossen“.
„Warum dieser Vorschlag?“ zeigt jeden Grund mit Plus und Minus.

**Verwerfen** merkt sich das Paar (ohne Standort) und senkt seine Punktzahl beim nächsten Mal um 0,20 je Verwerfen (höchstens
0,60): Ein Grenzfall verschwindet nach einem Verwerfen ganz, ein starker Treffer bleibt sichtbar, aber mit niedrigerem Etikett.
Dieselbe Fahrt (gleiche Strecke, gleiche Zeit) kommt nach dem Verwerfen nicht zurück.

## 5. Postfach, Entscheidungen, Zahlen

- **Übernehmen** legt über das Repository die normale Fahrt an: Von/Nach (Haltestelle, ID), Verkehrsmittel, **Normalpreis aus
  derselben Berechnung wie im Fahrt-Editor** (`FareEstimator.estimate(from:via:to:…)` mit deiner Standard-Klasse und -Vorteilscard
  am Tag der Fahrt, Bundesländer der Halte, Preisquelle der Methode). Ein Test (`CandidateValuation`) prüft, dass Betrag,
  Kilometer und Bundesländer **identisch** zur manuellen Berechnung sind. Eine Einschränkung: Der Vorschlag nimmt immer den
  Tabellenpreis (offline, kein Netzaufruf, Preisquelle „Tabelle“); der Fahrt-Editor kann mit Zustimmung zu Live-Daten den
  Live-Preis des Tages einsetzen. Ohne Live-Preis – oder wenn er mit der Tabelle übereinstimmt, was der Editor selbst anzeigt –
  ist der Betrag derselbe. Danach: Toast mit „Rückgängig“, Haptik, ein kleiner
  Pop samt Konfetti-Burst auf der Bilanz-Karte (Reduce Motion: nur Aufblitzen).
- **Bearbeiten**: Von, Nach und Verkehrsmittel (Zug, Bus, Bim, U-Bahn, oder das erkannte) ändern; der Wert folgt sofort.
- **Verwerfen**: bleibt als kleiner Eintrag (Paar, Zeit, ohne Punkte) für 90 Tage.
- **Keine Doppelten** (`CandidateDedup`): dieselbe Strecke in derselben Richtung am selben Tag (oder ±90 Minuten) deckt der
  eingetragene Eintrag ab – auch wenn er abends getippt wurde. Ein Eintrag deckt nur so viele Fahrten, wie er Teilstrecken hat
  („Hin & Retour“ = beide Richtungen); wer zweimal A → B fährt und eine eingetragen hat, bekommt die andere vorgeschlagen. Eine
  längere Fahrt ersetzt den kürzeren, noch offenen Vorschlag (der Zug hielt 4 Minuten in X und fuhr weiter: A → X wird A → B).
- Vorschläge, die 14 Tage unbeachtet bleiben, verschwinden.

## 6. Daten und Datenschutz – genau

| Was | Wo | Wie lange | Wofür |
|---|---|---|---|
| Grobe Standortpunkte, Aufenthalte, Betreten/Verlassen von Bahnhöfen | eine JSON-Datei in `Application Support/TripDetection/points.json`, vom Backup ausgenommen, Dateischutz bis zur ersten Entsperrung | **höchstens 36 Stunden** (älteres wird bei jedem Schreiben gelöscht, höchstens 3000 Punkte) | der Detektor |
| Vorschlag (`TripCandidateEntity`) | SwiftData, nur auf diesem Gerät | bis zur Entscheidung (höchstens 14 Tage); danach als kleiner Eintrag 90 Tage | Postfach, Verwerfen-Gedächtnis |
| Erkennungs-Protokoll | `Application Support/TripDetection/log.json` | höchstens 14 Tage, 120 Einträge | damit du die Treffsicherheit beurteilen kannst |
| Route der Karte | **keine Koordinaten**: 2–16 Punkte relativ zur Fahrt (0…1) | wie der Vorschlag | Mini-Strecke auf der Karte |

- **Gelöscht** wird: beim Übernehmen oder Verwerfen (die Punkte dieser Fahrt), beim Ausschalten der Erkennung, mit **„Alle
  Standortdaten löschen“** (Punkte, Protokoll, alle Vorschläge samt Verlauf) und mit „Alle Daten löschen“. Übernommene Fahrten bleiben.
- **Nicht** im Export (CSV, Backup der App), nicht in der Cloud-Synchronisierung; die Punkte-Datei ist zudem vom iOS-Backup
  ausgenommen. (Die Vorschläge liegen im selben Speicher wie deine Fahrten und teilen dessen iOS-Backup-Schicksal – sie enthalten
  nur Haltestellennamen und Zeiten, keine Koordinaten.) Das Modell ist rein lokal und kommt in keinem
  Sync-Pfad vor; auch das Konto-Wechsel-Löschen (`deleteAllLocalData`) nimmt es mit.
- **Nichts verlässt das Gerät** – außer, mit Zustimmung zu Live-Daten, je Vorschlag **eine** Fahrplanfrage (§7): zwei
  Haltestellennamen und eine Uhrzeit, keine Koordinate.
- `Info.plist`: `NSLocationWhenInUseUsageDescription` und `NSLocationAlwaysAndWhenInUseUsageDescription` auf Deutsch und genau;
  `UIBackgroundModes`: `fetch`, `location` (für laufende Aufzeichnungen und den Aussteige-Wecker). **Keine Berechtigung, die
  ein bezahltes Entwicklerkonto braucht**: kein Push, keine zeitkritischen Mitteilungen, keine Wallet, kein CloudKit, keine
  neuen Entitlements – `project.yml` und die `.entitlements` sind unverändert; die App bleibt per AltStore/SideStore installierbar.
- Die App hat keine `PrivacyInfo.xcprivacy`; es gibt also nichts zu aktualisieren. Käme eine, müssten Standort (nicht verknüpft,
  nicht für Tracking) und der Zugriff auf `UserDefaults` dort stehen.
- Der frühere Geofence-Schalter („Automatisch erkennen“, Schlüssel `detection.enabled`) gilt nicht mehr: Beim ersten Start
  werden seine Regionen beendet, offene Vorschläge wandern ins Postfach, und die neue Erkennung bleibt **aus**, bis du die
  Erklärung bestätigt hast.

## 7. Fahrplan-Abgleich (optional)

Nur mit deiner Zustimmung zu Live-Daten (`docs/OEBB_LIVE.md` §2) und dem Schalter „Fahrplan zum Abgleich nutzen“. Für einen
**neuen** Vorschlag fragt die App **einmal** die ÖBB-Fahrplanauskunft (Verbindungssuche nach den Haltestellen-IDs, 20 Minuten vor
der Abfahrt) – über denselben gedrosselten Client wie der Fahrplan (40 Anfragen pro Minute für die ganze App, ehrlicher
User-Agent). Gesendet werden zwei Haltestellennamen/IDs und eine Zeit. Passt eine Verbindung (Abfahrt ±15 Minuten, Ankunft
±25 Minuten), steht auf der Karte „Fahrplan: REX 5429 fährt um 08:07“ und das Etikett kann „Sicher“ werden. Gibt es keine, sinkt
der Wert; ist keine Antwort zu haben, bleibt alles wie ohne Abgleich. Live-Tests wie üblich nur mit `KB_LIVE_TESTS=1`.

## 8. Erkennungs-Protokoll

Einstellungen › Fahrten erkennen › Erkennungs-Protokoll: je Bewegung ein Eintrag mit Zeit, Haltestellennamen und dem Grund –
„Vorgeschlagen (wahrscheinlich): Bahnhof nur 60 m entfernt; Verbindung steht in der Preistabelle …“, „Nicht vorgeschlagen: Mit 5
km/h zu langsam für eine Zugfahrt“, „Luftlinie nur 3,3 km (ab 5 km)“, „Ziel ohne Haltestelle in 500 m (nächste: 1,8 km)“, „Zu
unsicher“, „Schon erfasst“, „Übernommen“. **Keine Koordinaten.** Es ist dafür da, dass du nach ein paar Wochen siehst, ob die
Erkennung zu deinem Alltag passt.

## 9. Grenzen

- Mindestens ein **Aufenthalt von 3 Minuten an einem Bahnhof** an beiden Enden (Betreten und Verlassen des 250-m-Kreises um einen
  deiner 15 häufigsten Bahnhöfe, oder ein von iOS gemeldeter Aufenthalt). Wer vom Zug direkt durch die Sperre geht und keinen
  Aufenthalt hat, wird nicht erkannt – dafür gibt es Modus A.
- Neue Bahnhöfe außerhalb der 15 häufigsten brauchen einen iOS-Aufenthalt; wann iOS diesen meldet, entscheidet iOS.
- Bus, Bim und U-Bahn: im Hintergrund nur, wenn die Regeln halten (selten, Mindeststrecke 5 km); sonst per Aufzeichnung.
- iOS entscheidet, wann die App im Hintergrund aufwacht. Es gibt keine Zusage für eine bestimmte Minute, und nach einem
  beendeten App-Prozess (Wischen im App-Umschalter) kommen nur noch iOS-Ereignisse, die die App neu starten.
- Ein laufendes „Fahrt aufzeichnen“ überlebt das Beenden der App durch den Nutzer nicht.
- Die Karte der Aufzeichnung ist eine Skizze ohne Straßen und Kacheln.

## 10. Aufbau

```
Packages/KlimaCore/Sources/KlimaCore/Detection/
  CoarsePoint, VisitRecord, CoarseTrack, LocationProviding, ScriptedTrackProvider   Eingabetypen, Anbieter (CoreLocation / skriptiert)
  StationMatcher (StationLookup, StationList)      Bahnhof-Zuordnung (Bahnhof schlägt Bushaltestelle)
  TripDetector, DetectorConfig, DetectionRejection Regeln, Aufenthalte, Umstiege, Ablehnungsgründe
  CandidateRanking, PairHistory                    Punkte, Etiketten, Verwerfen-Gedächtnis
  RollingPointBuffer                               der 36-Stunden-Puffer
  CandidateDedup                                   eingetragene Fahrten, Postfach, Ersetzen
  RecordingSession                                 Modus A: Live-Zahlen und Vorschlag
  CandidateValuation                               dieselben Zahlen wie der Fahrt-Editor
  TimetableConfirmation (TimetableLookup)          Auswertung der Fahrplan-Antwort
  DetectionLog, RouteSketch, ScriptedTrack
Shared/TripCandidateEntity.swift                   SwiftData, additiv, lokal
Shared/RecordingActivityAttributes.swift, Shared/WidgetViews/RecordingActivityViews.swift, Widgets/Sources/RecordingLiveActivity.swift
App/Sources/Services/TripDetectionService.swift    Modus B (CoreLocation, Puffer, Auswertung, Fahrplan-Frage, Benachrichtigung)
App/Sources/Services/Detection/                    DetectionStores (Dateien), TripRecorder + CoreLocationFeed (Modus A)
App/Sources/Data/Repository+Detection.swift        Vorschläge einfügen, übernehmen, verwerfen, löschen
App/Sources/Features/TripDetect/                   Postfach, Karte, Aufzeichnung, Erklärung, Einstellungen, Protokoll, Szenen
App/Sources/Features/LiveActivity/RecordingActivityController.swift
```

Die Benachrichtigung „Fahrt erkannt?“ (nur wenn Mitteilungen schon erlaubt sind, nur im Hintergrund) hat **keinen Erfassen-Knopf**:
Jede Fahrt wird erst angesehen.

## 11. Gerätecheckliste (nur auf einem echten iPhone prüfbar)

Vorher: Standort und Mitteilungen für KlimaBilanz erlauben; Live-Aktivitäten an.

**Modus A**
1. Fahrten-Tab › Aufzeichnen › starten. Erlaubnis „Beim Verwenden der App“ → blaue Standortanzeige oben, Aufzeichnung läuft.
2. Sperrbildschirm / Dynamic Island: „Aufzeichnung läuft“ mit Zeit, Strecke, Bahnhof. Aktualisiert sich etwa alle 10 s.
3. iPhone sperren und in die Tasche: nach der Fahrt hat die Karte den ganzen Weg, nicht nur den Anfang (Hintergrund-Standort).
4. Tunnel / Lücke: „GPS-Signal schwach“ erscheint und verschwindet; der Weg danach fehlt nicht.
5. Beenden: Vorschlag mit richtigem Von/Nach/Verkehrsmittel und Wert; Übernehmen → Fahrt in der Liste, Statistik und Widget
   haben den gleichen Betrag wie eine getippte Fahrt derselben Strecke (nebeneinander vergleichen).
6. Versehentlich starten und gleich beenden: „Zu kurz für eine Fahrt“, nichts gespeichert.
7. Standort in iOS ausschalten, dann Aufzeichnung starten: Hinweis „Standort ist aus“ mit Knopf „Einstellungen öffnen“.
8. Akku: eine Stunde Aufzeichnung – wie viel Prozent? (Notieren.)

**Modus B**
9. Einstellungen › Fahrten erkennen › Hintergrund-Erkennung: zuerst erscheint die Erklärung; ohne „Verstanden, einschalten“ wird
   nichts angefragt. Danach „Beim Verwenden“ und „Immer“.
10. Eine bekannte Strecke fahren (Hin und zurück, mit Wartezeit am Bahnsteig ≥ 3 Minuten): nach der Ankunft und einigen
    Minuten Vorschlag in der Übersicht (und, falls erlaubt, die Mitteilung). Etikett und „Warum?“ prüfen.
11. Dieselbe Strecke mit dem Auto (zwei Orte mit Bahnhof): kommt höchstens als „Vielleicht“, mit dem Hinweis auf das Auto, oder gar nicht.
12. Zu Fuß / mit dem Rad zwischen zwei Bahnhöfen: kein Vorschlag, im Protokoll „zu langsam“.
13. Verwerfen: dieselbe Strecke beim nächsten Mal mit niedrigerem Etikett oder gar nicht.
14. Eine Fahrt vorher von Hand eintragen, dann fahren: kein Doppelter.
15. Mit Live-Daten-Zustimmung: Karte zeigt „Fahrplan: … fährt um …“ und „Sicher“; ohne Zustimmung nie „Sicher“.
16. Einstellungen › „Alle Standortdaten löschen“: Puffer (Zahl der Orte) wird 0, Protokoll leer, Vorschläge weg, übernommene Fahrten da.
17. Erkennung ausschalten und wieder einschalten: „Gespeichert auf diesem iPhone“ beginnt bei null (Punkte wurden gelöscht); in den iOS-Einstellungen bleibt „Immer“ stehen (das entzieht nur iOS).
18. Zwei Tage im Alltag laufen lassen, danach das Erkennungs-Protokoll lesen: Wie viele echte Fahrten wurden vorgeschlagen, wie
    viele fehlten, wie viele Falsche? Akkuverbrauch unter iOS-Einstellungen › Batterie.
19. Installation per AltStore/SideStore mit der neuen Version: startet ohne Entitlement-Fehler.

## 12. Was in CI geprüft ist

- KlimaCore (`swift test`, Linux): Detektor, Bewertung, Puffer, Deduplizierung, Aufzeichnung, Zahlen-Gleichheit – synthetische Spuren
  für Zug mit Zwischenhalten, Regionalzug mit GPS-Lücke im Tunnel, Auto auf der Autobahn neben der Bahn, Auto am Bahnhof, Gehen,
  Rad, Bim, Aufenthalt am Bahnhof, Tag mit zwei Fahrten, Fahrt über Mitternacht, beide Zeitumstellungen, Umstieg, Dublette einer
  eingetragenen Fahrt.
- Typprüfung (Linux, `tools/typecheck`) und macOS-Build in CI; Bildschirme `tripDetectInbox`, `tripDetectRecord`,
  `tripDetectRecordIdle`, `tripDetectReview`, `tripDetectExplain`, `tripDetectSettings`, `tripDetectSettingsOff`,
  `tripDetectLog`, `tripDetectEdit`, `tripDetectInboxAX5` mit synthetischen Daten, ohne Systemdialoge.
- **Nicht** prüfbar in CI: echte Standortereignisse, Aufwachen im Hintergrund, Akku, Live Activity auf dem Sperrbildschirm,
  die Fahrplan-Antwort der ÖBB, die Berechtigungsdialoge, Treffsicherheit im Alltag.
