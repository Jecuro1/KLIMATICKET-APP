# Widgets: Cache, Einwilligung, Familien

Stand: Widget-Track („Viele Widgets“). Die Bestandswidgets (Amortisation, Schnellerfassung, Controls, „Unterwegs“) bleiben
unverändert in ihrer Form; neu sind die Widgets unten. Plan und Begründung: `docs/WIDGETS` steht in diesem Abschnitt, die
Entscheidungen des Owners in §8.

## 1. Grundregeln

- **Widgets machen nie einen Netzaufruf.** Sie lesen nur den Cache in der App Group (`AppGroup.defaults`). Die Prüfung
  liegt in `scripts/check_integration.py` (Widget-Target ohne `URLSession`, `HafasClient`, `LiveDataService`).
- **Die App schreibt den Live-Cache nur mit Einwilligung** (`LiveDataService.consent == .granted`). Der Einwilligungsstand wird
  nach `widgets.consent.v1` gespiegelt. Widerruf leert alle Live-Caches sofort und lädt die Widgets neu.
- **Abrufe nur bei sichtbarer App**, höchstens alle 15 Minuten (`WidgetCacheSync.minimumInterval`), nie aus
  `BGAppRefreshTask` (Regel D5 in `OEBB_LIVE.md`).
- **Ehrlicher Stand**: Mittlere und große Widgets zeigen „Stand HH:mm“. Ist der Cache älter als zwei Stunden, zeigt das
  Widget „Stand HH:mm · App öffnen für aktuelle Zeiten“ und keine Verspätungen mehr.
- **Quellenvermerk** „Quelle: ÖBB-Fahrplanauskunft“ auf mittleren und großen Live-Widgets (`OEBB_LIVE.md` E7).
- **Keine Logos, keine Markenfarben.** Symbole nur als SF Symbols.

## 2. Schlüssel der App Group

| Schlüssel | Typ (KlimaCore) | Geschrieben von | Inhalt |
|---|---|---|---|
| `widgets.consent.v1` | `WidgetConsent` | App (Einwilligung) | undecided / granted / declined |
| `widgets.connections.v1` | `WidgetConnectionCache` | App, bei Abruf | nächste Verbindungen je Favorit (`uuidString`) |
| `widgets.departures.v1` | `WidgetDepartureCache` | App, bei Abruf | nächste Abfahrten je Station |
| `widgets.disruptions.v1` | `WidgetDisruptionCache` | App, bei Abruf | Störungen der Linien, die der Nutzer fährt |
| `widgets.stations.v1` | `WidgetStationList` | App, bei Änderung | Heimat-Station und Favoriten-Stationen, höchstens 10, mit Ausstattung |
| `widgets.liveFollow.active.v1` | Bool | App (Live verfolgen) | ob ein Zug verfolgt wird |
| `widgets.liveFollow.request.v1` | Bool | Control | Auftrag an die App: an / aus |
| `widgetSnapshot.v1` | `WidgetSnapshot` | App | Ticket-Snapshot; neu: `heat` (84 Tageszahlen) |

Alle Caches sind versioniert, neue Felder sind optional. Schreiben nur bei Änderung des Inhalts; neu laden mit
`reloadTimelines(ofKind:)` nur der betroffenen Art, nie `reloadAllTimelines()` für Live-Daten.

## 3. Daten und Ausstattung

- **Zugausstattung** (je Fahrt, aus den Remarks Typ A): WLAN, Bordrestaurant, Ruhezone, Familienzone, Rollstuhl,
  WC rollstuhltauglich (`OC`, `OG`), Fahrradmitnahme, Businessabteil. Das Widget beschriftet sie als „im Zug“.
- **Stationsausstattung** aus den Ortsdaten: Bike+Ride (B+R), Park+Ride (P+R) und Barrierefreiheit (ganz oder teilweise).
  **Aufzüge und WC an Haltestellen** sind in den Ortsdaten nicht enthalten. Sie werden deshalb nicht angezeigt. Die
  Erweiterung der OSM-Extraktion ist ein eigenes Paket (ODbL, Quellenvermerk in `stops_osm.bin`).
- **Störungen** werden über die Linien zugeordnet, die in den Ergebnissen der Lieblingsfahrten vorkommen. Die Meldungen
  haben keine Position; die Anzeige nennt die Linien.

## 4. Widgets

| Widget (kind) | Familien | Daten |
|---|---|---|
| Nächste Verbindung (`nextConnection`) | sSmall, sMedium, sLarge, aRectangular, aInline | Cache, Konfiguration: Lieblingsfahrt |
| Abfahrten (`departures`) | sMedium, sLarge, aRectangular, aInline | Cache, Konfiguration: Station (Standard Heimat-Station) |
| Störungen auf meinen Linien (`disruptions`) | sSmall, sMedium, aRectangular, aInline | Cache |
| Ticket-Restzeit (`ticketRemaining`) | sSmall, aCircular, aInline | Snapshot |
| Break-even (`breakEven`) | sSmall, aCircular, aRectangular, aInline | Snapshot (Prognose) |
| Jahresrückblick (`yearReview`) | sSmall, sMedium | Snapshot; ab Dezember oder in den letzten 30 Tagen, sonst Countdown |
| Fahrten-Kalender (`heatmap`) | sMedium, sLarge | Snapshot (`heat`), zwölf Wochen, Montag oben |
| Gipfel-Fortschritt (`summit`) | sSmall (auch StandBy), aRectangular, aInline | Snapshot |

Controls: **Zug-Radar** (öffnet `klimabilanz://radar`), **Verbindung suchen** (öffnet `klimabilanz://tab/planner`),
**Live verfolgen** (Toggle mit `SetValueIntent`). Zum Einschalten öffnet die App den Zug-Radar, damit ein Zug gewählt wird;
zum Ausschalten beendet sie die Verfolgung. Beide Wege laufen über die App (`.foreground`), weil die Verfolgung in der
App-Prozess lebt.

Bestand unverändert: Amortisation, Schnellerfassung, Fahrt erfassen, Lieblingsfahrt erfassen, „Unterwegs“.

## 5. Zeitplan der Einträge

Die Einträge liegen genau an den Zeitpunkten, an denen sich die Liste ändert: eine Minute vor jeder Abfahrt und beim
Veralten des Caches (`WidgetTimeline.entryDates`). Countdowns laufen über `Text(_:style: .relative)` ohne Neuladen.
Ohne Daten oder bei nur einem Eintrag fragt WidgetKit nach 30 Minuten erneut.

## 6. Tests

Die reine Logik liegt in KlimaCore und hat Linux-Tests (`Tests/KlimaCoreTests/Widgets/WidgetCacheTests.swift`):
Frische des Caches, Filter nach Abfahrt und Verspätung, Zeitplan-Einträge, Heatmap-Raster (Montag, Wochen, Zukunft),
Jahresrückblick-Sichtbarkeit, Abbildung der HAFAS-Antworten, Codable.

## 7. Vorschau (DEBUG)

Die Routen `widgetsGallery`, `widgetsGalleryDark`, `widgetsNextConnection`, `widgetsHeatmap`, `widgetsLockScreen`,
`widgetsStandBy` rendern dieselben SwiftUI-Views in Widget-Größe mit Demodaten (`WidSamples`, `WidgetSnapshot.sample`),
ohne Netz. WidgetKit lässt sich im Simulator nicht aufnehmen; die Vorschau ersetzt das nicht auf dem Gerät.

## 8. Entscheidungen des Owners (offen)

1. Gipfel-Fortschritt: als eigenes Widget für Sperrbildschirm und StandBy gebaut; in der Amortisation bleibt er auch.
2. Heimat-Station ist Standard für „Abfahrten“.
3. Strecken und Ziele am gesperrten Gerät: derzeit sichtbar. Ein Schalter „Auf dem Sperrbildschirm ausblenden“ fehlt.
4. Stationsausstattung: nur B+R, P+R und Barrierefreiheit, weil mehr nicht in den Daten steht.
5. Inline-Zeile der Amortisation: unverändert (Prozent); die Widersprüche zwischen `DESIGN_FINAL_SYNTHESIS.md` §9.10 und `DESIGN.md` §5.9
   sind nicht entschieden.
6. WC in der Planner-Ansicht: `OEBB_LIVE.md` §C3.4 ordnet `OC` dem Rollstuhl-Symbol zu (Goldens in `Fixtures/OEBB/ux`). Das
   Widget zeigt `OC` und `OG` als WC (`WidgetCacheBuilder.trainEquipment`). Die Planner-Chips sind unverändert, weil die
   Spezifikation und die Goldens sie festlegen. Ändern müsste man beides zusammen.

## 9. Nicht gebaut

- Watch-Komplikationen: kein watchOS-Target im Projekt.
- Stationsausstattung Aufzug und WC: Pipeline-Erweiterung, eigenes Paket.
- Via-Favoriten in „Nächste Verbindung“: werden nicht abgefragt (der Cache hätte die Zwischenhalte nicht).
