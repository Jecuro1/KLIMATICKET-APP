# KlimaBilanz · Look & Feel (Farbe, Bewegung, Haptik, Zahlen)

Einstellungen › Darstellung › **Look & Feel**. Du wählst die Akzentfarbe der ganzen App (sechs Paletten, auf Lesbarkeit getestet), wie
stark sich die App bewegt, wie stark sie vibriert, und ein paar Regeln für Zahlen (Beträge mit oder ohne Cent, Wochenstart, CO₂-Einheit).
App-Symbol und Palette schlagen sich gegenseitig vor. Kein Netz, keine Berechtigung, kein Datenmodell: alles steht in einem JSON-Wert
`theme.v1` in der App Group.

Nicht gebaut (bewusst): eine Dichte-Option (`Theme.Spacing` ist überall), andere Einheiten als km und €, neue Symbol-Grafiken, eigene
Himmel je Theme (STRETCH, gestrichen), Wechsel ohne Schließen der Einstellungen (STRETCH, gestrichen).

## 1. Code

| Ort | Inhalt |
|---|---|
| `Packages/KlimaCore/Sources/KlimaCore/Appearance/ThemePalette.swift` | die sechs Paletten als Hex-Werte (hell, dunkel), Tokens, Farben mit Bedeutung |
| `…/Appearance/ThemeContrast.swift` | WCAG-Kontrast, Kartenflächen, die Kontrast-Schranken je Palette, `shippable` |
| `…/Appearance/MotionLevel.swift` | Bewegung Voll · Ruhig · Aus und was davon mit „Bewegung reduzieren“ bleibt (`MotionBehavior`) |
| `…/Appearance/HapticLevel.swift` | Haptik Aus · Dezent · Voll, die Tabelle `HapticTable` über jedes `Haptic`, Migration des alten Schalters |
| `…/Appearance/FormatPrefs.swift` | Beträge, Wochenstart, CO₂-Einheit, die Beispielzeilen (`AppearanceFormat`) |
| `…/Appearance/AppearancePrefs.swift` | `theme.v1`: Version, Palette, Bewegung, Haptik, Zahlen; tolerant beim Lesen |
| `…/Appearance/AppearancePairing.swift` | App-Symbol ↔ Palette |
| `Tests/KlimaCoreTests/Appearance/` | 34 Linux-Tests (`swift test --filter Appearance`) |
| `Shared/ThemePalettes.swift` | `ThemeColorSet`: die Farben einer Palette, einmal gebaut |
| `Shared/ThemeRuntime.swift` | welche Palette `Theme.accent` & Co. gerade lesen; Widgets lesen `theme.v1` |
| `App/Sources/Features/Appearance/AppearanceStore.swift` | Auswahl speichern, beim Schließen anwenden, `-KBTheme`, Szenen |
| `…/AppearanceRuntime.swift` | Bewegung und Zahlen für `Format`, `MotionPolicy`, Himmel, Hochzählen, Neigung, Wochen-Kalender |
| `…/AppearanceSwitchHost.swift` | der eine Moment des Wechsels (nach dem Schließen der Einstellungen) |
| `…/AppearanceHaptics.swift` | `Haptic` → Tabelle → `SensoryFeedback` |
| `…/AppearanceView.swift`, `AppearanceStage.swift`, `AppearancePaletteGrid.swift`, `AppearanceChoice.swift` | die Seite |
| `…/AppearanceEntryViews.swift` | Zeile in den Einstellungen, Vorschläge Symbol ↔ Palette |
| `…/AppearanceScreenshotHost.swift` | CI-Szenen |

Haken in fremden Dateien, alle mit `MARK: themes`: `Shared/Theme.swift` (sechs Tokens), `MotionPolicy.swift`, `Haptics.swift`,
`Components.swift` (Toast-Haptik), `Backgrounds.swift` (Himmel), `NumericMotion.swift` (Hochzählen), `MotionTilt.swift` (Neigung),
`ScrollMotion.swift` (schrumpfender Titel), `SummitChart.swift` (die Route des Gipfel-Diagramms zeichnet die Routen-Stopps der
Palette), `AmortizationHero.swift` (der Betrag im Urteil: Gletscher behält seinen Verlauf, andere Paletten zeigen `accentText`),
`Format.swift` (`euro`, `kg`), `DashSupport.swift` und `DashInsights.swift` (Woche),
`StatsCalc.swift`, `StatsCalendarCard.swift`, `StatsDistributionCards.swift` (Wochenstart), die Auswahl-Ticks in Statistik, Ticket,
Vorteilen und Fahrt-Editor (`selectionHapticsEnabled`), `AppState.swift` (`AppSettings.look`), `RootView.swift` (Id, Szenen),
`SetPreferencesSections.swift` (Zeile), `AppIconPickerView.swift` (Vorschlag).

## 2. Paletten

| Palette | Idee | accent hell / dunkel | accentText hell / dunkel |
|---|---|---|---|
| Gletscher (Standard) | Klares Eis – das Original | `#2A7BD4` / `#7CC4FF` | `#1D5FB0` / `#9DD3FF` |
| Zirbe | Waldgrün, Bergsee und Lärchengold | `#24804F` / `#6FD39A` | `#196B40` / `#8FE0B2` |
| Morgenrot | Warmes Licht über dem Grat | `#CC5A1E` / `#FFA772` | `#A8461A` / `#FFB98F` |
| Dämmerung | Blaue Stunde in Violett | `#6B5FD9` / `#A99FFF` | `#5446C2` / `#C2BAFF` |
| Alpenglühen | Rosé, wenn die Gipfel glühen | `#CF4F79` / `#FF8FAB` | `#B23A63` / `#FFADC2` |
| Graphit | Ruhiges Schiefergrau | `#4A5A72` / `#B8C4D6` | `#3B4A60` / `#CBD5E3` |

Eine Palette ändert genau sechs Tokens: `accent`, `accentText`, `prominentTint`, `routeGradient` (= `progressGradient`, drei Stopps bei
0 / 55 / 100 %) und `ctaGradient`. Alles andere in `Theme.swift` bleibt `static let`. Zwei Stellen zeichnen die Route mit eigenen Werten und folgen der Palette über
einen Haken: das Gipfel-Diagramm der Übersicht (`ThemeColorSet.routeLight` / `routeDark`) und der Betrag im Urteil des Heros. **Farben mit Bedeutung ändern sich nie**: `positive`
(Zirbe-Grün, Gewinn, CO₂), `negative` (Rot), `summit` (Orange, Gipfel), `live` (Echtzeit-Grün) – ein Test liest `Theme.swift` und
prüft, dass keine davon über die Laufzeit gelesen wird. Die Verkehrsmittel-Farben bleiben ebenfalls. `Theme.glacier` ist die Marken-
farbe und bleibt; Gletscher reicht genau diese Instanz als `accent` weiter.

Keine Palette übernimmt die Markenfarben der ÖBB oder eines anderen Verkehrsunternehmens.

**Ein Farbwert pro Palette und Token.** `ThemeRuntime` baut jede Palette einmal (`ThemeColorSet`, eine Klasse) und gibt immer dieselben
Instanzen heraus: Zwei Lesezugriffe auf `Theme.accent` sind gleich, Zeilen rendern nicht neu, nur weil eine Farbe frisch gebaut wurde.
Der Zugriff geht über ein `NSLock` (Widgets und Formatierer lesen auch abseits des Main Actor).

## 3. Kontrast-Schranken

Jede Palette muss jede Schranke bestehen, sonst bietet die Seite sie nicht an (`ThemeContrast.shippable`; heute alle sechs):

- `accentText` ≥ 4,5 : 1 auf der hellen Karte (Weiß 77 % über `#E6ECF3`), der dunklen Karte (Weiß 7 % über `#08132A`) und auf
  `background` / `sheetBackground` beider Erscheinungen (6 Schranken),
- `accent` ≥ 3 : 1 auf beiden Karten (Symbole, Schalter, Ringe),
- Weiß auf `prominentTint` ≥ 3 : 1 (hell und dunkel) und auf jedem CTA-Stopp (fette Beschriftung).

13 Schranken je Palette, gerechnet nach WCAG 2.x (sRGB, Alpha über dem Untergrund verrechnet). Ein Test baut absichtlich eine blasse
Palette und erwartet, dass alle 13 scheitern. „Kontrast erhöhen“ von iOS bleibt wirksam: die Seite ändert keine System-Einstellung, und
die festen Texttoken (`textPrimary` usw.) gehören keiner Palette.

## 4. Wann der Wechsel passiert

Die Auswahl wird sofort gespeichert. **Haptik** wirkt sofort (du spürst die Stufe, die du antippst). **Farbe, Bewegung und Zahlen**
erreichen die App, wenn die Einstellungen geschlossen sind: `AppearanceSwitchHost` wartet das Schließen ab (0,45 s), dann schaltet
`AppearanceStore.applyPending()` die Laufzeiten um, erhöht `revision`, und `RootView` gibt `MainTabView` diese Id – jeder Tab wird unter
einer Überblendung (`Motion.smooth`) neu gebaut. So gibt es nie einen halb umgefärbten Bildschirm. Die Seite selbst zeigt die Wahl
sofort in ihrer Vorschau und sagt „Farbe, Bewegung und Zahlen wechseln, sobald du die Einstellungen schließt.“

Der Preis des Neubaus: Navigationspfade und Scrollpositionen in den Tabs beginnen neu (der gewählte Tab bleibt). Das passiert nur, wenn
sich Farbe, Bewegung oder Zahlen wirklich geändert haben.

**Sicherheitsnetz (Schritt 0).** Bevor es Paletten gab, lasen die sechs Tokens schon über `ThemeRuntime`, nur mit Gletscher. Vergleich mit
dem Lauf davor (gleiche Szenen `dashboard`, `trips`, `stats`, `ticket`, `settings`, `hero`, hell und dunkel): 7 von 12 Bildern
pixelgleich, die übrigen mit höchstens 3 von 255 Kanalstufen Abweichung (Rendering-Rauschen, nichts verschoben). Die Perf-Läufe stehen
in §9.

## 5. Bewegung

| Stufe | Was läuft |
|---|---|
| Voll (Standard) | alles wie in `docs/MOTION.md` |
| Ruhig | Übergänge bleiben; still stehen: Himmel-Drift und Sterne, Hochzählen der Hero-Zahlen, Neigungs-Parallaxe (Ticket), schrumpfender Hero beim Scrollen |
| Aus | `MotionPolicy.isStatic`: jede Animation der App beginnt im Endzustand (wie im Screenshot-Modus). Übergänge von iOS selbst (Sheets, Navigation) bleiben – das sagt der Text unter der Auswahl |

„Bewegung reduzieren“ von iOS gewinnt immer: keine Stufe bringt zurück, was es wegnimmt (Test `testSystemReduceMotionAlwaysWins`).
Die Haptik hängt nicht an der Bewegung: Screenshot-Läufe schweigen (`MotionPolicy.isScreenshot`), „Aus“ bei Bewegung nicht.

## 6. Haptik

`HapticTable` ordnet jedem `Haptic`-Fall (11, ein Test liest `Haptics.swift`) zu, was gespielt wird. **Voll** ist genau das bisherige
Verhalten (ein Test vergleicht mit `Haptic.feedback`). **Dezent** senkt jeden Stoß eine Stufe (`snap`: medium → light, `tap`: light 0,7 →
light 0,45) und lässt die Auswahl-Ticks weg; Bestätigungen, Warnungen, Fehler und Meilensteine bleiben. **Aus** spielt nichts.

Der alte Schalter „Haptisches Feedback“ (`hapticsEnabled` in den Standard-Defaults) wird beim ersten Laden übernommen: `false` → Aus,
`true` oder nie gesetzt → Voll. Ab dem ersten Speichern gilt `theme.v1`. `AppSettings.hapticsEnabled` bleibt als „nicht Aus“ für die
bestehenden Aufrufer; Auswahl-Ticks fragen `selectionHapticsEnabled` (nur bei Voll).

Auf der Seite spielt die Haptik-Auswahl einmal einen `snap` in der gewählten Stufe – die eine Haptik dieser Aktion.

## 7. Zahlen

| Option | Werte | Beispielzeile |
|---|---|---|
| Beträge | Automatisch (bisher: Cent unter € 1.000, wenn es Cent gibt) · Ganze Euro · Immer mit Cent | `€ 1.300 · € 23,40` · `€ 23,40 → € 23` · `€ 1.300 → € 1.300,00` |
| Woche beginnt am | Montag (Standard) · Sonntag | `Mo Di Mi Do Fr Sa So` · `So Mo Di Mi Do Fr Sa` |
| CO₂ | Automatisch (kg unter 1.000 kg, dann t) · Immer kg | `980 kg · 1,2 t` · `1,2 t → 1.240 kg` |

- Beträge betreffen `Format.euro(x)` ohne feste Nachkommastellen. Wer ausdrücklich 0 oder 2 Stellen verlangt (Tarifpreise, Fahrtpreis,
  `euroPrecise`, die gerundeten Wochen-Deltas), behält sie.
- „Automatisch“ bei CO₂ entscheidet nach den angezeigten, gerundeten Kilogramm: 999,9 kg heißt jetzt „1,0 t“, nicht mehr „1.000 kg“
  (die einzige Änderung gegenüber vorher, Test).
- Der Wochenstart gilt für die Wochen-Karte der Übersicht (`DashWeekStats`: welche Tage „diese Woche“ sind und die Reihenfolge der
  Balken), das Wochentags-Diagramm der Statistik (Reihenfolge) und die Zeilen des Reise-Kalenders. Widgets bleiben bei Montag.
- Negative Beträge: „-€ 23,40“ (Formatierer de-AT), Schwelle nach Betrag.

## 8. Speicher, Widgets, Launch-Argumente

`theme.v1` (App Group, `AppearancePrefs`, JSON mit sortierten Schlüsseln): `{"format":{"amounts":"auto","co2":"auto","weekStart":"monday"},
"haptics":"voll","motion":"voll","palette":"gletscher","version":1}`. Unlesbares, Unbekanntes oder Fehlendes wird Feld für Feld zum
Standard, nie zum Fehler. Screenshot- und Perf-Läufe speichern nichts.

Widgets und Live Activities zeichnen in einem eigenen Prozess: `ThemeRuntime` liest dort `theme.v1` (höchstens alle 2 s). Nach einem
Palettenwechsel bittet die App iOS um neue Timelines (`reloadAllTimelines`); wann iOS sie zeichnet, entscheidet iOS.

`-KBTheme <id>` (`gletscher`, `zirbe`, `morgenrot`, `daemmerung`, `alpengluehen`, `graphit`) wählt die Palette für einen Start, ohne zu
speichern. Das Screenshot-Skript gibt pro Szene keine eigenen Argumente mit; deshalb nennt jede Theme-Szene ihre Auswahl in
`AppearanceLaunch.screenshotPrefs` – mit derselben Wirkung.

**App-Symbol ↔ Palette** (`AppearancePairing`): Alpin → Gletscher, Nacht → Dämmerung, Sonnenaufgang → Morgenrot, Gletscher → Gletscher,
Minimal → Graphit; umgekehrt Zirbe → Alpin (kein grünes Symbol), Alpenglühen → Sonnenaufgang. Look & Feel zeigt „Passendes App-Symbol“,
die App-Symbol-Seite „Passendes Theme“; beides mit einem Knopf „Übernehmen“, nie automatisch.

## 9. Was geprüft ist – und was nicht

Geprüft (Linux): 34 Tests `swift test --filter Appearance` (Paletten vollständig, Kontrast, Bedeutungsfarben gleich, Bewegung gegen
„Bewegung reduzieren“, Haptik-Tabelle über jeden Fall und gleich `Haptic.feedback`, Zahlenbeispiele, Wochenstart 25./26.10.2026,
Paarung vollständig, Migration, tolerantes Lesen). Typecheck App und Widgets.

Geprüft (CI, Simulator): Screenshots der Szenen `themeSettings`, `themeGallery`, `themeOptions`, `themeAX5`, `themeDash`, `themeStats`,
`themeStatsFormat`, `themeTicket`, `themeSettingsRow`, `themeIcon`, hell und dunkel; Pixelvergleich Gletscher vorher / nachher (§4).

Nur auf einem echten iPhone prüfbar:

1. Palette wechseln, Einstellungen schließen: Überblendung ohne Aufblitzen, kein unerwarteter Zustandsverlust (Navigationspfade in
   den Tabs beginnen bewusst neu).
2. Ein Widget nach dem nächsten Neuzeichnen in der neuen Farbe (Home-Bildschirm, Sperrbildschirm, Live Activity).
3. Haptik Dezent und Voll fühlbar verschieden; Auswahl-Ticks bei Dezent weg.
4. Bewegung Ruhig: Himmel steht, Ticket neigt sich nicht; Aus: nichts animiert außer iOS-Übergängen.
5. „Kontrast erhöhen“ mit jeder Palette; Bildlauf bei 120 Hz ohne Ruckeln.
