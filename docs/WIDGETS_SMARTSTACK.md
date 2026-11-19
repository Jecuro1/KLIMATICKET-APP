# Widgets: Sperrbildschirm, Smart Stack und Apple Watch

Stand: Track „smartwidgets“ (Widgets, Smart Stack und Watch-Anzeige). Ergänzt `docs/WIDGETS.md`; dort gelten weiter alle
Grundregeln (kein Netz in der Extension, Live-Caches nur mit Einwilligung, höchstens alle 15 Minuten, nur bei sichtbarer App).
Dieser Track macht **keine** neuen Abrufe, braucht **kein** neues Entitlement und **kein** neues Target: Es bleibt bei der einen
Widget-Extension (zwei App-IDs bei einer kostenlosen Apple-ID), ohne APNs und ohne WidgetKit-Push.

## 1. Gesperrt & privat

Zwei Schalter in der Widget-Galerie (Einstellungen › Widgets, Abschnitt „Gesperrt & privat“):

| Schalter | Standard | Was verborgen wird, solange das iPhone gesperrt ist |
|---|---|---|
| Strecken auf dem Sperrbildschirm verbergen | **an** | Stationsnamen, Ziele und Richtungen, Namen der Lieblingsfahrten |
| Beträge verbergen | aus | Euro-Beträge: „noch € 354“, „+ € 412“, Wert der Favoriten, „Wert € 946“, die Inline-Zeile, der Gipfel-Fortschritt |

Prozent, Tage, Abfahrtszeiten, Linien, Gleise und Verspätungen bleiben sichtbar.

**Technik.** Jeder betroffene Text trägt `widPrivate(.route)` oder `widPrivate(.amount)` (`Shared/WidgetViews/WidPrivacy.swift`).
Ist der Schalter an, ist der Text `privacySensitive()`. Solange das Gerät gesperrt ist, zeichnet iOS das Widget mit dem
Redaktionsgrund `.privacy` und setzt an diese Stellen einen Platzhalter derselben Größe: Das Layout springt nicht. VoiceOver
liest dort „Inhalt verborgen“; Sätze, die mehrere Texte zusammenfassen (z. B. die Zeile einer Abfahrt), lassen das Verborgene
weg. Die einzeilige Abfahrten-Zeile über der Uhr kann nur ganz oder gar nicht verborgen werden; gesperrt sagt sie deshalb
„Abfahrten · 07:42 S 4“ statt des Stationsnamens. Ebenso die Inline-Zeile des Gipfel-Fortschritts: gesperrt mit verborgenen
Beträgen „73 % · Gipfel“ statt „73 % · noch € 354“.

**Speicher.** Die Wahl liegt in der App Group unter `widgets.privacy.v1` (`WidgetPrivacy`, KlimaCore) und wird in den
Ticket-Snapshot kopiert (`WidgetSnapshot.hidesRoutesWhenLocked`, `hidesAmountsWhenLocked`, beide optional, Schlüssel bleibt
`widgetSnapshot.v1`). Ein Snapshot von vor dem Update dekodiert als Standard (Strecken verborgen, Beträge sichtbar; Test
`testOldSnapshotDecodesAsDefaults`). Das Widget folgt `WidgetPrivacy.resolve(stored:snapshot:)`: zuerst der Schlüssel (er
existiert auch ohne Ticket, für die Live-Widgets), dann der Snapshot, dann der Standard. Ein Umschalten lädt alle Widgets einmal
neu (`WidgetPrivacyStore`); Screenshot- und Perf-Läufe schreiben nichts.

**Nicht betroffen.** Alle Live-Aktivitäten („Unterwegs“, „Live verfolgen“, Aussteige-Wecker, Aufzeichnung) bleiben auf
Sperrbildschirm, Dynamic Island und einer gekoppelten Watch unverändert vollständig, ebenso das Steuerelement „Lieblingsfahrt
erfassen“ im Kontrollzentrum (Name und Wert der Fahrt; für Steuerelemente ist kein Verbergen eingebaut). Die Galerie sagt das.

## 2. Inline-Zeile der Amortisation (Entscheidung zu WIDGETS.md §8.5)

Über der Uhr (accessoryInline) stand bisher „73 % rentiert“. Entschieden: Die Zeile nennt, was fehlt oder was gewonnen ist –
die Prozent stehen schon im runden und im rechteckigen Widget.

| Zustand | Text | gesprochen |
|---|---|---|
| noch nicht rentiert | `€ 142 bis zum Ziel` | „Noch 142 Euro bis zum Ticketpreis“ |
| rentiert | `Lohnt sich · +€ 37` | „Ticket lohnt sich, 37 Euro im Plus“ |
| abgelaufen | `Ticket abgelaufen` | |
| kein Ticket | `Kein Ticket erfasst` | |

Höchstens 22 Zeichen (`InlineAmortizationText.maxLength`); sehr große Beträge fallen auf kürzere Fassungen zurück („noch
€ 1.234.567“, „Im Plus · +€ 123.456“, zuletzt nur der Betrag). Zwischen „€“ und Zahl steht ein geschütztes Leerzeichen. Die
Beträge sind dieselben ganzen Euro wie im Widget sonst (`WidFigures`), also passen „€ 354 bis zum Ziel“ und „noch € 354“
zusammen. Symbol: Berg, nach dem Break-even die Fahne.

## 3. Smart-Stack-Relevanz

`WidgetRelevance` (KlimaCore) gibt jedem Timeline-Eintrag eine Punktzahl (`TimelineEntryRelevance`):

| Widget | Punkte |
|---|---|
| Nächste Verbindung, Abfahrten | 100 ab 45 Minuten vor der nächsten Abfahrt bis zur Abfahrt, danach in 5 Minuten linear auf 0; sonst 0 (jeder Wert gilt bis zum nächsten Eintrag, siehe §7) |
| Ticket-Restzeit | 30 an jedem der letzten 14 Tage der Gültigkeit (Wiener Kalendertage, letzter Tag eingeschlossen), sonst 0 |
| Break-even | 60 am Tag der Prognose, solange das Ticket noch nicht rentiert ist, sonst 0 |
| alle anderen | keine Angabe (das System entscheidet allein) |

Die Einträge kommen weiter nur aus den Caches der App. Damit die Punkte ohne Neuladen steigen, bekommt die Timeline der
Live-Widgets zusätzlich die Zeitpunkte 45 Minuten vor einer Abfahrt und das Ende des Abklingens
(`WidgetRelevance.departureChangeDates`, höchstens 16 Einträge statt 12). Zusätzliche Einträge kosten kein Reload-Budget.
Ob der Smart Stack das Widget wirklich nach vorne dreht, entscheidet iOS.

## 4. Sperrbildschirm-Familien

| Widget | Kreis | Rechteck | Inline |
|---|---|---|---|
| Nächste Verbindung | **neu**: Ring der letzten 45 Minuten, Abfahrt, Verspätung | ja | ja |
| Abfahrten | **neu**: Linie, Abfahrt, Ring, Verspätung | ja | ja |
| Ticket-Restzeit | ja | **neu**: Tage, „bis 31. Jän.“, Balken; am letzten Tag „Heute · letzter Tag“ | ja |
| Amortisation | ja | ja | ja (neuer Text, §2) |
| Break-even | ja | ja | ja |

Vibrant wie jedes Sperrbildschirm-Widget: keine eigenen Farben, die Kennzahl `widgetAccentable()`, jede Zahl mit
Sprachausgabe. Der Ring ist `ProgressView(timerInterval:countsDown:)` mit Kreis-Stil: Das System lässt ihn selbst ablaufen.

## 5. Live-Aktivitäten auf der Apple Watch

„Unterwegs“ und „Live verfolgen“ melden die kleine Familie an (`.supplementalActivityFamilies([.small])`). Mit
`@Environment(\.activityFamily) == .small` zeigen sie ein eigenes Layout (`Shared/WidgetViews/ActivitySmallViews.swift`,
Texte aus `ActivitySmallText`, KlimaCore):

- Zeile 1: Linie oder Verkehrsmittel, geplante Zeit und Verspätung – „RJX 66 07:42 +3“. Vor der Abfahrt die Abfahrt mit der
  Abfahrtsverspätung (aus der tatsächlichen Abfahrtszeit), unterwegs die Ankunft mit der Verspätung am Ziel. Linien über acht
  Zeichen werden zu „Zug“.
- Zeile 2: das Ziel, gekürzt („Wien Hbf“, „Feldkirch Bf“, „St. Anton“).
- Zeile 3: „Abfahrt in“ / „Ankunft in“ / „Weiter in“ mit `Text(timerInterval:)`, das die Watch selbst herunterzählt (Minuten
  und Sekunden, „16:56“; ab einer Stunde „2:51:56“); bei einer eigenen Fahrt ohne bekannte Ankunft „Fahrzeit“ aufwärts.
- Die Verspätung ist ab fünf Minuten getönt, und zwar die, die in Zeile 1 steht (vor der Abfahrt die Abfahrtsverspätung).
- Zeile 4, nur wenn die Daten alt sind: „Stand 07:40“ (Live verfolgen) bzw. „Noch nicht gespeichert“ (Unterwegs).
- VoiceOver: ein ganzer Satz, z. B. „RJX 66 nach Wien Hbf, Abfahrt um 07:45, 3 Minuten später.“

ContentState und Attribute sind unverändert (4-KB-Grenze), Sperrbildschirm und Dynamic Island ebenso. Eine eigene Watch-App
gibt es nicht und kann es nicht geben (ein watchOS-Target lässt sich mit kostenloser Apple-ID nicht sideloaden). Laut Apple
zeigt watchOS 11 und neuer die Live-Aktivitäten des gekoppelten iPhones im Smart Stack; ausprobiert ist das nicht.

## 6. Tests

`Tests/KlimaCoreTests/Widgets/WidgetSmartStackTests.swift` (Linux, `swift test --filter Widget`): Relevanz bei −60, −45, −1,
0, +1, +2,5, +5 Minuten und an den Ticketgrenzen (15., 14., letzter Tag, abgelaufen), Break-even-Tag, zusätzliche
Eintragszeitpunkte, Inline-Texte und ihre Länge bis 10¹⁸ €, NaN und negativ, alter und neuer Snapshot-JSON, Vorrang der
gespeicherten Wahl, die Zeilen der kleinen Live-Aktivität (vor der Abfahrt, unterwegs, alt, Ende, eigene Fahrt).

## 7. Vorschau (DEBUG, CI-Szenen)

`SmartWidgetsScreenshotHost`: `widgetsPrivacy` (die Galerie beim Abschnitt, gesperrte Vorschau), `widgetsPrivacyAmounts`
(auch Beträge verborgen), `widgetsPrivacyAX5`, `widgetsPrivacyAX5Switches` und `widgetsPrivacyAX5Bottom` (größte Schrift: oben, bei den Schaltern,
beim Hinweis),
`widgetsAccessory` (alle Sperrbildschirm-Familien, „neu“ markiert), `widgetsAccessoryLocked` (dieselben gesperrt),
`widgetsAccessoryBottom` und `widgetsAccessoryLockedBottom` (die unteren Zeilen mit Break-even und Gipfel),
`liveActivitySmall` (Watch-Bühne mit fünf Zuständen), `widgetsRelevance` (Punkte der Demo-Timelines, Uhr auf 07:00 gestellt).
Alles Demodaten, kein Netz, kein Systemdialog.

Die Vorschau in der App zeichnet den Ring der runden Abfahrts-Widgets als `Gauge`, der alle 30 Sekunden neu berechnet wird:
Außerhalb von Widgets ist der Kreis-Stil von `ProgressView` ein Lade-Rädchen. Im Widget selbst (Umgebung `widgetFamily ==
.accessoryCircular`) ist es laut Apple die Kapazitätsanzeige, die das System selbst ablaufen lässt – auf dem Gerät zu prüfen.

Die Punkte gelten jeweils ab ihrem Eintrag bis zum nächsten: Das Abklingen nach der Abfahrt ist in der Timeline eine Stufe
(100 bis zum nächsten Eintrag, spätestens fünf Minuten nach der Abfahrt 0), keine Rampe.

## 8. Nur auf dem Gerät prüfbar (offen)

- Ob iOS die markierten Stellen am gesperrten Gerät wirklich ausblendet (Sperrbildschirm, StandBy) und ob die Umgebung dabei
  `.privacy` meldet (davon hängt „Inhalt verborgen“ für VoiceOver und die gesperrte Abfahrten-Zeile ab; ohne sie greift
  `privacySensitive` trotzdem).
- Smart-Stack-Reihenfolge (das System entscheidet), StandBy-Nachtmodus, Speicher der Extension (rund 30 MB, nicht gemessen),
  das tägliche Reload-Budget (etwa 40 bis 70 je Widget).
- Die Watch-Anzeige: kein gekoppelter Watch-Simulator in CI; das Verhalten stammt aus Apples Dokumentation und wurde mit einem
  per AltStore/SideStore installierten Build nicht ausprobiert.
- Gerätecheck für den Owner: Schalter an, iPhone sperren, Sperrbildschirm- und Home-Widgets ansehen; „Live verfolgen“ mit
  gekoppelter Watch starten und den Smart Stack ansehen.

## 9. Gesehen (CI-Screenshots, Simulator, hell und dunkel)

- Lauf 43438388828: erste Szenen. Der Kreis-Stil von `ProgressView` war in der App ein Lade-Rädchen (behoben, §7), das
  Symbol der Inline-Zeile wurde mit dem Betrag verdeckt (behoben), bei AX5 brachen die Schaltertitel mitten im Wort (behoben:
  Schalter unter dem Text).
- Lauf 43444084719: Abschnitt in der echten Galerie (unter StandBy), Uhrzeit der Vorschau ist die echte, Watch-Bühne mit
  Stapelkarte, Umstiegszeile „Umstieg 16:15 · in Wien Hbf · Weiter in …“. Die Abfahrtszeit berührte den Ring (behoben).
- Lauf 43450975954: Zeit im Ring mit Abstand, AX5 bei den Schaltern ohne Worttrennung. Die helle AX5-Szene bei den Schaltern
  zeigte einmal den Startbildschirm (Start im CI-Simulator über 8 s, die dunkle Aufnahme derselben Szene startete in 1 s).

## 10. Review (19. Nov. 2026)

Gegenprüfung des Tracks auf `main`. Behoben:

- **Gipfel-Fortschritt** zeigte „noch € 354“ / „+ € 37“ auch mit „Beträge verbergen“ – auf dem Sperrbildschirm und in
  StandBy, für das er gebaut ist. Jetzt `widPrivate(.amount)` im kleinen und im rechteckigen Widget, die Inline-Zeile sagt
  gesperrt „73 % · Gipfel“, VoiceOver lässt den Betrag weg.
- **Was nicht verborgen wird**: Die Galerie nannte nur zwei Live-Aktivitäten. Sie sagt jetzt „Live-Aktivitäten und
  „Lieblingsfahrt erfassen“ im Kontrollzentrum zeigen weiterhin alles“ (§1).
- **Ticket-Restzeit, rechteckig**: Am letzten gültigen Tag stand „0 Tage“; jetzt „Heute · letzter Tag“ wie in der App.
  Abgelaufen sagt VoiceOver „war gültig bis …“. Das kleine Home-Widget und der Kreis zeigen am letzten Tag weiter „0“
  (älter als dieser Track, unverändert).
- **Runder Countdown** von „Nächste Verbindung“: das Symbol des Verkehrsmittels der Verbindung statt immer der Straßenbahn.
- **Watch-Zeile**: Die Tönung folgt der Verspätung, die in Zeile 1 steht (vor der Abfahrt die Abfahrtsverspätung, nicht die
  am Ziel); ohne Liniennamen sagt VoiceOver „Zug nach …“ statt „ nach …“ (Linux-Tests).
- **Vorschau-Uhr** in „Gesperrt & privat“: Wiener Zeit wie alle Zeiten der Widgets.
- **Watch-Fußzeile** („Stand 15:39“, „Fahrt speichern“) ist immer orange; vorher hing die Farbe an der Verspätung. Die
  Watch-Seite (nur CI-Szene) sagt „kann … zeigen“ statt „zeigt“: ausprobiert ist es nicht.
- **Weniger Arbeit in der Extension**: `WidgetPrivacy.current` dekodiert den Snapshot nur noch, wenn der Schlüssel
  `widgets.privacy.v1` nicht beide Schalter enthält (die App schreibt immer beide).

Geprüft und so gelassen: Relevanz-Zahlen und Tagesgrenzen (Wiener Kalendertage, Sommerzeit über `startOfDay`), die Beträge
der Inline-Zeile (dieselben ganzen Euro wie die übrigen Widgets), kein Netz in Extension und `Shared/`, keine neuen
Entitlements, kein SwiftData-Feld, Schreiben nur in die App Group, Screenshot-Läufe schreiben nichts.

Offen, nicht geändert:

- Auf der Watch steht der Countdown als „16:56“ (Minuten:Sekunden) unter Uhrzeiten wie „16:16“. `Text(timerInterval:)` bleibt,
  weil es nach der Abfahrt bei 0:00 stehen bleibt; `Text(_, style: .relative)` zählt danach wieder hoch.
- Die Watch-Zeile nennt die geplante Zeit mit Verspätung („07:42 +3“), die Widgets die erwartete Zeit mit Verspätung
  („07:45 +3“), die Live-Aktivität am iPhone die erwartete Abfahrt mit der Verspätung am Ziel. Eine gemeinsame Regel fehlt.
