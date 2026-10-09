# iOS 26 SwiftUI API cheat sheet (KlimaBilanz)

Verified 2026-10-09 against Apple's documentation JSON (`developer.apple.com/tutorials/data/documentation/<path>.json`, the same data that the
`developer.apple.com/documentation/<path>` pages render) and against the WWDC25 session "Code" tabs. Every signature below was copied from those
declarations. Raw dumps are in `research/apple_docs/*.txt` and `research/wwdc/code_2025_*.txt`.

Scope: deployment target **iOS 26.0**, built on GitHub Actions `macos-26` with **Xcode 26.6** (the runner default, which ships the **iOS 26.5 SDK**),
Swift 5 language mode.

---

## 0. Ground rules (read first)

1. **Apple's docs now show the iOS 27 SDK.** WWDC26 and Xcode 27 shipped in June and September 2026. The doc pages list iOS 27 APIs such as
   `TabRole.prominent`, `Query.sections`, `Schema.Attribute.Option.codable`, `toolbarMinimizationBehavior` and `ArrangementView`, and their
   declarations print `@ContentBuilder` in place of `@ViewBuilder`. That `@ContentBuilder` is an Xcode 27 change. On Xcode 26 the same closures
   are `@ViewBuilder`, and call sites are identical. **Check the "introduced" version of every API.** Anything marked 27.x does not exist in the
   Xcode 26.6 SDK and fails to compile.
2. **iOS 26.1+ APIs need `if #available(iOS 26.1, *)`**, because the deployment target is 26.0. Known cases:
   - `GlassButtonStyle.init(_ glass: Glass)`
   - `tabViewBottomAccessory(isEnabled:content:)`
3. **WWDC25 beta code does not always match the shipped API.** Verified differences:
   - `.rect(corner: .containerConcentric)` (beta) is now `.rect(corners: .concentric)` or `ConcentricRectangle()`.
   - `glassEffect(_:in:isEnabled:)` does not exist. The only form is `glassEffect(_:in:)`.
   - `AppIntent.openAppWhenRun` is deprecated in iOS 26 ("Please provide 'supportedModes' instead").
4. GitHub runner `macos-26` (image 20260907): Xcode 26.0.1, 26.1.1, 26.2, 26.3, 26.4.1, 26.5 and **26.6 (default)**. Xcode 27 is only a "public
   preview" there. Keep `xcode-select` on `Xcode_26*`. The current `ios.yml` already does this.
   Source: https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-26-arm64-Readme.md
5. **Do not add `.metal` files unless CI installs the Metal Toolchain.** In Xcode 26 the Metal compiler is a separately downloaded component, and
   builds fail with `error: cannot execute tool 'metal' due to missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain`.
   The runner README does not list it. See §4.10.

### Availability table (iOS)

| API | iOS | Doc path (prefix `https://developer.apple.com/documentation/`) |
|---|---|---|
| `glassEffect(_:in:)`, `Glass.regular/.clear/.identity`, `.tint(_:)`, `.interactive(_:)` | 26.0 | swiftui/view/glasseffect(_:in:), swiftui/glass |
| `GlassEffectContainer(spacing:content:)` | 26.0 | swiftui/glasseffectcontainer/init(spacing:content:) |
| `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)`, `glassEffectTransition(_:)` | 26.0 | swiftui/view/glasseffectid(_:in:) |
| `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`, `.glass(_ glass:)` static func | 26.0 | swiftui/primitivebuttonstyle/glass |
| `GlassButtonStyle(_ glass:)` initializer | **26.1** | swiftui/glassbuttonstyle/init(_:) |
| `ToolbarSpacer(_:placement:)`, `SpacerSizing.fixed/.flexible` | 26.0 | swiftui/toolbarspacer |
| `ToolbarContent.sharedBackgroundVisibility(_:)` | 26.0 | swiftui/toolbarcontent/sharedbackgroundvisibility(_:) |
| `ToolbarContent.matchedTransitionSource(id:in:)` | 26.0 | swiftui/toolbarcontent/matchedtransitionsource(id:in:) |
| `DefaultToolbarItem(kind:placement:)` | 26.0 | swiftui/defaulttoolbaritem/init(kind:placement:) |
| `tabBarMinimizeBehavior(_:)` (`.automatic/.never/.onScrollDown/.onScrollUp`) | 26.0 | swiftui/view/tabbarminimizebehavior(_:) |
| `tabViewBottomAccessory(content:)` | 26.0 (iOS only) | swiftui/view/tabviewbottomaccessory(content:) |
| `tabViewBottomAccessory(isEnabled:content:)` | **26.1** | swiftui/view/tabviewbottomaccessory(isenabled:content:) |
| `\.tabViewBottomAccessoryPlacement` (`.inline/.expanded`, optional) | 26.0 | swiftui/environmentvalues/tabviewbottomaccessoryplacement |
| `Tab(role: .search)`, `Tab(value:role:content:)` | 18.0 | swiftui/tab/init(role:content:) |
| `TabRole.prominent` | **27.0, do not use** | swiftui/tabrole/prominent |
| `tabViewSearchActivation(_:)`, `searchToolbarBehavior(.minimize)` | 26.0 | swiftui/view/searchtoolbarbehavior(_:) |
| `backgroundExtensionEffect()` | 26.0 | swiftui/view/backgroundextensioneffect() |
| `scrollEdgeEffectStyle(_:for:)` (`.automatic/.hard/.soft`), `scrollEdgeEffectHidden(_:for:)` | 26.0 | swiftui/view/scrolledgeeffectstyle(_:for:) |
| `safeAreaBar(edge:alignment:spacing:content:)` (VerticalEdge and HorizontalEdge overloads) | 26.0 | swiftui/view/safeareabar(edge:alignment:spacing:content:) |
| `ConcentricRectangle`, `.rect(corners: .concentric)`, `Edge.Corner.Style.concentric(minimum:)` | 26.0 | swiftui/concentricrectangle |
| `Button(role: .close/.confirm, action:)` | 26.0 | swiftui/buttonrole/close |
| `navigationSubtitle(_:)` | 26.0 on iOS | swiftui/view/navigationsubtitle(_:) |
| `ToolbarItemPlacement.largeSubtitle`, `listSectionMargins(_:_:)` | 26.0 | swiftui/toolbaritemplacement/largesubtitle |
| `Chart3D`, `SurfacePlot`, `chartZScale`, `chart3DPose` | 26.0 | charts/chart3d |
| `chartXSelection(value:)`, `chartScrollableAxes(_:)`, `chartXVisibleDomain(length:)` | 17.0 | swiftui/view/chartxselection(value:) |
| `MeshGradient(width:height:points:colors:background:smoothsColors:colorSpace:)` | 18.0 | swiftui/meshgradient |
| `.symbolEffect(.drawOn / .drawOff)` (`DrawOnSymbolEffect`), `symbolVariableValueMode(.draw)`, `symbolColorRenderingMode(.gradient)` | 26.0 | symbols/drawonsymboleffect |
| `.symbolEffect(.breathe / .wiggle / .rotate)` | 18.0 | symbols/wigglesymboleffect |
| `.symbolEffect(.bounce / .pulse)` | 17.0 | symbols/bouncesymboleffect |
| `SensoryFeedback.press(_:)`, `.release(_:)`, `.selection(_:)` (new parameterised forms) | 26.0 | swiftui/sensoryfeedback/press(_:) |
| `@Animatable` macro, `@AnimatableIgnored` | Xcode 26 macro (doc lists iOS 13+) | swiftui/animatable() |
| `AppIntent.supportedModes` / `IntentModes` / `continueInForeground(_:alwaysConfirm:)` | 26.0 | appintents/appintent/supportedmodes |
| `openAppWhenRun` | deprecated 26.0 | appintents/appintent/openappwhenrun |
| `WidgetConfiguration.pushHandler(_:)` | 26.0 | swiftui/widgetconfiguration/pushhandler(_:) |
| `\.levelOfDetail` | 26.0 on iOS | swiftui/environmentvalues/levelofdetail |
| `WebAuthenticationSession.authenticate(using:callback:preferredBrowserSession:additionalHeaderFields:)` | 17.4 | authenticationservices/webauthenticationsession/authenticate(using:callback:preferredbrowsersession:additionalheaderfields:) |
| `authenticate(using:callbackURLScheme:preferredBrowserSession:)` | 16.4, deprecated 27.2 | (same page family) |
| SwiftData `@Model` subclassing (inheritance) | 26.0 | WWDC25 session 291 |
| SwiftData `#Unique`, `#Index`, `ModelContainer(for:configurations: any DataStoreConfiguration...)` | 18.0 | swiftdata/unique(_:) |

---

## 1. Liquid Glass

### 1.1 `glassEffect` and `Glass`

Declarations:

```swift
// nonisolated func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View
// struct Glass: Equatable, Sendable
//   static var regular: Glass   static var clear: Glass   static var identity: Glass
//   func tint(_ color: Color?) -> Glass
//   func interactive(_ isEnabled: Bool = true) -> Glass
```

The default shape is a capsule (`DefaultGlassEffectShape`). `.identity` means "no glass". Use it to toggle the effect without changing view
identity, because `isEnabled:` does not exist.

```swift
Text("Hat sich's rentiert?")
    .font(.headline)
    .padding(.horizontal, 16).padding(.vertical, 10)
    .glassEffect()                                      // regular, capsule

Label("Ersparnis", systemImage: "eurosign.circle.fill")
    .padding()
    .glassEffect(in: .rect(cornerRadius: 16))           // custom shape

Image(systemName: "plus")
    .font(.title2.weight(.semibold))
    .frame(width: 56, height: 56)
    .glassEffect(.regular.tint(.green).interactive(), in: .circle)   // tinted + reacts to touch

// .clear: more transparent, for glass over photos or the mesh hero
HeroNumber().padding().glassEffect(.clear, in: .rect(cornerRadius: 28))

// Toggle the effect without an if/else, which would change view identity
Chip().glassEffect(isHighlighted ? .regular.tint(.accentColor) : .identity)
```

Apple guidance (doc article "Applying Liquid Glass to custom views" and WWDC25-323):
- Apply `glassEffect` **after** the other appearance modifiers. It captures the content above it.
- Use `.tint` only to convey meaning, such as a call to action.
- Add `.interactive()` to custom controls.
- Limit how many glass effects are on screen at once.
- Do not stack glass on glass. Toolbars, tab bars and sheets are already glass.

### 1.2 `GlassEffectContainer`, morphing, union

```swift
// @MainActor init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content)
// nonisolated func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View
// @MainActor func glassEffectUnion(id: (some Hashable & Sendable)?, namespace: Namespace.ID) -> some View
// @MainActor func glassEffectTransition(_ transition: GlassEffectTransition) -> some View   // .matchedGeometry (default) | .materialize | .identity
```

Morphing floating action cluster. The pattern is Apple's: the morph happens inside a container, under `withAnimation`, with stable IDs in one
namespace.

```swift
struct QuickActionCluster: View {
    @Namespace private var glassNS
    @State private var expanded = false

    var body: some View {
        GlassEffectContainer(spacing: 20) {          // > HStack spacing: shapes blend at rest; == spacing: they merge only while animating
            HStack(spacing: 20) {
                if expanded {
                    Button { /* Lieblingsfahrt */ } label: {
                        Image(systemName: "star.fill").frame(width: 48, height: 48)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("favorite", in: glassNS)

                    Button { /* Scan */ } label: {
                        Image(systemName: "qrcode.viewfinder").frame(width: 48, height: 48)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("scan", in: glassNS)
                }

                Button {
                    withAnimation(.bouncy) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "xmark" : "plus")
                        .font(.title2.weight(.semibold))
                        .frame(width: 56, height: 56)
                        .contentTransition(.symbolEffect(.replace))
                }
                .glassEffect(.regular.tint(.green).interactive(), in: .circle)
                .glassEffectID("main", in: glassNS)
            }
        }
    }
}
```

Union: several views share one glass shape at rest, for example a segmented "Woche | Monat | Jahr" pill built from separate buttons.

```swift
GlassEffectContainer(spacing: 8) {
    HStack(spacing: 8) {
        ForEach(Range.allCases) { r in
            Button(r.title) { range = r }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassEffect(range == r ? .regular.tint(.green) : .regular)
                .glassEffectUnion(id: "rangePicker", namespace: glassNS)
        }
    }
}
```

Use `.glassEffectTransition(.materialize)` for elements that appear far from their siblings (beyond the container spacing).

### 1.3 Buttons

```swift
Button("Fahrt erfassen") { }.buttonStyle(.glassProminent)  // filled, uses the accent / .tint()
Button("Mehr erfahren") { }.buttonStyle(.glass)
Button("Speichern") { }.buttonStyle(.glass(.regular.tint(.green)))  // static func glass(_:) is listed as iOS 26.0
// GlassButtonStyle(.clear) (the initializer) is iOS 26.1. Wrap it in if #available(iOS 26.1, *).

Button(role: .close) { dismiss() }    // iOS 26: system "X" button (role-only initializer: init(role:action:))
Button(role: .confirm) { save() }     // iOS 26: system checkmark / confirm

Button("…") { }.buttonBorderShape(.capsule).controlSize(.large)   // .controlSize(.extraLarge) also exists
```

Note: `.glassProminent` is declared `@MainActor`, while `.glass` is `nonisolated`. Both work in `body`.

### 1.4 Toolbars

```swift
@Namespace private var ns
@State private var showAdd = false

NavigationStack {
    DashboardView()
        .navigationTitle("Bilanz")
        .navigationSubtitle("KlimaTicket Ö Classic · gültig bis 14.03.")   // iOS 26
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ProfileAvatarButton()
            }
            .sharedBackgroundVisibility(.hidden)          // avatar without a glass capsule

            ToolbarItemGroup(placement: .topBarTrailing) {    // grouped into ONE glass capsule
                Button("Filter", systemImage: "line.3.horizontal.decrease") { }
                Button("Teilen", systemImage: "square.and.arrow.up") { }
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing) // splits the glass groups

            ToolbarItem(placement: .topBarTrailing) {
                Button("Fahrt", systemImage: "plus") { showAdd = true }
                    .buttonStyle(.borderedProminent)          // the WWDC25-256 way to tint one toolbar item
                    .tint(.green)
            }
            .matchedTransitionSource(id: "addTrip", in: ns)   // ToolbarContent overload, iOS 26
        }
        .sheet(isPresented: $showAdd) {
            AddTripView()
                .presentationDetents([.medium, .large])
                .navigationTransition(.zoom(sourceID: "addTrip", in: ns))   // sheet morphs out of the button
        }
}

// Bottom bar with a flexible spacer + system search item (WWDC25-323)
.toolbar {
    ToolbarItem(placement: .bottomBar) { FilterPicker() }
    ToolbarSpacer(.flexible, placement: .bottomBar)
    DefaultToolbarItem(kind: .search, placement: .bottomBar)
    ToolbarSpacer(.fixed, placement: .bottomBar)
    ToolbarItem(placement: .bottomBar) { NewTripButton() }
}

// Badge on a toolbar button
Button("Hinweise", systemImage: "bell") { }.badge(unread)
```

Declarations:
- `ToolbarSpacer(_ sizing: SpacerSizing = .flexible, placement: ToolbarItemPlacement = .automatic)`
- `func sharedBackgroundVisibility(_ visibility: Visibility) -> some ToolbarContent`

Apple guidance:
- Remove custom backgrounds or darkening behind bar items. They fight the automatic scroll-edge effect.
- Icons render monochrome. Tint them only to convey meaning.

### 1.5 TabView (iOS 18 `Tab` API plus iOS 26 behaviours)

```swift
enum AppTab: Hashable { case dashboard, trips, stats, search }

struct RootTabs: View {
    @State private var tab: AppTab = .dashboard
    @State private var query = ""

    var body: some View {
        TabView(selection: $tab) {
            Tab("Bilanz", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.dashboard) {
                NavigationStack { DashboardView() }
            }
            Tab("Fahrten", systemImage: "tram.fill", value: AppTab.trips) {
                NavigationStack { TripsView() }
            }
            .badge(pendingCount)
            Tab("Statistik", systemImage: "chart.pie.fill", value: AppTab.stats) {
                NavigationStack { StatsView() }
            }
            Tab(value: AppTab.search, role: .search) {        // separate search tab; turns into a search field
                NavigationStack { StationSearchView(query: query) }
            }
        }
        .searchable(text: $query, prompt: "Bahnhof oder Fahrt suchen")   // .searchable goes on the TabView
        .tabBarMinimizeBehavior(.onScrollDown)                 // re-expands when scrolling up
        .tabViewBottomAccessory { QuickLogAccessory() }        // iOS 26.0: always visible
    }
}

struct QuickLogAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement   // TabViewBottomAccessoryPlacement?

    var body: some View {
        if placement == .inline {             // collapsed into the minimized tab bar
            Label("Pendeln", systemImage: "bolt.fill").labelStyle(.iconOnly)
        } else {                               // .expanded or nil
            HStack { Image(systemName: "bolt.fill"); Text("Pendelfahrt erfassen") }
        }
    }
}
```

Showing or hiding the accessory dynamically (`isEnabled:` needs 26.1):

```swift
extension View {
    @ViewBuilder
    func quickLogAccessory(isVisible: Bool) -> some View {
        if #available(iOS 26.1, *) {
            self.tabViewBottomAccessory(isEnabled: isVisible) { QuickLogAccessory() }
        } else {
            self.tabViewBottomAccessory { QuickLogAccessory() }
        }
    }
}
```

Gotchas:
- With a typed `TabView(selection:)`, every tab needs `value:`, including the search tab: `Tab(value:role:content:)`.
- `Tab(role: .search) { }` without a value only works in a selection-less `TabView`.
- `.tabViewSearchActivation(.searchTabSelection)` focuses the field when the tab is selected.
- `.searchToolbarBehavior(.minimize)` collapses toolbar search to a button.

### 1.6 Sheets

```swift
.sheet(isPresented: $showDetail) {
    TripDetail()
        .presentationDetents([.height(220), .medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
}
```

In iOS 26, partial-height sheets are inset with a Liquid Glass background. At full height they become opaque. **Do not set
`.presentationBackground(...)`** unless you deliberately want to replace the glass. Apple: "consider removing that and let the new material
shine" (WWDC25-323).

`presentationCornerRadius(_:)` exists from 16.4 but fights the concentric inset. Avoid it.

Zoom from a source: `.matchedTransitionSource(id:in:)` on the source view or the toolbar item, plus `.navigationTransition(.zoom(sourceID:in:))`
on the sheet or destination content. Both are iOS 18 (the toolbar-content variant is iOS 26).

```swift
// Navigation push with zoom (card -> detail)
NavigationLink {
    TicketDetailView(ticket: t)
        .navigationTransition(.zoom(sourceID: t.id, in: ns))
} label: {
    TicketCard(ticket: t)
        .matchedTransitionSource(id: t.id, in: ns)
}
// Optional styling of the source:
// .matchedTransitionSource(id: t.id, in: ns) { $0.clipShape(RoundedRectangle(cornerRadius: 24)).shadow(radius: 8) }
```

### 1.7 Extension, edges, concentric shapes

```swift
// Hero image extends (mirrored and blurred) under the sidebar or safe area without clipping
Image("alpine_hero").resizable().aspectRatio(contentMode: .fill)
    .backgroundExtensionEffect()

ScrollView { … }
    .scrollEdgeEffectStyle(.soft, for: .top)   // .hard for dense UIs (WWDC example: .hard, for: .top)
    .scrollEdgeEffectHidden(false, for: .bottom)

// Custom bar that participates in the scroll-edge effect (iOS 26)
ScrollView { … }
    .safeAreaBar(edge: .bottom) { SummaryStrip().padding(.horizontal) }

// Corners concentric with the container (device corners / sheet / card)
CustomControl()
    .background(.tint, in: ConcentricRectangle())
// or .rect(corners: .concentric), or .rect(corners: .concentric(minimum: 12))
// Set a container shape for children: .containerShape(.rect(cornerRadius: 28))
```

### 1.8 Liquid Glass "don'ts"

- `glassEffect(_:in:isEnabled:)` does not exist. Use `.identity`.
- `.rect(corner: .containerConcentric)` is beta-only and does not compile. Use `.rect(corners: .concentric)`.
- Don't put `glassEffect` on every list row. Group glass in `GlassEffectContainer`. Prefer standard components, which are already glass.
- Don't put opaque backgrounds behind toolbars or tab bars, or `presentationBackground` on sheets.
- Text on glass becomes vibrant automatically. Avoid low-contrast custom colours on `.clear` glass. Use `.regular` for text-heavy elements.

---

## 2. Swift Charts (iOS 26)

There is no new 2D chart API in iOS 26. The new piece is **`Chart3D`** (real, iOS 26.0, with `SurfacePlot` and 3D `PointMark/RuleMark/RectangleMark`).
It is not useful for this app. Avoid it on phones.

Declarations (all `nonisolated`):

```swift
// LineMark(x: PlottableValue<X>, y: PlottableValue<Y>)                     LineMark(x:y:series:)
// AreaMark(x:y:stacking: MarkStackingMethod = .standard)                   AreaMark(x:yStart:yEnd:)
// BarMark(x:y:width: MarkDimension = .automatic, height: = .automatic, stacking: = .standard)
// SectorMark(angle:innerRadius: MarkDimension = .automatic, outerRadius: = .automatic, angularInset: CGFloat? = nil)   // iOS 17
// RuleMark(x: PlottableValue<X>, yStart: CGFloat? = nil, yEnd: CGFloat? = nil)   -> RuleMark(x: .value(...)) compiles
// RuleMark(xStart: CGFloat? = nil, xEnd: CGFloat? = nil, y: PlottableValue<Y>)   -> RuleMark(y: .value(...)) compiles
// PointMark(x:y:)
// func chartXSelection<P: Plottable>(value: Binding<P?>) -> some View        // iOS 17; also (range: Binding<ClosedRange<P>?>)
// func chartAngleSelection<P: Plottable>(value: Binding<P?>) -> some View
// func chartScrollableAxes(_ axes: Axis.Set) -> some View
// func chartXVisibleDomain<P: Plottable & Numeric>(length: P) -> some View  // for a Date axis the length is SECONDS
// func chartScrollPosition(x: Binding<some Plottable>) / (initialX: some Plottable)
// func annotation(position: AnnotationPosition = .automatic, alignment: Alignment = .center, spacing: CGFloat? = nil,
//                 overflowResolution: AnnotationOverflowResolution, @ViewBuilder content: () -> C) -> some ChartContent
// AnnotationOverflowResolution(x: .Strategy = .automatic, y: .Strategy = .automatic); Strategy: .automatic | .disabled | .fit | .padScale | .fit(to: .chart/.plot)
// InterpolationMethod: .linear .monotone .catmullRom .cardinal .stepStart .stepCenter .stepEnd
```

### 2.1 Amortisation chart: cumulative savings vs. ticket price, with gradient, selection and annotation

```swift
import SwiftUI
import Charts

struct SavingsPoint: Identifiable {
    let date: Date
    let cumulative: Double          // € of regular fares avoided so far
    var id: Date { date }
}

struct AmortizationChart: View {
    let points: [SavingsPoint]
    let ticketPrice: Double
    @State private var selectedDate: Date?          // must be Optional and the same type as the x value

    private var selected: SavingsPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Datum", p.date), y: .value("Gespart", p.cumulative))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(colors: [Color.green.opacity(0.45), Color.green.opacity(0.0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                LineMark(x: .value("Datum", p.date), y: .value("Gespart", p.cumulative))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.green)
            }

            RuleMark(y: .value("Ticketpreis", ticketPrice))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Color.secondary)
                .annotation(position: .top, alignment: .leading) {
                    Text("Ticketpreis \(ticketPrice, format: .currency(code: "EUR"))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

            if let p = selected {                       // ChartContentBuilder supports if / if-let
                RuleMark(x: .value("Auswahl", p.date))
                    .foregroundStyle(Color.primary.opacity(0.2))
                    .annotation(position: .top, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.date, format: .dateTime.day().month(.abbreviated))
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(p.cumulative, format: .currency(code: "EUR"))
                                .font(.callout.weight(.semibold).monospacedDigit())
                        }
                        .padding(8)
                        .glassEffect(in: .rect(cornerRadius: 12))
                    }
                PointMark(x: .value("Datum", p.date), y: .value("Gespart", p.cumulative))
                    .symbolSize(90)
                    .foregroundStyle(Color.green)
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .sensoryFeedback(.selection, trigger: selected?.id)
        .frame(height: 240)
    }
}
```

Chart gotchas:
- AreaMark plus LineMark in one `ForEach` works for one series. For several series, pass `series: .value("Serie", s.name)` to `LineMark`,
  or the lines join up.
- Use `Color.primary.opacity(...)` rather than `.primary.opacity(...)` in `foregroundStyle`. Implicit-member chains on a generic `ShapeStyle`
  parameter sometimes fail type-checking.
- Big `Chart { }` bodies can hit "unable to type-check this expression in reasonable time". Split marks into small `ChartContent` structs
  (`struct SavingsMarks: ChartContent { var body: some ChartContent { … } }`).

### 2.2 Monthly bars, scrollable

```swift
Chart(monthly) { m in
    BarMark(x: .value("Monat", m.month, unit: .month),
            y: .value("Ersparnis", m.saved))
        .foregroundStyle(.linearGradient(colors: [.teal, .green], startPoint: .bottom, endPoint: .top))
        .cornerRadius(6)
        .annotation(position: .top) {
            Text(m.saved, format: .currency(code: "EUR").precision(.fractionLength(0)))
                .font(.caption2).foregroundStyle(.secondary)
        }
}
.chartScrollableAxes(.horizontal)
.chartXVisibleDomain(length: 60 * 60 * 24 * 183)     // about 6 months, in seconds for a Date axis
.chartScrollPosition(initialX: Date.now)
```

### 2.3 Donut (SectorMark)

```swift
@State private var selectedValue: Double?      // chartAngleSelection returns the CUMULATIVE value, not the category

Chart(shares) { s in
    SectorMark(angle: .value("Anteil", s.value), innerRadius: .ratio(0.62), angularInset: 1.5)
        .cornerRadius(5)
        .foregroundStyle(by: .value("Verkehrsmittel", s.name))
        .opacity(selectedName == nil || selectedName == s.name ? 1 : 0.35)
}
.chartAngleSelection(value: $selectedValue)
.chartLegend(.hidden)
.chartBackground { proxy in
    GeometryReader { geo in
        if let anchor = proxy.plotFrame {
            let frame = geo[anchor]
            VStack { Text("Fahrten").font(.caption); Text("\(total)").font(.title2.bold()) }
                .position(x: frame.midX, y: frame.midY)
        }
    }
}
// selectedName: walk the shares accumulating value until running sum >= selectedValue
```

`chartForegroundStyleScale(["Zug": .green, "Bus": .orange, …])` fixes the colours for categories (it takes `KeyValuePairs`).

---

## 3. SwiftData

Declarations:

```swift
// macro Model()                                     // class must be `final class` (recommended) with stored vars
// macro Attribute(_ options: Schema.Attribute.Option..., originalName: String? = nil, hashModifier: String? = nil)
//   options: .unique .externalStorage .preserveValueOnDeletion .spotlight .allowsCloudEncryption .ephemeral .transformable(by:)   (.codable is iOS 27, do not use)
// macro Relationship(_ options: ..., deleteRule: Schema.Relationship.DeleteRule = .nullify, minimumModelCount: Int? = 0,
//                    maximumModelCount: Int? = 0, originalName: String? = nil, inverse: AnyKeyPath? = nil, hashModifier: String? = nil)
//   DeleteRule: .cascade .deny .noAction .nullify
// Query(filter: Predicate<Element>? = nil, sort descriptors: [SortDescriptor<Element>] = [], transaction: Transaction? = nil)
// Query(filter: Predicate<Element>? = nil, sort keyPath: KeyPath<Element, Value>, order: SortOrder = .forward, transaction: = nil)
// Query(_ descriptor: FetchDescriptor<Element>, transaction: = nil)   also an animation: variant of each
// ModelConfiguration(_ name: String? = nil, schema: Schema? = nil, isStoredInMemoryOnly: Bool = false, allowsSave: Bool = true,
//                    groupContainer: ModelConfiguration.GroupContainer = .automatic, cloudKitDatabase: = .automatic)
// ModelConfiguration(_ name: String? = nil, schema: Schema? = nil, url: URL, allowsSave: Bool = true, cloudKitDatabase: = .automatic)
// GroupContainer: .automatic | .identifier("group.…") | .none
// ModelContainer(for: Schema, migrationPlan: (any SchemaMigrationPlan.Type)? = nil, configurations: [ModelConfiguration]) throws
// ModelContainer(for: any PersistentModel.Type..., migrationPlan: = nil, configurations: ModelConfiguration...) throws
// ModelContext(_ container: ModelContainer); context.fetch(FetchDescriptor<T>(predicate: = nil, sortBy: = []))
// Scene/View .modelContainer(_:)  (@MainActor)
// #Unique<T>([\.a, \.b]) / #Index<T>([\.date]) are iOS 18
```

### 3.1 Migration-safe models (enum stored as raw string, defaults everywhere, money in cents)

```swift
import Foundation
import SwiftData

enum TransportMode: String, Codable, CaseIterable, Sendable { case train, regionalTrain, bus, tram, metro, ferry }

@Model
final class TicketPeriod {
    var id: UUID = UUID()
    var productRaw: String = "classic"          // KlimaTicket product id (enum raw value, not an enum)
    var priceCents: Int = 0                      // integer cents: exact sums, trivial predicates
    var validFrom: Date = Date.now
    var validUntil: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Trip.ticket)   // inverse declared on ONE side only
    var trips: [Trip]? = []                      // optional to-many keeps CloudKit possible later

    init(productRaw: String, priceCents: Int, validFrom: Date, validUntil: Date) {
        self.productRaw = productRaw
        self.priceCents = priceCents
        self.validFrom = validFrom
        self.validUntil = validUntil
    }
}

@Model
final class Trip {
    var id: UUID = UUID()
    var date: Date = Date.now
    var originID: String = ""
    var destinationID: String = ""
    var modeRaw: String = TransportMode.train.rawValue
    var regularFareCents: Int = 0                // what a normal ticket would have cost
    var distanceKm: Double = 0
    var isReturn: Bool = false
    var note: String? = nil
    var ticket: TicketPeriod?

    // Computed wrapper. Not persisted. NEVER use it inside #Predicate.
    var mode: TransportMode {
        get { TransportMode(rawValue: modeRaw) ?? .train }
        set { modeRaw = newValue.rawValue }
    }

    init(date: Date, originID: String, destinationID: String, mode: TransportMode, regularFareCents: Int) {
        self.date = date
        self.originID = originID
        self.destinationID = destinationID
        self.modeRaw = mode.rawValue
        self.regularFareCents = regularFareCents
    }
}
```

Migration-safe rules (lightweight migration):
- Every **new** stored property gets a default value in its declaration, or is optional.
- Rename with `@Attribute(originalName: "oldName")`.
- A type change needs a custom `MigrationStage`.
- Avoid `@Attribute(.unique)` and `#Unique` if CloudKit may come later. CloudKit forbids unique constraints and requires optional or defaulted
  properties and optional relationships.

### 3.2 `#Predicate` pitfalls and working patterns

```swift
struct TripsList: View {
    @Query private var trips: [Trip]

    init(period: TicketPeriod, mode: TransportMode?) {
        // 1) Capture plain values into local lets BEFORE the macro. No self, no enums, no computed properties.
        let start = period.validFrom
        let end = period.validUntil
        let modeRaw = mode?.rawValue ?? ""
        let allModes = (mode == nil)

        _trips = Query(
            filter: #Predicate<Trip> { trip in
                trip.date >= start && trip.date < end && (allModes || trip.modeRaw == modeRaw)
            },
            sort: \Trip.date, order: .reverse
        )
    }

    var body: some View { List(trips) { TripRow(trip: $0) } }
}

// Text search: use localizedStandardContains (supported in predicates)
let needle = query
let p = #Predicate<Trip> { $0.originID.localizedStandardContains(needle) || $0.destinationID.localizedStandardContains(needle) }

// Imperative fetch, for widgets, App Intents or aggregation
let ctx = ModelContext(container)
var fd = FetchDescriptor<Trip>(predicate: #Predicate { $0.date >= start }, sortBy: [SortDescriptor(\.date)])
fd.fetchLimit = 500
let rows = try ctx.fetch(fd)
let savedCents = rows.reduce(0) { $0 + $1.regularFareCents }
```

Known pitfalls (Apple Developer Forums threads 735638, 736196, 737929, 738145):
- Comparing an enum property, or `.rawValue` of an enum case, inside `#Predicate` gives a compile error ("Key path cannot refer to enum case"),
  an `unsupportedPredicate` error, or a runtime crash. **Store the raw `String` and compare against a captured `let`.**
- Optional enum or transformable properties in predicates crash. Keep predicate fields non-optional primitives (`String`, `Int`, `Double`,
  `Bool`, `Date`, `UUID`).
- Computed properties, custom methods and `self` are not allowed inside `#Predicate`. Hoist values out.
- Keep the predicate a single boolean expression.
- Relationship traversal (`$0.ticket?.id == x`) may work but is fragile. Prefer a flat attribute or a date range, as above.
- Don't sort `@Query` by a computed property. Sort in memory instead.

### 3.3 ModelContainer in the App Group (app and widget share the store)

```swift
enum Persistence {
    static let schema = Schema([Trip.self, TicketPeriod.self])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        if inMemory {
            return try! ModelContainer(for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
        // AppGroup.containerURL is nil when the entitlement is missing (unsigned or sideloaded without group). Never force-unwrap it.
        let base = AppGroup.containerURL ?? URL.applicationSupportDirectory
        let dir = base.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = ModelConfiguration(schema: schema, url: dir.appending(path: "KlimaBilanz.store"))
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Never crash on launch. Fall back to memory and surface the error in UI or logs.
            return try! ModelContainer(for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
    }
}

@main
struct KlimaBilanzApp: App {
    let container = Persistence.makeContainer()
    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(container)
    }
}
```

`ModelConfiguration(groupContainer: .identifier("group.…"))` also works, but it **requires** the entitlement. Prefer the `url:` form with a
fallback.

For widgets, prefer a small JSON snapshot written by the app to the App Group container (as `Shared/WidgetSnapshot.swift` already does) over
opening SwiftData from the extension. A snapshot is cheaper, avoids store migration races, and doesn't need the models in the widget target.

Optional versioned schema (only needed when you first make a non-lightweight change):

```swift
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Trip.self, TicketPeriod.self] }
}
enum KlimaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
// ModelContainer(for: schema, migrationPlan: KlimaMigrationPlan.self, configurations: [config])
```

iOS 26 adds `@Model` class inheritance (`@available(iOS 26, *) @Model class BusinessTrip: Trip`; predicates can use `$0 is BusinessTrip`). It
isn't needed here.

---

## 4. Animations and polish

### 4.1 Animated MeshGradient background (TimelineView)

```swift
// init(width: Int, height: Int, points: [SIMD2<Float>], colors: [Color], background: Color = .clear,
//      smoothsColors: Bool = true, colorSpace: Gradient.ColorSpace = .device)          // iOS 18
struct AlpineMeshBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            // Use Double time RELATIVE to a start date. Float(timeIntervalSinceReferenceDate) has ~64 s resolution, so the animation would freeze.
            let t = context.date.timeIntervalSince(start)
            MeshGradient(width: 3, height: 3,
                         points: Self.points(t),
                         colors: Self.colors)
                .ignoresSafeArea()
        }
    }

    // Built outside the view builder with explicit types, which avoids "unable to type-check this expression"
    static func points(_ t: Double) -> [SIMD2<Float>] {
        let dx = Float(0.08 * sin(t * 0.45))
        let dy = Float(0.06 * cos(t * 0.35))
        return [
            SIMD2<Float>(0, 0),   SIMD2<Float>(0.5, 0),            SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 0.5), SIMD2<Float>(0.5 + dx, 0.5 + dy), SIMD2<Float>(1, 0.5),
            SIMD2<Float>(0, 1),   SIMD2<Float>(0.5, 1),            SIMD2<Float>(1, 1)
        ]
    }
    static let colors: [Color] = [
        .indigo, .blue, .teal,
        .blue, .mint, .cyan,
        .teal, .green, .mint
    ]
}
```

Rule: `points.count == colors.count == width * height`, or rendering breaks. Keep border points on the 0 and 1 edges.

### 4.2 Rolling numbers

```swift
// static func numericText(value: Double) -> ContentTransition       // iOS 17
Text(savedEuro, format: .currency(code: "EUR"))
    .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
    .contentTransition(.numericText(value: savedEuro))
    .animation(.snappy, value: savedEuro)        // or wrap the state change in withAnimation
// Countdown variant: .contentTransition(.numericText(countsDown: true))
```

### 4.3 SF Symbols effects

```swift
// Discrete (needs value:) : bounce, wiggle, breathe, pulse, rotate (all also indefinite)
// Indefinite (isActive:) : pulse, breathe, rotate, variableColor, drawOn, drawOff
// Transition             : drawOn, drawOff, appear, disappear  -> .transition(.symbolEffect(.drawOn))
Image(systemName: "checkmark.seal.fill").symbolEffect(.bounce, value: tripCount)
Image(systemName: "bell.fill").symbolEffect(.wiggle, value: unread)                  // iOS 18
Image(systemName: "leaf.fill").symbolEffect(.breathe)                               // iOS 18, indefinite
Image(systemName: "dot.radiowaves.left.and.right").symbolEffect(.pulse, options: .repeat(.periodic(delay: 1.0)))
Image(systemName: "arrow.triangle.2.circlepath").symbolEffect(.rotate, isActive: isSyncing)

// iOS 26 Draw (SF Symbols 7): the symbol draws along its path. Default playback is by layer.
Image(systemName: "signature").symbolEffect(.drawOff, isActive: isHidden)   // toggling draws off, then back on
Image(systemName: "checkmark.circle").symbolEffect(.drawOn.individually, isActive: isPending)
if showCheck { Image(systemName: "checkmark").transition(.symbolEffect(.drawOn)) }

// iOS 26 variable draw and gradient rendering
Image(systemName: "thermometer.high", variableValue: fraction)
    .symbolVariableValueMode(.draw)            // .color | .draw
    .symbolColorRenderingMode(.gradient)       // .flat | .gradient

// Swapping symbols
Image(systemName: isFav ? "star.fill" : "star").contentTransition(.symbolEffect(.replace))
```

### 4.4 Haptics

```swift
// sensoryFeedback(_ feedback: SensoryFeedback, trigger: T) where T: Equatable                    // iOS 17
// sensoryFeedback(_:trigger:condition: (T, T) -> Bool)      sensoryFeedback(trigger: T, _ feedback: () -> SensoryFeedback?)
.sensoryFeedback(.success, trigger: tripCount)
.sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: selectedTab)
.sensoryFeedback(.success, trigger: isAmortized) { old, new in !old && new }   // only when the ticket breaks even
// Values: .success .warning .error .selection .increase .decrease .start .stop .alignment .levelChange .pathComplete .impact
// iOS 26 adds .press(_:), .release(_:), .selection(_:)
```

### 4.5 PhaseAnimator and KeyframeAnimator

```swift
// PhaseAnimator(_ phases: some Sequence<Phase>, content: (Phase) -> Content, animation: (Phase) -> Animation? = { _ in .default })   // repeats forever
PhaseAnimator([false, true]) { glow in
    Circle().fill(.green.gradient)
        .scaleEffect(glow ? 1.06 : 1.0)
        .opacity(glow ? 1 : 0.75)
} animation: { _ in .easeInOut(duration: 1.6) }

// Trigger-driven modifier form
.phaseAnimator([0.0, 1.0, 0.0], trigger: savedCount) { content, phase in
    content.scaleEffect(1 + 0.08 * phase)
} animation: { _ in .spring(duration: 0.25) }

// Keyframes (content closure is @Sendable, so the value type must be Sendable; a plain struct is)
struct PopValues { var scale = 1.0; var rotation = Angle.zero; var y = 0.0 }

.keyframeAnimator(initialValue: PopValues(), trigger: celebrateCount) { content, v in
    content.scaleEffect(v.scale).rotationEffect(v.rotation).offset(y: v.y)
} keyframes: { _ in
    KeyframeTrack(\.scale) {
        SpringKeyframe(1.25, duration: 0.18)
        SpringKeyframe(1.0, spring: .bouncy)
    }
    KeyframeTrack(\.rotation) {
        CubicKeyframe(.degrees(-8), duration: 0.1)
        CubicKeyframe(.degrees(8), duration: 0.1)
        CubicKeyframe(.zero, duration: 0.1)
    }
    KeyframeTrack(\.y) {
        LinearKeyframe(-14, duration: 0.15)
        SpringKeyframe(0, spring: .bouncy)
    }
}
// SpringKeyframe(_ to:, duration: TimeInterval? = nil, spring: Spring = Spring(), startVelocity: = nil)
// CubicKeyframe(_ to:, duration: TimeInterval, startVelocity: = nil, endVelocity: = nil)
// LinearKeyframe(_ to:, duration: TimeInterval, timingCurve: UnitCurve = .linear)
```

### 4.6 Scroll-driven effects

```swift
// scrollTransition(_ configuration: ScrollTransitionConfiguration = .interactive, axis: Axis? = nil,
//                  transition: @escaping @Sendable (EmptyVisualEffect, ScrollTransitionPhase) -> some VisualEffect)
TripCard(trip: trip)
    .scrollTransition(.animated.threshold(.visible(0.9))) { content, phase in
        content
            .opacity(phase.isIdentity ? 1 : 0.4)
            .scaleEffect(phase.isIdentity ? 1 : 0.94)
            .blur(radius: phase.isIdentity ? 0 : 2)
    }
// phase: .identity | .topLeading | .bottomTrailing ; phase.value in -1...1

// visualEffect(_ effect: @escaping @Sendable (EmptyVisualEffect, GeometryProxy) -> some VisualEffect)
HeroImage()
    .visualEffect { content, proxy in
        let minY = proxy.frame(in: .scrollView).minY
        return content
            .offset(y: minY > 0 ? -minY * 0.5 : 0)      // parallax / stretch
            .scaleEffect(minY > 0 ? 1 + minY / 600 : 1, anchor: .bottom)
    }

// @Sendable closures cannot read @State or @Observable main-actor state directly. Use a capture list (WWDC25-266):
.visualEffect { [pulse] content, _ in content.blur(radius: pulse ? 2 : 0) }
```

Paging carousel: `.scrollTargetLayout()` on the `LazyHStack`, plus `.scrollTargetBehavior(.viewAligned)` on the `ScrollView`.

### 4.7 TextRenderer (iOS 18 `textRenderer(_:)`)

```swift
struct ShimmerRenderer: TextRenderer {
    var progress: Double                       // 0…1
    var animatableData: Double {               // TextRenderer refines Animatable
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let lines = Array(layout)
        for (lineIndex, line) in lines.enumerated() {
            for run in line {
                for (i, slice) in run.enumerated() {               // RunSlice = glyph-level piece
                    var copy = ctx
                    let phase = progress * Double(run.count + 6) - Double(i) - Double(lineIndex) * 2
                    copy.opacity = 0.35 + 0.65 * max(0, min(1, phase))
                    copy.draw(slice)                                // draw(_:options: = .init())
                }
            }
        }
    }
}

Text("Rentiert!")
    .font(.largeTitle.bold())
    .textRenderer(ShimmerRenderer(progress: shimmer))
    .onAppear { withAnimation(.easeInOut(duration: 1.2)) { shimmer = 1 } }
```

### 4.8 `@Animatable` macro (Xcode 26)

```swift
@Animatable
struct ProgressArc: Shape {
    var progress: Double
    var lineWidth: CGFloat
    @AnimatableIgnored var clockwise: Bool
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
                     startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * progress), clockwise: !clockwise)
        }
    }
}
```

### 4.9 ContentUnavailableView

```swift
// init(_ title: LocalizedStringResource, systemImage name: String, description: Text? = nil)
ContentUnavailableView("Noch keine Fahrten", systemImage: "tram.fill",
                       description: Text("Erfasse deine erste Fahrt und sieh, ab wann sich dein KlimaTicket rentiert."))

ContentUnavailableView {
    Label("Kein Ticket hinterlegt", systemImage: "ticket")
} description: {
    Text("Lege dein KlimaTicket an, um die Bilanz zu starten.")
} actions: {
    Button("Ticket anlegen") { showSetup = true }.buttonStyle(.glassProminent)
}

ContentUnavailableView.search(text: query)     // standard "no results for …"
```

### 4.10 Metal shaders (`colorEffect` / `layerEffect`). CI warning.

```swift
// colorEffect(_ shader: Shader, isEnabled: Bool = true)                       // MSL: [[ stitchable ]] half4 name(float2 position, half4 color, args...)
// layerEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: = true)   // MSL: [[ stitchable ]] half4 name(float2 position, SwiftUI::Layer layer, args...)
// distortionEffect(_:maxSampleOffset:isEnabled:)                              // MSL: [[ stitchable ]] float2 name(float2 position, args...)
// ShaderLibrary.default / ShaderLibrary.<name>(args...) via dynamic member lookup
// Shader.Argument: .float(_) .float2 .float3 .float4 .color(_) .colorArray .floatArray .image(_) .data(_) .boundingRect
```

```metal
// Shimmer.metal
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>     // community-standard header for SwiftUI::Layer (Apple's doc text says <SwiftUI/SwiftUI.h>)
using namespace metal;

[[ stitchable ]] half4 shimmer(float2 position, half4 color, float time, float width) {
    float band = 0.5 + 0.5 * sin(position.x / width * 6.2831 - time * 3.0);
    return half4(color.rgb + half3(band * 0.25) * color.a, color.a);
}
```

```swift
TimelineView(.animation) { ctx in
    let t = Float(ctx.date.timeIntervalSince(start))
    TicketCard()
        .colorEffect(ShaderLibrary.shimmer(.float(t), .float(320)))
}
```

**CI risk:** a `.metal` file triggers `error: cannot execute tool 'metal' due to missing Metal Toolchain; use: xcodebuild -downloadComponent
MetalToolchain` on Xcode 26 unless the CI step runs `xcodebuild -downloadComponent MetalToolchain` and `xcrun metal --version` succeeds. There are
known flaky cases where an export/import workaround is needed (CircleCI KB, Apple forums 787221 / 802155).

Recommendation: **ship without `.metal` files.** Get the shimmer from `TextRenderer`, the gradient from `MeshGradient`, and blur, `visualEffect`
and Liquid Glass from SwiftUI. All of these build with no extra toolchain.

---

## 5. WidgetKit

Declarations:

```swift
// StaticConfiguration(kind: String, provider: Provider, @ViewBuilder content: @escaping (Provider.Entry) -> Content) where Provider: TimelineProvider
// AppIntentConfiguration(kind: String, intent: Intent.Type = Intent.self, provider: Provider, content:) where Provider: AppIntentTimelineProvider (Intent: WidgetConfigurationIntent)
// TimelineProvider: placeholder(in:) / getSnapshot(in:completion:) / getTimeline(in:completion:)   (completions are @preconcurrency @Sendable in the newest SDK)
// AppIntentTimelineProvider: placeholder(in:) / snapshot(for:in:) async / timeline(for:in:) async
// Timeline(entries:policy:)  policy: .atEnd | .never | .after(Date)
// View.containerBackground(_ style: some ShapeStyle, for: .widget) / containerBackground(for: .widget, alignment: = .center) { view }
// WidgetFamily: systemSmall/Medium/Large/ExtraLarge(iPad)/ExtraLargePortrait(visionOS), accessoryCircular/Rectangular/Inline (Lock Screen), accessoryCorner (watch)
// \.widgetFamily, \.widgetRenderingMode (.fullColor | .accented | .vibrant), \.showsWidgetContainerBackground, \.widgetContentMargins
// View.widgetAccentable(_: Bool = true), Image.widgetAccentedRenderingMode(_: WidgetAccentedRenderingMode?)
//   WidgetAccentedRenderingMode: .accented | .accentedDesaturated | .desaturated | .fullColor   (iOS 18)
// GaugeStyle: .accessoryCircular | .accessoryCircularCapacity | .accessoryLinear | .accessoryLinearCapacity
// WidgetConfiguration: .configurationDisplayName .description .supportedFamilies .contentMarginsDisabled() .containerBackgroundRemovable(_:) .pushHandler(_:) (iOS 26)
// WidgetCenter.shared.reloadTimelines(ofKind:) / reloadAllTimelines()
```

### 5.1 Static widget fed by an App Group snapshot

```swift
import WidgetKit
import SwiftUI

struct BalanceEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct BalanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> BalanceEntry { BalanceEntry(date: .now, snapshot: .preview) }

    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        completion(BalanceEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        let entry = BalanceEntry(date: .now, snapshot: WidgetSnapshot.load())
        // The app calls WidgetCenter.shared.reloadAllTimelines() after every change. This is just a safety refresh.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60 * 60 * 3))))
    }
}

struct BalanceWidget: Widget {
    let kind = "BalanceWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceProvider()) { entry in
            BalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Ticket-Bilanz")
        .description("Zeigt, wie viel sich dein KlimaTicket schon rentiert hat.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct KlimaBilanzWidgets: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
        QuickLogWidget()
    }
}
```

The `@escaping (Entry) -> Void` completion signature (without `@Sendable`) compiles in Swift 5 mode, because the requirement is
`@preconcurrency`. The current repo code does this and CI builds succeed. In Swift 6 mode, add `@Sendable`.

### 5.2 Family-adaptive view with accented / glass rendering (iOS 26 Home Screen "clear" and "tinted")

In iOS 26, the clear and tinted Home Screen looks render the widget in **accented mode**. All content is tinted white, and the background is
replaced by glass or a tint (WWDC25-278). Opaque images become white silhouettes unless you set `widgetAccentedRenderingMode`.

```swift
struct BalanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: BalanceEntry

    private var fraction: Double { min(max(entry.snapshot?.amortizedFraction ?? 0, 0), 1) }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if renderingMode == .fullColor {
                    LinearGradient(colors: [.teal, .green], startPoint: .topLeading, endPoint: .bottomTrailing)
                }   // in accented/vibrant the system supplies the glass or tint background
            }
            .widgetURL(URL(string: "klimabilanz://dashboard"))
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: fraction) {
                Image(systemName: "tram.fill")
            } currentValueLabel: {
                Text("\(Int(fraction * 100))")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("KlimaTicket").font(.headline).widgetAccentable()
                Gauge(value: fraction) { Text("Bilanz") }.gaugeStyle(.accessoryLinearCapacity)
                Text("\(Int(fraction * 100)) % rentiert").font(.caption)
            }
        case .accessoryInline:
            Text("Ticket \(Int(fraction * 100)) % rentiert")
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image("Mountains")
                    .resizable().scaledToFit()
                    .widgetAccentedRenderingMode(.desaturated)     // keeps detail in clear/tinted
                Text(entry.snapshot?.net ?? 0, format: .currency(code: "EUR"))
                    .font(.title2.bold().monospacedDigit())
                    .widgetAccentable()                             // accent group = tinted colour
                    .contentTransition(.numericText(value: entry.snapshot?.net ?? 0))
            }
        }
    }
}
```

### 5.3 Interactive widget button

```swift
// Button(intent: some AppIntent, label:)  /  Button(_ titleKey:, intent:)  /  Toggle(isOn:intent:label:)   (iOS 17)
Button(intent: LogFavoriteTripIntent(favoriteID: fav.id, title: fav.title)) {
    Label(fav.title, systemImage: "plus.circle.fill")
}
.buttonStyle(.plain)
```

Rules (Apple article "Adding interactivity to widgets and Live Activities"):
- Interactive buttons and toggles are supported in system widget sizes and in accessoryCircular and accessoryRectangular on iPhone and iPad.
- The intent runs **in the widget extension process**, unless `openAppWhenRun` or `supportedModes` makes it a foreground intent, or it is a
  `LiveActivityIntent` or `AudioPlaybackIntent`. So the intent file must belong to **both targets** (here `Shared/` is compiled into both).
- **Widgets don't resolve parameters.** Every `@Parameter` must be set in the initializer you pass to `Button(intent:)`.
- When `perform()` returns, the system reloads the timeline. Finish writing the App Group data before returning.
- For "just open the app", use `widgetURL(_:)` or `Link`, not a Button.

### 5.4 Sharing data (App Group)

```swift
// FileManager.containerURL(forSecurityApplicationGroupIdentifier:) -> URL?   (nil on iOS when the entitlement is missing)
// UserDefaults(suiteName:) -> UserDefaults?
```

`Shared/AppGroup.swift` already handles AltStore's `ALTAppGroups` rewrite and the nil fallback. Write snapshots atomically with
`data.write(to: url, options: .atomic)`, then call `WidgetCenter.shared.reloadAllTimelines()`.

---

## 6. App Intents

Declarations:

```swift
// protocol AppIntent: PersistentlyIdentifiable, Sendable   -> stored properties must be Sendable
// static var title: LocalizedStringResource { get }        func perform() async throws -> Self.PerformResult
// static var supportedModes: IntentModes { get }           // iOS 26. IntentModes: .background, .foreground, .foreground(.immediate | .dynamic | .deferred)
// static var openAppWhenRun: Bool                          // deprecated 26.0; true in an extension -> runtime error
// func continueInForeground(_ dialog: IntentDialog? = nil, alwaysConfirm: Bool = true) async throws   // iOS 26
// var systemContext: IntentSystemContext   -> systemContext.currentMode (== .foreground / .canContinueInForeground)
// AppShortcut(intent:phrases:shortTitle: LocalizedStringResource, systemImageName: String)
// protocol AppShortcutsProvider: Sendable { @AppShortcutsBuilder static var appShortcuts: [AppShortcut] { get } ; static var shortcutTileColor }
// ShortcutTileColor: .blue .grape .grayBlue .grayBrown .grayGreen .lightBlue .lime .navy .orange .pink .purple .red .tangerine .teal .yellow
```

```swift
import AppIntents

struct ShowBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Ticket-Bilanz anzeigen"     // static let, not static var (Swift 6 safety)
    static let description = IntentDescription("Sagt dir, wie viel sich dein KlimaTicket schon rentiert hat.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let s = WidgetSnapshot.load() else {
            return .result(dialog: "Öffne KlimaBilanz und lege zuerst dein Ticket an.")
        }
        return .result(dialog: "Dein Ticket ist zu \(Int((s.amortizedFraction * 100).rounded())) % rentiert.")
    }
}

// Opens the app (iOS 26 way; the deployment target is 26, so no availability check)
struct OpenAddTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Fahrt erfassen"
    static let supportedModes: IntentModes = .foreground          // replaces `openAppWhenRun = true`
    @MainActor
    func perform() async throws -> some IntentResult {
        AppGroup.defaults.set(true, forKey: "intent.openAddTrip")  // or route via a @MainActor navigator
        return .result()
    }
}

// Background first, foreground on demand
struct LogTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Fahrt loggen"
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    @Parameter(title: "Von") var from: String
    @Parameter(title: "Nach") var to: String
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // … log …
        if systemContext.currentMode.canContinueInForeground {
            try? await continueInForeground(alwaysConfirm: false)
        }
        return .result(dialog: "Fahrt \(from) – \(to) gespeichert.")
    }
}

struct KlimaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ShowBalanceIntent(),
                    phrases: ["Hat sich mein Ticket in \(.applicationName) rentiert?",
                              "\(.applicationName) Bilanz"],
                    shortTitle: "Bilanz",
                    systemImageName: "eurosign.circle")
        AppShortcut(intent: OpenAddTripIntent(),
                    phrases: ["Neue Fahrt in \(.applicationName)"],
                    shortTitle: "Fahrt erfassen",
                    systemImageName: "plus.circle")
    }
    static let shortcutTileColor: ShortcutTileColor = .teal
}
```

App Intents gotchas:
- Every App Shortcut phrase must contain `\(.applicationName)`. The App Intents metadata processor rejects the build otherwise.
- At most one `AppShortcutsProvider` per app. It lives in the **app** target.
- Parameter types must be intent-compatible (`String`, `Int`, `Double`, `Bool`, `Date`, `URL`, `AppEntity`, `AppEnum`). A Swift `enum` needs
  `AppEnum`.
- `@MainActor func perform()` is allowed and is the simplest way to touch UI state.
- `static var title = …` is fine in Swift 5 mode. In Swift 6 it's an error ("not concurrency-safe"). Prefer `static let`.
- `OpenAddTripIntent` in `Shared/Intents.swift` currently uses `static var openAppWhenRun: Bool = true`. This is a deprecation warning only, but
  if that intent ever runs from the widget extension it errors. Switch to `static let supportedModes: IntentModes = .foreground`.

---

## 7. AuthenticationServices

Declarations:

```swift
// SignInWithAppleButton(_ label: SignInWithAppleButton.Label = .signIn,
//                       onRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
//                       onCompletion: @escaping (Result<ASAuthorization, any Error>) -> Void)        // iOS 14
// Label: .signIn | .continue | .signUp      Style via .signInWithAppleButtonStyle(.black | .white | .whiteOutline)
// ASAuthorizationOpenIDRequest.nonce: String?    ASAuthorizationAppleIDCredential.identityToken: Data?  (JWT)
// ASAuthorizationAppleIDProvider().credentialState(forUserID:) async throws -> CredentialState
// @Environment(\.webAuthenticationSession)   (iOS 16.4)
// authenticate(using: URL, callback: ASWebAuthenticationSession.Callback, preferredBrowserSession: BrowserSession? = nil,
//              additionalHeaderFields: [String: String]) async throws -> URL      // iOS 17.4; additionalHeaderFields has NO default
// authenticate(using: URL, callbackURLScheme: String, preferredBrowserSession: = nil) async throws -> URL   // deprecated 27.2
// Callback: .customScheme("klimabilanz") | .https(host:path:)     BrowserSession: .ephemeral | .shared
```

### 7.1 Sign in with Apple and nonce (CryptoKit)

```swift
import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

enum Nonce {
    static func random(length: Int = 32) -> String {
        precondition(length > 0)
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct AppleSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentNonce: String?
    let onToken: (_ idToken: String, _ rawNonce: String, _ fullName: PersonNameComponents?) async throws -> Void

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            let nonce = Nonce.random()
            currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Nonce.sha256(nonce)          // Apple gets the HASH
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard
                    let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    let tokenData = credential.identityToken,
                    let idToken = String(data: tokenData, encoding: .utf8),
                    let rawNonce = currentNonce
                else { return }
                Task { try? await onToken(idToken, rawNonce, credential.fullName) }  // backend gets the RAW nonce
            case .failure(let error):
                // ASAuthorizationError.canceled (1001) = user cancelled, so don't show an error.
                // .unknown (1000) usually means a missing or invalid "Sign in with Apple" entitlement (unsigned or re-signed builds).
                print("Apple sign-in failed:", error)
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 52)
        .clipShape(Capsule())
    }
}
// Supabase: try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: rawNonce))
// Apple returns fullName/email ONLY on the first authorization. Persist them immediately (Supabase docs).
```

### 7.2 Google / Microsoft (OAuth) via `WebAuthenticationSession`

```swift
struct OAuthButton: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    let authorizeURL: URL            // provider or Supabase /authorize URL with redirect_to=klimabilanz://auth-callback

    var body: some View {
        Button("Mit Google fortfahren") {
            Task {
                do {
                    let callbackURL = try await webAuthenticationSession.authenticate(
                        using: authorizeURL,
                        callback: .customScheme("klimabilanz"),     // must match CFBundleURLSchemes
                        preferredBrowserSession: .ephemeral,        // no shared Safari cookies
                        additionalHeaderFields: [:]                 // required argument (no default)
                    )
                    let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    _ = items.first { $0.name == "code" }?.value     // PKCE code, or parse the fragment for tokens
                } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                    // user cancelled
                } catch {
                    // show error
                }
            }
        }
        .buttonStyle(.glass)
    }
}
```

Notes:
- `.https(host:path:)` callbacks need Associated Domains (`webcredentials:` or `applinks:`), so they are not usable for sideloaded builds. Use
  `.customScheme`.
- The supabase-swift SDK's `signInWithOAuth(provider:redirectTo:)` drives `ASWebAuthenticationSession` itself. Use the raw API only if you
  bypass the SDK.

---

## 8. Swift language mode and concurrency (minimise compile errors)

### 8.1 Recommended settings (what compiles most reliably on Xcode 26.6)

```yaml
# project.yml  settings.base   (current repo values, keep them)
SWIFT_VERSION: "5.0"                 # Swift 5 language mode: concurrency diagnostics are mostly warnings
SWIFT_STRICT_CONCURRENCY: minimal    # only code that explicitly adopts concurrency is checked
# Do NOT set SWIFT_DEFAULT_ACTOR_ISOLATION (unset = nonisolated, the default for non-template projects)
# Do NOT set SWIFT_APPROACHABLE_CONCURRENCY for now
```

```swift
// Packages/KlimaCore/Package.swift  (current, keep)
// swift-tools-version: 6.0
//   swiftLanguageModes: [.v5]
// If you ever want MainActor-by-default in a package: tools 6.2 + swiftSettings: [.defaultIsolation(MainActor.self)]  (PackageDescription 6.2)
```

What the settings do (Apple "Build settings reference"):
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` infers `@MainActor` on all unannotated code in the module. New Xcode 26 templates enable it.
  Existing and XcodeGen projects default to `nonisolated`.
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` enables `DisableOutwardActorInference`, `GlobalActorIsolatedTypesUsability`,
  `InferIsolatedConformances`, `InferSendableFromCaptures` and `NonisolatedNonsendingByDefault`. The last one **changes runtime behaviour**:
  nonisolated async functions run on the caller's actor unless marked `@concurrent`.
- `SWIFT_STRICT_CONCURRENCY` is always `complete`, with errors, in Swift 6 mode.

Why not MainActor default isolation here: it makes `@Model` classes, `Codable` DTOs, `TimelineProvider`s and intent helpers main-actor-isolated.
Typical errors:
- `Conformance of 'X' to protocol 'Encodable' crosses into main actor-isolated code`
- `Main actor-isolated conformance … cannot be used in nonisolated context`
- `@ModelActor` cannot create models

These hit the widget extension and shared code hardest (Donny Wals, Fatbobman, Swift Forums). If you adopt it later, do it **only for the app
target** and mark shared value types `nonisolated`.

### 8.2 Isolation facts that hold regardless of settings

- `View`, `App`, `Widget` and `Link` are `@MainActor @preconcurrency` protocols or types. `body` and view methods run on the main actor.
- `TimelineProvider` methods, `AppIntent.perform()` and `EntityQuery` methods are **not** main-actor-isolated. `AppIntent` is `Sendable`.
- `@Observable` adds no actor isolation. For UI state, write `@MainActor @Observable final class AppState { … }` explicitly.
- `@Model` classes are not `Sendable` in the Xcode 26 SDK in practice. Never pass model instances across actors. Pass
  `persistentModelID` or plain value snapshots.

### 8.3 Common compile pitfalls and fixes

| Symptom | Fix |
|---|---|
| `Call to main actor-isolated instance method 'x' in a synchronous nonisolated context` (TimelineProvider, EntityQuery or intent calling a `@MainActor` store) | Make the helper `nonisolated` and pure (read the snapshot file), or `await MainActor.run { … }` in async code, or mark `perform()` `@MainActor`. |
| `Main actor-isolated property 'x' can not be referenced from a Sendable closure` in `visualEffect`, `scrollTransition`, `onGeometryChange(for:of:)` transform, `keyframeAnimator` content | Capture the value: `.visualEffect { [pulse] content, _ in … }`. These closures are `@Sendable` by declaration. |
| `Static property 'shared' is not concurrency-safe …` (Swift 6 / complete) | `@MainActor static let shared`, or make the type `@MainActor`, or `nonisolated(unsafe) static var` as a last resort. |
| `Conformance of 'X' to 'Encodable' crosses into main actor-isolated code` (only with MainActor default isolation) | Mark the type `nonisolated struct X: Codable`, or don't enable default isolation. |
| `Capture of 'self' with non-sendable type in a @Sendable closure` in `Task.detached` | Use `Task { }` (inherits the actor), or copy needed values into locals first. |
| `Stored property 'x' of 'Sendable'-conforming struct 'MyIntent' has non-sendable type` | Make the parameter types `Sendable` (value types), not class references. |
| Huge view builder: `The compiler is unable to type-check this expression in reasonable time` | Split into subviews or `@ViewBuilder` functions, give literals explicit types (`[SIMD2<Float>]`, `Double`), and avoid long chained ternaries inside modifiers. |
| `'openAppWhenRun' was deprecated in iOS 26.0` | `static let supportedModes: IntentModes = .foreground` |
| `xxx is only available in iOS 26.1 or newer` | `if #available(iOS 26.1, *) { … } else { … }`. Inside modifier chains, use a `@ViewBuilder` extension. |
| `cannot find 'X' in scope` for an API seen in the docs | It is probably iOS 27 (`TabRole.prominent`, `Query.sections`, `.codable`, `toolbarMinimizationBehavior`, `ToolbarOverflowMenu`, `visibilityPriority`, `ArrangementView`, `reorderable()`). Don't use it. |

---

## 9. Sources

Apple docs (all `https://developer.apple.com/documentation/...`):
- swiftui/applying-liquid-glass-to-custom-views
- swiftui/view/glasseffect(_:in:)
- swiftui/glass
- swiftui/glasseffectcontainer
- swiftui/view/glasseffectid(_:in:)
- swiftui/view/glasseffectunion(id:namespace:)
- swiftui/glasseffecttransition
- swiftui/primitivebuttonstyle/glass
- swiftui/primitivebuttonstyle/glassprominent
- swiftui/glassbuttonstyle/init(_:)
- swiftui/toolbarspacer
- swiftui/toolbarcontent/sharedbackgroundvisibility(_:)
- swiftui/view/tabbarminimizebehavior(_:)
- swiftui/view/tabviewbottomaccessory(content:)
- swiftui/view/tabviewbottomaccessory(isenabled:content:)
- swiftui/tab/init(role:content:)
- swiftui/tabrole/prominent
- swiftui/view/backgroundextensioneffect()
- swiftui/view/scrolledgeeffectstyle(_:for:)
- swiftui/concentricrectangle
- swiftui/buttonrole/close
- swiftui/view/chartxselection(value:)
- swiftui/view/chartscrollableaxes(_:)
- charts/chart3d
- charts/chartcontent/annotation(position:alignment:spacing:overflowresolution:content:)-1kiow
- swiftui/meshgradient
- swiftui/contenttransition/numerictext(value:)
- symbols/drawonsymboleffect
- swiftui/view/symbolvariablevaluemode(_:)
- swiftui/view/sensoryfeedback(_:trigger:)
- swiftui/phaseanimator
- swiftui/view/keyframeanimator(initialvalue:trigger:content:keyframes:)
- swiftui/view/scrolltransition(_:axis:transition:)
- swiftui/view/visualeffect(_:)
- swiftui/textrenderer
- swiftui/view/coloreffect(_:isenabled:)
- swiftui/view/layereffect(_:maxsampleoffset:isenabled:)
- swiftui/shaderlibrary
- swiftui/contentunavailableview
- swiftui/animatable()
- swiftdata/model()
- swiftdata/relationship(_:deleterule:minimummodelcount:maximummodelcount:originalname:inverse:hashmodifier:)
- swiftdata/query
- swiftdata/modelconfiguration
- swiftdata/modelcontainer
- foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)
- widgetkit/staticconfiguration/init(kind:provider:content:)
- widgetkit/widgetrenderingmode
- swiftui/image/widgetaccentedrenderingmode(_:)
- widgetkit/adding-interactivity-to-widgets-and-live-activities
- appintents/appintent/supportedmodes
- appintents/intentmodes
- appintents/appintent/openappwhenrun
- appintents/appshortcut
- authenticationservices/signinwithapplebutton/init(_:onrequest:oncompletion:)
- authenticationservices/webauthenticationsession
- xcode/build-settings-reference
- packagedescription/swiftsetting/defaultisolation(_:_:)
- updates/swiftui (iOS 27 changes)

WWDC25 (code tabs): videos/play/wwdc2025/ 323 (Build a SwiftUI app with the new design), 256 (What's new in SwiftUI), 278 (What's new in widgets),
275 (App Intents), 313 (Charts 3D), 291 (SwiftData inheritance), 266 (Concurrency in SwiftUI), 245 (What's new in Swift), 337 (SF Symbols 7).

Other:
- Runner image: github.com/actions/runner-images (macos-26-arm64-Readme.md)
- CircleCI KB: "Resolving Metal Toolchain Execution Missing Error in Xcode 26"
- Apple Developer Forums: 735638, 736196, 737929, 738145 (SwiftData enum predicates); 787221, 802155 (Metal toolchain)
- donnywals.com/setting-default-actor-isolation-in-xcode-26
- fatbobman.com/en/posts/default-actor-isolation
- supabase.com/docs/guides/auth/social-login/auth-apple
