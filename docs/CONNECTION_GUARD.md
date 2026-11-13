# Anschluss-Wächter

„Erwische ich meinen Anschluss?“ – beantwortet, während du fährst. Wer eine Verbindung mit Umstieg **live verfolgt**, sieht oben im
Blatt der Verfolgung eine Karte: wie viele Minuten zum Umsteigen bleiben, ob es knapper wird, beide Züge am Umstiegsbahnhof mit Zeit
und Gleis, den Fußweg dazwischen – und, wenn es eng wird oder der Anschluss weg ist, die nächsten Verbindungen ab dem Umstiegsbahnhof.

Stand 2026-11-13. Code: `Packages/KlimaCore/Sources/KlimaCore/Live/Guard/` (Logik, Linux-Tests in
`Packages/KlimaCore/Tests/KlimaCoreTests/Live/Guard/`), `App/Sources/Features/Planner/Guard/` (Dienst, Karte, Abzeichen, Alternativen,
Demo, Screenshot-Szenen). Spezifikation dieser Welle: radar2 `anschluss`.

## 1 Was der Wächter kann – und was nicht

- Er prüft **nur, solange die App offen ist**. Es gibt keine Push-Mitteilungen (kein APNs ohne bezahlten Developer-Account) und keine
  eigene Hintergrundarbeit: keine Abfrage, kein Timer, keine neue Mitteilung im Hintergrund.
- Im Hintergrund kommt höchstens die bestehende Mitteilung **„Anschluss knapp“** der Live-Verfolgung – nur mit eingeschalteten
  Live-Mitteilungen und nur, wenn iOS der App eine Hintergrund-Aktualisierung gewährt (frühestens 10–15 Min nach der letzten, nie
  garantiert, `docs/OEBB_LIVE.md` §R8). Diese Mitteilung rechnet jetzt mit denselben Minuten wie die Karte (§6).
- Der einzige vorab geplante Alarm der App ist der **Aussteige-Wecker** (`docs/EXIT_ALARM.md`). Die Karte bietet „Wecker fürs
  Umsteigen“ an: er klingelt vor der Ankunft am Umstiegsbahnhof, auch wenn die App zu ist.
- **Ob ein Zug wartet, sagt die Auskunft nicht.** Die Karte sagt nie „wartet“ oder „gesichert“. Die Einschätzung rechnet mit den
  Prognosen beider Züge.
- Die Karte sagt das immer selbst (Fußzeile, zwei Sätze, siehe §8).

## 2 Woher die Zahlen kommen

**Eine Formel für Detail, Karte und Mitteilung** (`TransferBuffer.minutes`):
Umstiegszeit = Abfahrt des Anschlusses − Ankunft des Zubringers, auf ganze Minuten gerundet (zur geraden Zahl, wie
`JourneyPresentation.minutesBetween`), dann minus Fußweg. 4 Min 40 s sind 5 Min, −30 s sind 0, −90 s sind −2. Die Verbindungsdetails
(`JourneyPresentation.transfers`, „Knapp: 3 min zum Umsteigen“), die Karte und die Mitteilung „Anschluss knapp“ rufen dieselbe Funktion
auf; dieselben Daten geben überall dieselbe Zahl. Ein Test vergleicht sie für jeden Umstieg der aufgezeichneten Planer-Antworten.

- **Zubringer** (der verfolgte Zug): Ankunft am Umstiegsbahnhof, Echtzeit sonst Fahrplan. Es zählt die **neuere** Antwort – die eigene
  Reconstruction des Wächters oder die JourneyDetails der Live-Verfolgung (die fragt den Zubringer ohnehin jede Minute; der Wächter
  liest mit und fragt nicht selbst). Darum kann die Karte neuer sein als ein offenes Verbindungsdetail – dann unterscheiden sich die
  Daten, nie die Formel.
- **Anschluss**: Abfahrt am Umstiegsbahnhof aus der Reconstruction der Verbindung (`HafasClient.refresh`, ohne Zwischenhalte, ohne
  Linienverlauf). Nach zwei fehlgeschlagenen Reconstructions in Folge (Fehler der Auskunft, nicht „offline“) fragt der Wächter die
  JourneyDetails des Anschlusszugs; der Halt wird über die Location-ID, sonst die extId gefunden.
- **Fußweg**: die Fußweg- und Umstiegs-Abschnitte zwischen den beiden Fahrten, so gezählt wie in den Verbindungsdetails. Ohne solchen
  Abschnitt zählt 0 und die Karte sagt „Fußweg nicht bekannt“.
- Beobachtet wird der **nächste** Umstieg nach dem verfolgten Zug. Spätere Umstiege stehen als einfache Zeilen da („Danach: Umstieg in
  Wiener Neustadt Hbf, 12 Min laut Fahrplan“), ohne eigenen Zustand.
- Der Wächter startet nur, wenn die Verbindung mindestens zwei Fahrten und einen Reconstruction-Schlüssel hat und die Verfolgung genau
  ihre erste Fahrt ist. Er startet mit „Live verfolgen“ im Verbindungsdetail und auf der Pendel-Karte (dort mit den Verkehrsmitteln
  des Fahrplans für die Alternativen).
- **Weiter verfolgen**: Nach „Umstieg vorbei“ bietet die Karte „REX 41 weiter verfolgen“ an. Ein Tipp verfolgt den Anschluss; hat
  die Verbindung danach noch einen Umstieg, bekommt er einen eigenen Wächter (auf der zweiten Fahrt).

## 3 Zustände und Schwellen

Unsere eigenen Regeln, hier aufgeschrieben (`ConnectionGuard.rawState`). Die Schwellen sind die der Verbindungsdetails (`TransferRisk`:
ab 5 sicher, 2–4 knapp, unter 2 gefährdet).

| Zustand | Wann | Farbe (Token) |
|---|---|---|
| Sicher | 5 Min oder mehr und nicht fallend (oder fallend, aber noch 10 oder mehr) | `positive` |
| Wird knapper | 5 oder mehr, aber in den letzten 10 Min um 2 oder mehr gefallen – oder 2 bis 4 Min | `summit` |
| Wackelt | 0 oder 1 Min, oder 1 Min zu wenig („Es fehlt dir 1 Min“); oder die Auskunft markiert den Anschluss als nicht erreichbar (`isRchbl` false) – das macht höchstens „Wackelt“, nie „Verpasst“ | `summit`, kräftiger |
| Wahrscheinlich verpasst | 2 oder mehr Minuten zu wenig, solange der Anschluss noch nicht abgefahren ist – eine **Prognose** aus beiden Zügen | `negative` |
| Verpasst | die Abfahrt des Anschlusses (Echtzeit, sonst Fahrplan) ist vorbei, und der Zubringer war noch nicht da – eine Tatsache der Daten | `negative` |
| Fällt aus | Zubringer oder Anschluss fällt aus, oder einer hält nicht am Umstiegsbahnhof | `negative` |
| Nach Fahrplan | keiner der beiden Züge hat Echtzeit | `textSecondary` |
| Umstieg vorbei | 2 Min nach der Abfahrt des Anschlusses, und die letzte Umstiegszeit war 0 oder mehr; der Wächter endet | `textTertiary` |

Reihenfolge der Prüfung: Ausfall, Verpasst, Umstieg vorbei, ohne Echtzeit, dann die Minuten mit dem Trend.

- **Trend**: aus jeder neuen Antwort ein Wert (Zeit der Anfrage, Minuten), zehn Minuten lang gemerkt. *Fallend*: jetzt mindestens 2 Min
  unter dem höchsten Wert der letzten 10 Min („Wird knapper: vor 4 Min waren es 9 Min“); *steigend*: mindestens 2 über dem niedrigsten
  („Entspannt sich: vor 3 Min waren es 2 Min“; fehlte damals Zeit: „vor 2 Min fehlte 1 Min“); sonst „Gleichbleibend“. Mit nur einer
  Antwort sagt die Karte keinen Trend, nach Fahrplan auch nicht (der Fahrplan hat keinen Verlauf).
- **Hysterese**: Schlechter zeigt sie sofort. Besser erst, wenn zwei neue Antworten hintereinander besser sagen; gezeigt wird die
  vorsichtigere der beiden. Ohne neue Antwort wird nichts besser – auch „Verpasst“ und „Fällt aus“ nicht, nur eine neue Antwort, die
  es klar anders sagt. „Wahrscheinlich verpasst“ folgt der normalen Regel, weil eine spätere Prognose sehr wohl sagen kann, dass es
  reicht. „Umstieg vorbei“ zeigt sie sofort.

## 4 Anfragen, Takt, Datenmenge

Der Wächter fragt nur, wenn **alles** gilt (`GuardPlan.next`): die Verfolgung hat noch seinen Zubringer als Ziel; die App ist aktiv
(`didBecomeActive`/`willResignActive`); Live-Daten sind verfügbar (Zustimmung, Schalter, Kill-Switch, Offline-Modus, online); kein
Stromspar-Modus; der Wächter ist für diese Fahrt nicht aus; die Zeit liegt im Fenster **Abfahrt des Zubringers laut Fahrplan − 30 Min
… Abfahrt des Anschlusses + 5 Min**.

- „Verfolgung aktiv“ heißt: das **Ziel** der Verfolgung, nicht ihre Stufe. Die Stufe der Verfolgung wird bei der *geplanten* Abfahrt des
  Anschlusses „angekommen“; ein verspäteter Anschluss (geplant 14:40, erwartet 14:45) wird trotzdem weiter geprüft und endet mit
  „Umstieg vorbei“ um 14:47.
- **Takt**: eine Reconstruction alle 120 s, alle 60 s, solange es schlechter als „Sicher“ steht. Sofort beim Start, bei der Rückkehr
  in die App (wenn die letzte Antwort älter als 60 s ist) und auf „Jetzt prüfen“ (höchstens alle 20 s, auch im Stromspar-Modus).
  Nie zwei Anfragen gleichzeitig. Nach Fehlern wartet er 15, 30, 60, dann 120 s.
- **Nach einem Neustart** kommt der Wächter mit der Verfolgung zurück. Das Laden fragt nichts – auch nicht in einer
  Hintergrund-Aktualisierung der Verfolgung; die Schleife startet erst, wenn die App aktiv ist.
- **Budget**: alle Anfragen laufen über `HafasClient` → `RequestThrottle` (40 je Minute für die ganze App) und `LiveHealth`, **nicht**
  über das Budget des Zug-Radars. Schlimmster Fall mit der Verfolgung: etwa 1 (Verfolgung) + 1 (Wächter) + 0,33 (Suche) ≈ 2,3 Anfragen
  je Minute – weit innerhalb der 16 je Minute, die der Radar freilässt.
- **Hintergrund**: nichts. Die bestehende Hintergrund-Aktualisierung der Verfolgung bleibt genau, wie sie ist (eine JourneyDetails).
- **Datenmenge**: eine Reconstruction ohne Zwischenhalte etwa 10–30 KB (aufgezeichnet *mit* Zwischenhalten: 32 KB), eine Suche nach
  Alternativen etwa 50–150 KB, einmal. Bei 60 s Takt also höchstens etwa 2 MB je Stunde. Nicht gemessen: diese Welle macht keine
  Live-Anfragen; die Zahlen stammen aus den aufgezeichneten Antworten.

## 5 Alternativen

`GuardAlternatives`: eine TripSearch, gesucht wie im Fahrplan.

- **Von** dem Umstiegsbahnhof; fällt der Zubringer aus, bevor er abgefahren ist, vom Einstiegshalt. **Nach** dem Endziel der Verbindung.
  **Ab** max(jetzt, erwartete Ankunft des Zubringers + Fußweg), bei einem ausgefallenen Zubringer jetzt. **Verkehrsmittel** wie beim
  Start im Fahrplan gespeichert („Nur mit KlimaTicket gültig“ gilt weiter). 4 Ergebnisse, ohne Via, ohne Zwischenhalte.
- **Auswahl**: weg mit Abfahrten vor dem Zeitpunkt (auf die Minute), ausgefallenen Verbindungen und solchen, die mehr als 3 Stunden nach
  der geplanten Ankunft ankommen; sortiert nach Ankunft, dann Abfahrt; die ersten drei. Dazu „22 Min später als geplant“ / „wie
  geplant“ / „3 Min früher als geplant“ gegen die geplante Ankunft der ursprünglichen Verbindung.
- **Automatisch** einmal, wenn der Zustand „Wahrscheinlich verpasst“, „Verpasst“ oder „Fällt aus“ wird (im Hintergrund vorgemerkt und
  erst beim Öffnen gesucht); sonst auf „Alternativen ansehen“. Höchstens eine neue Suche je 3 Minuten und Wächter; das Ergebnis bleibt so
  lange stehen („Neue Suche in 2 Min möglich“).
- **Verfolgen** startet die Live-Verfolgung der ersten Fahrt der Alternative (wie „Live verfolgen“ im Fahrplan) und, wenn sie einen
  Umstieg hat, einen neuen Wächter. **Im Fahrplan öffnen** öffnet den Fahrplan mit Start, Ziel und Abfahrt der Alternative
  (`PlannerModel.openGuardSearch`, mit den Orten der Auskunft statt Namen).

## 6 Die Mitteilung „Anschluss knapp“

Was sich geändert hat (`FollowTransfer`, `LiveFollowSnapshot.transferBufferMinutes`):

- `FollowTransfer` hat drei neue optionale Felder: `expectedDeparture`, `expectedAt`, `walkMinutes`. Gespeicherte Verfolgungen älterer
  Versionen lesen sich unverändert (Test).
- Nach jeder Antwort gibt der Wächter der Verfolgung die erwartete Abfahrt des Anschlusses, die Zeit dieser Antwort und den Fußweg
  (`LiveFollowTracker.updateTransferEstimate`).
- Die Mitteilung rechnet mit `TransferBuffer.minutes`: Abfahrt = die erwartete, solange sie höchstens 10 Min alt ist, sonst die
  geplante; minus Fußweg, wenn bekannt. Sie kommt bei **unter 5 Min** und trägt dieselbe Zahl wie die Karte.
- Vorher: erwartete Ankunft gegen *geplante* Abfahrt, ohne Fußweg, in Sekunden verglichen und abgerundet (4 Min 40 s gaben „noch
  4 Min“, die Karte sagt 5 und „Sicher“). Die alte Eigenschaft `transferBufferSeconds` bleibt für andere Aufrufer.
- Die **Live Activity** zeigt beim Umstieg dieselbe Abfahrt („Umstieg in Linz Hbf · 14:41“): die erwartete, solange sie frisch ist,
  sonst die geplante (`FollowLiveState.make`).
- **Hintergrund**: Läuft eine Hintergrund-Aktualisierung mehr als 10 Min nach dem letzten Öffnen, ist die Schätzung alt, und die
  Mitteilung rechnet wieder mit der geplanten Abfahrt – lieber eine Warnung zu viel als eine zu wenig. Der Text der Mitteilung bleibt
  („Anschluss knapp“ / „Anschluss wahrscheinlich verpasst“).

## 7 Speicher

- **Ein** Datensatz, Version 1 (`GuardRecord`): Fahrt-ID der Verfolgung, eine schlanke Kopie der Verbindung (Abschnitte ohne
  Zwischenhalte, Linienverlauf und Hinweise; der Reconstruction-Schlüssel), welcher Umstieg, die Verkehrsmittel, „Nur mit KlimaTicket
  gültig“, Zeitpunkt, „Wächter aus“.
- Als Datei `Guard/record.json` in Application Support, **von der Sicherung ausgenommen** (`isExcludedFromBackup`), lesbar nach dem
  ersten Entsperren – nach dem Muster von `DetectionFiles`. Nicht in UserDefaults (die gehören zur iPhone-Sicherung), nicht im Export
  der App, nicht synchronisiert. Es ist deine Reise bis zum Endziel.
- Gelöscht, wenn die Verfolgung endet oder ersetzt wird, wenn der Wächter endet („Umstieg vorbei“ oder Ende des Fensters) oder wenn der
  Datensatz älter als 12 Stunden ist. In Demo- und Screenshot-Starts wird nichts gelesen oder geschrieben.
- Werte für den Trend und die Zustände: nur im Speicher.
- Keine neue Einstellung. „Wächter aus“ im Menü der Karte schaltet ihn für diese Fahrt ab (keine Anfragen mehr; die Karte sagt es).

## 8 Texte

Alle Texte stehen in `GuardText` (getestet in `GuardTextTests`).

- Karte: Titel „Anschluss in St. Pölten Hbf“; Chip „Sicher“ / „Wird knapper“ / „Wackelt“ / „Wahrscheinlich verpasst“ / „Verpasst“ /
  „Fällt aus“ / „Nach Fahrplan“ / „Umstieg vorbei“ (mit Symbol, nie nur Farbe; bei großen Schriften bricht der Chip um).
- Große Zeile: „6 Min zum Umsteigen“ · „Es fehlt dir 1 Min“ · „Es fehlen dir 4 Min“ · „REX 2 fällt aus“ · „REX 2 ist abgefahren“.
- Trend, Züge („Ankunft RJX 66 · 14:31 (+3) · Gleis 4“, ohne Echtzeit „14:40 laut Fahrplan“), Fußweg („Fußweg laut Fahrplan: 3 Min“ /
  „Fußweg nicht bekannt“), „Gleis geändert: 5 → 7“, „REX 2 ist laut Prognose um 14:40 abgefahren.“, „Die ÖBB-Auskunft markiert den
  Anschluss als nicht erreichbar.“, „Keine Echtzeit-Daten: gerechnet nach Fahrplan.“, „Danach: Umstieg in …“.
- Status: „Stand 14:27 · nächste Prüfung in 1 Min“ · „Stromspar-Modus: keine automatische Prüfung.“ · „Wächter für diese Fahrt aus.“ ·
  „Ohne Internet keine Prüfung. Gezeigt ist der Stand von 14:21.“ · „Für die Prüfung braucht es Live-Daten.“ · „Automatische Prüfung ab
  13:50“ · „Die Auskunft antwortet gerade nicht · neuer Versuch in 1 Min“ · „Prüfung beendet“.
- Fußzeile (immer): „KlimaBilanz prüft deinen Anschluss nur, solange die App offen ist. Im Hintergrund kommt höchstens die Mitteilung
  „Anschluss knapp“ – nur mit eingeschalteten Live-Mitteilungen und nur, wenn iOS die App kurz aufweckt. Das ist nicht garantiert.“ und
  „Ob ein Zug wartet, sagt die Auskunft nicht. Die Einschätzung rechnet mit den Prognosen beider Züge.“
- VoiceOver: die Karte ist ein Element mit einem Satz („Anschluss in St. Pölten Hbf: wackelt, 1 Minute zum Umsteigen, wird knapper.
  Ankunft RJX 66 um 14 Uhr 31, 3 Minuten später. Abfahrt REX 2 um 14 Uhr 40, 1 Minute später, Gleis 7. Fußweg 3 Minuten.“) und den
  Aktionen „Alternativen ansehen“, „Jetzt prüfen“, „Wecker fürs Umsteigen“, „Wächter aus“.
- Toasts (einer je Verschlechterung, mit Haptik `.warning`, nur bei offener App): „Anschluss in St. Pölten wird knapper“ · „… wackelt“ ·
  „… wahrscheinlich verpasst“ · „… verpasst“ · „REX 2 fällt aus“.
- Abzeichen im Zubehör der Tab-Leiste: „knapper“, „wackelt“, „wohl verpasst“, „verpasst“, „fällt aus“ mit dem Umstiegs-Symbol; VoiceOver
  liest „Anschluss wahrscheinlich verpasst“ usw. Bei „Sicher“ kein Abzeichen.
- Alternativen: „Weiter ab St. Pölten Hbf“, „Nach Wiener Neustadt Hbf · ab 14:42“, „ab 14:52 · Gleis 3“, „an 16:10“, „1 Umstieg“,
  „Verfolgen“ (VoiceOver „Diese Verbindung live verfolgen“), „Im Fahrplan öffnen“, „Tipp: Mit „Verfolgen“ prüft KlimaBilanz auch den
  neuen Umstieg.“, „Suche Verbindungen …“, „Die Auskunft kennt gerade keine passende Verbindung. Sieh im Fahrplan nach.“, „Neue Suche in
  2 Min möglich“, „Eine Suche bei der ÖBB-Auskunft, gesucht wie im Fahrplan (Nur mit KlimaTicket gültig: an).“

## 9 Demo

`GuardDemo` baut auf der Demo-Fahrt des Zug-Radars auf („RJX 66“ Wien Hbf → … → Linz Hbf, +5 in Linz), mit 3 Min Fußweg und einem
erfundenen „REX 41 Linz Hbf → Summerau“; Zeiten relativ zu jetzt, die Antworten je Szene vorgegeben. Kein Netz, keine
Mitteilungs-Erlaubnis, keine Live Activity, keine Datei.

Screenshot-Szenen (`GuardScreenshotHost`): `guardSafe` (8 Min, gleichbleibend), `guardTighter` (6 Min, vor 4 Min 9), `guardShaky`
(1 Min, wackelt, Gleis geändert), `guardMissed` („Es fehlen dir 4 Min“, „Wahrscheinlich verpasst“, die Alternativen öffnen sich
selbst), `guardCancelled` („REX 41 fällt aus“), `guardNoRealtime` (nach Fahrplan, nur die Karte – neben der Demo-Verfolgung mit
Echtzeit wäre „keine Echtzeit“ falsch), `guardAlternatives` (drei Zeilen und der Tipp), `guardAccessory` (Abzeichen im Zubehör),
`guardAX5` (Karte bei AX5), `guardOver` („Umstieg vorbei“ mit „REX 41 weiter verfolgen“ und dem nächsten Umstieg, nur die Karte).

Mit `-KBDemo` außerhalb der Screenshots: Der Demo-Fahrplan hat keine Reconstruction; der Wächter einer Demo-Verbindung antwortet mit
der Verbindung, wie sie beim Start war, und sucht Alternativen im Demo-Fahrplan. Die Demo-Verfolgung kennt nur die Radar-Fahrten; eine
Planer-Demo-Verbindung zeigt in der Verfolgung „Keine Verbindung zu ÖBB“ (unverändert gegenüber vorher).

## 10 Geprüft / nicht geprüft

Geprüft (Linux, `swift test --filter "ConnectionGuard|TransferBuffer|FollowTransferAlignment|GuardPlan|GuardGate|GuardAlternatives|GuardRecord|GuardText"`):
Schwellen 10, 9, 5, 4, 2, 1, 0, −1, −2 mit Trend; Hysterese; Verpasst als Tatsache (auch bei gerundet 0 Min); Wahrscheinlich verpasst
nicht klebrig; Ausfälle; ohne Echtzeit; `isRchbl` false; Umstieg vorbei nach der *erwarteten* Abfahrt; Mitternacht und
Zeitumstellung 25.10.2026; dieselbe Zahl wie die Verbindungsdetails für jeden aufgezeichneten Umstieg; Fenster, Takt, Rückkehr,
„Jetzt prüfen“, nie zwei gleichzeitig, Backoff, Rückfall auf JourneyDetails, Stromspar-Modus, ohne Live-Daten keine Anfrage
(Test-Doppel, das eine simulierte Stunde lang nie fragt), Hintergrund, „Wächter aus“; Alternativen (Abfrage, Auswahl, Texte, 3-Minuten-
Grenze); Datensatz (Version, schlanke Kopie, Müll, 12 h, gleiche Fahrt mit gleichem Umstieg); die Mitteilung (alte Datensätze, frisch
gegen alt, Fußweg, 4 Min 40 s, dieselben Minuten wie die Karte); die Live Activity mit der erwarteten Abfahrt; „weiter verfolgen“
(Ziel und eigener Wächter für den nächsten Umstieg); jeder Text. Typprüfung der App unter Linux, Screenshots auf dem Simulator.

**Nicht geprüft:**
- Was `isRchbl` false wirklich bedeutet: alle aufgezeichneten Antworten sagen `true`. Darum nur ein Hinweis und höchstens „Wackelt“.
- Ob die Echtzeit der ÖBB für zwei Züge gut genug ist, dass „Verpasst“ der Wirklichkeit entspricht.
- Ob eine Reconstruction nach der Abfahrt des Zubringers noch antwortet (ein alter Kontext kann scheitern; dann der Rückfall).
- Die Datenmengen ohne Zwischenhalte (nicht gemessen, diese Welle macht keine Live-Anfragen).
- Nichts davon lief auf einem echten iPhone.

## 11 Geräte-Checkliste

1. Eine echte Verbindung mit Umstieg im Fahrplan öffnen, „Live verfolgen“, das Blatt der Verfolgung öffnen: die Karte erscheint;
   Minuten, Zeiten und Gleise mit der Anzeige am Umstiegsbahnhof und mit dem Verbindungsdetail vergleichen (gleiche Zahl bei gleichem
   Stand).
2. Die App 15 Min verlassen und zurückkehren: genau eine Prüfung sofort („Stand“ springt auf jetzt), danach wieder alle 1–2 Min.
3. Flugmodus (oder Tunnel): „Ohne Internet keine Prüfung. Gezeigt ist der Stand von …“; nach dem Flugmodus prüft er von selbst weiter.
4. Stromspar-Modus: „Stromspar-Modus: keine automatische Prüfung.“; „Jetzt prüfen“ geht trotzdem (höchstens alle 20 s).
5. „Wächter aus“ im Menü: die Karte sagt „Wächter für diese Fahrt aus.“, es gehen keine Anfragen mehr (Funktionen › Datenschutz,
   Zähler der ÖBB-Auskunft).
6. Ein verspäteter Anschluss: der Wächter läuft nach der geplanten Abfahrt weiter und endet mit „Umstieg vorbei“ 2 Min nach der
   erwarteten Abfahrt.
7. „Wahrscheinlich verpasst“ oder „Verpasst“: die Alternativen öffnen sich einmal; „Verfolgen“ startet die neue Verfolgung, „Im
   Fahrplan öffnen“ den Fahrplan.
8. Mit eingeschalteten Live-Mitteilungen und geschlossener App: kommt „Anschluss knapp“, trägt sie dieselbe Zahl wie zuletzt die Karte
   (solange die Karte vor höchstens 10 Min offen war).
9. App beenden und neu öffnen während der Verfolgung: die Karte kommt mit der Verfolgung zurück und prüft sofort einmal.
10. Live Activity auf dem Sperrbildschirm während des Umstiegs: „Umstieg in … · 14:45“ zeigt die erwartete Abfahrt, solange der
    Wächter sie vor höchstens 10 Min gesehen hat.
