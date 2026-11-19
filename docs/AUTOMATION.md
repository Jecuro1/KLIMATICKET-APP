# Automatik – „Wenn … dann …“

Stand: Track „Automatik“ (November 2026). Eigene Regeln auf dem iPhone, wie Kurzbefehle, aber in der App: „Wenn meine verfolgte
Fahrt 10 Minuten Verspätung hat, dann sag es mir“, „30 Tage vor Ablauf erinnern“, „werktags um 19 Uhr, wenn noch keine Fahrt
erfasst ist“. Ein **Testlauf** erklärt, warum eine Regel auslöst oder nicht, und **„Zuletzt ausgelöst“** zeigt, was passiert ist.

Code: Logik in `Packages/KlimaCore/Sources/KlimaCore/Automation/` (Linux-Tests unter `Tests/KlimaCoreTests/Automation/`,
`swift test --filter Automation`, 58 Tests), App in `App/Sources/Services/Automation/` (Speicher, Runner, Mitteilungen, Lese-Schnappschuss)
und `App/Sources/Features/Automation/` (Liste, Editor, Testlauf, Protokoll, Demo-Szenen).

## 1. Das Versprechen (Ehrlichkeit)

> Regeln laufen nur, wenn die App offen ist oder wenn iOS eine vorab geplante Mitteilung zustellt.

Genauer: Eine Regel kann nur auslösen

1. **nach dem Speichern** (Meilenstein, Fahrt erfasst) – also in der offenen App,
2. **bei einer Antwort von „Live verfolgen“** – im Vordergrund oder im Hintergrund-Abruf, den die Verfolgung ohnehin bei iOS bestellt
   (docs/OEBB_LIVE.md §R8). Die Regel liest diese Antwort, sie stellt **keine eigene Anfrage**,
3. **als lokale Mitteilung, die die App vorab geplant hat** (vor Ablauf, Tag ohne Fahrt), oder
4. wenn so eine geplante Mitteilung in der **offenen App** ankommt (dann als Hinweis statt Banner, nach einer zweiten Prüfung).

Es gibt keinen Server, keine Push-Mitteilungen, kein Hintergrund-Programm, keine Ortung. Regeln **schreiben nie Fahrten** und
**fragen nichts im Netz ab**: Die einzige Stelle, die den Datenspeicher berührt, ist `AutoSnapshot.swift`, und die liest nur
(`FetchDescriptor`, kein Insert, kein Save). Prüfung: `grep -rn "Repository\|URLSession" App/Sources/Features/Automation App/Sources/Services/Automation`
findet nichts.

## 2. Bausteine einer Regel (`AutoRule`)

`AutoRule {id, name, isEnabled, trigger, conditions, actions, cooldownMinutes, createdAt, templateID}`.

| Auslöser | Wann geprüft | Feuert | Bleibt still |
|---|---|---|---|
| **Vor Ablauf** (`ticketDeadline`, 1/7/14/30/60 Tage) | vorab geplant, 09:00 Wiener Zeit | am Tag *Ablauftag − N* (Kalendertage, Monatsenden und Sommerzeit korrekt) | kein Ticket, Termin vorbei, Ticket abgelaufen |
| **Meilenstein** (`milestone`, 25/50/75/100 %) | nach jedem Speichern | wenn der erfasste Wert den gewählten Anteil des Preises wirklich erreicht hat (dieselbe Schwelle wie das Gipfelbuch) und für dieses Ticket noch nicht gemeldet wurde | darunter; schon gemeldet; was beim Einschalten schon erreicht war; ein abgelaufenes Ticketjahr (z. B. im Ticket-Tab noch gewählt) |
| **Tag ohne Fahrt** (`dayWithoutTrip`, Wochentage + Uhrzeit) | vorab geplant, 14 Tage | zur Uhrzeit, wenn an dem Tag keine Fahrt erfasst ist | ein Tag mit Fahrt wird abgesagt (§4) |
| **Verspätung der verfolgten Fahrt** (`followDelay`, 3–30 Min) | bei jeder Antwort von „Live verfolgen“ | wenn die Verspätung **am Ausstieg** (Ankunft, sonst Abfahrt) mindestens den Wert erreicht | darunter; keine Verfolgung; keine Echtzeit für den Ausstieg; Fahrt zu Ende; schon gemeldet |
| **Fahrt erfasst** (`tripLogged`, Filter: Mindestwert, Verkehrsmittel, Strecke in beide Richtungen) | nach dem Speichern | für eine neu gespeicherte Fahrt (eine Reise mit Etappen zählt als eine Fahrt mit summiertem Wert), die zum Filter passt | Filter passt nicht; Import mit mehr als 3 Fahrten; Fahrten, die älter als 10 Minuten sind (z. B. per Sync) |

**Bedingungen** (je Auslöser nur die sinnvollen): nur an bestimmten Wochentagen, nur zwischen zwei Uhrzeiten (über Mitternacht
möglich), nur wenn heute noch keine Fahrt erfasst ist, nur mit gültigem Ticket. „Wochenende ruhig“ gilt für alle Regeln: Samstag und
Sonntag meldet sich keine; eine Erinnerung vor Ablauf, die aufs Wochenende fiele, kommt schon am Freitag (eine Frist wird nie verschluckt).

**Aktionen**: *sag es mir* (in der offenen App ein Hinweis mit Haptik, sonst eine lokale Mitteilung; eigener Titel möglich),
*öffne „Fahrt erfassen“* (der Tipp auf Mitteilung oder Hinweis öffnet das Formular; gespeichert wird erst dort), *Kurzbefehl
anbieten* (ein Knopf „Kurzbefehl starten“ öffnet `shortcuts://run-shortcut?name=…` – iOS zeigt dafür die Kurzbefehle-App, das ist
nie unbemerkt). **Nicht angeboten:** Orts-Auslöser (die 20 Regionen gehören der Fahrterkennung), Aktionen, die Fahrten anlegen oder
ändern, Skripte.

**Prozent und Euro wie in der Übersicht**: Jede Prozentzahl der Automatik (Zeile, Mitteilung, Testlauf) rundet wie der Gipfel der
Übersicht (`SummitFigures.percent`): 61,6 % ist „62 %“, nie „100 %“ vor dem Break-even, danach abgerundet. Ausgelöst wird aber erst,
wenn der Wert die Schwelle wirklich erreicht: bei 49,6 % zeigt die Übersicht 50 %, die Zeile sagt „nächster Meilenstein: 50 % ·
knapp davor“ und der Testlauf „knapp unter 50 % amortisiert“. Die Grundlage im Testlauf nennt ganze Euro wie die Übersicht
(„€ 860 von € 1.400“, nie der volle Preis vor dem Break-even).

**Vor Ablauf mit „Wochenende ruhig“**: Rückt die Erinnerung vom Samstag oder Sonntag auf den Freitag, nennt sie die Tage, die dann
wirklich bleiben („Noch 37 Tage gültig“ statt 36, „läuft morgen ab“ statt „heute“) – dieselbe Zählung wie die Resttage der Übersicht.

**Cooldown** (nur Verspätung und Fahrt erfasst): nach einer Meldung schweigt die Regel 15 Min bis 1 Tag. Verspätungen werden außerdem
nur einmal je Fahrt gemeldet; erst wenn die Verspätung unter den Wert fällt und wieder steigt, erneut.

## 3. Mitteilungen und Plätze

- Bezeichner: geplant `rule.<Regel-ID>.<yyyyMMdd>` (Wiener Kalendertag), sofort gesendet `rule.<Regel-ID>.<yyyyMMdd>.<HHmmss>`.
- iOS hält für eine App nach unserem Stand 64 ausstehende Mitteilungen. Die Automatik nimmt **höchstens 16**. Jede Regel bekommt
  zuerst ihren nächsten Termin, dann den zweiten usw. – eine ferne Frist wird nicht von täglichen Regeln verdrängt. Passen mehr
  Termine nicht hinein, sagt der Bildschirm es („Mehr Termine als Plätze: 18 Termine warten …“) statt sie still zu verlieren; sie
  rücken beim nächsten Öffnen nach.
- „Tag ohne Fahrt“ wird für 14 Tage geplant; „vor Ablauf“ ist ein einziger Termin, egal wie weit weg (Abweichung vom ursprünglichen
  Plan, der alles auf 14 Tage begrenzte: sonst käme die Erinnerung 30 Tage vorher nur, wenn die App in den zwei Wochen davor
  geöffnet wurde).
- Jede Mitteilung trägt den Untertitel „Automatik · <Regelname>“ und die Kategorie mit dem Knopf **„Regel ansehen“** (öffnet die
  Regel-Liste als Blatt). In **Einstellungen › Mitteilungen › Alle Alarme** steht jede Regel als eine Zeile der Art **„Automatik“**
  (Schalter = Regel an/aus, Löschen = Regel löschen); der Verlauf dort zeigt ihre Mitteilungen.
- Die Erlaubnis fragt iOS, sobald die erste Regel eingeschaltet wird, die über iOS kommt (Termin oder Verspätung; wie bei den
  Routen-Erinnerungen) – nie für Meilenstein und „Fahrt erfasst“ (die melden sich nach dem Speichern in der offenen App), nie für
  „Wochenende ruhig“, nie in Screenshot- oder Perf-Läufen.
- **Ohne Erlaubnis** melden sich Regeln mit Termin (vor Ablauf, Tag ohne Fahrt) **gar nicht** – auch nicht bei offener App, denn sie
  kommen nur als vorab geplante Mitteilung. Der Bildschirm sagt das („Mitteilungen in iOS aus – meldet sich nicht“ statt „nächste:
  19:00“), zeigt keine belegten Plätze und keine nächste Mitteilung, der Testlauf einer solchen Regel trägt den Hinweis, Alle Alarme
  zeigt keinen Termin, und es gibt „Einstellungen öffnen“. Die anderen Regeln melden sich dann nur, solange die App offen ist.

## 4. Abgleich (`AutoRuleScheduler.reconcile`)

Beim Start, bei jeder Rückkehr in den Vordergrund, nach jedem Speichern und nach jeder Änderung an den Regeln wird der Plan neu
berechnet und mit den ausstehenden `rule.`-Mitteilungen abgeglichen: Was fehlt, kommt dazu; was sich geändert hat (Zeit, Text), wird
ersetzt; was nicht mehr gilt (Regel aus oder gelöscht, Hauptschalter aus, **der Tag hat jetzt eine Fahrt**), wird entfernt.
Andere Mitteilungen der App fasst der Abgleich nie an. Eine wegen einer Fahrt abgesagte Mitteilung steht im Protokoll als „abgesagt“.
Kommt eine geplante Mitteilung in der offenen App an, prüft die Engine sie mit `.slotDue` noch einmal.

Alle Zeiten sind Wiener Zeit. Tage werden mit dem Kalender gezählt, nie mit 86 400 Sekunden: 19:00 bleibt 19:00 über die Umstellungen
am 29.3.2026 und 25.10.2026 (Tests). Eine Uhrzeit in der Lücke (02:30 am 29.3.) rückt um die Lücke nach vorn (03:30), eine doppelte
(02:30 am 25.10.) ist die erste; jeder Tag hat genau eine Mitteilung. Der Kalender-Trigger wird aus den Wiener Komponenten des
berechneten Zeitpunkts gebaut, damit der angezeigte Termin der ist, zu dem iOS zustellt.

## 5. Bildschirme

**Einstellungen › Automatik** (`AutoRulesView`): Kopf mit Hauptschalter, Zahl der aktiven Regeln, nächste Mitteilung und der Leiste
der 16 Plätze; Hinweise (Automatik aus, Mitteilungen aus, zu viele Termine, von iOS abgelehnt); **Deine Regeln** als Sätze mit Zustand
(„nächste: Mo 19:00“, „verfolgt RJ 66 · jetzt 12 Min“, „nächster Meilenstein: 75 % · jetzt 61 %“), Schalter, Wischen zum Löschen
und Duplizieren; **Vorlagen** (30 Tage vor Ablauf; bei 50, 75 und 100 % gratulieren; werktags 19:00 erinnern, wenn keine Fahrt
erfasst ist; ab 10 Min Verspätung der verfolgten Fahrt; nach jeder Fahrt ab € 20; Wochenende ruhig); **Zuletzt ausgelöst**.

**Editor** (`AutoRuleEditorView`): oben der Satz „**Wenn** [Auslöser] **und** [Bedingung], **dann** [Aktion]“ – jeder Teil ist ein
Menü. Darunter der **Testlauf**: Er zeigt wörtlich `AutoText.explanation` des Urteils der Engine (`AutoRuleEngine.evaluate(…, .probe)`),
also nie etwas anderes als die Entscheidung („Würde jetzt auslösen: Verspätung 12 Min ist mindestens 10 Min (RJ 66, Ausstieg
Innsbruck Hbf), Bedingungen erfüllt, kein Cooldown“, „Löst nicht aus: erst 3 Min Verspätung, ausgelöst wird ab 5 Min“, „Löst heute
nicht aus: heute ist schon eine Fahrt erfasst. Nächster Termin: morgen 19:00“), eine Vorschau der Mitteilung und die Grundlage
(„die letzte Antwort von „Live verfolgen“ (RJ 66, 17:41) – keine neue Abfrage“). Ist der Testlauf offen, rechnet er bei jeder
Änderung neu – mit den Fakten, die er gelesen hat (kein Lesen des Speichers je Tastendruck; „Nochmal prüfen“ liest neu). Eine Regel,
die das Sichern einschalten würde (neu, aus, oder Auslöser geändert), beurteilt er so, wie sie eingeschaltet wäre: schon erreichte
Meilensteine sind dann gemerkt, also sagt er nie „Würde jetzt auslösen“ für einen Meilenstein, den die gesicherte Regel nicht feiert
(`AutoLedger.switchesOn`, dieselbe Frage wie beim Sichern). Der Text ist auswählbar; VoiceOver liest ihn als einen Satz. Gespeichert
wird erst mit „Sichern“.

**Zuletzt ausgelöst** (`AutoLogView`): die letzten 30 Ereignisse nach Tagen – „in der App gezeigt“, „als Mitteilung gesendet“,
„geplant, von iOS zugestellt“ (beim nächsten Öffnen aus der Mitteilungszentrale übernommen), „abgesagt“ – mit Regel, Uhrzeit und Grund.

Barrierefreiheit: jede Regelzeile liest sich als ganzer Satz mit Zustand („Abendcheck, eingeschaltet. Wenn Mo–Fr um 19:00 …“), alle
Auswahlen sind beschriftet, Auswahl-Chips brechen bei großer Schrift um, Wochentage werden ausgeschrieben vorgelesen.

## 6. Speicher

UserDefaults, versioniertes JSON, nichts wird synchronisiert oder gesendet; die Schlüssel beginnen mit `rules.`:

| Schlüssel | Inhalt |
|---|---|
| `rules.v1` | Version, Hauptschalter, „Wochenende ruhig“, bis zu 40 Regeln |
| `rules.log.v1` | „Zuletzt ausgelöst“, 30 Einträge |
| `rules.ledger.v1` | Meilensteine je Regel und Ticket, die gemeldete Verfolgung, letzte Meldung je Regel (Cooldown), der Zeitpunkt der zuletzt geprüften Fahrten |

Lesen ist tolerant: Unlesbares ergibt „keine Regeln“; eine Regel mit unbekanntem Auslöser (z. B. aus einer neueren Version) wird
einzeln verworfen; eine Regel, die eine unbekannte Bedingung verloren hat, kommt **ausgeschaltet** zurück (sie würde sonst öfter
auslösen als gewählt). „Alle Daten löschen“ entfernt Regeln, Protokoll, Merker und alle geplanten Regel-Mitteilungen.
Keine SwiftData-Änderung.

## 7. Was nur ein echtes iPhone zeigt

- **Zustellzeit** lokaler Mitteilungen (iOS bündelt, Fokus-Modi, „Geplante Zusammenfassung“), die Erlaubnis-Abfrage.
- Ob eine Regel über Tage hinweg verlässlich plant und absagt: „Abendcheck“ für morgen einschalten, ohne Fahrt bleiben, die Mitteilung
  um 19:00 abwarten; am nächsten Tag vorher eine Fahrt erfassen und prüfen, dass nichts kommt (Protokoll: „abgesagt“).
- Verspätung im **Hintergrund-Abruf** der Verfolgung (iOS entscheidet, wann er läuft).
- Der Sprung in die Kurzbefehle-App (`shortcuts://run-shortcut`) und ob der Kurzbefehl mit genau diesem Namen gefunden wird.
- Der Hinweis in der offenen App, wenn eine geplante Mitteilung im Vordergrund ankommt.

## 8. Bewusst nicht gebaut, und was vom Stretch blieb

- **„Übliche Zeit“** (Auslöser aus den Wochentag-Mittelwerten der eigenen Fahrten) – Stretch, gestrichen.
- Gebaut aus dem Stretch: die Aktion **Kurzbefehl anbieten** und die Vorlage **„Wochenende ruhig“** (ein Schalter für alle Regeln).
- Orts-Auslöser, Aktionen, die Fahrten schreiben, Skripte, Push, Server.

## 9. Einbau in die App (eine markierte Zeile je Stelle, `// MARK: automation`)

| Stelle | Was |
|---|---|
| `Data/CommitEffects.swift` | nach jedem Speichern `AutoRunner.didCommit` (entprellt, 0,6 s) |
| `Features/Planner/LiveFollow/LiveFollowTracker.swift` | nach jeder Antwort `await AutoRunner.followUpdated` (auch im Hintergrund-Abruf; gewartet, damit die Mitteilung vor dem Einschlafen raus ist) – als letzter Schritt der Antwort, damit eine Verfolgung, die während des Wartens auf iOS beendet wird, nicht danach ihre Live Activity, ihren Datensatz oder ihren Hintergrund-Abruf zurückbekommt |
| `Core/RootView.swift` | Szene aktiv → `sceneBecameActive` (Protokoll übernehmen, neu planen); Blatt „Regel ansehen“; Screenshot-Szenen |
| `KlimaBilanzApp.swift` | `willPresent`: Hinweis statt Banner; `didReceive`: Fahrt erfassen, Regel ansehen, Kurzbefehl |
| `Services/NotificationCategories.swift` | die Kategorien `rule` und `rule.shortcut` |
| `Features/Alarms/*` | eine Zeile je Regel, Art „Automatik“ (Symbol, Farbe, Schalter, Löschen) |
| `Data/Repository.swift` | „Alle Daten löschen“ löscht auch Regeln, Protokoll, Merker und geplante Mitteilungen |
| `Features/Settings/SettingsView.swift` | die Zeile „Automatik“ unter „Mitteilungen“ |
| `Packages/KlimaCore/…/Alarms/AlarmKinds.swift` | Art `automation`, Präfix `rule.` |

Der Runner ist ein eigenes Singleton (`AutoRunner.shared`) statt einer Eigenschaft von `AppState` – so bleibt `AppState.swift` unberührt.

## 10. Demo und Screenshots

`-KBScreenshot <name> -KBDemo YES`, Uhr fest auf Donnerstag, 12.11.2026, 17:42; erfundene Regeln, Fakten und Protokoll; keine
System-Mitteilung, keine Abfrage, kein Netz (`AutoDemo.swift`):
`automationList`, `automationListBottom` (Vorlagen, Protokoll), `automationEditor`, `automationEditorBottom` (Filter, Bedingungen,
„Dann“), `automationTest` (Testlauf der Verspätungsregel), `automationLog`, `automationBudget` (mehr Termine als Plätze),
`automationAX5` und `automationAX5Rows` (größte Schrift), `automationSettingsRow` (die Zeile in Einstellungen),
`automationDenied` (Mitteilungen in iOS aus), `automationMilestone` (Testlauf von „Meilensteine feiern“: 61 %, € 860 von € 1.400).

## 11. Review (adversarial, November 2026)

Gefunden und behoben: (1) ohne Mitteilungs-Erlaubnis versprachen Liste, Kopf, Plätze, Einstellungen-Zeile und Alle Alarme
„nächste: 19:00“, und der Hinweis sagte, Regeln meldeten sich dann in der offenen App – Regeln mit Termin melden sich aber gar nicht;
(2) Prozente abgerundet („jetzt 61 %“, Übersicht „62 %“); (3) der Testlauf einer neuen oder ausgeschalteten Meilenstein-Regel sagte
„Würde jetzt auslösen“ für Meilensteine, die das Einschalten als erreicht merkt; (4) ein im Ticket-Tab gewähltes altes Ticketjahr
hätte beim nächsten Speichern „Dein Ticket hat sich rentiert“ gemeldet; (5) eine auf Freitag gerückte Ablauf-Erinnerung sagte „läuft
morgen ab“ oder „Noch 30 Tage“, obwohl ein bzw. zwei Tage mehr blieben; (6) Meilenstein, „Fahrt erfasst“ und „Wochenende ruhig“
fragten nach der Mitteilungs-Erlaubnis, obwohl sie keine brauchen; (7) der Testlauf las bei jedem Tastendruck Tickets und Fahrten neu;
(8) der gewartete Aufruf in `LiveFollowTracker` stand vor Live Activity und Datensatz; (9) „Duplizieren“ bei 40 Regeln tat still
nichts; (10) der Hinweis-Text verschwieg den Hintergrund-Abruf von „Live verfolgen“. Tests: `AutomationReviewTests`.
