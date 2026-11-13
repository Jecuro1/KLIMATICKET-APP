# Pendel-Modus

Stand: Track „Pendel-Modus und Abfahrten“ (November 2026). Für Menschen, die jeden Tag dieselbe Strecke fahren: Die App kennt
die Stammstrecke, zeigt kurz vor der Abfahrt, was auf ihr gerade los ist, und legt die Ein-Tipp-Aktionen dorthin, wo sie gebraucht
werden. Dieses Dokument beschreibt, was gebaut ist, welche Regeln gelten, was nur ein echtes iPhone beweisen kann (§9) und was
bewusst fehlt (§10). Live-Regeln bleiben in `docs/OEBB_LIVE.md` (§2 Rechtsrahmen).

Code: Logik in `Packages/KlimaCore/Sources/KlimaCore/Commute/` (Linux-Tests unter `Tests/KlimaCoreTests/Commute/`, 54 Tests),
App in `App/Sources/Services/Commute/` (Einstellungen, Kartenzustand, Siri) und `App/Sources/Features/Commute/` (Karte,
Einstellungsseite, Demo-Szenen).

## 1. Die Karte in der Übersicht

`CommuteCardSection` sitzt in der Übersicht über „Schnell erfassen“. Vier Gesichter, entschieden von Einstellungen und Uhr:

| Zustand | Wann | Was die Karte zeigt |
|---|---|---|
| 1. Einladung | Modus aus, der Erkenner ist sich **sicher** (§2), beide Enden sind App-Stationen, das Paar wurde nicht in den letzten 30 Tagen abgelehnt und ist nicht die gespeicherte Strecke eines ausgeschalteten Modus | „Ist das dein Arbeitsweg?“, Strecke, die Belege („34 Fahrten an 17 Tagen in 7 Wochen · Mo–Fr · meist 07:20 hin, 17:10 zurück“ – Fahrten gezählt wie in der Statistik, §2), „Ja, merken“ / „Nein“. „Nein“ hält 30 Tage still, der Toast bietet „Rückgängig“. „Stammstrecke entfernen“ zählt für diese Strecke wie ein „Nein“. |
| 2. Kompakt | Modus an, außerhalb des Live-Fensters | „Nächste Pendelfahrt heute 17:12“ aus dem Plan, Strecke, wann die Züge kommen („Live ab 16:27“, „Live morgen ab 06:35“; ohne Live-Daten „laut Plan, ohne Live-Daten“), runder „+“-Knopf (Fahrt erfassen). **Keine Abfrage** – deshalb steht hier nicht „aktualisiert beim Öffnen“. |
| 3. Live | Ab 45 Minuten vor einer geplanten Abfahrt bis 30 Minuten danach | Die nächsten drei Verbindungen: Zeit, Abzeichen („pünktlich“, „+2“, „+5“ bernstein ab 3, „+12“ rot ab 10, „Ausfall“ mit durchgestrichener Zeit, „Fahrplan“ ohne Echtzeit), Linie, Ziel, Ankunft, Umstiege, Gleis (ein geändertes Gleis ist getönt und trägt ein Tausch-Symbol). Darunter „Stand 07:31 · Echtzeit · aktualisiert beim Öffnen“. Oben ein großer Countdown zur frühesten Abfahrt, die noch fährt (liegt sie mehr als eine Minute zurück, bleibt sein Platz leer – kein „jetzt“ für eine halbe Stunde), und „Richtung tauschen“. |
| 4. Störung | Die erste Verbindung fällt aus oder ist mindestens 10 Minuten spät | Rotes Band: „Dein Zug fällt aus – nächste Verbindung 07:42, Gleis 3“ bzw. „Dein Zug ist 12 Minuten verspätet – schneller: 07:27, Gleis 3“ (§5). Die genannte Verbindung trägt in der Liste „Alternative“. |

Ohne Live-Daten (keine Zustimmung, abgelehnt, Schalter aus, Kill-Switch, offline) zeigt die Karte im Fenster den Plan
(„07:20 laut deinem Plan · Mo–Fr“). Ist die Zustimmung **noch offen**, bietet sie einmal „Verspätung und Gleis live sehen?“ an –
das öffnet die bekannte Zustimmungskarte des Fahrplans im Blatt. Abgelehnt oder ausgeschaltet steht nur eine ruhige Zeile mit dem
Grund; es gibt keine zweite Frage und keine Schleife. Modus an, aber ohne Strecke: „Stammstrecke fehlt“ öffnet die Einrichtung.
Modus aus und nichts zu fragen: die Übersicht bleibt, wie sie war (kein Platz, kein Abstand).

**Schnellaktionen** (Karte, Kontextmenü der Karte, VoiceOver-Aktionen): „Fahrt erfassen“ (Formular vorbefüllt mit der Strecke, Richtung
nach Tageszeit oder „Hin und retour“, wenn das die gemerkte Wahl ist; gespeichert wird erst im Formular), „Live verfolgen“ (die
bestehende Verfolgung für die erste fahrende Verbindung; nur mit Live-Daten), „Rückfahrt planen“ (Fahrplan in Gegenrichtung zur
Planzeit, wenn die heute noch kommt) und „Verbindung ändern“ (Fahrplan mit derselben Richtung ab jetzt, alle Optionen des Planers).
Bei Bedienungshilfen-Schriftgrößen stehen die vier Knöpfe untereinander, der Kopf der Karte ebenfalls.

`klimabilanz://commute` springt zur Übersicht; ist der Modus eingerichtet, pulsiert die Karte einmal, sonst öffnet die Einrichtung.

## 2. Stammstrecke erkennen (`CommuteDetector`)

Rein, auf dem Gerät, ohne Speicher. Eingabe: die erfassten Fahrten der letzten **56 Tage**.

- Beide Richtungen eines Paares zählen zusammen (Schlüssel: Stations-ID, sonst der normalisierte Name). Teilstrecken einer Reise
  (`docs/JOURNEYS.md`) werden zu einer Fahrt vom ersten Start zum letzten Ziel. Für die Regel unten zählt „Hin und retour“ als zwei
  Fahrten. **Angezeigt** („34 Fahrten“ in Einladung und Vorschlag) wird dagegen die Zahl der erfassten Fahrten so, wie die Statistik
  sie zählt (`JourneySummary.tripCount`: ein „Hin und retour“-Eintrag und eine Reise mit Etappen sind je eine Fahrt) – sonst nennt die
  Einladung für dieselben Fahrten doppelt so viele wie die Statistik (`CommuteGuess.trips`, Linux-Test).
- Ein Paar **qualifiziert** mit mindestens **6 Fahrten** in mindestens **3 verschiedenen Wochen** an mindestens **2 Wochentagen**.
- **Sicher** (nur dann fragt die Übersicht) ist das meistgefahrene qualifizierte Paar, wenn es mindestens das **1,5-Fache** des
  Zweiten hat; sonst „mittel“ – das erscheint nur als Vorschlag in den Einstellungen.
- Uhrzeiten werden nur verwendet, wenn sie etwas bedeuten: nicht alle Mitternacht (importierte Daten ohne Uhrzeit), beide Richtungen
  mit mindestens zwei Zeiten, Mediane mindestens **2 Stunden** auseinander (sonst ein Erfassungs-Cluster am Abend) und je Richtung
  eine Streuung (mittlere absolute Abweichung) bis **90 Minuten**. Dann gilt die frühere Richtung als Hinfahrt, gerundet auf 5 Minuten.
- Ohne brauchbare Zeiten entscheidet der Heimatbahnhof, sonst das Ende, an dem öfter gestartet wurde.

Tests: positive Fälle, Negative (zufällige Fahrten, ein einmaliger Urlaub, nur Hin-und-retour an einem Tag), Gleichstand, Zeiten.
Die Zahlen sind die des Plans, **nicht** an echten Verläufen abgestimmt (§9).

## 3. Fenster und Richtung (`CommuteWindow`)

- Alle Uhrzeiten sind Minuten nach Mitternacht in Wiener Zeit; Tage werden mit `Calendar` gebaut, nie mit 86 400 s. In der
  Frühjahrsnacht (02:00–03:00 gibt es nicht) gilt die nächste existierende Zeit, im Herbst die erste.
- Das Live-Fenster öffnet **45 Minuten** vor einer geplanten Abfahrt und bleibt **30 Minuten** danach offen. Überlappen zwei
  Fenster, gilt das mit der näheren Abfahrt. Ein Fenster über Mitternacht gehört zum Wochentag seiner Abfahrt.
- Die Karte zeigt die Fahrt, deren Fenster offen ist, sonst die nächste geplante Abfahrt (um 10 Uhr also schon die Rückfahrt um
  17:12). Auf der Karte lässt sich die Richtung für das laufende Fenster tauschen.
- „Fahrt erfassen“ und Siri nehmen die Richtung der Tageszeit: vor 13 Uhr die Hinfahrt, danach die Rückfahrt – liegen beide
  Planzeiten auf derselben Seite von 13 Uhr (Spät- oder Nachtschicht), die zeitlich nähere.

## 4. Verbindungen (`CommuteStatus`, `CommuteSearch`)

- Eine Suche je Aktualisierung: Start → Ziel (bzw. umgekehrt), 6 Ergebnisse, ohne Zwischenhalte und ohne Linienzug. Die Karte zeigt
  drei, der Berater (§5) sieht alle.
- Verspätung = Abfahrtsverspätung der ersten Fahrt am Start, gerundet auf ganze Minuten wie überall in der App. Schwellen: 1–2 neutral,
  ab 3 bernstein, ab 10 rot; „Ausfall“, sobald irgendeine Teilfahrt ausfällt. Die Bedeutung steht immer auch als Text im Abzeichen.
- Eine Verbindung bleibt bis eine Minute nach ihrer (Echtzeit-)Abfahrt auf der Karte; eine ausgefallene bis zu ihrer Planzeit.
- VoiceOver liest eine Zeile als einen Satz: „Zug 07:42 nach Innsbruck, 5 Minuten verspätet, Gleis 4“.

## 5. Alternative (`CommuteAdvisor`)

Nur für die erste Verbindung. **Ausfall:** genannt wird die Verbindung derselben Suche, die als erste ankommt und fährt.
**Mindestens 10 Minuten spät:** genannt wird nur eine Verbindung, die **früher ankommt** als die verspätete; sonst sagt das Band
„keine schnellere Verbindung“. Die App erfindet nie eine Verbindung.

## 6. Siri und Kurzbefehle

- „Wann fährt mein nächster Zug in KlimaBilanz?“ (`CommuteNextIntent`) liest die Verbindungen, die die Karte zuletzt geladen hat,
  wenn sie höchstens **15 Minuten** alt sind, und sagt Zeit, Verspätung, Gleis, bei Ausfall die Alternative und „Stand 07:31“. Sonst
  antwortet Siri aus dem Plan und sagt, warum („Verspätungen siehst du, wenn du KlimaBilanz öffnest“ bzw. „Live-Daten sind
  ausgeschaltet“). Siri macht **keine** Abfrage.
- „Pendelfahrt in KlimaBilanz erfassen“ (`CommuteLogIntent`) erfasst die Stammstrecke für jetzt – hin und retour, wenn das gemerkt ist,
  sonst in der Richtung der Tageszeit. Wie die Schnellerfassung der Widgets wird die Anfrage zuerst vorgemerkt
  (`CommuteLogQueue`) und dann über das Repository gespeichert (ein Commit, Widgets, Sync): sofort, wenn die App ihren Speicher offen
  hat, sonst beim nächsten Öffnen. Der Wert kommt aus derselben Tariflogik wie im Formular (`Repository.facts`); gespeichert wird über
  `Repository.addCommuteTrips`. Zwei Abarbeitungen laufen nie gleichzeitig (Aktivierung der App und Siri zugleich): sonst würde jede
  vorgemerkte Fahrt zweimal gespeichert.
- Beide Sätze enthalten den App-Namen (Pflicht für App Shortcuts). Damit sind es 8 von 10 möglichen App Shortcuts.

## 7. Live-Daten und Rechtsrahmen

- Abfragen nur mit der bestehenden Live-Zustimmung, nur im Vordergrund, nur solange die Karte im Live-Fenster auf dem Bildschirm
  ist (weggescrollt, anderer Tab oder App im Hintergrund: Pause), höchstens **einmal pro Minute**
  (`CommuteSearch.minRefreshInterval`), im Stromsparmodus nur beim Öffnen, und nur über `LiveDataService.timetable` –
  das ist `nil` ohne Zustimmung, mit ausgeschaltetem Fahrplan, Kill-Switch oder offline. `CommuteSearch.connections` wirft dann
  `consentRequired`, **bevor** irgendetwas passiert (nicht einmal die Stationssuche); ein Linux-Test prüft, dass dabei keine Anfrage
  entsteht. Die Anfrage selbst läuft durch den gemeinsamen HAFAS-Client und dessen `RequestThrottle` (40 Anfragen je Minute für die
  ganze App, mindestens 0,3 s Abstand, ehrlicher User-Agent). Eine offene Karte kostet eine Suche je Minute; beim ersten Mal kommen bis
  zu zwei Stationssuchen dazu (danach 30 Tage gemerkt). Findet die ÖBB-Auskunft eine der beiden Stationen nicht, fragt die Karte für
  diese Strecke nicht mehr jede Minute, sondern sagt es einmal („Wähle sie in den Pendel-Einstellungen neu“). Gesperrt oder gedrosselt
  (`blocked`, `rateLimited`) hält der gemeinsame Schutzschalter (`LiveHealth`) jede weitere Anfrage zurück.
- Der **Offline-Modus** (Einstellungen › Funktionen) schaltet alles ab; Karte, Einstellungen und Siri nennen ihn als Grund statt
  „Fahrplan live ist aus“.
- Kein Hintergrundabruf, kein BGAppRefresh, keine Mitteilung, kein Widget-Cache. Der Standort wird nicht verwendet.
- Die letzte Antwort liegt für Siri in den UserDefaults der App (`commute.snapshot.v1`), höchstens 15 Minuten wird sie vorgelesen.

## 8. Einstellungen und Speicher

Einstellungen › Pendeln (`CommuteSettingsPage`): Schalter, Stammstrecke („Vorschlag“ aus §2, eine Strecke aus „Meine Routen“
oder zwei Stationen; „Richtung tauschen“ bestimmt, wo die Hinfahrt beginnt), Wochentage, Abfahrt der Hin- und der Rückfahrt (aus dem
Zeitplan der Route vorbefüllt), „Hin und retour erfassen“, der Stand der Live-Daten (mit dem Angebot, sie einzuschalten, solange
nichts entschieden ist), die Siri-Sätze und „Stammstrecke entfernen“.

Gespeichert als versioniertes JSON in den UserDefaults der App (`commute.settings.v1`, `CommuteSettingsStore`); jedes Feld wird
einzeln gelesen, damit eine ältere oder neuere Form nichts zurücksetzt. **Keine SwiftData-Änderung, nichts wird synchronisiert,
nichts liegt in der App Group.** CI-Screenshot- und Perf-Läufe halten alles nur im Speicher. „Alle Daten löschen“ entfernt
Einstellungen, Siri-Antwort und vorgemerkte Siri-Fahrten.

## 9. Was nur ein echtes iPhone zeigt

- HAFAS-Echtzeit über iOS-`URLSession` (die Cloudflare-Frage R1 ist nur mit curl geprüft).
- Ob Verspätung und Gleis zum ÖBB-Auftritt passen: Zustimmung geben, die Karte im Morgenfenster öffnen und denselben Zug vergleichen.
- Wie gut die Erkennung auf echten Verläufen trifft (die Schwellen sind die des Plans).
- Ob Siri die deutschen Sätze per Stimme erkennt, und „Wann fährt mein nächster Zug?“ aus der Kurzbefehle-App.
- „Pendelfahrt erfassen“ bei geschlossener App: vorgemerkt und beim nächsten Öffnen gespeichert.

Verspätungen erscheinen nur, während die App offen ist. Ohne Push (kein bezahlter Apple-Developer-Account) lässt sich das nicht ändern.

## 10. Bewusst nicht gebaut (Stretch, gestrichen)

- **Abendliche Erinnerung** „Hast du die Pendelfahrt heute erfasst?“: nicht gebaut (keine Mitteilung, kein Eintrag in „Alarme“).

## 11. Demo und Screenshots

`CommuteFixture` (St. Anton am Arlberg ⇄ Innsbruck Hbf, die „Arbeit“-Route der Demo-Daten), feste Uhrzeit, synthetische Verbindungen
durch denselben KlimaCore-Code wie echte Antworten, kein Netz. Szenen (`-KBScreenshot <name> -KBDemo YES`): `commuteSetup`
(Einladung), `commuteMorning` (07:04, geändertes Gleis), `commuteDelayed` (+12 mit schnellerer Verbindung), `commuteCancelled`,
`commuteNoConsent`, `commuteEvening` (kompakt, 17:12), `commuteAX5`, `commuteAX5Rows` und `commuteAX5Bottom` (Verspätung bei größter
Schrift: Kopf, Zeilen, Knöpfe), `commuteSettings` und `commuteSettingsBottom`,
`stopDetailDepartures` (Innsbruck Hbf mit der Demo-Abfahrtstafel). In anderen Screenshot-Szenen erscheint die Karte nie; die
Haltestellen-Szenen zeigen jetzt den Abschnitt „Nächste Abfahrten“ mit Demo-Daten (so beschriftet).

## 12. Nächste Abfahrten im Haltestellen-Detail

`StopFeatureFlags.showsDepartures` ist an. Der Abschnitt „Nächste Abfahrten“ (`StopDeparturesSection`) sitzt unter der Kopfkarte
der Haltestelle und zeigt die nächsten **8 Abfahrten** einer Abfahrtstafel (HAFAS StationBoard, 90 Minuten, bis zu 30 Einträge):
dieselben Zeilen wie die Abfahrtstafel des Fahrplans (Zeit mit Echtzeit, Liniensymbol, Ziel, Hinweis, Gleis/Steig, geändertes Gleis
getönt, Ausfall durchgestrichen), darunter „Stand 07:31 · Echtzeit“ (Demo: „Demo-Daten“) und oben „Alle Abfahrten“ → die
Abfahrtstafel des Fahrplans für diese Station (alle Abfahrten, Ankünfte, andere Zeit).

- Geladen wird nur, wenn der Abschnitt auf dem Bildschirm ist und die App aktiv ist, dann höchstens einmal pro Minute, solange er
  sichtbar bleibt (im Stromsparmodus nur beim Öffnen). Eine Abfahrt bleibt bis eine Minute nach ihrer (Echtzeit-)Abfahrt, eine
  ausgefallene bis zu ihrer Planzeit.
- Gate wie §7: `LiveStopDepartureProvider` (`App/Sources/Services/Live/Departures/`) fragt `LiveDataService.timetable`; ohne
  Live-Daten wirft `StopBoardDepartures.load` `consentRequired`, bevor die Station gesucht wird (Linux-Test). Erst danach wird der
  Stations-Abgleich (`StationLinker`) und damit der Live-Client überhaupt angelegt. Eine Anfrage je Laden über die gemeinsame Drossel.
- Ohne Zustimmung bietet der Abschnitt einmal „Abfahrten live sehen?“ an; abgelehnt oder „Fahrplan live“ aus: Der Abschnitt fehlt
  ganz. Kill-Switch und offline: eine Zeile mit dem Grund. Findet die ÖBB-Suche die Haltestelle nicht, sagt der Abschnitt das einmal
  („keine Abfahrtstafel“) und fragt für dieses Detail nicht weiter; lehnt nur die Tafel einen gemerkten Ort ab, wird er vergessen und
  beim nächsten Laden neu gesucht.
- **Abweichung vom Plan:** Der Plan wollte `StopDepartureProviding` (KlimaCore-Vertrag mit `StopDepartures` und Offline-`LineRef`s)
  umsetzen. Gebaut ist stattdessen eine Abfahrtstafel als `BoardRow`s (`StopBoardSnapshot`), weil Live-Linien sich nicht verlässlich
  auf die Offline-Linien abbilden lassen und die Zeilen so genau wie die Abfahrtstafel des Fahrplans aussehen. Der alte Vertrag bleibt
  unverändert und unbenutzt.
- Nur auf dem iPhone prüfbar: echte Tafeln über iOS-`URLSession`, Meta-Stationen mit mehreren Haltepunkten, Steige an Busbahnhöfen.

## 13. Review (November 2026)

Ein zweiter Blick auf den fertigen Track hat gefunden und behoben:

- Die Einladung und die Vorschläge nannten „Fahrten“ mit „Hin und retour“ doppelt gezählt – die Statistik zählt dieselben Einträge
  einfach. Jetzt dieselbe Zahl wie in der Statistik (§2).
- Nach „Pendel-Modus“ aus oder „Stammstrecke entfernen“ fragte die Übersicht sofort wieder „Ist das dein Arbeitsweg?“ für genau diese
  Strecke. Jetzt nicht mehr (§1); eine Vermutung ohne App-Stationen wird gar nicht erst angeboten.
- Die kompakte Karte sagte „aktualisiert beim Öffnen“, obwohl außerhalb des Fensters nichts abgefragt wird; jetzt „Live ab 16:27“.
- Der Countdown zeigte nach der Abfahrt bis zu 30 Minuten „jetzt“; jetzt bleibt er leer.
- Der Fußtext „Vor 13 Uhr zeigt die Karte die Hinfahrt“ stimmte nicht (die Karte zeigt die nächste Fahrt); die 13-Uhr-Regel gilt
  für „Fahrt erfassen“ und Siri und steht jetzt dort.
- Der Offline-Modus hieß auf der Karte „Fahrplan live ist ausgeschaltet“, und Siri riet, die App zu öffnen; beides nennt ihn jetzt.
- Siri konnte bis zu 15 Minuten die Züge einer eben geänderten Strecke vorlesen; jede Änderung der Einstellungen verwirft die Antwort.
- Gleichzeitige Abarbeitung der Siri-Warteschlange hätte Fahrten doppelt speichern können; sie läuft jetzt nacheinander.
- Unbekannte Station oder Haltestelle: einmal sagen statt jede Minute neu suchen (§7, §12).
- Die Linienzeichen der drei Zeilen beginnen jetzt auf einer Kante, egal wie breit das Abzeichen ist („pünktlich“ oder „+4“).
- Symbol-Effekte von Störungsband und Einladung folgen „Bewegung reduzieren“.
- Einstellungen › Pendeln: Seit dem Scroll-Schritt der CI-Szene hingen zwei Task-Modifier an der Liste, und die Vorschläge des
  Erkenners blieben in der Szene leer („Noch kein Vorschlag“ trotz Vorschlag). Jetzt ein Task (Erkenner, danach der CI-Scroll), und
  „Noch kein Vorschlag“ erscheint erst, wenn der Erkenner gelaufen ist. Ob das auf dem iPhone genauso war, ist offen; die Szene
  `commuteSettings` prüft jetzt genau diesen Weg.
- Die Einladung verspricht Verspätung und Gleis nur, wenn Live-Daten an sind; sonst „deinen Plan – mit Live-Daten auch …“.
