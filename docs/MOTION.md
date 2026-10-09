# KlimaBilanz – Motion System

> Bewegung ist Teil des Designs, kein Effekt obendrauf. Jede Animation erklärt etwas: woher etwas kommt, was sich
> geändert hat, dass etwas geklappt hat. **Physisch, schnell, zielgerichtet – nie verspielt oder langsam.**

Code: `Shared/Motion/MotionTokens.swift` (Tokens, auch für Widgets) und `App/Sources/DesignSystem/Motion/*.swift`
(Modifier, Komponenten, Haptik, Tipps). Galerie: CI-Screenshot-Routen `motionGallery`, `motionGallery2`, `motionGallery3`
(nur Debug-Builds, `MotionGalleryView`). Ergänzt `docs/DESIGN.md` §6.

## 1. Prinzipien

1. **Folgt dem Finger.** Was berührt wird, reagiert sofort (`Motion.press` ≤ 0,18 s) und federt zurück (`Motion.release`).
2. **Erklärt Herkunft.** Details wachsen aus der Karte, die sie geöffnet hat (Zoom), Glas verschmilzt statt zu springen,
   Auswahl-Kapseln gleiten.
3. **Zahlen leben.** Jede Zahl, die sich ändert, rollt (`.numericValue`); Hero-Werte zählen beim ersten Erscheinen einmal hoch.
4. **Einmal, nicht immer.** Eintritte (Reveal, Count-in) laufen nur beim ersten Erscheinen eines Screens – nie bei
   Aktualisierung, Tab-Wechsel oder Zurück-Scrollen.
5. **Bestätigung ist spürbar.** Erfolg = Haptik + kurzer Pop, nicht mehr. Feiern nur bei echten Meilensteinen.
6. **Immer abschaltbar.** Reduce Motion → Überblendungen statt Bewegung. Screenshot-Modus → sofort Endzustand.
7. **120 Hz oder gar nicht.** Nur Transformationen und Deckkraft animieren; kein Layout, keine Unschärfe über großen Flächen.

## 2. Tokens (`Motion`)

| Token | Wert | Wofür |
|---|---|---|
| `Motion.snappy` | spring 0,30 s · bounce 0,12 | alles, was der Finger direkt auslöst: Tippen, Toggles, Chips, Segmente, kleine Zustandswechsel |
| `Motion.smooth` | spring 0,42 s · bounce 0 | Layout-Änderungen, Karten auf-/zuklappen, Glas-Morph, Inhalt tauschen |
| `Motion.bouncy` | spring 0,50 s · bounce 0,32 | spürbare Bestätigung: Tausch-Knopf, Favorit-Stern, „Fahrt erfasst“-Pop. **Sparsam.** |
| `Motion.gentle` | spring 0,80 s · bounce 0,06 | große, ruhige Bewegungen: Hero-Zahl, Charts, Hintergrund |
| `Motion.reveal` | spring 0,55 s · bounce 0,12 | Eintritt beim ersten Erscheinen (gestaffelt) |
| `Motion.number` | spring 0,50 s · bounce 0,10 | Ziffern-Rollen (`.numericText`) |
| `Motion.countIn` | ease-out-expo 1,1 s | Hero-Wert zählt einmal hoch |
| `Motion.press` / `.release` | 0,18 s / 0,36 s · bounce 0,28 | Finger runter / Finger hoch |
| `Motion.crossfade` | easeInOut 0,22 s | Ersatz für jede Feder bei Reduce Motion |
| `Motion.Springs.*` | dieselben Federn als `Spring` | `SpringKeyframe(…, spring: Motion.Springs.bouncy)` |

Dauern (`Motion.Duration`): `instant` 0,12 · `quick` 0,22 · `standard` 0,35 · `slow` 0,6 · `countIn` 1,1 ·
`celebration` 1,4 (Obergrenze für jede Feier). **Nichts, worauf die Nutzerin warten muss, dauert länger als 0,5 s.**

Distanzen (`Motion.Distance`): Reveal 14 pt + 97 %; Fokus 8 pt Blur + 92 % (nur Hero/kurze Überschriften);
Drücken 95 % (Buttons, Chips) bzw. 98 % (Karten, Zeilen).

## 3. Policy – jede Animation läuft durch einen Wrapper

```swift
withMotion(Motion.bouncy) { isFavorite.toggle() }          // statt withAnimation
withMotion(Motion.smooth) { expand() } completion: { … }
view.motionAnimation(Motion.smooth, value: total)          // statt .animation(_:value:)
view.motionTransition(.rise)                                // statt .transition(_:), Reduce Motion → .opacity
MotionPolicy.isStatic                                       // CI-Screenshots: Endzustand sofort
MotionPolicy.animation(Motion.snappy)                       // → Animation? (nil / crossfade / spring)
```

Übergänge (`AnyTransition`): `.rise` (Zeilen, Karten, Inline-Abschnitte), `.pop` (Badges, Häkchen), `.lift` (von unten:
Leisten, Banner), `.drop` (von oben: Toasts). Für Inhaltswechsel an Ort und Stelle: `.blurReplace` (System) – nur bei
kleinen Elementen.

## 4. Eintritt: Reveal & Stagger

```swift
ScrollView {
    VStack(spacing: 12) {
        HeroView().reveal(.focus)
        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
            CardView(card).reveal(order: index + 1)
        }
    }
}
.revealScope()   // ein Eintritt pro Screen
```

- Stile: `.rise` (Standard: Karten, Zeilen, Abschnitte), `.focus` (Hero-Zahl, kurze Überschrift – Blur nur hier),
  `.pop` (Badges, Chips), `.fade` (dichte Inhalte, Charts).
- **Stagger-Regeln:** 45 ms Versatz (`Motion.Stagger.step`), ab dem 9. Element kein weiterer Versatz (`maxSteps` 8) – der
  ganze Eintritt ist nach < 0,9 s vorbei. Reihenfolge = Lesereihenfolge (oben → unten, links → rechts). Pro Screen
  höchstens **ein** gestaffelter Block; Listen mit vielen Zeilen staffeln nur die ersten sichtbaren.
- `revealScope()` auf den Screen (ScrollView oder Wurzel): Was später als `Motion.Stagger.window` (0,9 s) nach dem ersten
  Erscheinen dazukommt (nachgeladene Daten, hineingescrollte Zeilen, recycelte `List`-Zellen), erscheint sofort.
- Nie auf Elementen, die bei jeder Aktualisierung neu erzeugt werden (`.id(UUID())`) – sonst blinkt es.
- Reduce Motion: nur Einblenden. Screenshot-Modus: sofort sichtbar.

## 5. Zahlen

```swift
Text(Format.euro(total)).font(Theme.Typography.numberMedium).numericValue(total)       // jede Änderung rollt
CountUpText(value: summary.totalValue) { Format.euro($0) }.font(Theme.Typography.priceNumeral)  // Hero: zählt 1× hoch
CountUpText(value: 77, from: 73) { "\(Int($0)) %" }                                     // „73 → 77 %“
```

- Schrift immer `monospacedDigit()` (Theme-Zahlen-Fonts sind es schon), sonst springt die Breite.
- `numericValue(_, countsDown: true)` für Countdowns („noch 142 Tage“).
- `CountUpText`: VoiceOver liest immer den Endwert; das Format läuft pro Frame → nur `Format.*` (gecachte Styles).
- Hero-Count-in nur für **den einen** Hauptwert eines Screens (Übersicht: %, Ticket: Tage, Statistik: Ersparnis).

## 6. Haptik-Vokabular (`Haptic`, `.haptic(_:trigger:)`)

| Haptic | Bedeutung | Beispiele |
|---|---|---|
| `.success` | gespeichert / erfasst | Fahrt gespeichert, Favorit 1-Tap erfasst, Import fertig |
| `.warning` | etwas wird entfernt | Fahrt gelöscht, „Alles löschen“ bestätigt |
| `.error` | fehlgeschlagen | Speichern/Anmelden fehlgeschlagen |
| `.selection` | Wert gewählt | Segment, Chip, Verkehrsmittel, Ticketjahr, Picker |
| `.tap` | leichter Tipp | Knopf-Druck (`.pressable(haptic: true)`), Karte drehen, Tauschen, Auf-/Zuklappen |
| `.snap` | rastet ein | Karussell landet, Drag abgelegt, wichtiger Toggle |
| `.increase` / `.decrease` | Wert hoch / runter | Stepper, Mitfahrende, Preis anpassen |
| `.milestone` | Schwelle überschritten | 25/50/75 %, Break-even, neuer Erfolg |
| `.start` / `.stop` | Vorgang beginnt / endet | Live-Fahrt, Fahrterkennung |

```swift
.haptic(.success, trigger: savedCount)
.haptic(.milestone, trigger: summary.isPaidOff, when: { old, new in !old && new })
```

Alle folgen Einstellungen › Haptik (`AppSettings.hapticsEnabled`) und schweigen im Screenshot-Modus. **Eine Haptik pro
Aktion** – nie Haptik + Toast-Haptik doppelt (der globale Toast spielt `.success` schon selbst).

## 7. Drücken & Symbole

```swift
Button { … } label: { ChipLabel() }.buttonStyle(.pressable)              // 95 %
NavigationLink(value: trip) { TripRow(trip: trip) }.buttonStyle(.pressableCard)  // 98 %
Button { … } label: { … }.buttonStyle(.pressable(scale: 0.9, haptic: true))
Image(systemName: isFav ? "star.fill" : "star").symbolReplaceTransition().symbolBounce(on: isFav)
```

- `.symbolBounce(on:)` bei Tipp-Bestätigung; `.symbolReplaceTransition()` bei Zustandswechsel (play/pause, star/star.fill,
  plus/xmark). `.wiggle` / `.breathe` nur für echte Aufmerksamkeit (neue Version, Fehler) und nie dauerhaft.
- Bestehende Styles bleiben: `.primary` (CTA, drückt schon), `.glass`/`.glassProminent` (System-Glas reagiert selbst).
  `.pressable` für eigene Labels (Chips, Kacheln, Karten, Icon-Knöpfe).

## 8. Glas, das verschmilzt

```swift
GlassMorphGroup(spacing: 14) { ns in
    HStack(spacing: 14) {
        if isExpanded { actionButtons.morphingGlass(in: .circle, id: "a", namespace: ns) }
        mainButton.morphingGlass(.regular.tint(Theme.accent).interactive(), in: .circle, id: "main", namespace: ns)
    }
}
GlassSegmentedPicker(selection: $range, options: ["Woche", "Monat", "Jahr"]) { Text($0) }   // Kapsel gleitet, Haptik
segmentButton.unitedGlass(in: .capsule, union: "range", namespace: ns)                    // mehrere Knöpfe, eine Glasform
```

- Morph immer innerhalb **eines** `GlassEffectContainer`, mit stabilen IDs, ausgelöst über `withMotion(Motion.bouncy/.smooth)`.
- Container-`spacing` ≥ Stack-Spacing: Formen verschmelzen nur beim Animieren, ruhen getrennt.
- Glas nur für Bedienelemente (DESIGN.md §2). Auswahl-Kapsel im Segment ist **kein** Glas (nie Glas auf Glas).

## 9. Zoom-Navigation

```swift
NavigationStack { TripsList() }.zoomTransitionScope()
NavigationLink(value: trip) { TripRow(trip: trip) }.zoomSource(id: trip.id, cornerRadius: Theme.Radius.tile)
.navigationDestination(for: TripEntity.self) { TripDetailView(trip: $0).zoomDestination(id: $0.id) }
```

- Für jeden Weg Karte/Zeile → Detail (Fahrt, Erfolg, Ticket-Detail, Favorit) und für Sheets, die aus einem Knopf kommen
  (`.zoomSource` auf dem Knopf, `.zoomDestination` auf dem Sheet-Inhalt).
- `cornerRadius` = Radius der Quelle, sonst springt die Ecke. Ohne `zoomTransitionScope` tun beide Modifier nichts.
- Reduce Motion: Standard-Push/-Sheet.

## 10. Scrollen

```swift
card.scrollCardTransition()                     // Karten setzen sich beim Hereinscrollen von unten (95 % → 100 %)
ScrollView(.horizontal) { LazyHStack { ForEach(…) { $0.carouselItem() } }.scrollTargetLayout() }
    .carouselScrolling()                         // einrasten, 16-pt-Rand, Schatten nicht abgeschnitten

@State private var condense = ScrollCondense()
ScrollView { hero.heroCondense(condense) … }.tracksScrollCondense(condense, distance: 180)
CompactTitle(condense: condense)                // liest condense.value – nur diese View rendert beim Scrollen neu
.scrollEdgeEffectStyle(.soft, for: .top)        // weiche Kante unter der Navigationsleiste
```

- Scroll-Effekte sind Render-Transformationen (`scrollTransition`, `visualEffect`) – keine State-Änderung pro Frame.
- `ScrollCondense` ist quantisiert (1/48) und geklemmt: über der Distanz kommen keine Updates mehr. Der Wert wird nur in
  kleinen Unter-Views gelesen, nie im `body` des ganzen Screens.
- Kein animierter Blur auf großen Flächen während des Scrollens; keine `scrollCardTransition` in `List` (Zellen recyceln).

## 11. Feiern

```swift
medal.celebrate(trigger: achievement.isUnlocked)          // Pop + Wackeln + Anheben + Lichtblitz, ~0,6 s, .milestone-Haptik
medal.celebrationRing(trigger: count, color: Theme.gold)   // Ring dehnt sich aus und verblasst
star.celebrationBurst(trigger: favoriteCount)              // 12 Punkte fliegen aus der Mitte
BreakEvenCelebration(…)                                    // Vollbild „Rentiert!“ (Tippen schließt)
```

- Nur echte Meilensteine: Break-even, 25/50/75 %, neuer Erfolg, erste Fahrt. Nie für Routine-Aktionen.
- Kurz (≤ `Motion.Duration.celebration`), nie blockierend, jederzeit wegtippbar. Reduce Motion: nur Lichtblitz/Haptik,
  kein Konfetti, kein Ring.

## 12. Dauerbewegung (nur wenn sichtbar)

```swift
Image(systemName: "dot.radiowaves.left.and.right").breathing()   // Live-Fahrt, Erkennung aktiv
climberDot.pulsingHalo(Theme.dusk)                                 // „du bist hier“, Kletterer auf der Route
ContinuousMotionReader { isRunning in icon.symbolEffect(.variableColor, isActive: isRunning) }
```

Endlose Effekte laufen nur, solange man sie sieht: auf dem Bildschirm (auch in Scroll-Views,
`onScrollVisibilityChange`), Szene aktiv, kein App-Sheet darüber (`ambientSkyPaused`), kein Reduce Motion, kein
Stromsparmodus, nie in Screenshots. **Nie `repeatForever` direkt** – immer über `ContinuousMotionReader`.

## 13. Tipps (TipKit, `KBTips`)

```swift
TipView(KBTips.TripSwipe()).kbTipStyle()        // inline, über der Liste, die er erklärt
chip.popoverTip(KBTips.QuickLog())              // am Bedienelement
KBTips.used(KBTips.TripSwipe())                 // Geste ausgeführt → nie wieder zeigen
```

Katalog: `QuickLog` (Favorit = 1 Tipp, lang drücken), `TripSwipe` (Wischen in Fahrten), `SwapStations` (Von/Nach tauschen),
`ChartScrub` (über die Grafik fahren), `TicketFlip` (Ticket umdrehen), `LongPress` (Vorschau + Aktionen). Konfiguriert
einmal pro Start in `RootView` (`KBTips.configure()`, stündlich höchstens ein neuer Tipp, jeder max. 2–3 ×), nie in
Screenshot-/Perf-Läufen. Tipps nur für **versteckte** Gesten – was sichtbar beschriftet ist, braucht keinen Tipp.

## 14. Reduce Motion & Reduce Transparency

| Muster | Normal | Reduce Motion |
|---|---|---|
| Reveal | Feder, Versatz, Skalierung | nur Einblenden |
| Zahlen | Ziffern rollen, Count-in | Überblendung, Endwert sofort |
| Drücken | 95/98 % | leichtes Abdunkeln |
| Zoom | System-Zoom | Standard-Push/-Sheet |
| Scroll-Karten / Karussell / Hero | Skalierung + Versatz | nur Deckkraft |
| Feiern | Pop, Ring, Burst | Lichtblitz + Haptik |
| Symbole | bounce / replace | `symbolEffectsRemoved` |
| Dauerbewegung (breathing, Halo) | läuft, solange sichtbar | aus |

Reduce Transparency: Karten werden opak (`FrostedCardModifier` erledigt das), Glas regelt das System. Animationen ändern
daran nichts – keine Animation darf Deckkraft als einzigen Bedeutungsträger nutzen.

## 15. Performance-Regeln

- Nur `scaleEffect`, `offset`, `rotationEffect`, `opacity` animieren. Kein `frame`/`padding` in Animationen auf Listen.
- Kein `repeatForever`/endlose `PhaseAnimator` off-screen oder unter Sheets: endlose Effekte nur über
  `ContinuousMotionReader` / `.breathing()` / `.pulsingHalo()` (§12).
- Keine Formatter/Sortierung im `body`; `CountUpText`-Formate sind `Format.*` (gecacht).
- Max. eine animierte Ebene pro Screen (der Himmel); Charts zeichnen einmal (`Motion.gentle`).
- Blur nur auf kleinen Elementen (`.focus`-Reveal), nie animiert über Karten während des Scrollens.

## 16. Screen-Checkliste

1. `revealScope()` auf den Screen, `reveal(order:)` auf die Blöcke in Lesereihenfolge.
2. Hauptwert: `CountUpText`; alle anderen Zahlen: `.numericValue`.
3. Karten/Zeilen, die etwas öffnen: `.buttonStyle(.pressableCard)` + `zoomSource`/`zoomDestination`.
4. Auswahl: `GlassSegmentedPicker` oder Chips mit `.haptic(.selection, …)`.
5. Speichern/Löschen: `.haptic(.success/.warning, …)` + Toast; Meilensteine: `.celebrate`.
6. Versteckte Gesten: passender `KBTips`-Tipp, nach Nutzung `KBTips.used`.
7. Screenshot hell + dunkel ansehen, einmal mit Reduce Motion durchtippen.
