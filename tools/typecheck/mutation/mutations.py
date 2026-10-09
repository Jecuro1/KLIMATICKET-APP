# Mutation catalogue for the type-check harness (applied to a pristine copy of 26aec96).
# Each mutation: id, cat, desc, edits=[(path, old, new)] (old=None -> create file with `new`).
# Every mutation is a mistake that real Xcode (iOS 26 SDK, Swift 5 mode, minimal concurrency) rejects.

CMP = "App/Sources/DesignSystem/Components.swift"
TDV = "App/Sources/Features/Trips/List/TripDetailView.swift"
ROOT = "App/Sources/Core/RootView.swift"
APPST = "App/Sources/Core/AppState.swift"
THEME = "Shared/Theme.swift"
NOTIF = "App/Sources/Services/NotificationService.swift"
LOC = "App/Sources/Services/LocationService.swift"
REPO = "App/Sources/Data/Repository.swift"
MONTH = "App/Sources/Features/Statistics/StatsMonthlyCard.swift"
SAV = "App/Sources/Features/Statistics/StatsSavingsCard.swift"
SNAP = "Widgets/Sources/SnapshotProvider.swift"
INT = "Shared/Intents.swift"
HERO = "App/Sources/DesignSystem/AmortizationHero.swift"
PREFS = "App/Sources/Features/Settings/SetPreferencesSections.swift"
STATUS = "App/Sources/Features/Ticket/TktStatusCards.swift"
TKTV = "App/Sources/Features/Ticket/TicketView.swift"
SUPA = "App/Sources/Services/SupabaseClient.swift"

M = []


def mut(id, cat, desc, *edits, anyfile=False):
    M.append(dict(id=id, cat=cat, desc=desc, edits=list(edits), anyfile=anyfile))


# --- argument labels / wrong modifier signatures -------------------------------------------
mut("L01", "label", "padding(horizontal:) instead of padding(.horizontal, _)",
    (CMP, "            .padding(.horizontal, 14)\n", "            .padding(horizontal: 14)\n"))
mut("L02", "label", "frame mixing height: with maxWidth:",
    (TDV, ".frame(height: 220)", ".frame(height: 220, maxWidth: .infinity)"))
mut("L03", "label", "background(_:shape:) instead of background(_:in:)",
    (TDV, ".background(.regularMaterial, in: .capsule)", ".background(.regularMaterial, shape: .capsule)"))
mut("L04", "label", "Label(_:systemName:) instead of systemImage:",
    (TDV, 'Label("Luftlinie \\(Format.km(route.straightKm))", systemImage: "scope")',
     'Label("Luftlinie \\(Format.km(route.straightKm))", systemName: "scope")'))
mut("L05", "label", "Image(systemImage:) instead of Image(systemName:)",
    (CMP, "                Image(systemName: symbol)\n                    .font(.system(size: 14, weight: .semibold))",
     "                Image(systemImage: symbol)\n                    .font(.system(size: 14, weight: .semibold))"))
mut("L06", "label", "shadow(color:blur:y:) instead of radius:",
    (CMP, "radius: 16, y: 8)", "blur: 16, y: 8)"))
mut("L07", "label", "overlay(.bottomLeading) without alignment: label",
    (TDV, ".overlay(alignment: .bottomLeading) { distanceChip }", ".overlay(.bottomLeading) { distanceChip }"))
mut("L08", "label", "Tab(_:systemName:value:) instead of systemImage:",
    (ROOT, "Tab(AppTab.trips.title, systemImage: AppTab.trips.symbol, value: AppTab.trips) {",
     "Tab(AppTab.trips.title, systemName: AppTab.trips.symbol, value: AppTab.trips) {"))
mut("L09", "label", "sensoryFeedback(.impact(style:)) instead of impact(weight:intensity:)",
    ("App/Sources/Features/Ticket/TktCardStack.swift", ".impact(weight: .light, intensity: 0.7)", ".impact(style: .light)"))
mut("L10", "label", "Format.euro(_:digits:) (app helper) instead of decimals:",
    (MONTH, ".accessibilityValue(Format.euro(bar.projected, decimals: 0))", ".accessibilityValue(Format.euro(bar.projected, digits: 0))"))
mut("L11", "label", "Color(hexString:) instead of the app's Color(hex:)",
    (THEME, 'Color(hex: "#2A7BD4"), Color(hex: "#7A6FE0")', 'Color(hexString: "#2A7BD4"), Color(hex: "#7A6FE0")'))

# --- API that does not exist / not on iOS 26.0 -----------------------------------------------
mut("A01", "nonexistent", "glassEffect(_:in:isEnabled:) (does not exist)",
    (CMP, "            .glassEffect(.regular, in: .capsule)\n            .padding(.top, Theme.Spacing.xs)",
     "            .glassEffect(.regular, in: .capsule, isEnabled: true)\n            .padding(.top, Theme.Spacing.xs)"))
mut("A02", "nonexistent", "Glass.thick (no such variant)",
    ("App/Sources/Features/Ticket/TktCardStack.swift", ".glassEffect(.regular, in: .circle)", ".glassEffect(.thick, in: .circle)"))
mut("A03", "nonexistent", "buttonStyle(.liquidGlass) (no such style)",
    ("App/Sources/DesignSystem/Celebration.swift", ".buttonStyle(.glassProminent)", ".buttonStyle(.liquidGlass)"))
mut("A04", "nonexistent", "navigationTitleDisplayMode (macOS-ish name, not on iOS)",
    (TKTV, ".navigationBarTitleDisplayMode(.inline)", ".navigationTitleDisplayMode(.inline)"))
mut("A05", "availability", "GlassButtonStyle(.clear) without #available(iOS 26.1)",
    (STATUS, ".buttonStyle(.glass)", ".buttonStyle(GlassButtonStyle(.clear))"))
mut("A06", "availability", "tabViewBottomAccessory(isEnabled:) (26.1) without #available",
    (ROOT, "        .tabBarMinimizeBehavior(.onScrollDown)\n",
     "        .tabBarMinimizeBehavior(.onScrollDown)\n        .tabViewBottomAccessory(isEnabled: true) { Text(\"Fahrt läuft\") }\n"))
mut("A07", "availability", "\\.accessibilityReduceHighlightingEffects (26.4) without #available",
    (CMP, "struct ToastOverlay: View {\n    @Environment(AppState.self) private var app\n",
     "struct ToastOverlay: View {\n    @Environment(AppState.self) private var app\n    @Environment(\\.accessibilityReduceHighlightingEffects) private var reduceHighlighting\n"))
mut("A08", "availability", "WidgetFamily.accessoryCorner (watchOS only) in supportedFamilies",
    ("Widgets/Sources/AmortizationWidget.swift", ".accessoryCircular, .accessoryRectangular, .accessoryInline])",
     ".accessoryCircular, .accessoryRectangular, .accessoryCorner])"))
mut("A09", "availability", "UIApplication.shared in Shared/ (widget extension)",
    (INT, "        AppGroup.defaults.set(true, forKey: Self.pendingKey)\n",
     "        AppGroup.defaults.set(true, forKey: Self.pendingKey)\n        UIApplication.shared.open(URL(string: \"klimabilanz://add\")!)\n"))

# --- type mismatches ---------------------------------------------------------------------------
mut("T01", "binding-vs-closure", "Binding<Station?> passed where (Station) -> Void is expected (the real CI error)",
    (PREFS, "            StationPickerView(title: \"Heimatbahnhof\") { station in\n                app.settings.homeStationID = station.id\n            }\n",
     "            StationPickerView(title: \"Heimatbahnhof\", selection: $homeStation)\n"),
    (PREFS, "private var favorites: [FavoriteRouteEntity]\n",
     "private var favorites: [FavoriteRouteEntity]\n    @State private var homeStation: Station?\n"))
mut("T02", "optional", "String? passed to Text(_:)",
    (CMP, "Text(toast.title).font(.subheadline.weight(.semibold))", "Text(toast.subtitle).font(.subheadline.weight(.semibold))"))
mut("T03", "optional", "String? passed to a String parameter (StationIndex.station(id:))",
    (TDV, "let fromStation = trip.fromStationID.flatMap { stations.station(id: $0) } ?? stations.station(named: trip.fromName)",
     "let fromStation = stations.station(id: trip.fromStationID) ?? stations.station(named: trip.fromName)"))
mut("T04", "binding", "Bool passed to Toggle(isOn:) instead of Binding<Bool>",
    (STATUS, "Toggle(isOn: Binding(get: { isOn }, set: { setEnabled($0) })) {", "Toggle(isOn: isOn) {"))
mut("T05", "binding", "$app on an @Environment(AppState.self) value (needs @Bindable)",
    (PREFS, "Toggle(isOn: $settings.hapticsEnabled) {", "Toggle(isOn: $app.settings.hapticsEnabled) {"))
mut("T06", "shapestyle", "foregroundStyle(UIColor) - UIColor is not a ShapeStyle",
    (CMP, "                .foregroundStyle(Theme.textSecondary)\n                .lineLimit(2)",
     "                .foregroundStyle(UIColor.secondaryLabel)\n                .lineLimit(2)"))
mut("T07", "shapestyle", "foregroundColor(LinearGradient) - expects Color?",
    (TDV, "            .foregroundStyle(Theme.textPrimary)\n            .padding(.horizontal, 10)",
     "            .foregroundColor(Theme.routeGradient)\n            .padding(.horizontal, 10)"))
mut("T08", "type", "CGFloat property changed to Int (arithmetic with CGFloat/Double)",
    (CMP, "    var size: CGFloat = 40\n", "    var size: Int = 40\n"))
mut("T09", "type", "presentationDetents(.medium) instead of a Set",
    (ROOT, "            TripEditorView(draft: draft)\n", "            TripEditorView(draft: draft)\n                .presentationDetents(.medium)\n"))
mut("T10", "type", "Text(_:format:) with .number.precision(0) (expects a Precision)",
    (HERO, "Text(Format.number(shownPercent))", "Text(shownPercent, format: .number.precision(0))"))
mut("T11", "type", "ContentUnavailableView description: String instead of Text",
    (CMP, "struct EmptyStateView: View {\n",
     "struct EmptyStateView: View {\n    private var unavailable: some View {\n        ContentUnavailableView(\"Keine Fahrten\", systemImage: \"tram\", description: \"Erfasse deine erste Fahrt\")\n    }\n"))
mut("T12", "type", "ForEach over [Int] without id: (Int is not Identifiable)",
    (STATUS, "ForEach(Self.options, id: \\.self) { offset in", "ForEach(Self.options) { offset in"))
mut("T13", "type", "[String: Any] passed to SecItemAdd without `as CFDictionary`",
    (SUPA, "SecItemAdd(add as CFDictionary, nil)", "SecItemAdd(add, nil)"))
mut("T14", "type", "SHA256.hash(String) instead of hash(data:)",
    (SUPA, "base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))", "base64URL(Data(SHA256.hash(verifier)))"))
mut("T15", "type", "URLSession.data(from: URLRequest) (expects URL)",
    ("App/Sources/Services/UpdateService.swift", "let (data, response) = try await URLSession.shared.data(for: request)",
     "let (data, response) = try await URLSession.shared.data(from: request)"))
mut("T16", "type", "value.as(String) without .self in a Charts axis label",
    (MONTH, "value.as(String.self)", "value.as(String)"))
mut("T17", "type", "contentTransition(.numericText(countsDown:value:)) (no such combination)",
    (HERO, ".contentTransition(.numericText(value: shownPercent))", ".contentTransition(.numericText(countsDown: true, value: shownPercent))"))

# --- async / throws / isolation ----------------------------------------------------------------
mut("C01", "try", "missing try on a throwing async call (UNUserNotificationCenter.add)",
    (NOTIF, "try? await center.add(UNNotificationRequest(identifier: \"breakeven.\\(ticketName)\", content: content, trigger: nil))",
     "await center.add(UNNotificationRequest(identifier: \"breakeven.\\(ticketName)\", content: content, trigger: nil))"))
mut("C02", "await", "missing await on an async call",
    (APPST, "        await updates.checkIfDue(force: false)\n", "        updates.checkIfDue(force: false)\n"))
mut("C03", "try", "missing try on Task.sleep(for:)",
    (APPST, "            try? await Task.sleep(for: .seconds(2.6))", "            await Task.sleep(for: .seconds(2.6))"))
mut("C04", "await", "async call in a synchronous function",
    (ROOT, "            Task { await app.updates.checkIfDue(force: true) }", "            await app.updates.checkIfDue(force: true)"))
mut("C05", "isolation", "@MainActor method called from a nonisolated delegate method",
    (LOC, "        Task { @MainActor in self.finish(last) }", "        self.finish(last)"))
mut("C06", "isolation", "@MainActor initializer called from a nonisolated static func",
    ("App/Sources/Core/Format.swift", "    static func days(_ n: Int)",
     "    static func homeStation() -> String? { AppSettings().homeStationID }\n\n    static func days(_ n: Int)"))
mut("C07", "isolation", "main-actor property mutated from Task.detached",
    (ROOT, "            Task { await app.updates.checkIfDue(force: true) }", "            Task.detached { app.selectedTab = .overview }"))
mut("C08", "self", "implicit self in an escaping closure inside a class",
    (LOC, "        Task { @MainActor in self.finish(nil) }", "        DispatchQueue.main.async { finish(nil) }"))
mut("C09", "mutating", "mutating a plain stored property of a View",
    (CMP, "        .accessibilityAddTraits(isSelected ? .isSelected : [])\n",
     "        .accessibilityAddTraits(isSelected ? .isSelected : [])\n        .onLongPressGesture { isSelected.toggle() }\n"))

# --- enums / switches --------------------------------------------------------------------------
mut("E01", "enum-case", "wrong enum case (.gondola) in a switch over TransportMode",
    (THEME, "        case .cableCar: Color(light: \"#23876A\", dark: \"#6BD6A9\")", "        case .gondola: Color(light: \"#23876A\", dark: \"#6BD6A9\")"))
mut("E02", "exhaustive", "non-exhaustive switch over TransportMode (case removed)",
    (THEME, "        case .other: Color(light: \"#64748B\", dark: \"#94A3B8\")\n", ""))
mut("E03", "exhaustive", "non-exhaustive switch over AppTab",
    (APPST, "        case .add: \"Erfassen\"\n", ""))
mut("E04", "enum-case", "SortOrder.descending in @Query (it is .reverse)",
    (TKTV, "@Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \\TripEntity.date, order: .reverse)",
     "@Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \\TripEntity.date, order: .descending)"))
mut("E05", "enum-case", "UNNotificationSound.defaultSound (it is .default)",
    (NOTIF, "        content.sound = .default\n        var comps = DateComponents()", "        content.sound = .defaultSound\n        var comps = DateComponents()"))
mut("E06", "enum-case", "PHPickerFilter .image (it is .images)",
    (TKTV, "matching: .images)", "matching: .image)"))

# --- SwiftData -----------------------------------------------------------------------------------
mut("D01", "predicate", "#Predicate in @Query referencing a non-existent property",
    ("App/Sources/Features/Settings/SetAccountSection.swift", "@Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }) private var trips",
     "@Query(filter: #Predicate<TripEntity> { $0.removedAt == nil }) private var trips"))
mut("D02", "fetchdescriptor", "SortDescriptor key path of another model in FetchDescriptor<TripEntity>",
    (REPO, "sortBy: [SortDescriptor(\\.date, order: .reverse)]", "sortBy: [SortDescriptor(\\.startDate, order: .reverse)]"))
mut("D03", "fetchdescriptor", "wrong generic argument: FetchDescriptor<TripEntity> where favourites are returned",
    (REPO, "(try? context.fetch(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.deletedAt == nil },",
     "(try? context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil },"))
mut("D04", "predicate", "unsupported function (lowercased()) inside #Predicate",
    (REPO, "(try? context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil },",
     "(try? context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil && $0.fromName.lowercased().contains(\"wien\") },"))
mut("D05", "query", "@Query #Predicate<TicketEntity> on a [TripEntity] property",
    ("App/Sources/Features/Settings/SetAccountSection.swift", "@Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }) private var trips",
     "@Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var trips"))
mut("D06", "observable", "@AppStorage inside an @Observable class",
    ("App/Sources/Features/Dashboard/DashTicker.swift", None,
     "import SwiftUI\n\n@Observable\nfinal class DashTicker {\n    @AppStorage(\"dash.tick\") var tick = 0\n}\n"))

# --- result builders ------------------------------------------------------------------------------
mut("B01", "viewbuilder", "if let on a non-optional value inside a ViewBuilder",
    (CMP, "            Text(label)\n                .font(Theme.Typography.caption)\n                .foregroundStyle(Theme.textSecondary)\n                .lineLimit(2)\n",
     "            if let label {\n                Text(label)\n                    .font(Theme.Typography.caption)\n                    .foregroundStyle(Theme.textSecondary)\n                    .lineLimit(2)\n            }\n"))
mut("B02", "viewbuilder", "guard let ... else { return EmptyView() } inside body",
    (CMP, "        if let toast = app.toast {\n            HStack(spacing: Theme.Spacing.s) {",
     "        guard let toast = app.toast else { return EmptyView() }\n        if true {\n            HStack(spacing: Theme.Spacing.s) {"))
mut("B03", "viewbuilder", "print(...) statement inside a ViewBuilder",
    (CMP, "        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {\n            HStack {\n",
     "        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {\n            print(\"render \\(value)\")\n            HStack {\n"))
mut("B04", "viewbuilder", "@ViewBuilder removed from a helper whose switch returns different views",
    ("Shared/WidgetViews/AmortizationWidgetView.swift", "    @ViewBuilder\n    private func content(for snapshot: WidgetSnapshot) -> some View {",
     "    private func content(for snapshot: WidgetSnapshot) -> some View {"))
mut("B05", "missing-return", "missing return at the end of a computed property (SIL)",
    (PREFS, "        if let state = station.federalState?.displayName { return \"\\(station.name) · \\(state)\" }\n        return station.name\n",
     "        if let state = station.federalState?.displayName { return \"\\(station.name) · \\(state)\" }\n"))

# --- names / imports / duplicates --------------------------------------------------------------
mut("N01", "theme-token", "misspelled Theme token Theme.Spacing.md",
    (CMP, "        .padding(Theme.Spacing.m)\n", "        .padding(Theme.Spacing.md)\n"))
mut("N02", "theme-token", "misspelled Theme token Theme.secondaryText",
    (TDV, "                            .foregroundStyle(Theme.textSecondary)", "                            .foregroundStyle(Theme.secondaryText)"))
mut("N03", "theme-token", "non-existent Theme.Radius.large",
    (TDV, ".clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))",
     ".clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))"))
mut("N04", "import", "missing import KlimaCore",
    (LOC, "import KlimaCore\n", ""))
mut("N05", "import", "missing import Charts",
    (MONTH, "import Charts\n", ""))
mut("N06", "import", "missing import MapKit",
    (TDV, "import MapKit\n", ""))
mut("N07", "import", "missing import UserNotifications",
    (NOTIF, "import UserNotifications\n", ""))
mut("N08", "import", "missing import WidgetKit (WidgetCenter)",
    (REPO, "import WidgetKit\n", ""))
mut("N09", "duplicate", "duplicate type name across files (struct Toast)",
    ("App/Sources/Features/Dashboard/DashToast.swift", None,
     "import Foundation\n\nstruct Toast: Identifiable {\n    let id = UUID()\n    var title: String\n}\n"), anyfile=True)
mut("N10", "duplicate", "duplicate Color(hex:) initializer across files",
    ("App/Sources/DesignSystem/ColorHex.swift", None,
     "import SwiftUI\n\nextension Color {\n    init(hex: String) {\n        self.init(uiColor: UIColor(hex: hex))\n    }\n}\n"), anyfile=True)

# --- closures -----------------------------------------------------------------------------------------
mut("K01", "closure-arity", "onChange closure with three parameters",
    (HERO, ".onChange(of: percent) { _, new in", ".onChange(of: percent) { old, new, transaction in"))
mut("K02", "closure-arity", "ForEach content closure with two parameters (Charts)",
    (MONTH, "            ForEach(bars) { bar in\n", "            ForEach(bars) { index, bar in\n"))
mut("K03", "closure-arity", "sensoryFeedback condition closure with one parameter",
    ("App/Sources/Features/Ticket/TktEditSheet.swift", ".sensoryFeedback(.selection, trigger: selection) { _, _ in hapticsEnabled }",
     ".sensoryFeedback(.selection, trigger: selection) { _ in hapticsEnabled }"))

# --- Charts ----------------------------------------------------------------------------------------------
mut("H01", "charts", "BarMark(x:height:width:) - height is a MarkDimension, not a value",
    (MONTH, "BarMark(x: .value(\"Monat\", bar.id), y: .value(\"Wert\", bar.actual * grow), width: .ratio(Self.barRatio))",
     "BarMark(x: .value(\"Monat\", bar.id), height: .value(\"Wert\", bar.actual * grow), width: .ratio(Self.barRatio))"))
mut("H02", "charts", "LineMark series: String instead of PlottableValue",
    (SAV, "series: .value(\"Reihe\", \"Glanz\"))", "series: \"Glanz\")"))
mut("H03", "charts", "PlottableValue .value(_) without a label",
    (SAV, "AreaMark(x: .value(\"Datum\", point.date), y: .value(\"Wert\", point.value * grow))",
     "AreaMark(x: .value(point.date), y: .value(\"Wert\", point.value * grow))"))
mut("H04", "charts", "RuleMark(y:) with a raw Double instead of .value(...)",
    (MONTH, "RuleMark(y: .value(\"Durchschnitt\", average))", "RuleMark(y: average)"))

# --- MapKit ---------------------------------------------------------------------------------------------
mut("P01", "mapcontent", "Text inside Map { } (not MapContent)",
    (TDV, "            Marker(route.toLabel, systemImage: \"flag.fill\", coordinate: route.to)\n",
     "            Text(route.toLabel)\n            Marker(route.toLabel, systemImage: \"flag.fill\", coordinate: route.to)\n"))
mut("P02", "mapkit", "Marker(_:systemImage:location:) instead of coordinate:",
    (TDV, "Marker(route.toLabel, systemImage: \"flag.fill\", coordinate: route.to)", "Marker(route.toLabel, systemImage: \"flag.fill\", location: route.to)"))
mut("P03", "mapkit", "MapPolyline(points:) with CLLocationCoordinate2D values",
    (TDV, "MapPolyline(coordinates: [route.from, route.to])", "MapPolyline(points: [route.from, route.to])"))
mut("P04", "mapkit", "Map(position:) with a value instead of a Binding",
    (TDV, "Map(initialPosition: .region(region), interactionModes: [])", "Map(position: .region(region), interactionModes: [])"))
mut("P05", "corelocation", "CLLocation.latitude (it is .coordinate.latitude)",
    (LOC, "GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)", "GeoPoint(latitude: loc.latitude, longitude: loc.longitude)"))

# --- WidgetKit ----------------------------------------------------------------------------------------
mut("W01", "timelineprovider", "getTimeline completion with the entry type instead of Timeline<Entry>",
    (SNAP, "func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {",
     "func getTimeline(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {"))
mut("W02", "timelineprovider", "placeholder(context:) instead of placeholder(in:)",
    (SNAP, "func placeholder(in context: Context) -> SnapshotEntry {", "func placeholder(context: Context) -> SnapshotEntry {"))
mut("W03", "timelineprovider", "Timeline(entries:) with a single entry",
    (SNAP, "completion(Timeline(entries: [entry], policy: .after(refresh)))", "completion(Timeline(entries: entry, policy: .after(refresh)))"))
mut("W04", "widget", "AppIntentConfiguration with a plain TimelineProvider",
    ("Widgets/Sources/QuickLogWidget.swift", "StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in",
     "AppIntentConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in"))
mut("W05", "widget", "WidgetCenter.reloadTimelines(kind:) instead of ofKind:",
    (INT, "        WidgetCenter.shared.reloadAllTimelines()\n", "        WidgetCenter.shared.reloadTimelines(kind: \"quicklog\")\n"))
mut("W06", "widget", "containerBackground(.widget) without for:",
    ("Shared/WidgetViews/WidArt.swift", "containerBackground(for: .widget) {", "containerBackground(.widget) {"))
mut("W07", "timelineprovider", "TimelineReloadPolicy .after without a date",
    (SNAP, "policy: .after(refresh)))", "policy: .after))"))

# --- App Intents ----------------------------------------------------------------------------------------
mut("I01", "appintent", "perform() declared ProvidesDialog but returns .result()",
    (INT, "    func perform() async throws -> some IntentResult {\n", "    func perform() async throws -> some IntentResult & ProvidesDialog {\n"))
mut("I02", "appintent", "static var title: String (must be LocalizedStringResource)",
    (INT, "static var title: LocalizedStringResource = \"Ticket-Bilanz anzeigen\"", "static var title: String = \"Ticket-Bilanz anzeigen\""))
mut("I03", "appintent", "@Parameter(name:) instead of title:",
    (INT, "@Parameter(title: \"Fahrt\")", "@Parameter(name: \"Fahrt\")"))
mut("I04", "appintent", "AppShortcut systemImage: instead of systemImageName:",
    ("App/Sources/Core/Shortcuts.swift", "systemImageName: \"star.fill\"", "systemImage: \"star.fill\""))
mut("I05", "appintent", "AppEntity without defaultQuery",
    (INT, "    static var defaultQuery = FavoriteRouteQuery()\n", ""))
mut("I06", "appintent", "perform() returning a value without ReturnsValue",
    (INT, "        return .result(dialog: \"\\(favorite.title) erfasst.\")\n", "        return .result(value: favorite.title)\n"))

# --- UIKit / ObjC frameworks -----------------------------------------------------------------------------
mut("U01", "uikit", "UIApplication.open(_:completion:) instead of completionHandler:",
    ("App/Sources/Services/UpdateService.swift", "            UIApplication.shared.open(url)\n            return\n",
     "            UIApplication.shared.open(url, completion: nil)\n            return\n"))
mut("U02", "usernotifications", "UNCalendarNotificationTrigger(dateComponents:repeats:)",
    (NOTIF, "trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))", "trigger: UNCalendarNotificationTrigger(dateComponents: comps, repeats: true))"))

# ============================== wave 2 ==============================================================
AUTH = "App/Sources/Services/AuthService.swift"
DET = "App/Sources/Services/TripDetectionService.swift"
TILT = "App/Sources/DesignSystem/MotionTilt.swift"
TSUP = "App/Sources/Features/Ticket/TktSupport.swift"
APPM = "App/Sources/KlimaBilanzApp.swift"
MODELS = "Shared/Models.swift"
AG = "Shared/AppGroup.swift"
VAL = "App/Sources/Features/Onboarding/OnboardingValidityStep.swift"
EDIT = "App/Sources/Features/Ticket/TktEditSheet.swift"

# --- hand-written ObjC framework stubs ---------------------------------------------------------------
mut("X01", "authservices", "ASAuthorization.Scope .mail (it is .email)",
    (AUTH, "request.requestedScopes = [.fullName, .email]", "request.requestedScopes = [.fullName, .mail]"))
mut("X02", "authservices", "Optional PersonNameComponents passed to PersonNameComponentsFormatter.string(from:)",
    (AUTH, "let name = credential.fullName.map { formatter.string(from: $0) }.flatMap { $0.isEmpty ? nil : $0 }",
     "let name: String? = formatter.string(from: credential.fullName)"))
mut("X03", "authservices", "WebAuthenticationSession preferredBrowserSession: .private (it is .ephemeral)",
    (AUTH, "preferredBrowserSession: .ephemeral)", "preferredBrowserSession: .private)"))
mut("X04", "try", "missing try on WebAuthenticationSession.authenticate",
    (AUTH, "let callback = try await webSession.authenticate(", "let callback = await webSession.authenticate("))
mut("X05", "corelocation", "CLCircularRegion(center:radius:id:) instead of identifier:",
    (DET, "radius: 250, identifier: id)", "radius: 250, id: id)"))
mut("X06", "corelocation", "CLRegion.notifiesOnEntry (it is notifyOnEntry)",
    (DET, "region.notifyOnEntry = true", "region.notifiesOnEntry = true"))
mut("X07", "corelocation", "startMonitoring(_:) without the for: label",
    (DET, "            manager.startMonitoring(for: region)\n", "            manager.startMonitoring(region)\n"))
mut("X08", "usernotifications", "UNNotificationCategory without intentIdentifiers:",
    (DET, "UNNotificationCategory(identifier: Self.notificationCategory, actions: [confirm], intentIdentifiers: [])",
     "UNNotificationCategory(identifier: Self.notificationCategory, actions: [confirm])"))
mut("X09", "coremotion", "CMDeviceMotionHandler closure with one parameter",
    (TILT, "{ [weak self] motion, _ in", "{ [weak self] motion in"))
mut("X10", "coremotion", "CMAttitude.rollAngle (it is .roll)",
    (TILT, "motion.attitude.roll / 0.6", "motion.attitude.rollAngle / 0.6"))
mut("X11", "imageio", "Data passed to CGImageSourceCreateWithData without `as CFData`",
    (TSUP, "CGImageSourceCreateWithData(data as CFData, nil)", "CGImageSourceCreateWithData(data, nil)"))
mut("X12", "imageio", "[CFString: Any] passed to CGImageDestinationAddImage without `as CFDictionary`",
    (TSUP, "CGImageDestinationAddImage(destination, image, properties as CFDictionary)", "CGImageDestinationAddImage(destination, image, properties)"))
mut("X13", "uikit", "UIPasteboard.text (it is .string)",
    ("App/Sources/Features/Settings/SetAccountSection.swift", "UIPasteboard.general.string = AppConfig.authCallback", "UIPasteboard.general.text = AppConfig.authCallback"))
mut("X14", "uikit", "UIDevice.osVersion (it is systemVersion)",
    ("App/Sources/Features/Settings/SetAboutSection.swift", "UIDevice.current.systemVersion", "UIDevice.current.osVersion"))
mut("X15", "uikit", "URL? passed to UIApplication.canOpenURL",
    ("App/Sources/Services/UpdateService.swift", "        guard let url = URL(string: string) else { return false }\n        return UIApplication.shared.canOpenURL(url)",
     "        return UIApplication.shared.canOpenURL(URL(string: string))"))
mut("X16", "uikit", "UIImage(named:) result used as non-optional UIImage",
    ("App/Sources/Features/Settings/SetComponents.swift", "                    if let image = UIImage(named: name) { return image }\n",
     "                    let image: UIImage = UIImage(named: name)\n                    return image\n"))
mut("X17", "usernotifications", "UNNotificationPresentationOptions .alertStyle (no such option)",
    (APPM, "[.banner, .sound, .list]", "[.banner, .sound, .alertStyle]"))
mut("X18", "isolation", "@MainActor statics read from a nonisolated async delegate method without MainActor.run",
    (APPM, "        await MainActor.run {\n            guard category", "        do {\n            guard category"))

# --- SwiftData / Foundation -----------------------------------------------------------------------------
mut("X19", "swiftdata", ".modelContainer(for: container) (for: takes model types)",
    (APPM, ".modelContainer(container)", ".modelContainer(for: container)"))
mut("X20", "swiftdata", "ModelConfiguration(inMemory:) (it is isStoredInMemoryOnly:)",
    (MODELS, "            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])\n        }\n        let storeURL",
     "            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(inMemory: true)])\n        }\n        let storeURL"))
mut("X21", "swiftdata", "cloudKitDatabase: .disabled (it is .none)",
    (MODELS, "cloudKitDatabase: .none)", "cloudKitDatabase: .disabled)"))
mut("X22", "try", "ModelContext.save() without try",
    (REPO, "do { try context.save() } catch { print(\"⚠️ save failed: \\(error)\") }", "context.save()"))
mut("X23", "swiftdata", "@Environment(ModelContext.self) instead of \\.modelContext",
    (ROOT, "    @Environment(\\.modelContext) private var context\n    @Environment(\\.scenePhase) private var scenePhase\n    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]\n\n    var body: some View {\n        @Bindable var app = app\n",
     "    @Environment(ModelContext.self) private var context\n    @Environment(\\.scenePhase) private var scenePhase\n    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]\n\n    var body: some View {\n        @Bindable var app = app\n"))
mut("X24", "optional", "UserDefaults? returned where UserDefaults is expected",
    (AG, "static var defaults: UserDefaults { resolved.defaults ?? .standard }", "static var defaults: UserDefaults { resolved.defaults }"))
mut("X25", "foundation", "FileManager.containerURL(forApplicationGroupIdentifier:) (wrong label)",
    (AG, "FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)", "FileManager.default.containerURL(forApplicationGroupIdentifier: id)"))
mut("X26", "foundation", "URL.applicationSupport (it is applicationSupportDirectory)",
    (MODELS, "let support = URL.applicationSupportDirectory", "let support = URL.applicationSupport"))
mut("X27", "optional", "Calendar.date(byAdding:) result used as Date",
    ("App/Sources/Features/Onboarding/OnboardingWelcomeStep.swift", "Format.dayMonth(Calendar.vienna.date(byAdding: .day, value: 66, to: Date()) ?? Date())",
     "Format.dayMonth(Calendar.vienna.date(byAdding: .day, value: 66, to: Date()))"))
mut("X28", "foundation", "Date.formatted(date:) without time:",
    ("App/Sources/Core/Format.swift", "    static func days(_ n: Int)",
     "    static func shortDate(_ d: Date) -> String { d.formatted(date: .abbreviated) }\n\n    static func days(_ n: Int)"))

# --- more SwiftUI ---------------------------------------------------------------------------------------
mut("S01", "swiftui", "spring(duration:damping:) (it is bounce:)",
    (APPST, "withAnimation(.spring(duration: 0.45, bounce: 0.3))", "withAnimation(.spring(duration: 0.45, damping: 0.3))"))
mut("S02", "swiftui", "symbolEffect(.bounce, trigger:) (it is value:)",
    (CMP, ".symbolEffect(.bounce, value: toast.id)", ".symbolEffect(.bounce, trigger: toast.id)"))
mut("S03", "swiftui", "SymbolEffectOptions .repeating(2) (it is .repeat(2))",
    (CMP, ".symbolEffect(.pulse, options: .repeat(2))", ".symbolEffect(.pulse, options: .repeating(2))"))
mut("S04", "swiftui", "Font.Weight .semiBold typo",
    (CMP, "                    .font(.system(size: 14, weight: .semibold))\n", "                    .font(.system(size: 14, weight: .semiBold))\n"))
mut("S05", "swiftui", "async call inside .onAppear (synchronous closure)",
    (ROOT, "            MainTabView().onAppear { app.selectedTab = .trips }", "            MainTabView().onAppear { await app.refreshRemoteContent() }"))
mut("S06", "swiftui", "ButtonRole .delete (it is .destructive)",
    (PREFS, "Button(\"Entfernen\", role: .destructive) {", "Button(\"Entfernen\", role: .delete) {"))
mut("S07", "swiftui", "pickerStyle(.dropdown) (no such style on iOS)",
    (TKTV, ".pickerStyle(.menu)", ".pickerStyle(.dropdown)"))
mut("S08", "swiftui", "scrollContentBackground(hidden:) (takes a Visibility)",
    (EDIT, "            .scrollContentBackground(.hidden)\n", "            .scrollContentBackground(hidden: true)\n"))
mut("S09", "swiftui", "DatePicker displayedComponents: .day (it is .date)",
    (EDIT, "DatePicker(\"Gültig ab\", selection: $draft.start, displayedComponents: .date)", "DatePicker(\"Gültig ab\", selection: $draft.start, displayedComponents: .day)"))
mut("S10", "swiftui", "focused($focus, equals:) with a case of another enum",
    (VAL, ".focused($focus, equals: .holder)", ".focused($focus, equals: .name)"))
mut("S11", "swiftui", "Link(destination:) with an optional URL",
    ("App/Sources/Features/Settings/SetAboutSection.swift", "                if let url = SetAboutSection.feedbackURL {\n                    Link(destination: url) {",
     "                if true {\n                    Link(destination: SetAboutSection.feedbackURL) {"))
mut("S12", "swiftui", "keyboardType(.decimal) (it is .decimalPad)",
    (EDIT, ".keyboardType(.decimalPad)", ".keyboardType(.decimal)"))
mut("S13", "swiftui", "@AppStorage with an unsupported type (Date)",
    (CMP, "struct ToastOverlay: View {\n    @Environment(AppState.self) private var app\n",
     "struct ToastOverlay: View {\n    @Environment(AppState.self) private var app\n    @AppStorage(\"toast.lastShown\") private var lastShown: Date = .now\n"))
mut("S14", "swiftui", "ScrollView(showIndicators:) (it is showsIndicators:)",
    (EDIT, "        ScrollView(.horizontal) {", "        ScrollView(.horizontal, showIndicators: false) {"))
mut("S15", "swiftui", "transition(.slide(edge:)) (slide takes no edge)",
    (CMP, ".transition(.move(edge: .top).combined(with: .opacity))", ".transition(.slide(edge: .top))"))
mut("S16", "swiftui", "frame alignment: .left (it is .leading)",
    (CMP, "        .frame(maxWidth: .infinity, alignment: .leading)\n        .frostedCard(cornerRadius: Theme.Radius.tile)", "        .frame(maxWidth: .infinity, alignment: .left)\n        .frostedCard(cornerRadius: Theme.Radius.tile)"))

# --- Swift language / app types --------------------------------------------------------------------------
mut("Z01", "memberwise", "memberwise init arguments in the wrong order",
    (ROOT, "StatTile(value: \"\\(snap.summary.tripCount)\", label: \"Fahrten\", symbol: \"tram.fill\")",
     "StatTile(label: \"Fahrten\", value: \"\\(snap.summary.tripCount)\", symbol: \"tram.fill\")"))
mut("Z02", "memberwise", "memberwise init missing a required argument",
    (ROOT, "StatTile(value: \"\\(snap.summary.tripCount)\", label: \"Fahrten\", symbol: \"tram.fill\")",
     "StatTile(value: \"\\(snap.summary.tripCount)\", label: \"Fahrten\")"))
mut("Z03", "access", "private helper of another type used (Format.styled)",
    (CMP, "struct EmptyStateView: View {\n",
     "private let kbStyle = Format.styled(.dateTime)\n\nstruct EmptyStateView: View {\n"))
mut("Z04", "access", "private struct of another file used (TripListDetailMap)",
    (CMP, "struct EmptyStateView: View {\n",
     "private var kbMapPreview: Any.Type { TripListDetailMap.self }\n\nstruct EmptyStateView: View {\n"))
mut("Z05", "conformance", "Codable struct with a non-Codable property (Color)",
    ("App/Sources/Features/Dashboard/DashPalette.swift", None,
     "import SwiftUI\n\nstruct DashPalette: Codable {\n    var name: String\n    var tint: Color\n}\n"))
mut("Z06", "conformance", "Identifiable struct without id",
    ("App/Sources/Features/Dashboard/DashRow.swift", None,
     "import Foundation\n\nstruct DashRow: Identifiable {\n    var title: String\n}\n"))
mut("Z07", "conformance", "String enum with an integer raw value",
    ("App/Sources/Features/Dashboard/DashFilter.swift", None,
     "enum DashFilter: String, CaseIterable {\n    case all = \"all\"\n    case month = 2\n}\n"))
mut("Z08", "type", "Int @State bound to Slider (needs BinaryFloatingPoint)",
    ("App/Sources/Features/Dashboard/DashSlider.swift", None,
     "import SwiftUI\n\nstruct DashSlider: View {\n    @State private var count = 3\n    var body: some View {\n        Slider(value: $count, in: 0...10)\n    }\n}\n"))
mut("Z09", "type", "Double(String) used as non-optional",
    ("App/Sources/Features/Dashboard/DashParse.swift", None,
     "import Foundation\n\nenum DashParse {\n    static func value(_ text: String) -> Double {\n        let v: Double = Double(text)\n        return v\n    }\n}\n"))
mut("Z10", "type", "sorted(by: \\.keyPath) on a non-Comparable-predicate",
    (REPO, "return counts.sorted { $0.value > $1.value }.prefix(limit).map(\\.key)", "return counts.sorted(by: \\.value).prefix(limit).map(\\.key)"))

# C07 (Task.detached inside a View) is only a *warning* in Swift 5 mode: the View's main-actor isolation
# comes from the @preconcurrency View protocol, so the compiler downgrades the violation (same compiler and
# same SwiftUICore declaration as Xcode). C07b is the same mistake outside a View, which Xcode rejects.
for _m in M:
    if _m["id"] == "C07":
        _m["xcode_warning_only"] = True
mut("C07b", "isolation", "main-actor property mutated from Task.detached in a nonisolated helper",
    ("App/Sources/Core/Format.swift", "    static func days(_ n: Int)",
     "    static func resetTab(_ app: AppState) { Task.detached { app.selectedTab = .overview } }\n\n    static func days(_ n: Int)"))

# X18: AppDelegate conforms to the @MainActor UIApplicationDelegate, so the class (and its async
# UNUserNotificationCenterDelegate witness) is inferred @MainActor - dropping MainActor.run is legal.
for _m in M:
    if _m["id"] == "X18":
        _m["xcode_warning_only"] = True
mut("X18b", "isolation", "explicit @MainActor static read from a nonisolated method",
    (APPM, "    @MainActor static var container: ModelContainer?\n",
     "    @MainActor static var container: ModelContainer?\n\n    nonisolated func currentTab() -> AppTab? { AppDelegate.appState?.selectedTab }\n"))

# S13: @AppStorage supports Date since iOS 18 (SwiftUI.swiftinterface: init(wrappedValue:_:store:) where
# Value == Date), so it is valid code; S13b uses a type AppStorage really does not support.
for _m in M:
    if _m["id"] == "S13":
        _m["xcode_warning_only"] = True
mut("S13b", "swiftui", "@AppStorage with an unsupported type ([String])",
    (CMP, "struct ToastOverlay: View {\n    @Environment(AppState.self) private var app\n",
     "struct ToastOverlay: View {\n    @Environment(AppState.self) private var app\n    @AppStorage(\"toast.history\") private var history: [String] = []\n"))
