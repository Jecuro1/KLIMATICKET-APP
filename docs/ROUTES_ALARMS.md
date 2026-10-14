# Meine Routen und Alarme

Stand: Track „Gespeicherte Routen und Alarme“ (Recherche in der Scotty-Lücken-Analyse). Dieses Dokument beschreibt, was umgesetzt ist,
was bewusst fehlt und welche Kennungen als Vertrag gelten. Live-Regeln bleiben in `docs/OEBB_LIVE.md` (§2 Rechtsrahmen).

## 1. Meine Routen

### 1.1 Modell

- Eine gespeicherte Route ist die bestehende `FavoriteRouteEntity` (`Shared/Models.swift`). Keine zweite Tabelle.
- Neues Feld `scheduleRaw: String = ""`: der Wochentag- und Uhrzeit-Plan als `RouteSchedule.raw`, Form `"0,1,2,3,4;07:30;10"`
  (Wochentage Mo = 0 … So = 6; Uhrzeit; Vorlauf in Minuten). Leer = kein Zeitplan.
- Migration: additives Feld mit Standardwert. Bestehende Speicher öffnen ohne Versionswechsel (SwiftData-Leichtmigration). Es gibt
  keinen Migrationsplan im Projekt; das bleibt so, solange nur Felder mit Standard dazukommen.
- Via-Halte liegen wie bisher in `viaRaw` (`TripViaCodec`). Reihenfolge: `sortIndex`, per Ziehen umordnen (`SavedRoutes.moved`).

### 1.2 Cloud-Sync (bewusst nicht geändert)

- `scheduleRaw` ist **nicht** im Cloud-DTO (`FavoriteDTO`, Sync in `App/Sources/Services/SyncService.swift`). Der Zeitplan bleibt auf dem Gerät,
  auf dem er angelegt wurde. Andere Geräte sehen die Route, aber nicht ihren Zeitplan.
- Eine spätere DTO-Erweiterung ist additiv: ein optionales Feld `schedule` (String, Standard leer) im Worker-Schema (D1) und im DTO.
  Ältere Apps ignorieren das Feld. Das ist nicht umgesetzt, weil das Backend-Schema (`docs/CLOUDFLARE_BACKEND.md`) eine eigene Freigabe braucht.

### 1.3 Erinnerungen

- Je Wochentag eine wiederkehrende lokale Mitteilung (`UNCalendarNotificationTrigger`, `repeats: true`), `leadMinutes` vor der Abfahrt,
  in Europe/Vienna. Die Kennung ist `route.<Route-UUID>.<Wochentag der Erinnerung>`. Ein Vorlauf kann eine Erinnerung auf den Vortag
  schieben (Montag 00:05 mit 10 Min Vorlauf → Sonntag 23:55); `RouteSchedule.reminderSlots` rechnet das.
- Beim Speichern einer Route werden alle ihre Erinnerungen ersetzt (`SavedRouteReminders.apply`). Die Berechtigung wird nur gefragt,
  wenn die Route einen Zeitplan hat. Ohne Erlaubnis bleibt die Route gespeichert, die Erinnerung nicht; der Editor sagt das.
- Keine Anfrage ans Netz, kein Hintergrundlauf der App. iOS löst die Mitteilungen selbst aus.

### 1.4 Live-Abfahrten (Einwilligung, Zwischenspeicher)

- Die nächsten Abfahrten kommen aus dem Widget-Zwischenspeicher (`WidgetCache.connections`, geschrieben von `WidgetCacheSync.refreshLive`).
  Die Route-Ansicht fragt nichts selbst ab. Die Aktualisierung prüft die Einwilligung, die Drosselung (15 Min, außer
  „Ziehen zum Aktualisieren“) und das Anfragebudget.
- Nur Direktstrecken ohne Zwischenhalt und ohne Kombi-Vorlage haben Abfahrten (so fragt auch das Widget). Für die anderen steht das
  im Text, es wird nichts vorgetäuscht.
- Ohne Einwilligung, bei Sperre oder ohne Netz zeigt die Liste den Grund in Worten (`SavedRouteDepartures.unavailableText`).

### 1.5 Preis und CO₂

- Der Preis ist der gespeicherte Preis je Fahrt. Beim Anlegen mit zwei bekannten Stationen schätzt der Editor ihn und die Strecke mit dem
  App-Schätzer (`app.estimator`, `FareEstimator`), wenn der Nutzer den Preis nicht selbst eingetragen hat. Ohne Preis steht „Preis offen“.
- CO₂ je Fahrt = Strecke × Faktor des Verkehrsmittels (`app.catalog.emissions`, `EmissionFactors`; Standardwerte des Umweltbundesamts,
  `SavedRoutes.co2Kg`). Hin und zurück zählt doppelt.

### 1.6 Aktionen

- **Suchen:** öffnet die Planer-Suche auf der Route (`SavedRouteSearch`): dieselbe Logik wie ein `klimabilanz://plan`-Link
  (`handleDeepLink`). Die Suche startet nur mit bekannten Orten und nutzt den Live-Verkehr nur mit Einwilligung.
- **Als Widget:** iOS legt Widgets nur auf dem Home-Bildschirm an, KlimaBilanz kann das nicht. Das Blatt zeigt die drei Schritte
  („Nächste Verbindung“, Strecke wählen). Die Strecke erscheint in der Widget-Auswahl, weil sie eine Lieblingsfahrt ist.
- **Als Siri-Befehl:** `SavedRouteSearchIntent` (`App/Sources/Features/Routes/SavedRouteIntents.swift`) mit der App-Kurzbefehl-Phrase
  „Strecke <Route> suchen in KlimaBilanz“ und `OpenURLIntent` auf den Planer-Link. Der Kurzbefehl öffnet die App. Die Siri-Kachel im
  Detail (`SiriTipView`) hängt an derselben Absicht. **Ungeprüft auf Gerät:** ob Siri die Kachel für eine Absicht mit Parameter zeigt.
- Der Kurzbefehl-Zähler steigt von 5 auf 6 (Grenze 10 je App).

## 2. Alarme einsehen

Der Bildschirm „Alarme“ (`App/Sources/Features/Alarms/`) ist aus Einstellungen › Mitteilungen erreichbar. Er zeigt alles, was einen
Hinweis auslösen kann.

### 2.1 Quellen und Kennungen (Vertrag)

| Art | Kennung | Quelle |
|---|---|---|
| Live verfolgen | `livefollow-…` (sofort, nicht ausstehend) | `FollowRecordStore` (laufende Verfolgung) |
| Abfahrtserinnerung | `planner.reminder.<Verbindung>` | `PlannerReminders` |
| Route mit Zeitplan | `route.<Route-UUID>.<Wochentag>` | `SavedRouteReminders` |
| Ticket läuft ab | `renewal.<Ticket-UUID>.<Tage>` | `NotificationService` |
| Verlängerungsbrief / Widerspruch | `advisor.renewal.<Ticket-UUID>` | `AdvReminder` |
| Fahrgastrechte | `perk.passengerRights.<Art>.<Ticket-UUID>` | `PerkReminder` |
| Wochenrückblick | `weekly.summary` (Sonntag 18:00, Einstellung) | `AppSettings.weeklySummaryEnabled` |
| Störungen | keine | es gibt keine Störungs-Abos; der Bildschirm sagt das |

Die Präfixe stehen in `AlarmIdentifier` (KlimaCore). Eine Änderung verwaist die bereits geplanten Mitteilungen auf dem Gerät.

### 2.2 Ein, aus, löschen, bearbeiten

- **Aus** entfernt die ausstehende Mitteilung und merkt sich ihren Auslöser (`PausedAlarmStore`, UserDefaults). **An** plant sie neu,
  nur wenn der Termin noch kommt und die Erlaubnis da ist. Ein Termin in der Vergangenheit bleibt als „abgelaufen“ aus.
- Mehrere Mitteilungen einer Zeile (alle Wochentage einer Route, alle Fristen eines Tickets) schalten gemeinsam
  (`AlarmIdentifier.groupKey`).
- **Löschen** einer Routen-Erinnerung entfernt auch den Zeitplan der Route. Die Route bleibt.
- **Bearbeiten:** Routen öffnen den Editor, Ticket-Fristen führen zum Tab „Ticket“. Ein Wochenrückblick wird nur ein- oder ausgeschaltet.
- Live verfolgen: „Aus“ beendet die Verfolgung.

### 2.3 Verlauf (30 Mitteilungen, nur auf dem Gerät)

- Speicher: `NoticeHistoryStore` (UserDefaults, `alarms.history`), höchstens 30, neueste zuerst, je Kennung einmal.
- Einträge kommen aus `willPresent` (Mitteilung bei geöffneter App) und aus den Mitteilungen, die iOS noch als zugestellt listet
  (beim Öffnen des Bildschirms). Mitteilungen, die der Nutzer bereits aus der Mitteilungs-Zentrale entfernt hat und die nicht im Vordergrund
  ankamen, fehlen. Der Bildschirm sagt das nicht ausdrücklich; das ist eine offene Stelle.
- „Leeren“ setzt eine Zeitmarke. Ältere Systemeinträge kommen danach nicht zurück.

### 2.4 Grenzen (ehrlich benannt)

- iOS nimmt nur begrenzt viele ausstehende lokale Mitteilungen an. Nach unserem Stand sind es 64 je App. Diese Zahl ist **nicht gegen die
  Apple-Dokumentation geprüft**. Der Bildschirm zeigt die Belegung und warnt ab drei Vierteln.
- Live-Mitteilungen (Verspätung, Gleis, Ausfall) sind sofort zugestellte Mitteilungen. Sie stehen nicht in der Liste der ausstehenden
  Alarme. Der Bildschirm sagt das.
- Die Liste zeigt Berechtigung und Einwilligung in Worten, mit einem Knopf zu den Einstellungen, wenn Mitteilungen aus sind.

## 3. Reine Logik (KlimaCore, Linux-getestet)

- `Routes/RouteSchedule.swift`: Wochentage, Zeitplan-Format, Erinnerungs-Slots mit Vorlauf, nächster Termin und nächste Erinnerung (Wiener Zeit).
- `Routes/SavedRoutes.swift`: Umordnen wie `Array.move`, Routenzeile, CO₂, nächste gecachte Verbindung.
- `Alarms/AlarmKinds.swift`: Arten, Kennungen, Gruppen, Route-ID aus Kennung.
- `Alarms/AlarmModel.swift`: Auslöser als Werte, pausierter Alarm, Zeile, Sortierung, Budget ausstehender Mitteilungen.
- `Alarms/NoticeHistory.swift`: Verlauf mit Obergrenze 30, Dubletten, Zusammenführung.
- Tests: `Packages/KlimaCore/Tests/KlimaCoreTests/Routes/` und `…/Alarms/` (36 Tests, alle grün auf Linux).

## 4. Demo und Screenshots

- `-KBDemo` ohne Netz: die Routen aus `DemoData` (die Strecke „Arbeit“ hat den Zeitplan Mo–Fr 07:20), Abfahrten aus
  `SavedRouteDemo` (feste Zeiten relativ zu jetzt), Alarme aus `AlarmsDemoScene`.
- CI-Routen (`ScreenshotRouter`, Marke „// MARK: routes“): `routesList`, `routeDetail`, `routeEdit`, `alarmsList`, `alarmHistory`.

## 5. Offene Entscheidungen des Eigentümers

1. Zeitplan in die Cloud synchronisieren (Schema- und DTO-Änderung, siehe 1.2)?
2. Störungs-Abos anbieten? Es gibt dafür keine Quelle; eine Mitteilung dazu wäre neu und braucht eine Freigabe nach §2.
3. Die Live-Mitteilungen in die Alarm-Liste aufnehmen (sie sind nicht ausstehend, also nur als Verlauf sichtbar)?
