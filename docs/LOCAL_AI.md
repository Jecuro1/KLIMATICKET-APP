# Lokale KI auf dem Gerät (KlimaBilanz)

Stand: Oktober 2026 · Gilt für iOS 26 und Xcode 26.6. Diese Datei beschreibt, was die lokale KI tut, wann sie läuft, was das
Gerät braucht und was sie nicht kann. Sie ist ehrlich gemeint: Was hier nicht steht, ist nicht geprüft.

## 1. Was läuft wann

- **Modell:** das Apple-Foundation-Modell auf dem Gerät (Framework `FoundationModels`, iOS 26). Es läuft lokal, ohne Server,
  ohne Netzanfrage, ohne Kosten pro Aufruf.
- **Nur im Vordergrund, nur auf Anfrage:** Das Modell wird gefragt, wenn du „Suche in Worten“ benutzt, das Sheet
  „Warum lohnt sich mein Ticket?“ öffnest oder der Planer einen Vorschlag für die übliche Fahrzeit formuliert. Jeder Aufruf
  nutzt eine eigene Sitzung; es gibt keine langlebige Unterhaltung.
- **Hintergrund: keine Modellaufrufe.** Das gilt für Hintergrund-Tasks, Hintergrund-Starts, Widgets und Mitteilungen.
  Der Wochenrückblick wird beim Aktivieren der App (Vordergrund) geschrieben und als Text in die lokale Sonntags-Mitteilung
  gelegt. Die Mitteilung zeigt also den Stand vom letzten Öffnen, und der Text nennt sein Datum („Stand …“).
- **Ohne Modell arbeitet alles:** Jede KI-Funktion hat einen regelbasierten Ersatz im Modul `KlimaCore/Assistant`. Die Regeln
  laufen immer, auch ohne Apple Intelligence und ohne Schalter.

## 2. Verfügbarkeit und was der Nutzer sieht

Quelle: `SystemLanguageModel.default.availability` und `supportsLocale(de_AT)`, beim Öffnen der Einstellungen neu gelesen.
Die Zustände stehen in Einstellungen › KI auf dem Gerät (`AssistantAvailability`):

| Zustand | Bedeutung | Was passiert |
|---|---|---|
| Bereit | Modell verfügbar, Deutsch unterstützt, in KlimaBilanz an | KI formuliert, Regeln prüfen die Zahlen |
| Apple Intelligence ist aus | Im iOS-System abgeschaltet | Regeln, Hinweis mit dem Weg zur Einstellung |
| Gerät nicht geeignet | Kein Modell auf diesem Gerät oder iOS-Version | Regeln |
| Deutsch nicht unterstützt | Modell läuft, aber nicht auf Deutsch | Regeln |
| Modell wird vorbereitet | Erster Start oder Download | Regeln, bis das Modell bereit ist |
| In KlimaBilanz aus | Schalter „KI nutzen“ aus | Regeln |

Der Schalter „KI nutzen“ steht unter Einstellungen › KI und ist standardmäßig an. Aus heißt: Das Modell wird nie gefragt.

**Was das Gerät braucht:** ein iPhone, das Apple Intelligence unterstützt, iOS 26, Apple Intelligence eingeschaltet und
Deutsch als Sprache des Modells. Welche Geräte und Sprachen tatsächlich gehen, entscheidet das System zur Laufzeit. Diese
Datei nennt bewusst keine Gerätetabelle.

## 3. Die Funktionen und ihr Ersatz

| Funktion | Mit KI | Ohne KI (Regeln) | Ort |
|---|---|---|---|
| Suche in Worten („nächste Woche Freitag nach Innsbruck, Rückfahrt Sonntag“) | Modell liefert Felder per `@Generable`, Prüfung in `TripQueryValidator` | `TripQueryParser`: Ort, Tag, Uhrzeit, „bis“ als Ankunft, Rückfahrt | Planer: Button „In Worten suchen“ |
| Warum lohnt sich mein Ticket? | Text aus den Zahlen der Bilanz, geprüft in `AssistantNumberGuard` | Regeltext `BalanceFacts.ruleText` mit denselben Zahlen | Übersicht, unter der Bilanz-Karte |
| Wochenrückblick | Ein Satz, geprüft wie oben | `WeeklyRecapFacts.ruleText` | Sonntags-Mitteilung (Text vom letzten Öffnen) |
| Strecke zur üblichen Zeit | Ein Satz über die Strecke, geprüft wie oben | Regeln: mindestens 3 Fahrten in ±1 Stunde und mindestens 40 % | Planer: „Vorschlag für jetzt“ |

Die Auswahl (welche Strecke, welcher Tag, welche Uhrzeit) kommt immer aus den Regeln. Die KI formuliert nur.

## 4. Garantien

1. **Keine erfundenen Zeiten, Orte, Tage.** Das Modell liefert Felder (Ort, Datum, Uhrzeit, Ankunft). `TripQueryValidator`
   übernimmt nur, was der Satz hergibt: ein Ort nur, wenn er im Satz steht; eine Uhrzeit nur, wenn ihre Zahl im Satz steht;
   ein Datum nur innerhalb von 365 Tagen ab heute; „Ankunft“ nur bei „bis“, „spätestens“ oder „Ankunft“ im Satz.
2. **Regeln zuerst.** Die Regeln lesen den Satz zuerst. Das Modell füllt nur Felder, die die Regeln offen lassen.
3. **Keine erfundenen Zahlen im Text.** Jede Zahl im Ergebnis eines Modells muss als Angabe in der Liste stehen, die dem Modell
   gegeben wurde (`AssistantNumberGuard`: `1.400` und `1400` sind gleich, `23,50` und `23.5` ebenfalls). Passt eine Zahl nicht,
   verwirft KlimaBilanz den Modelltext und zeigt den Regeltext. Zu lange oder mehrzeilige Texte werden ebenfalls verworfen.
4. **Kein Rechnen durch das Modell.** Die Zahlen kommen aus `SavingsSummary` und dem Wochenauszug, die die App ohnehin berechnet.
   Das Modell bekommt nur eine Liste fertiger Angaben.
5. **Quelle immer sichtbar.** Jeder KI-bezogene Text trägt eine Zeile: „Mit der KI auf deinem Gerät formuliert“, „Aus deinen
   Zahlen per Regeln“ oder „Demo – kein Modell befragt“.
6. **Keine Daten in Protokollen.** Die KI-Schicht schreibt keine Logs, keine Sätze, keine Zahlen und keine Fahrtdaten. Der
   Speicher hält nur die Antworten für den Wochenrückblick, im Arbeitsspeicher, bis der Prozess endet.

## 5. Datenschutz

- Eingaben (der Satz im Planer, die Zahlen der Bilanz, die Fahrten für den Wochenrückblick) verlassen das Gerät nicht.
- Die Einstellungen speichern nur den Schalter. Es gibt keine Synchronisation von KI-Texten.
- Die Texte sagen das auch: „Nichts verlässt dein Gerät.“

## 6. Was die KI nicht kann

- **Nichts im Hintergrund.** Keine Modellaufrufe in Hintergrund-Tasks, beim Start im Hintergrund, in Widgets oder in
  Mitteilungen. Ob das Modell aus einem Hintergrundkontext laufen dürfte, ist nicht geprüft und wird nicht zugesagt.
- **Keine Rückfahrt-Suche.** Der Planer sucht eine Richtung. Die Rückfahrt zeigt die Suche nur an, du suchst sie separat.
- **Keine Prognosen, keine neuen Zahlen.** Die Bilanz-Prognose ist die bestehende Rechnung; die KI erklärt sie nur.
- **Nicht bei jedem Satz.** Lange, mehrdeutige oder umgangssprachliche Sätze werden unvollständig erkannt. Dann bleibt das Feld
  „noch offen“, und du wählst den Ort im Planer.
- **Nicht geprüft auf einem Gerät.** Die Verfügbarkeit, die Deutsch-Unterstützung, die Antwortzeit und die Qualität der
  Formulierungen sind auf einem echten Gerät noch nicht geprüft.

## 7. Technik

- `Packages/KlimaCore/Sources/KlimaCore/Assistant/`: Zustände, Parser, Validator, Zahlenprüfung, Bilanz- und Rückblicktexte,
  Streckenvorschlag, Prompts. Rein, testbar unter Linux.
  Tests: `Packages/KlimaCore/Tests/KlimaCoreTests/Assistant/`.
- `App/Sources/Services/AI/`: `LocalAssistant` (der Dienst) und `AssistantEngine` (die einzige Stelle, die `FoundationModels`
  anspricht). Ohne das Framework gibt es `UnavailableAssistantEngine`.
- `App/Sources/Features/Assistant/`: Einstellungsseite, Sheets, Planer-Eingang, Demo-Szenen.
- Harness (`tools/typecheck`): Stub `FoundationModels` aus den Deklarationen des iOS-26.4-SDK-Interfaces und das
  Makro-Plugin für `@Generable` und `@Guide`. Der Harness prüft die echte Verzweigung (`#if canImport(FoundationModels)`).
  Die Stubs haben keinen Modellbetrieb; ein Modellaufruf ist im Harness nicht prüfbar.

## 8. Demo und Screenshots

- Mit `-KBDemo YES` fragt die App das Modell nie. Die Szenen zeigen deterministische Texte mit der Quelle „Demo“.
- Screenshot-Szenen (`-KBScreenshot`): `aiAvailable`, `aiUnavailable`, `aiPlannerQuery`, `aiBalance`.

## 9. Offen

- Gerätetest: Verfügbarkeit, Deutsch, Antwortzeit, Qualität der Formulierungen.
- Ob die Modell-Schnittstelle im Xcode-26.6-SDK genau so heißt, bestätigt erst der macOS-CI-Lauf.
- Der Begriff „KI“ in der Oberfläche folgt der Vorgabe des Besitzers („integrierte lokale KI“).
