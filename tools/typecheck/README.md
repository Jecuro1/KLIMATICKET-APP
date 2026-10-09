# Linux type-check harness for the iOS app

`tools/typecheck/run.sh` compiles the app target (`App/Sources` + `Shared`) and the widget extension
(`Widgets/Sources` + `Shared`) on Linux, against stand-ins for the iOS SDK. It reports the compiler errors
Xcode would report for our code: wrong argument labels, missing members, type mismatches, missing imports,
optional handling, non-exhaustive switches, duplicate declarations, result-builder violations, actor-isolation
errors, use of iOS 26.1+ API without `#available`, extension-unavailable API (`UIApplication.shared`) in the
widget, and the SIL diagnostics (definite initialization, missing `return`, exclusivity).

```
tools/typecheck/run.sh                      # check this checkout, both targets
tools/typecheck/run.sh --src /path/to/other/checkout
tools/typecheck/run.sh --target app|widgets|all
tools/typecheck/run.sh --fast               # type-check only (no SIL diagnostics), ~2x faster
tools/typecheck/run.sh --warnings --notes   # also warnings / the notes attached to each error
tools/typecheck/run.sh --regen -v           # force regeneration of the SDK stubs, verbose
```

Output is one line per error, paths relative to the checked repository:

```
App/Sources/Features/Settings/SetPreferencesSections.swift:65:66: error: cannot convert value of type 'Binding<Station?>' to expected argument type '(Station) -> Void'
Shared/ZZ.swift:2:37: error: 'shared' is only available in KBAppOnly [widgets]
typecheck: 2 error(s) in 41s
```

Exit status: 0 = no errors, 1 = errors, 2 = the harness itself failed (e.g. a broken stub).

`error: failed to produce diagnostic for expression` is a real error too: the expression does not
type-check, but the compiler could not say why (typical for an overload set reached through implicit
members such as `.value(...)`). Xcode's Swift 6.3 reports the same or a "no exact matches" error. Narrow it
down by giving the arguments explicit types; e.g. `BarMark(xStart: .value(...), xEnd: .value(...),
yStart: .value(...), yEnd: .value(...))` hits this because `BarMark` has no initializer taking four
`PlottableValue`s (`RectangleMark` does).
`[widgets]` / `[app]` marks an error in `Shared/` that only one target reports.

Requirements: Linux, Swift 6.3.x toolchain (`swiftc` on `PATH`, tested with swift-6.3.3-RELEASE), python3, git.
Runtime: first run about 2 minutes (it fetches and generates the SDK stubs, see below), then about 40 s
(`--fast`: about 20 s). Everything is cached in `tools/typecheck/.build/` (git-ignored).

## How it works

```
iOS SDK .swiftinterface files ──gen/transform.py──▶ Stubs/<M>/<M>.swiftinterface ─┐ (generated, not committed)
hand-written Stubs/<M>/*.swift (Objective-C / C frameworks) ───────────────────────┤
Stubs/KBAvailability (availability domains, Clang module) ─────────────────────────┤
Macros/* (compiler plugins: @Model, @Query, #Preview, @Entry, ...) ──────────────────┤
Packages/*/Sources (the real local packages) ──────────────────────────────────────┤
App/Sources, Shared, Widgets/Sources ──preprocess.py──▶ swiftc -emit-sil (Swift 5 mode) ┘
```

### 1. SDK stubs generated from Apple's interfaces

The Swift frameworks (SwiftUI, SwiftUICore, Charts, SwiftData, WidgetKit, AppIntents, Combine, CryptoKit,
StoreKit, CoreTransferable, UniformTypeIdentifiers, Symbols, DeveloperToolsSupport, os/OSLog, Accessibility,
ActivityKit and the cross-import overlays `_SwiftData_SwiftUI`, `_AppIntents_SwiftUI`, `_MapKit_SwiftUI`,
`_AuthenticationServices_SwiftUI`, `_StoreKit_SwiftUI`, `_PhotosUI_SwiftUI`) are **not hand-written**:
`gen/transform.py` converts the iOS SDK's own `arm64e-apple-ios.swiftinterface` into a Linux-buildable
textual interface. Every declaration keeps its exact signature (labels, generics, default arguments,
`@ViewBuilder`, `@MainActor`/`nonisolated`, `@preconcurrency`, `@_disfavoredOverload`, opaque result types),
so overload resolution and type inference behave as in Xcode. Mechanical rewrites only:

* bodies of `@inlinable` / `@_alwaysEmitIntoClient` / `@_transparent` declarations are removed (clients
  only need the signature), internal / `@usableFromInline` declarations are dropped;
* `@objc`, `@_originallyDefinedIn`, `@backDeployed`, ... are dropped (no Objective-C runtime on Linux);
* `@available` is mapped to what Linux can check (see *Availability*);
* a few type names are re-qualified where Linux puts them elsewhere (`CoreFoundation.CGFloat` →
  `Foundation.CGFloat`, `Foundation.URLSession` → `FoundationNetworking.URLSession`,
  `Foundation.LocalizedStringResource` → `FoundationShim.LocalizedStringResource`, `_LocationEssentials.` →
  `CoreLocation.`);
* the framework's own Clang-module re-exports are reproduced (`import SwiftUI` re-exports UIKit,
  SwiftUICore re-exports CoreGraphics/Foundation, UIKit re-exports Accessibility).

Declarations that still do not compile on Linux (they mention a framework that is not stubbed: CoreData,
RealityKit, Spatial, Intents, Photos, ...) are dropped one by one: the generator compiles the interface,
removes the declaration each error points at and repeats. `Stubs/<M>/PRUNED.txt` lists every dropped
declaration with the reason (SwiftUI: ~160 of ~10,000 declarations, mostly CoreData `@FetchRequest`,
visionOS/macOS-only API and Objective-C bridging internals).

Source: the **iOS 26.4 SDK** (the newest complete one in the public mirror github.com/xybp888/iOS-SDKs,
pinned commit, see `gen/fetch_sdk.sh`; the 26.5 copy there is truncated). CI builds with Xcode 26.6 / iOS 26.5
SDK, so API introduced in 26.5 is missing here (it would need `#available(iOS 26.5, *)` anyway).

**Licensing**: the generated interfaces are derived from Apple's SDK, so they are *not committed*. `run.sh`
fetches the ~25 needed `.swiftinterface` files on the first run (sparse partial git clone, a few seconds) and
generates the stubs locally (~90 s). Offline or on a Mac you can point it at a real SDK instead:
`KB_IOS_SDK_REF="$(xcrun --show-sdk-path --sdk iphoneos)" tools/typecheck/run.sh --regen`.
The stubs are regenerated automatically whenever the generator or a hand-written stub changes.

### 2. Hand-written stubs for Objective-C / C frameworks

Frameworks whose Swift API comes from Objective-C headers via the Clang importer are hand-written Swift
(`Stubs/<M>/*.swift`, built with `swiftc -emit-module -parse-as-library -enable-library-evolution`):
UIKit, CoreGraphics, CoreLocation, MapKit, UserNotifications, AuthenticationServices, Security, ImageIO,
CoreMotion, PDFKit, CoreSpotlight, the Objective-C parts of StoreKit / PhotosUI / Accessibility / os, and
`FoundationShim_ObjC`. They follow the importer's rules, checked against the iOS 26.4 headers:
`NS_SWIFT_UI_ACTOR` → `@MainActor @preconcurrency`, `NS_SWIFT_SENDABLE` → `@unchecked Sendable`,
`NS_SWIFT_NONISOLATED` → `nonisolated`, completion-handler methods also get their synthesised `async`
variant, `NS_ENUM` → `Int` enum, `NS_OPTIONS` → `OptionSet`, `NS_TYPED_ENUM` → `RawRepresentable` struct,
`NS_ERROR_ENUM` → error struct with `Code`. `@optional` delegate methods are protocol requirements with
default implementations. They only cover what the app and the generated SwiftUI stubs use.

### 3. Foundation: Linux vs. Darwin

swift-corelibs-foundation lacks some Darwin Foundation API. `FoundationShim` adds it and is implicitly
imported into every file (`-import-module FoundationShim`), so `import Foundation` behaves like on iOS:

* `Stubs/FoundationShim/select.txt` copies declarations from the SDK's `Foundation.swiftinterface`
  (`LocalizedStringResource`, `String(localized:)`, `String.LocalizationValue`, the `_FormatSpecifiable`
  interpolations, `URL.applicationSupportDirectory`, `URL.startAccessingSecurityScopedResource()`,
  `localizedStandardContains` for `#Predicate`, Combine publishers of `NotificationCenter`/`Timer`/`URLSession`,
  `JSONDecoder: TopLevelDecoder`, ...);
* `Stubs/FoundationShim_ObjC` hand-writes Objective-C Foundation API (`NSItemProvider`, `NSUserActivity`,
  `UndoManager`, `RelativeDateTimeFormatter`, `PersonNameComponentsFormatter`, `FileManager.containerURL(...)`,
  `ProcessInfo.isLowPowerModeEnabled`, `NSData.decompressed(using:)`, `Selector`) and the CoreFoundation
  type names (`CFString`, `CFData`, `CFDictionary`, ... as aliases of the NS classes, so `x as CFData` works);
* `FoundationShim` re-exports `FoundationNetworking` (on Linux `URLSession` lives there).

### 4. Availability (iOS 26.1+ API, app-extension-only API)

Linux has no iOS platform availability, so it is modelled with Swift's custom availability domains
(`-enable-experimental-feature CustomAvailability`, domains declared in the Clang module
`Stubs/KBAvailability`):

* SDK declarations introduced in iOS 26.1 … 26.5 get `@available(iOS_26_1)` … `@available(iOS_26_5)`;
  deployment-target-or-older availability is dropped; `@available(iOS, unavailable)` / obsoleted →
  `@available(*, unavailable)`; deprecations ≤ 26.0 become `@available(*, deprecated)` (`--warnings`).
* `preprocess.py` rewrites the app's `#available(iOS 26.2, *)` to `#available(iOS_26_1), #available(iOS_26_2)`
  and `@available(iOS 26.2, *)` accordingly. Using `GlassButtonStyle(.clear)` or
  `tabViewBottomAccessory(isEnabled:)` without a check therefore fails with
  `'init(_:)' is only available in iOS_26_1` (Xcode: "is only available in iOS 26.1 or newer").
* `@available(iOSApplicationExtension, unavailable)` / `NS_EXTENSION_UNAVAILABLE` API (e.g.
  `UIApplication.shared`, alternate icons) is `@available(KBAppOnly)`: always available in the app target,
  an error when the widget extension is checked (`-DKB_APP_EXTENSION`), like `APPLICATION_EXTENSION_API_ONLY`.

### 5. Macros

Apple's macro *declarations* come unchanged from the SDK, so macro arguments are type-checked exactly as in
Xcode. Their implementations (Apple-internal compiler plugins) are replaced by small plugins in `Macros/`,
built against the toolchain's own swift-syntax (`usr/lib/swift/host`) and loaded with
`-load-plugin-library`:

* `@Model` → `PersistentModel` + `Observable` conformance and the members `PersistentModel` requires;
  stored properties stay stored (same initialization rules for client code);
* `@Query var trips: [Trip]` → `get { _trips.wrappedValue }` + peer `var _trips: Query<[Trip].Element, [Trip]>`
  (so `_trips = Query(filter: ..., sort: ...)` in an `init` type-checks);
* `@Attribute`, `@Relationship`, `@Transient`, `#Unique`, `#Index`, `#Preview`, `@Previewable` expand to
  nothing - their arguments, including `#Preview` bodies, are still type-checked;
* `@Entry` → environment/transaction/container key + accessors; `@Animatable` → `Animatable` conformance.

`@Observable` / `@ObservationIgnored` and `#Predicate` use the toolchain's real `ObservationMacros` and
`FoundationMacros` plugins.

### 6. Compilation

* The local Swift packages listed under `packages:` in `project.yml` (KlimaCore, KlimaCloud, ...) are
  compiled from the checkout into modules first, in dependency order (`Package.swift` targets, language mode
  from `swiftLanguageModes` / tools version). Their errors are reported too. Each target only sees the
  packages `project.yml` lists in its `dependencies` (plus their dependencies), so `import KlimaCloud` in
  `Shared/` or `Widgets/` fails for the widget, as it would fail to build or link in Xcode. A target whose
  package has errors is not checked (stderr says so).
* Each target is compiled in one `swiftc -emit-sil -wmo` invocation (`--fast`: `-typecheck -j<cpus>`) with
  `-swift-version 5 -strict-concurrency=minimal -parse-as-library`, the stub search paths, the macro plugins,
  `-enable-cross-import-overlays` (`import SwiftData` + `import SwiftUI` pulls in `_SwiftData_SwiftUI`, as on
  iOS) and, for the widget, `-application-extension -Xcc -DKB_APP_EXTENSION`.
* `preprocess.py` copies the sources to `.build/work/` keeping every line in place (diagnostics point to the
  real file and line) and rewrites only: `#available`/`@available` for iOS 26.1+, `#selector(...)` →
  `__kbSelector(...)` (still type-checks the method reference), and blanks `@objc`/`@IBAction`/`@NSManaged`.

## Calibration

Ground truth: commit `26aec96` compiled in real Xcode CI (device + simulator, app + widget). Errors the
harness reported on it were all fixed in the stubs/harness (never in app code):

| iteration | errors on 26aec96 | fixed |
|---|---|---|
| 0 | 2  | harness: KlimaCore module search path |
| 1 | 10 | harness: cross-import overlays (`.swiftcrossimport` must sit next to the defining `.swiftinterface`, `-enable-cross-import-overlays`), `-continue-building-after-errors` (the driver had stopped after the first failing file) |
| 2 | 13 | stubs: `import SwiftUI` re-exports UIKit (SwiftUI.h), `RelativeDateTimeFormatter`, `PersonNameComponentsFormatter`, `ProcessInfo.isLowPowerModeEnabled`, `UIImage.byPreparingForDisplay()` (NS_SWIFT_ASYNC_NAME) |
| 3 | 2  | stubs: `URL.startAccessingSecurityScopedResource()` (member of the Darwin `URL` struct) |
| 4 | 0  | |

Further checks:

* **Known Xcode error reproduced**: on `da31086` the harness reports exactly the error Xcode CI reported,
  `SetPreferencesSections.swift:65:66: cannot convert value of type 'Binding<Station?>' to expected argument
  type '(Station) -> Void'` (plus the second argument at 65:91), and nothing else.
* **No false positives on every CI-green commit** (GitHub Actions `iOS` workflow, success): `26aec96`,
  `92595f9`, `a92db26`, `2571fc3`, `dd873af`, `838900a`, `16206e7`, `1f5f87e`, `3c2453a`, `82339c8`,
  `86240d8`, `f63b2fb` → 0 errors each (the Reports branch needed a PDFKit stub and the CGContext PDF API).
  Second round (last green runs of the `wip/*` branches): `acc5d9f`, `bb35fdf`, `2161db0`, `80dbf8d`
  (integration), `c57c7de`, `0d9baa2`, `2b1fafb` (p2-map), `4ff4623` (p2-reports), `93f3b4b`, `08d1559`,
  `a2cfd5b` (cloudflare) → 0 errors each; the last two needed support for the second local package
  (`KlimaCloud`).
* **Injected errors are caught** (one per category): extraneous label (`padding(.horizontal, top:)`), missing
  member, `Bool` passed for `Binding<Bool>`, `for` loop in a `@ViewBuilder`, optional member access,
  non-exhaustive `switch`, duplicate type, main-actor call from a nonisolated context, missing
  `import CoreLocation`, unknown property in `#Predicate` and in `@Query(sort:)`, `#Predicate` comparing `Int`
  with `String`, error inside a `#Preview` body, `AppIntent` without `title`, Charts mark with a missing
  `y:`, `glassEffect(_:in:isEnabled:)` (does not exist), `TabRole.prominent` (iOS 27), `GlassButtonStyle(_:)` and
  `tabViewBottomAccessory(isEnabled:)` without `#available` (but accepted inside `if #available(iOS 26.1, *)` and
  `@available(iOS 26.1, *)` declarations), `UIApplication.shared` in `Shared/` (widget only), missing `return`,
  use before initialization, exclusivity violations.

## Limitations

* Not a build: no linking, asset catalogs, Info.plist / entitlements, code signing, App Intents metadata
  extraction (e.g. the "every App Shortcut phrase must contain `\(.applicationName)`" check), Metal, or
  optimizer-only diagnostics (os_log argument constant-folding).
* `#if targetEnvironment(simulator)` is evaluated as false (device branch only); `#if DEBUG` is not defined.
* Hand-written stubs cover only what is used today. Using new UIKit / CoreLocation / UserNotifications /
  Security / MapKit / ... API produces `has no member` / `cannot find` errors that are stub gaps, not code
  bugs - check the real header and add the declaration (see below). Objective-C `@optional` requirements
  are modelled with default implementations, so a delegate method with a misspelled selector is not flagged
  (Xcode only warns about near-misses, too).
* Generated stubs come from the 26.4 SDK; 26.5-only API is missing. Pruned declarations (`PRUNED.txt`) are
  missing as well - e.g. CoreData `@FetchRequest`, `photosPicker(..., photoLibrary:)`, SiriKit
  `IntentConfiguration`.
* Darwin-only Foundation behaviour beyond the shimmed API: anything swift-corelibs-foundation declares
  differently from Darwin can differ (rare). `URLSession` & co. are Linux FoundationNetworking.
* The macro stand-ins approximate the type-level effect only: `@Model` does not convert stored properties
  into computed ones, `@Query`'s storage access level is not Apple's (internal here), `@Animatable` does not
  synthesise `animatableData`.
* Availability messages name the domain (`iOS_26_1`) instead of "iOS 26.1 or newer"; `#unavailable` and
  versions newer than 26.5 are only roughly modelled.
* Swift compiler: Linux 6.3.3 vs. Xcode 26.6's 6.3.x - type-checker performance limits ("unable to type-check
  this expression in reasonable time") can differ slightly.

## Extending the stubs

* **Missing member/type of an Objective-C / C framework** (UIKit, CoreLocation, MapKit, Security, ...):
  add it to `Stubs/<Framework>/<Framework>.swift` with the Swift name the importer gives the header
  declaration (labels, optionality from `nullable`/`_Nonnull`, `NS_SWIFT_NAME`, the `async` variant for
  completion handlers, isolation as above). Bodies are `{ _uiStub() }`-style traps, never executed. Quote the
  header declaration in a comment when the mapping is not obvious. The next `run.sh` rebuilds the module
  and regenerates the SDK stubs (~2 min) because generated modules may now keep declarations they pruned
  before.
* **Darwin-only Foundation API**: if it is in `Foundation.swiftinterface`, add a `type` / `member` /
  `conform` line to `Stubs/FoundationShim/select.txt` (new top-level types also go into `types.txt`);
  if it comes from an Objective-C header, add it to `Stubs/FoundationShim_ObjC/FoundationShim_ObjC.swift`
  (a whole replacement class shadows Linux Foundation's, see `PersonNameComponentsFormatter`).
* **Missing SwiftUI/Charts/... API**: these are generated; look in `Stubs/<M>/PRUNED.txt` why it was dropped
  (usually a type from an unstubbed framework) and stub that type, or adjust `gen/transform.py`.
* **A new framework**: hand-written → create `Stubs/<Name>/<Name>.swift` and add `(<Name>, [deps])` to
  `MODULES` in `build_stubs.py`; generated from the SDK → also add it to `MODULES` in `gen/transform.py`
  (with `objc=` naming the hand-written module that stands in for its Clang part) and to
  `build_stubs.py`; a cross-import overlay also goes into `CROSS_IMPORTS`.
* Debugging: `run.sh -v --notes`, `build_stubs.py --only <M>`, `gen/transform.py <M> -v`
  (needs `KB_IOS_SDK_REF=$(gen/fetch_sdk.sh)`).

## Files

| path | |
|---|---|
| `run.sh`, `run.py` | entry point: builds everything, preprocesses, compiles, prints errors |
| `preprocess.py` | line-preserving source rewrites (availability, `#selector`, `@objc`) |
| `build_stubs.py` | builds the stub modules and macro plugins (cached by content hash) |
| `gen/transform.py`, `gen/swiftiface.py` | SDK `.swiftinterface` → Linux stub generator with the prune loop |
| `gen/fetch_sdk.sh`, `gen/regen_all.sh` | fetch the SDK interfaces (pinned) / regenerate all generated stubs |
| `Stubs/<M>/<M>.swift` | hand-written stubs (committed) |
| `Stubs/<M>/<M>.swiftinterface`, `PRUNED.txt` | generated stubs (git-ignored) |
| `Stubs/KBAvailability/` | Clang module declaring the availability domains |
| `Macros/<Plugin>/` | macro plugin sources |
