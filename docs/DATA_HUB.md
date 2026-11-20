# Daten & Sicherung – Export, Import und automatische Sicherungen

Stand: Track „Daten“ (November 2026). **Einstellungen › Daten › Daten & Sicherung** beantwortet: *Was liegt auf diesem iPhone, wie
bekomme ich es heraus, und was passiert, wenn etwas schiefgeht?* Für eine App, die per AltStore/SideStore installiert wird (kein
iCloud-Sync über einen bezahlten Account, kein CloudKit), ist das die einzige Datensicherung, die nicht von einem Konto abhängt.

Code: Logik in `Packages/KlimaCore/Sources/KlimaCore/DataHub/` (Linux-Tests unter `Tests/KlimaCoreTests/DataHub/`,
`swift test --filter DataHub`, 38 Tests), App in `App/Sources/Data/Backup+V3.swift`, `App/Sources/Services/Backup/` (Ordner,
automatische Sicherung, Export, Wiederherstellen) und `App/Sources/Features/DataHub/` (Seiten, Demo-Szenen).

## 1. Das Versprechen

- **Nichts verlässt dein iPhone, außer du teilst eine Datei.** Es gibt keinen Server-Upload, keine Analyse. Alle Exporte entstehen erst,
  wenn du im Teilen-Menü ein Ziel wählst.
- **Sicherungen enthalten deine Daten, aber nie Geheimnisse:** Anmeldung, Schlüssel, die Live-Daten-Zustimmung, Name und Adresse der
  Briefe und Gerätezustände kommen nicht hinein (§3.2). Ein Wiederherstellen kann deshalb Zustimmung und Anmeldung nicht ändern.
- **Vor jedem zerstörerischen Schritt eine Sicherung:** vor „Alle Daten löschen“, vor dem Ersetzen durch die Daten eines Kontos und vor
  jedem Wiederherstellen (§4.3). Gelingt sie nicht, passiert nichts (beim Konto: die Frage kommt wieder).
- **Vorher sehen, was sich ändert:** Wiederherstellen zeigt zuerst „Das ändert sich: 12 neue Fahrten, 3 geänderte, 140 unverändert“ (§5).
- **Ehrlich, wo die Dateien liegen:** „Diese Sicherungen liegen auf diesem iPhone. Löschst du die App, sind sie weg. Kopiere sie in
  Dateien oder iCloud Drive.“ – auf der Seite und in der Liste, bei jeder Textgröße ganz lesbar.

## 2. Exportieren

Ein Zeitraum für alle Formate: **Ticketjahr** (das gewählte bzw. laufende Ticket, wie in der Übersicht) · **Kalenderjahr** (1. Jänner bis
31. Dezember, Wiener Zeit) · **Alles**. Jede Zeile zeigt, was drin ist und wie groß die Datei wird („154 Einträge · 18 KB“) – einmal
pro Zeitraum im Hintergrund gezählt. Eine leere Zeile („0 Einträge“) lässt sich nicht teilen.

| Format | Datei | Inhalt |
|---|---|---|
| Komplettsicherung | `KlimaBilanz-2026-11-19-Backup.json` | Version 3 (§3), **immer alles** (ein Wiederherstellen braucht jede Zeile) |
| Fahrten als Tabelle | `…-Fahrten-Ticketjahr-2026-27.csv` | der bestehende CSV-Export v2 (wieder importierbar), nur im Zeitraum |
| Monatsübersicht | `…-Monate-Ticketjahr-2026-27.csv` | Monat, Fahrten, Wert (€), Distanz (km), CO₂ gespart (kg), Zeile „Gesamt“ |
| Fahrten im Kalender | `…-Fahrten-Ticketjahr-2026-27.ics` | ein Termin pro Fahrt |
| Ticket-Fristen im Kalender | `…-Fristen.ics` | Ticketende und eingetragene Widerspruchsfrist, **ab heute** |
| Jahresbilanz als Text | als Text (Mail, Notizen) bzw. `KlimaBilanz-Jahresbilanz.md` | Markdown |

Der PDF-Jahresbericht bleibt, wo er war (Berichte), und ist von der Seite verlinkt.

**CSV (Excel in Österreich):** Strichpunkt, Dezimalkomma ohne Tausenderpunkt (`1060,45`, Excel liest es als Zahl), CRLF, UTF-8 mit BOM.
Die Monatsübersicht hat für jeden Monat des Zeitraums eine Zeile, auch für leere (Lücken sichtbar im Diagramm), Monatsnamen
österreichisch („Jänner 2027“) – aber nur bis zum Monat von heute (oder einer späteren eingetragenen Fahrt): ein laufendes Ticketjahr
listet keine kommenden Monate mit „0 Fahrten“. „Fahrten“ zählt wie die App: eine Reise aus mehreren Teilstrecken ist eine Fahrt. CO₂ wie überall:
Umweltbundesamt-Faktoren aus dem Tarif-Katalog, Auto allein gegenüber Öffi.

**Kalender (RFC 5545, auf dem Code von PlannerExport):** CRLF, Zeilen bei 75 Oktetten gefaltet (nie mitten in einem Umlaut), Komma,
Strichpunkt, Backslash und Zeilenumbruch maskiert. Titel „Zug: Innsbruck Hbf → St. Anton am Arlberg“, bei Hin & Retour
„(hin und retour)“. Eine Fahrt mit bekannter Dauer (Zeitbilanz) wird ein Termin von–bis; ohne Dauer ein **ganztägiger** Eintrag
(`TRANSP:TRANSPARENT`, blockiert nichts) – die Uhrzeit allein sagt nicht, wie lange die Fahrt dauerte. Fristen sind ganztägig mit einer
Erinnerung um 09:00 am Vortag. Stabile `UID`s: ein zweiter Import aktualisiert statt zu verdoppeln (je nach Kalender-App).

**Jahresbilanz (Markdown):** Überschrift mit Zeitraum, beim Ticketjahr Wert gegenüber Ticketpreis („noch € 400,00, bis es sich
rentiert“ bzw. „rentiert, € 100,00 im Plus“), Fahrten an Tagen, km, CO₂, eine Monatstabelle, die drei häufigsten Strecken (ab zwei
Fahrten, gereiht wie in Statistik: eine Reise ist eine Strecke vom ersten bis zum letzten Halt), Fußzeile mit Quelle. Keine Prognose – eine Bilanz zählt nur, was war.

## 3. Komplettsicherung, Version 3

### 3.1 Format

Version 2 (Tickets, Fahrten mit Zeit-Schlüsseln, Favoriten, Vorteile – die Sync-Zeilen ohne `user_id`) **plus** zwei neue Schlüssel:
`settings` (die erlaubten Einstellungen) und `checksum` (`"crc32:xxxxxxxx"`). Beide sind optional: eine App mit Version 2 ignoriert
sie und stellt eine Version-3-Datei wieder her; diese App liest Dateien der Version 1 und 2 wie bisher. Getestet in KlimaCore
(`DataHubEnvelopeTests`: ein Version-2-Leser öffnet eine Version-3-Datei, eine Version-2-Datei wird gelesen).

### 3.2 Einstellungen (`BackupSettingsPolicy`)

Erlaubt (Allow-List): `appearance`, `defaultDiscount`, `defaultTravelClass`, `homeStationID`, `hapticsEnabled`, `autoUpdateCheck`,
`renewalRemindersEnabled`, `weeklySummaryEnabled`, `localAIEnabled`, `map.layers`, `atlas.mapLook`, `planner.options`, `planner.sort`,
`commute.settings.v1`, `calendarSuggestions.prefs.v1`, `kb.whatif.scenarios.v1`, `rules.v1` und alles unter `theme.` (App Group),
`dash.`, `goals.`, `features.`, `radar.`, `radar2.`.

Verboten (Deny-List, gewinnt immer, auch unter einem erlaubten Präfix): jeder Schlüssel mit `token`, `secret`, `password`,
`credential`, `session`, `consent`, `auth`, `cookie`, `apikey`, `userid`, `keychain`, `bookmark`, `deviceid`, `udid` …; alles, was mit
`live`, `cloud.`, `sync.`, `auth.`, `backup.`, `letters.`, `store.`, `demo.`, `KB`, `NS`, `Apple` beginnt, und `rules.log`/`rules.ledger`
(Laufzustand). Das Buch der Ziele (`goals.ledger.v1`) kommt absichtlich mit: ein Ziel, das beim Sichern schon erfüllt war, poppt nach
dem Wiederherstellen nicht noch einmal (docs/DASHBOARD_LAYOUT.md §4). Zusätzlich wird ein Wert abgelehnt, der wie ein Token aussieht (JWT, „Bearer …“) oder größer als 256 KB ist. Die Keychain
wird für eine Sicherung nie gelesen. Getestet: ein eingeschmuggelter Token-Schlüssel und die Zustimmung werden abgelehnt.

Beim Wiederherstellen werden Einstellungen **nur auf Wunsch** übernommen (Schalter „Auch Einstellungen übernehmen“, aus) und erst
**beim nächsten Start** geschrieben (`backup.pendingSettings`, angewendet in `AppLaunch` bevor `AppState` entsteht): die Speicher der
Funktionen lesen ihre Schlüssel einmal und würden frisch geschriebene Werte sonst überschreiben. Auch dabei gilt die Allow-List noch einmal.

### 3.3 Prüfsumme

CRC-32 (wie zip/PNG) über die ganze Datei, mit der Prüfsumme selbst auf `00000000` gesetzt. Sie **erkennt beschädigte Dateien**
(abgeschnittene Kopie, gekipptes Byte, umkodierter Text) – **eine absichtliche Änderung beweist sie nicht**, jeder kann sie neu berechnen.
So steht es auch in der App. Eine Datei mit falscher Prüfsumme wird abgelehnt, **bevor eine einzige Zeile gelesen oder geschrieben wird**;
Dateien ohne Prüfsumme (Version 1/2) gehen wie bisher.

## 4. Automatische Sicherungen

### 4.1 Wann

Schalter **„Tägliche Sicherung“** (an). Geht die App in den Hintergrund, schreibt `AutoBackupService` höchstens einmal pro Wiener Tag
eine Sicherung – und nur, wenn sich seit der letzten etwas geändert hat. „Geändert“ ist ein Stempel aus Anzahl und jüngstem `updatedAt`
je Tabelle plus der CRC-32 der erlaubten Einstellungen (`backup.lastCommitStamp`). Ein leerer Speicher (kein Ticket, keine Fahrt) wird
nicht gesichert. Der Schreibvorgang läuft in einer Hintergrund-Aufgabe, die iOS ein paar Sekunden gewährt, und ist atomar: entweder
die ganze Datei oder keine. **„Jetzt sichern“** schreibt sofort, unabhängig von Tag und Stempel.

### 4.2 Wo

`Documents/Sicherungen/KlimaBilanz-2026-11-19-1803.json` (Datum und Minute, Wiener Zeit; eine zweite Datei in derselben Minute bekommt
`~2`). Dank `UIFileSharingEnabled` und `LSSupportsOpeningDocumentsInPlace` (Info.plist, keine Berechtigung) erscheint der Ordner in der
Dateien-App unter **Auf meinem iPhone › KlimaBilanz › Sicherungen**. In `Documents` liegt sonst nichts (LaunchTrace schreibt dort nur in
CI-Läufen). Dateischutz: lesbar nach dem ersten Entsperren.

Die Dateien liegen auf dem iPhone: Löschen der App löscht sie. Ein iCloud-Geräte-Backup enthält `Documents`, aber das ist keine Kopie,
an die man einzeln herankommt – daher der Banner und der Rat, sie in Dateien oder iCloud Drive zu kopieren.

### 4.3 Wie lange (`BackupRetention.plan`, rein)

7 tägliche, 4 wöchentliche, 3 monatliche: für die letzten 7 Tage mit einer Sicherung je die neueste, für die letzten 4 ISO-Wochen je die
neueste, für die letzten 3 Monate je die neueste; was eine Regel behält, bleibt (wie restic und Time Machine). Sicherungen **„vor dem
Löschen“** (`…-vor-dem-Loeschen.json`, vor „Alle Daten löschen“ und vor dem Ersetzen durch ein Konto) und **„vor dem
Wiederherstellen“** bleiben 30 Tage. **Die neueste Sicherung bleibt immer**, eine Datei mit Datum in der Zukunft (falsche Uhr) wird nie
gelöscht, und Dateien, die nicht von der App benannt sind (selbst hineinkopiert), fasst die Regel nie an. Getestet über Jahreswechsel
(ISO-Woche 53), Monatsenden und die Zeitumstellung, plus ein Zufallstest „die neueste bleibt“.

### 4.4 Datenbank-Kopien

Die Kopien, die `StoreLoader` selbst anlegt (vor einem App-Update, wenn das Öffnen scheitert, bei „Neu beginnen“), stehen in der Liste
**nur zum Teilen** (etwa für den Support). Wiederherstellen lassen sie sich hier nicht – sie sind SQLite-Dateien, keine Sicherung.

## 5. Wiederherstellen mit Vorschau

1. Datei wählen (Dateien, iCloud Drive …) oder in der Liste „Wiederherstellen“ tippen. Die Datei wird im Hintergrund gelesen und
   geprüft (`BackupInspection`): kein JSON / keine Tabellen → „kein KlimaBilanz-Backup“, anderes Format → abgelehnt, Prüfsumme falsch →
   abgelehnt. Nichts wurde geändert.
2. **Vorschau** (`BackupDiff.make`, rein): pro Tabelle neu, geändert, entfernt, unverändert, auf diesem iPhone neuer – genau die Regel
   des Zusammenführens: unbekannte Zeilen kommen dazu, eine Zeile der Datei gewinnt nur, wenn sie neuer ist (`updated_at`), gleiche
   bleiben, eine in der Datei später gelöschte verschwindet, eine hier gelöschte, in der Datei neuere kommt zurück. Eine doppelte Zeile
   zählt einmal. **Fahrten zählen wie in der App:** die Teilstrecken einer Reise sind eine Fahrt – alle neu: neu, alle entfernt:
   entfernt, sonst jede sichtbare Änderung (auch eine Teilstrecke mehr oder weniger): geändert. **Was du hier nach der Sicherung gelöscht hast, bleibt gelöscht** (die Löschung ist neuer als die Kopie in der Datei) –
   die Vorschau sagt es: „1 Eintrag, den du hier nach dieser Sicherung gelöscht hast, bleibt gelöscht.“ Dazu Format, App-Version, Datum, Prüfsumme und – falls die Datei Einstellungen hat, die anders sind – der Schalter
   „Auch Einstellungen übernehmen“.
3. **„Wiederherstellen“**: zuerst die Sicherung „vor dem Wiederherstellen“ (gelingt sie nicht: nichts passiert), dann das
   Zusammenführen wie bisher (nur ergänzen, nichts doppelt), Erinnerungen der Tickets neu planen. Die Meldung sagt, was die Vorschau
   versprochen hat („12 neue Fahrten, 3 geänderte · 1 Ticket“), nicht mehr jede geänderte Zeile samt Löschungen („95 Fahrten, 1 Tickets
   … importiert“). „Aus Sicherung wiederherstellen“ meldet, was danach auf dem iPhone ist.

**Mit KlimaBilanz-Konto (nicht geprüft):** nach „Alle Daten löschen“ liegen in der Cloud Löschungen, die neuer sind als jede ältere
Sicherung. Wer danach wiederherstellt, dem kann die nächste Synchronisierung die wiederhergestellten Zeilen nach derselben Regel
(neuer gewinnt) wieder entfernen. Ohne Konto betrifft das niemanden.

**Wenn sich der Datenspeicher nicht öffnen lässt** (StoreRecoveryView) steht über „Neu beginnen“ zusätzlich **„Aus Sicherung
wiederherstellen“** – nur, wenn eine lesbare Sicherung mit Daten in `Documents/Sicherungen` liegt. Es beginnt wie „Neu beginnen“ mit
einem leeren Speicher (der alte bleibt als Kopie) und spielt die neueste lesbare Sicherung ein.

## 6. Die Seiten

- **Einstellungen › Daten:** eine Zeile „Daten & Sicherung“ („Letzte Sicherung heute, 18:03 · Exportieren, Wiederherstellen“) statt der
  früheren Zeilen CSV, Backup, Wiederherstellen, CSV-Import und Jahresbericht, darunter wie bisher „Demo-Daten entfernen“ und „Alle
  Daten löschen“ (jetzt mit Sicherung davor). Die Fußzeile zählt Fahrten wie die Übersicht (eine Reise = eine Fahrt).
- **Daten & Sicherung:** Kopf „Deine Daten“ mit der Zahl der Fahrten (zählt hoch), Tickets und Favoriten, darunter die letzten 7 Tage –
  ein gefüllter Balken ist ein Tag mit Sicherung – und „Letzte Sicherung heute, 18:03“. Abschnitte Exportieren (mit PDF-Jahresbericht),
  Sicherungen (Schalter, Jetzt sichern, Liste, Banner, Regel), Wiederherstellen (aus Datei, CSV-Import).
- **Exportieren:** Zeitraum-Wahl, sechs Formate mit Vorschau-Zeile, PDF.
- **Sicherungen:** Banner, je Sicherung Datum, Art (Abzeichen „Vor dem Löschen“), Größe und Inhalt, **Prüfen** (liest die Datei neu und
  rechnet die Prüfsumme nach), **Teilen**, **Wiederherstellen**; darunter die Datenbank-Kopien.
- **Vorschau:** Überschrift „Das ändert sich: …“, je Tabelle ein Balken (neu, geändert, entfernt, bleibt) und die Zeile in Worten,
  Datei-Karte, Knopf „Wiederherstellen“ (bei nichts zu tun: „Nichts zu übernehmen“, gesperrt).

Barrierefreiheit: jede Sicherungs-Zeile ist **ein** Element (Datum, Art, Größe, Inhalt, nach Prüfen das Ergebnis) mit den Aktionen
Prüfen, Teilen, Wiederherstellen; die Vorschau ist Text (die Balken sind Dekoration, die Zeile darunter sagt dasselbe). Ab AX-Größen
stehen die drei Knöpfe untereinander, der Banner bricht um statt abzuschneiden.

Bewegung nur über Motion-Tokens: der Zähler im Kopf, die Balken der Vorschau wachsen einmal, Zeilen erscheinen mit `.rise`.

## 7. Speicher und Schlüssel

Kein SwiftData-Feld kommt dazu. Fahrten zählt die Seite wie die Übersicht: die Teilstrecken einer Reise sind eine Fahrt (in Tabelle und
Kalender heißen die Zeilen deshalb „Einträge“). UserDefaults: `backup.auto` (Schalter), `backup.lastCommitStamp` (Stempel der letzten Sicherung),
`backup.lastBackupDay` (Wiener Tag), `backup.pendingSettings` (Einstellungen für den nächsten Start). Alle `backup.`-Schlüssel stehen
auf der Deny-List: eine Sicherung trägt nie ihren eigenen Zustand weiter.

## 8. Demo und Szenen

`DataHubDemo` schreibt drei echte Version-3-Dateien aus den Demo-Daten in den temporären Ordner (vor 47 Minuten, vor zwei Tagen, „vor dem
Löschen“ vor neun Tagen – die älteren ohne die später erfassten Fahrten) und gibt sie dem Dienst; `Documents` wird nie berührt.
Szenen (`-KBScreenshot`): `dataHub`, `dataHubBottom`, `exportHub`, `autoBackups`, `backupBanner` (Liste bei AX5),
`backupRowsAX5` (die Sicherungs-Zeilen selbst bei AX5), `dataAX5` (Seite bei AX5), `backupPreview` (eine Datei „von einem anderen iPhone“ mit 12 neuen und 3 geänderten Fahrten und Einstellungen),
`dataSettingsRow`, `storeRecoveryBackup` und `dataRoundTrip`.

Gesehen in vier Screenshot-Läufen (hell und dunkel): der erste zeigte einen echten Fehler – eine Datei speichert ganze Sekunden
(ISO 8601), das iPhone Sekundenbruchteile, und die Vorschau nannte unveränderte Zeilen „hier neuer“; seither gilt dieselbe Sekunde als
dieselbe Fassung (Test in KlimaCore). Außerdem: Zahl und Wort bleiben beisammen, die drei Knöpfe einer Sicherung trennen nie
(Symbole, dann nur Wörter, dann untereinander), bei AX-Größen ein kleiner Titel, der Banner mit Symbol über dem Text. Der dritte
Lauf zeigte bei AX5 eine Zeile, deren Datum links abgeschnitten war (ein festes „Wiederherstellen“ war breiter als die Zeile):
untereinander dürfen die Knöpfe umbrechen und wachsen nur bis AX2; „Letzte Sicherung …“ und „Datei unversehrt“ stehen bei AX-Größen
ohne Symbol. Der vierte zeigt die Zeile in den Einstellungen.

**`dataRoundTrip` ist der CI-Test der Annahme:** die Demo-Daten werden mit dem eigenen Export gesichert, in einen leeren
In-Memory-Speicher wiederhergestellt und je Tabelle verglichen (sichtbare Zeilen und alle Zeilen samt gelöschten); das Ergebnis steht
im Bild und als Marke `data.roundtrip.identical` im Launch-Trace des CI-Laufs. (Die App hat kein Unit-Test-Ziel auf macOS; eine Szene
statt eines neuen Test-Targets hält das Projekt schlank.)

## 9. Getestet und nicht getestet

Getestet (Linux, KlimaCore): CRC-32 mit Prüfvektoren, Versiegeln/Prüfen, ein geändertes Byte, das Wort „checksum“ in einer Notiz,
Dateinamen, Aufbewahrung (Jahreswechsel, ISO-Woche 53, Zeitumstellung, Sicherheits-Sicherungen, Zukunftsdaten, Zufallstest), alle
Zählregeln der Vorschau und der Satz aus dem Plan, die Einstellungs-Regeln, ICS (CRLF, Faltung, Maskierung, Umlaute, ganztägig gegen
Uhrzeit, Fristen mit Erinnerung), Monats-CSV (Zahlenformat, leere Monate, Reisen, Gesamt), Jahresbilanz, Zeiträume, Version 2 ↔ 3,
beschädigte und fremde Dateien. App: Linux-Typprüfung; CI-Build, Screenshots, Rundreise-Szene.

**Nur auf einem echten iPhone prüfbar:** dass der Ordner in der Dateien-App erscheint; dass die Sicherung im Hintergrund fertig wird, wenn
iOS die App anhält; dass Kalender, Numbers/Excel, Mail und Notizen die Dateien öffnen wie gedacht; Wiederherstellen aus einer Sicherung
einer älteren App-Version; „Aus Sicherung wiederherstellen“ bei einem wirklich kaputten Speicher; dass übernommene Einstellungen nach
dem Neustart greifen; die VoiceOver-Aktionen der Zeilen.

## 10. Abweichungen vom Plan

- **Dateiname mit Uhrzeit** (`KlimaBilanz-2026-11-19-1803.json` statt nur Datum): sonst lässt sich „Jetzt sichern“ am selben Tag nicht
  von der täglichen unterscheiden und die Aufbewahrung nicht ordnen.
- **„Commit-Zähler“ als Stempel:** statt eines Zählers in `Repository.commit` (geteilte Datei) ein Stempel aus Anzahl und jüngster
  Änderung je Tabelle plus Einstellungen. Er erkennt auch Änderungen, die nicht über `commit` laufen (Sync, Import).
- **Einstellungen beim Wiederherstellen nur auf Wunsch und erst beim nächsten Start** (der Plan sagt nichts dazu; die Speicher der
  Funktionen würden sofort geschriebene Werte überschreiben).
- **Fristen-Kalender immer ab heute**, unabhängig vom Zeitraum (vergangene Fristen nützen im Kalender nichts).
- **Rundreise-Test als CI-Szene** statt eines macOS-Unit-Tests (kein Unit-Test-Ziel im Projekt).
- **Gestrichen (STRETCH):** „Sicherung in Ordner kopieren“ (Lesezeichen auf einen Ordner, etwa in iCloud Drive), flaches JSON der
  Fahrten mit Schema, Vorschau für den CSV-Import.

## 11. Review (adversarial, nach dem Bau)

Gefunden und behoben (`// MARK: review-daten`, Tests in KlimaCore):

- **Zahlen:** Die Vorschau zählte Teilstrecken als Fahrten („12 neue Fahrten“ für 12 Zeilen), während Kopf, Liste, Einstellungen und
  Statistik Reisen einmal zählen – jetzt zählt `BackupDiff` je Reise (`BackupRowStamp.group` = `journey_id`). Ohne neue Fahrt fehlte
  das Hauptwort („Das ändert sich: 3 geänderte, …“) – jetzt „3 geänderte Fahrten“. Die Meldung nach dem Wiederherstellen zählte jede
  Zeile samt Löschungen und sagte „1 Tickets“. Die häufigsten Strecken der Jahresbilanz zählten Teilstrecken, Statistik Reisen.
  Die Monatsübersicht listete kommende Monate eines laufenden Ticketjahrs mit „0 Fahrten“. „1000 KB“ heißt jetzt „1,0 MB“.
- **Sicherung vor dem Zerstörerischen:** „Durch Daten des Kontos ersetzen“ ersetzte auch, wenn die Sicherung davor scheiterte – jetzt
  nicht, mit Hinweis, und die Frage kommt wieder.
- **Ehrlichkeit:** „Prüfen“ zeigte bei einer Datei ohne Prüfsumme (oder einer, die gar keine Sicherung ist) ein grünes Siegel mit
  Erfolgs-Haptik – jetzt ein leeres Siegel „Ohne Prüfsumme“ bzw. die Ablehnung.
- **Liste:** Eine Sicherung, die bei offener Liste entsteht (die Sicherung vor dem Wiederherstellen), bekam nie ihren Inhalt angezeigt.

Offen (bewusst): Wiederherstellen bringt eine hier gelöschte Fahrt nicht zurück (die Löschung ist neuer; der Plan sagt „nur
ergänzen“) – zurück kommt sie nur in einen leeren Speicher. Ein Schalter „Gelöschte zurückholen“ wäre eine neue Funktion.

## 12. Geräte-Checkliste (Besitzer)

1. Einstellungen › Daten › Daten & Sicherung › „Jetzt sichern“. Dateien-App öffnen › Auf meinem iPhone › KlimaBilanz › Sicherungen:
   die Datei ist da.
2. Die Datei in iCloud Drive kopieren. In der App eine Fahrt löschen.
3. „Aus Datei wiederherstellen …“ › die Kopie in iCloud Drive wählen und die Vorschau lesen: „Nichts ändert sich …“ und „1 Eintrag, den
   du hier nach dieser Sicherung gelöscht hast, bleibt gelöscht.“ – Wiederherstellen ergänzt nur, es macht keine neuere Änderung
   rückgängig. Um die Fahrt zurückzuholen: auf einem leeren Speicher wiederherstellen (etwa nach „Alle Daten löschen“, Schritt 6).
4. App in den Hintergrund, am nächsten Tag nachsehen: eine neue tägliche Sicherung (nur, wenn sich etwas geändert hat).
5. Exportieren: jede der sechs Dateien einmal öffnen – Kalender (Import), Numbers/Excel (Spalten, Zahlen), Notizen (Text).
6. „Alle Daten löschen“ (nur mit Testdaten!): danach liegt eine „Vor dem Löschen“ in Sicherungen; aus ihr wiederherstellen.
