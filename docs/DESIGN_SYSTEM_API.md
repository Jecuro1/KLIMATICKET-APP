# KlimaBilanz Design System – SwiftUI API

Alle Feature-Module bauen ausschließlich auf diesen Tokens und Komponenten auf.
Tokens: `Shared/Theme.swift` (auch in Widgets nutzbar). Komponenten: `App/Sources/DesignSystem/`.

## Tokens (`Theme`)

| Token | Verwendung |
|---|---|
| `Theme.glacier/.glacier2/.dawn/.dawn2/.alpenglow/.pine/.dusk/.gold` | Alpine-Palette (siehe DESIGN.md §3) |
| `Theme.accent` (= glacier), `Theme.accentSecondary` (= dusk), `Theme.onAccent` | Marke, aktive Elemente, Text auf Akzent |
| `Theme.routeGradient`, `Theme.ctaGradient` | Route/Fortschritt (glacier→dusk→dawn), primärer Button |
| `Theme.sheetBackground` | ruhige Fläche für Sheets/Formulare |
| `Theme.background`, `Theme.surface`, `Theme.surfaceSecondary`, `Theme.separator` | Flächen |
| `Theme.textPrimary/.textSecondary/.textTertiary` | Text |
| `Theme.positive` | Wert, Ersparnis, „rentiert“ |
| `Theme.remaining` / `Theme.summit` | noch offen bis Break-even, Gipfel/Ziel-Marker |
| `Theme.negative`, `Theme.eco` | Verlust/Fehler, CO₂ |
| `Theme.positiveText`, `Theme.summitText`, `Theme.accentText` | **Kontrast-sichere Varianten (≥ 4,5:1) für kleinen Text** – Akzentfarben sonst nur als Flächen oder große Schrift |
| `Theme.progressGradient` | = routeGradient |
| `Theme.modeColor(_ mode: TransportMode) -> Color` | Farbe je Verkehrsmittel |
| `Theme.tierGradient(_ tier: Achievement.Tier) -> LinearGradient` | Erfolge |
| `Theme.celebrationColors: [Color]` | Konfetti |
| `Theme.Typography.hero/.heroTitle/.numberLarge/.numberMedium/.numberSmall/.title/.sectionTitle/.headline/.body/.caption/.kicker` | Schrift |
| `Theme.Spacing.xxs(4) xs(8) s(12) m(16) l(20) xl(28) xxl(40) screen(20) cardGutter(16)` | Abstände |
| `Theme.Radius.modeTile(12) chip(14) tile(20) formGroup(24) card(28) pass(30) sheet(38)` | Eckenradien (continuous) |
| `Theme.Typography.priceNumeral` | große Preis-/Tage-Zahl (46 Light Rounded) |

Farb-Helfer: `Color(hex:)`, `Color(light:dark:)` (Strings oder Colors).

## Container & Hintergrund

```swift
GlassCard(padding: CGFloat = 20, cornerRadius: CGFloat = 28, tint: Color? = nil, interactive: Bool = false) { content }
    // Frost-Karte (Material + spekularer Rand + Schatten) – Standard-Container für Inhalte über dem Himmel
view.frostedCard(cornerRadius: CGFloat = 28, tint: Color? = nil)   // dasselbe Rezept als Modifier
SurfaceCard(padding: CGFloat = 20, cornerRadius: CGFloat = 28) { content }   // ruhig/opak, für dichte Charts & Formulare
AmbientBackground(style: .standard | .onboarding, glow: Double = 0.7)   // Alpenhimmel (3×6 Mesh, Sonnen-Glühen, Sterne)
view.ambientBackground(.standard, glow: 0.7)                          // als Screen-Hintergrund
// Liquid Glass NUR für Bedienelemente: .glassEffect(...), .buttonStyle(.glass / .glassProminent), GlassEffectContainer
```

## Texte & Überschriften

```swift
Kicker(text: String, color: Color = Theme.textSecondary)            // "FREITAG, 9. OKTOBER"
SectionHeader(title: String, actionTitle: String? = nil, action: (() -> Void)? = nil)
```

## Kennzahlen

```swift
StatTile(value: String, unit: String? = nil, label: String, symbol: String, color: Color = Theme.accent)
ProgressRail(progress: Double, preview: Double? = nil, leadingLabel: String? = nil, trailingLabel: String? = nil,
             height: CGFloat = 10, fill: AnyShapeStyle = AnyShapeStyle(Theme.progressGradient))
```

## Fahrten & Verkehrsmittel

```swift
ModeIcon(mode: TransportMode, size: CGFloat = 40)
TripRow(trip: TripEntity, showsDate: Bool = true)
TripRow(fromName:toName:date:mode:distanceKm:value:isRoundTrip:showsDate:)
TripRow.short(_ name: String) -> String            // "Innsbruck Hauptbahnhof" → "Innsbruck Hbf"
RouteGlyph(color: Color = Theme.accent, endColor: Color = Theme.summit, height: CGFloat = 40)
```

## Bedienelemente

```swift
Chip(title: String, symbol: String? = nil, isSelected: Bool = false, tint: Color = Theme.accent, action: () -> Void)
Button("…") { }.buttonStyle(.primary)       // volle Breite, Marken-Verlauf
Button("…") { }.buttonStyle(.glass)         // iOS 26 Liquid Glass (sekundär)
Button("…") { }.buttonStyle(.glassProminent) // iOS 26 Liquid Glass (primär, klein)
AuthButtonStack(showsContinueWithoutAccount: Bool = false, onSignedIn: () -> Void = {}, onContinueWithoutAccount: () -> Void = {})
GoogleLogo(size:), MicrosoftLogo(size:)
```

## Zustände & Feedback

```swift
EmptyStateView(symbol: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil)
ToastOverlay()                                   // global in RootView, via app.showToast(symbol, title, subtitle)
ConfettiView(colors: [Color], count: Int = 90, duration: Double = 2.6)
BreakEvenCelebration(ticketName: String, profit: Double, onDismiss: () -> Void)
```

## Signatur-Komponenten

```swift
// Übersicht-Hero: riesige „73 %“, „€ 946 von € 1.400 amortisiert“ und die Gipfel-Grafik
AmortizationHero(snapshot: AnalyticsSnapshot, chartHeight: CGFloat = 250)

// Gipfel-Grafik allein (Ersparnis-Kurve klettert über den Bergkamm zum Break-even-Gipfel)
SummitChart(series: [CumulativePoint], forecast: [CumulativePoint], start: Date, end: Date, price: Double,
            breakEvenDate: Date?, isPaidOff: Bool, showsLabels: Bool = true)

// Ticket-Pass „Begleitkarte · kein Fahrschein“ (Mockup docs/design/final/04-ticket-*.jpg): Dämmerungs-Verlauf, Topo-Linien,
// Holo-Folie & Siegel (Neigung), Perforation mit Kerben, Stub mit Mini-Gipfel + „73 % amortisiert“ + „Original“-Knopf
TicketCard(title: String, subtitle: String /* Kicker, z. B. "Jahresticket · ganz Österreich" */, holder: String,
           validFrom: Date, validUntil: Date, ticketNumber: String, theme: TicketTheme,
           roll: Double = 0, pitch: Double = 0, hasPhoto: Bool = false,
           amortizedFraction: Double? = nil, valueText: String? = nil, onOriginal: (() -> Void)? = nil)
TicketTheme.allCases / .from(ticket.themeRaw) / .title / .colors / .ink   // twilight (Standard), aurora, alpenglow, glacier, signal, night
MiniSummit(progress: Double)   // kleiner Gipfel mit Route (66×44)

// Formen
RidgeShape(peakX:peakY:seed:roughness:), SmoothPath(points:), FlagShape()
```

## App-Symbol <!-- MARK: icons -->

```swift
AppIconChoice.allCases            // .alpin (primär) · .nacht · .sonnenaufgang · .gletscher · .minimal – title, subtitle, previewAsset
AppIconStore.shared.current       // das gerade aktive Home-Bildschirm-Symbol (@Observable); .select(_:completion:) wechselt es
AppIconImage(choice: AppIconChoice, size: CGFloat)   // Vorschau mit Home-Bildschirm-Form, hell/dunkel nach Umgebung
AppIconPickerView()               // Einstellungen › Darstellung › App-Symbol (Zeile: AppIconSettingsRow)
SetAppIconView(size:)             // aktives Symbol in Update-Sheet, „Über“, Updates
```

Artwork nur über `python3 scripts/render_app_icons.py` ändern (rendert alle `AppIcon*.appiconset` in hell/dunkel/getönt und die
`AppIconPreview-*.imageset`; `--check DIR` zeigt 60/40/29-px-Proben auf Home-Bildschirm-Hintergründen). Neue Alternative: im Skript
ergänzen, Name in `project.yml` (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`), in `.github/workflows/ios.yml` (Prüfung) und in
`AppIconChoice` eintragen.

## Bewegung

Vollständig in `docs/MOTION.md` (Tokens `Motion.*` in `Shared/Motion/`, Modifier in `App/Sources/DesignSystem/Motion/`).

```swift
withMotion(Motion.snappy / .smooth / .bouncy / .gentle) { … }      // Reduce-Motion- und Screenshot-fest
view.reveal(.rise | .focus | .pop | .fade, order: i)  ·  screen.revealScope()
Text(…).numericValue(value)  ·  CountUpText(value:from:delay:format:)
.buttonStyle(.pressable / .pressableCard / .pressable(scale:haptic:))
.haptic(.success | .warning | .error | .selection | .tap | .snap | .increase | .decrease | .milestone | .start | .stop, trigger:)
GlassMorphGroup { ns in … .morphingGlass(in:id:namespace:) }  ·  GlassSegmentedPicker(selection:options:label:)
.zoomTransitionScope()  ·  .zoomSource(id:cornerRadius:)  ·  .zoomDestination(id:)
.scrollCardTransition()  ·  .carouselScrolling()  ·  .carouselItem()  ·  ScrollCondense + .tracksScrollCondense / .heroCondense
.celebrate(trigger:)  ·  .celebrationRing(trigger:)  ·  .celebrationBurst(trigger:)
.symbolBounce(on:)  ·  .symbolReplaceTransition()  ·  .motionAnimation(_:value:)  ·  .motionTransition(.rise/.pop/.lift/.drop)
KBTips.QuickLog / TripSwipe / SwapStations / ChartScrub / TicketFlip / LongPress  ·  TipView(…).kbTipStyle()  ·  KBTips.used(_:)
@State private var tilt = MotionTilt()   // .roll / .pitch in −1…1; tilt.start() onAppear, tilt.stop() onDisappear
view.if(condition) { $0.modifier… }
```

## iOS-26-APIs, die im Projekt verwendet werden (geprüft)

- `.glassEffect(_ glass: Glass = .regular, in: some Shape)`; `Glass.regular / .clear / .identity`, `.tint(Color)`, `.interactive()`
- `GlassEffectContainer(spacing:) { … }`, `.glassEffectID(_:in:)` mit `@Namespace`
- `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`
- `Tab(_:systemImage:value:role:)`, `.tabBarMinimizeBehavior(.onScrollDown)`
- `MeshGradient(width:height:points:colors:smoothsColors:)`
- `.contentTransition(.numericText(value:))`, `.symbolEffect(.bounce, value:)`, `.sensoryFeedback(_:trigger:)`
- `.matchedTransitionSource(id:in:)` + `.navigationTransition(.zoom(sourceID:in:))`
- Swift Charts: `LineMark`, `AreaMark`, `BarMark`, `SectorMark(angle:innerRadius:angularInset:)`, `RuleMark`, `PointMark`, `.chartXSelection(value:)`
