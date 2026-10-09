# Wave 3: new-file mutations as (good, bad) pairs. All "good" variants are compiled together as a
# control run (must report 0 errors), so a "caught" bad variant is attributable to the mutation only.
# Each pair: id, cat, desc, path, good, bad.

P = []


def pair(id, cat, desc, path, good, bad):
    P.append(dict(id=id, cat=cat, desc=desc, path=path, good=good, bad=bad))


D = "App/Sources/Features/MutW3/"

pair("Y01", "uikit", "UIImage.systemImageNamed (ObjC factory; Swift only has init(systemName:))", D + "Y01.swift",
     "import UIKit\n\nenum Y01 {\n    static func image() -> UIImage? { UIImage(systemName: \"star\") }\n}\n",
     "import UIKit\n\nenum Y01 {\n    static func image() -> UIImage? { UIImage.systemImageNamed(\"star\") }\n}\n")

pair("Y02", "async", "async call directly in a Button action", D + "Y02.swift",
     "import SwiftUI\n\nstruct Y02: View {\n    func save() async {}\n    var body: some View {\n        Button(\"Sichern\") { Task { await save() } }\n    }\n}\n",
     "import SwiftUI\n\nstruct Y02: View {\n    func save() async {}\n    var body: some View {\n        Button(\"Sichern\") { await save() }\n    }\n}\n")

pair("Y03", "try", "throwing call in .task without try?/do-catch", D + "Y03.swift",
     "import SwiftUI\n\nstruct Y03: View {\n    func load() async throws {}\n    var body: some View {\n        Text(\"x\").task { try? await load() }\n    }\n}\n",
     "import SwiftUI\n\nstruct Y03: View {\n    func load() async throws {}\n    var body: some View {\n        Text(\"x\").task { try await load() }\n    }\n}\n")

pair("Y04", "type", "sheet(item:) with a non-Identifiable String?", D + "Y04.swift",
     "import SwiftUI\n\nstruct Y04Item: Identifiable { let id: String }\n\nstruct Y04: View {\n    @State private var picked: Y04Item?\n    var body: some View {\n        Text(\"x\").sheet(item: $picked) { Text($0.id) }\n    }\n}\n",
     "import SwiftUI\n\nstruct Y04Item: Identifiable { let id: String }\n\nstruct Y04: View {\n    @State private var picked: String?\n    var body: some View {\n        Text(\"x\").sheet(item: $picked) { Text($0) }\n    }\n}\n")

pair("Y05", "swiftui", ".onDelete on List instead of ForEach", D + "Y05.swift",
     "import SwiftUI\n\nstruct Y05: View {\n    @State private var items = [\"a\", \"b\"]\n    var body: some View {\n        List {\n            ForEach(items, id: \\.self) { Text($0) }\n                .onDelete { items.remove(atOffsets: $0) }\n        }\n    }\n}\n",
     "import SwiftUI\n\nstruct Y05: View {\n    @State private var items = [\"a\", \"b\"]\n    var body: some View {\n        List {\n            ForEach(items, id: \\.self) { Text($0) }\n        }\n        .onDelete { items.remove(atOffsets: $0) }\n    }\n}\n")

pair("Y06", "label", "aspectRatio(.fit) without contentMode:", D + "Y06.swift",
     "import SwiftUI\n\nstruct Y06: View {\n    var body: some View {\n        Image(systemName: \"star\").resizable().aspectRatio(contentMode: .fit)\n    }\n}\n",
     "import SwiftUI\n\nstruct Y06: View {\n    var body: some View {\n        Image(systemName: \"star\").resizable().aspectRatio(.fit)\n    }\n}\n")

pair("Y07", "nonexistent", "scrollTargetBehavior(.snap) (no such behavior)", D + "Y07.swift",
     "import SwiftUI\n\nstruct Y07: View {\n    var body: some View {\n        ScrollView(.horizontal) {\n            LazyHStack { ForEach(0..<5) { Text(\"\\($0)\") } }\n                .scrollTargetLayout()\n        }\n        .scrollTargetBehavior(.viewAligned)\n    }\n}\n",
     "import SwiftUI\n\nstruct Y07: View {\n    var body: some View {\n        ScrollView(.horizontal) {\n            LazyHStack { ForEach(0..<5) { Text(\"\\($0)\") } }\n                .scrollTargetLayout()\n        }\n        .scrollTargetBehavior(.snap)\n    }\n}\n")

pair("Y08", "label", "redacted(.placeholder) without reason:", D + "Y08.swift",
     "import SwiftUI\n\nstruct Y08: View {\n    var body: some View { Text(\"x\").redacted(reason: .placeholder) }\n}\n",
     "import SwiftUI\n\nstruct Y08: View {\n    var body: some View { Text(\"x\").redacted(.placeholder) }\n}\n")

pair("Y09", "charts", "chartXSelection(value:) with a non-optional Binding", D + "Y09.swift",
     "import SwiftUI\nimport Charts\n\nstruct Y09: View {\n    @State private var selected: Date?\n    var body: some View {\n        Chart { LineMark(x: .value(\"Tag\", Date.now), y: .value(\"Wert\", 1.0)) }\n            .chartXSelection(value: $selected)\n    }\n}\n",
     "import SwiftUI\nimport Charts\n\nstruct Y09: View {\n    @State private var selected: Date = .now\n    var body: some View {\n        Chart { LineMark(x: .value(\"Tag\", Date.now), y: .value(\"Wert\", 1.0)) }\n            .chartXSelection(value: $selected)\n    }\n}\n")

pair("Y10", "macro", "#Preview(trait:) instead of traits:", D + "Y10.swift",
     "import SwiftUI\n\n#Preview(traits: .sizeThatFitsLayout) {\n    Text(\"Vorschau\")\n}\n",
     "import SwiftUI\n\n#Preview(trait: .sizeThatFitsLayout) {\n    Text(\"Vorschau\")\n}\n")

pair("Y11", "macro", "error inside a #Preview body (unknown modifier)", D + "Y11.swift",
     "import SwiftUI\n\n#Preview {\n    Text(\"Vorschau\").padding()\n}\n",
     "import SwiftUI\n\n#Preview {\n    Text(\"Vorschau\").paddingAll()\n}\n")

pair("Y12", "macro", "@Entry with a type-mismatched default value", D + "Y12.swift",
     "import SwiftUI\n\nextension EnvironmentValues {\n    @Entry var y12Accent: Color = .blue\n}\n",
     "import SwiftUI\n\nextension EnvironmentValues {\n    @Entry var y12Accent: Color = 5\n}\n")

pair("Y13", "macro", "@Entry in an extension of View (not EnvironmentValues)", D + "Y13.swift",
     "import SwiftUI\n\nextension EnvironmentValues {\n    @Entry var y13Thing: Int = 1\n}\n",
     "import SwiftUI\n\nextension View {\n    @Entry var y13Thing: Int = 1\n}\n")

pair("Y14", "macro", "@Entry on a non-optional property without a default", D + "Y14.swift",
     "import SwiftUI\n\nextension EnvironmentValues {\n    @Entry var y14Value: Int = 0\n}\n",
     "import SwiftUI\n\nextension EnvironmentValues {\n    @Entry var y14Value: Int\n}\n")

pair("Y15", "swiftdata", "@Relationship inverse key path to a non-existent property", D + "Y15.swift",
     "import SwiftData\n\n@Model\nfinal class Y15Note {\n    var text: String = \"\"\n    @Relationship(deleteRule: .nullify) var trips: [TripEntity] = []\n    init() {}\n}\n",
     "import SwiftData\n\n@Model\nfinal class Y15Note {\n    var text: String = \"\"\n    @Relationship(deleteRule: .nullify, inverse: \\TripEntity.notes) var trips: [TripEntity] = []\n    init() {}\n}\n")

pair("Y16", "swiftdata", "@Attribute(.uniqueness) (it is .unique)", D + "Y16.swift",
     "import SwiftData\n\n@Model\nfinal class Y16Code {\n    @Attribute(.unique) var code: String = \"\"\n    init() {}\n}\n",
     "import SwiftData\n\n@Model\nfinal class Y16Code {\n    @Attribute(.uniqueness) var code: String = \"\"\n    init() {}\n}\n")

pair("Y17", "swiftdata", "FetchDescriptor.limit (it is fetchLimit)", D + "Y17.swift",
     "import SwiftData\n\nenum Y17 {\n    static func newest() -> FetchDescriptor<TripEntity> {\n        var d = FetchDescriptor<TripEntity>(sortBy: [SortDescriptor(\\.date, order: .reverse)])\n        d.fetchLimit = 5\n        return d\n    }\n}\n",
     "import SwiftData\n\nenum Y17 {\n    static func newest() -> FetchDescriptor<TripEntity> {\n        var d = FetchDescriptor<TripEntity>(sortBy: [SortDescriptor(\\.date, order: .reverse)])\n        d.limit = 5\n        return d\n    }\n}\n")

pair("Y18", "predicate", "#Predicate calling a method on an optional property", D + "Y18.swift",
     "import SwiftData\n\nenum Y18 {\n    static let wien = #Predicate<TripEntity> { $0.fromStationID == \"wien\" }\n}\n",
     "import SwiftData\n\nenum Y18 {\n    static let wien = #Predicate<TripEntity> { $0.fromStationID.hasPrefix(\"wien\") }\n}\n")

pair("Y19", "appintent", "@Parameter of a type that is not an intent value (Color)", D + "Y19.swift",
     "import AppIntents\nimport SwiftUI\n\nstruct Y19Intent: AppIntent {\n    static var title: LocalizedStringResource = \"Y19\"\n    @Parameter(title: \"Anzahl\") var count: Int\n    func perform() async throws -> some IntentResult { .result() }\n}\n",
     "import AppIntents\nimport SwiftUI\n\nstruct Y19Intent: AppIntent {\n    static var title: LocalizedStringResource = \"Y19\"\n    @Parameter(title: \"Farbe\") var color: Color\n    func perform() async throws -> some IntentResult { .result() }\n}\n")

pair("Y20", "appintent", "AppEnum without caseDisplayRepresentations", D + "Y20.swift",
     "import AppIntents\n\nenum Y20Mode: String, AppEnum {\n    case train, bus\n    static var typeDisplayRepresentation: TypeDisplayRepresentation = \"Verkehrsmittel\"\n    static var caseDisplayRepresentations: [Y20Mode: DisplayRepresentation] = [.train: \"Zug\", .bus: \"Bus\"]\n}\n",
     "import AppIntents\n\nenum Y20Mode: String, AppEnum {\n    case train, bus\n    static var typeDisplayRepresentation: TypeDisplayRepresentation = \"Verkehrsmittel\"\n}\n")

pair("Y21", "appintent", "perform() returning String instead of an IntentResult", D + "Y21.swift",
     "import AppIntents\n\nstruct Y21Intent: AppIntent {\n    static var title: LocalizedStringResource = \"Y21\"\n    func perform() async throws -> some IntentResult & ReturnsValue<String> { .result(value: \"ok\") }\n}\n",
     "import AppIntents\n\nstruct Y21Intent: AppIntent {\n    static var title: LocalizedStringResource = \"Y21\"\n    func perform() async throws -> String { \"ok\" }\n}\n")

pair("Y22", "widget", "ControlWidgetButton(action:) with a closure instead of an AppIntent", "Widgets/Sources/Y22Control.swift",
     "import WidgetKit\nimport SwiftUI\nimport AppIntents\n\nstruct Y22Control: ControlWidget {\n    var body: some ControlWidgetConfiguration {\n        StaticControlConfiguration(kind: \"y22\") {\n            ControlWidgetButton(action: OpenAddTripIntent()) { Label(\"Neu\", systemImage: \"plus\") }\n        }\n    }\n}\n",
     "import WidgetKit\nimport SwiftUI\nimport AppIntents\n\nstruct Y22Control: ControlWidget {\n    var body: some ControlWidgetConfiguration {\n        StaticControlConfiguration(kind: \"y22\") {\n            ControlWidgetButton(action: { print(\"tap\") }) { Label(\"Neu\", systemImage: \"plus\") }\n        }\n    }\n}\n")

pair("Y23", "widget", "Widget whose body is some View", "Widgets/Sources/Y23Widget.swift",
     "import WidgetKit\nimport SwiftUI\n\nstruct Y23Widget: Widget {\n    var body: some WidgetConfiguration {\n        StaticConfiguration(kind: \"y23\", provider: SnapshotProvider()) { entry in\n            Text(entry.date, style: .time)\n        }\n    }\n}\n",
     "import WidgetKit\nimport SwiftUI\n\nstruct Y23Widget: Widget {\n    var body: some View {\n        Text(\"y23\")\n    }\n}\n")

pair("Y24", "enum-case", "Text(_:style: .relativeTime) (it is .relative)", "Widgets/Sources/Y24Widget.swift",
     "import WidgetKit\nimport SwiftUI\n\nstruct Y24View: View {\n    let entry: SnapshotEntry\n    var body: some View { Text(entry.date, style: .relative) }\n}\n",
     "import WidgetKit\nimport SwiftUI\n\nstruct Y24View: View {\n    let entry: SnapshotEntry\n    var body: some View { Text(entry.date, style: .relativeTime) }\n}\n")

pair("Y25", "availability", "26.1 API inside if #available(iOS 26.0, *) (always true on 26.0)", D + "Y25.swift",
     "import SwiftUI\n\nstruct Y25: View {\n    var body: some View {\n        if #available(iOS 26.1, *) {\n            Button(\"x\") {}.buttonStyle(GlassButtonStyle(.clear))\n        } else {\n            Button(\"x\") {}.buttonStyle(.glass)\n        }\n    }\n}\n",
     "import SwiftUI\n\nstruct Y25: View {\n    var body: some View {\n        if #available(iOS 26.0, *) {\n            Button(\"x\") {}.buttonStyle(GlassButtonStyle(.clear))\n        } else {\n            Button(\"x\") {}.buttonStyle(.glass)\n        }\n    }\n}\n")

pair("Y26", "availability", "26.4 API in a declaration marked @available(iOS 26.1, *)", D + "Y26.swift",
     "import SwiftUI\n\n@available(iOS 26.4, *)\nstruct Y26: View {\n    @Environment(\\.accessibilityReduceHighlightingEffects) private var reduce\n    var body: some View { Text(reduce ? \"a\" : \"b\") }\n}\n",
     "import SwiftUI\n\n@available(iOS 26.1, *)\nstruct Y26: View {\n    @Environment(\\.accessibilityReduceHighlightingEffects) private var reduce\n    var body: some View { Text(reduce ? \"a\" : \"b\") }\n}\n")

pair("Y27", "uikit", "macOS-only colour name UIColor.windowBackgroundColor", D + "Y27.swift",
     "import UIKit\n\nenum Y27 {\n    static let background = UIColor.systemBackground\n}\n",
     "import UIKit\n\nenum Y27 {\n    static let background = UIColor.windowBackgroundColor\n}\n")

pair("Y28", "usernotifications", "UNNotificationRequest.trigger used as non-optional", D + "Y28.swift",
     "import UserNotifications\n\nenum Y28 {\n    static func repeats(_ r: UNNotificationResponse) -> Bool { r.notification.request.trigger?.repeats ?? false }\n}\n",
     "import UserNotifications\n\nenum Y28 {\n    static func repeats(_ r: UNNotificationResponse) -> Bool { r.notification.request.trigger.repeats }\n}\n")

pair("Y29", "uikit", "UIDevice.identifierForVendor used as non-optional", D + "Y29.swift",
     "import UIKit\n\n@MainActor\nenum Y29 {\n    static func vendor() -> String { UIDevice.current.identifierForVendor?.uuidString ?? \"\" }\n}\n",
     "import UIKit\n\n@MainActor\nenum Y29 {\n    static func vendor() -> String { UIDevice.current.identifierForVendor.uuidString }\n}\n")

pair("Y30", "uikit", "UIFont(name:size:) result used as non-optional", D + "Y30.swift",
     "import UIKit\n\nenum Y30 {\n    static let font: UIFont = UIFont(name: \"Avenir\", size: 12) ?? .systemFont(ofSize: 12)\n}\n",
     "import UIKit\n\nenum Y30 {\n    static let font: UIFont = UIFont(name: \"Avenir\", size: 12)\n}\n")

pair("Y31", "authservices", "ASAuthorizationAppleIDCredential.email used as non-optional", D + "Y31.swift",
     "import AuthenticationServices\n\nenum Y31 {\n    static func mail(_ c: ASAuthorizationAppleIDCredential) -> String { c.email ?? \"\" }\n}\n",
     "import AuthenticationServices\n\nenum Y31 {\n    static func mail(_ c: ASAuthorizationAppleIDCredential) -> String { c.email }\n}\n")

pair("Y32", "mapkit", "MKCoordinateSpan(latDelta:lonDelta:)", D + "Y32.swift",
     "import MapKit\n\nenum Y32 {\n    static let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)\n}\n",
     "import MapKit\n\nenum Y32 {\n    static let span = MKCoordinateSpan(latDelta: 0.1, lonDelta: 0.1)\n}\n")

pair("Y33", "mapkit", "MapCircle(center:radiusMeters:) (it is radius:)", D + "Y33.swift",
     "import SwiftUI\nimport MapKit\n\nstruct Y33: View {\n    let c = CLLocationCoordinate2D(latitude: 47, longitude: 11)\n    var body: some View {\n        Map { MapCircle(center: c, radius: 100) }\n    }\n}\n",
     "import SwiftUI\nimport MapKit\n\nstruct Y33: View {\n    let c = CLLocationCoordinate2D(latitude: 47, longitude: 11)\n    var body: some View {\n        Map { MapCircle(center: c, radiusMeters: 100) }\n    }\n}\n")

pair("Y34", "charts", "SectorMark(angle:) with a raw Double", D + "Y34.swift",
     "import SwiftUI\nimport Charts\n\nstruct Y34: View {\n    var body: some View {\n        Chart { SectorMark(angle: .value(\"Anteil\", 0.4), innerRadius: .ratio(0.6)) }\n    }\n}\n",
     "import SwiftUI\nimport Charts\n\nstruct Y34: View {\n    var body: some View {\n        Chart { SectorMark(angle: 0.4, innerRadius: .ratio(0.6)) }\n    }\n}\n")

pair("Y35", "charts", "foregroundStyle(by:) with a String instead of .value", D + "Y35.swift",
     "import SwiftUI\nimport Charts\n\nstruct Y35: View {\n    var body: some View {\n        Chart { BarMark(x: .value(\"Art\", \"Zug\"), y: .value(\"Wert\", 3)).foregroundStyle(by: .value(\"Art\", \"Zug\")) }\n    }\n}\n",
     "import SwiftUI\nimport Charts\n\nstruct Y35: View {\n    var body: some View {\n        Chart { BarMark(x: .value(\"Art\", \"Zug\"), y: .value(\"Wert\", 3)).foregroundStyle(by: \"Zug\") }\n    }\n}\n")

pair("Y36", "charts", "AxisMarks stride(by: .months) (it is .month)", D + "Y36.swift",
     "import SwiftUI\nimport Charts\n\nstruct Y36: View {\n    var body: some View {\n        Chart { LineMark(x: .value(\"Tag\", Date.now), y: .value(\"Wert\", 1)) }\n            .chartXAxis { AxisMarks(values: .stride(by: .month)) }\n    }\n}\n",
     "import SwiftUI\nimport Charts\n\nstruct Y36: View {\n    var body: some View {\n        Chart { LineMark(x: .value(\"Tag\", Date.now), y: .value(\"Wert\", 1)) }\n            .chartXAxis { AxisMarks(values: .stride(by: .months)) }\n    }\n}\n")

pair("Y37", "observable", "@Bindable on a class that is not @Observable", D + "Y37.swift",
     "import SwiftUI\n\n@Observable final class Y37Model { var n = 0 }\n\nstruct Y37: View {\n    @Bindable var model: Y37Model\n    var body: some View { Stepper(\"Anzahl\", value: $model.n) }\n}\n",
     "import SwiftUI\n\nfinal class Y37Model { var n = 0 }\n\nstruct Y37: View {\n    @Bindable var model: Y37Model\n    var body: some View { Stepper(\"Anzahl\", value: $model.n) }\n}\n")

pair("Y38", "observable", "@StateObject with an @Observable class (not ObservableObject)", D + "Y38.swift",
     "import SwiftUI\n\n@Observable final class Y38Model { var n = 0 }\n\nstruct Y38: View {\n    @State private var model = Y38Model()\n    var body: some View { Text(\"\\(model.n)\") }\n}\n",
     "import SwiftUI\n\n@Observable final class Y38Model { var n = 0 }\n\nstruct Y38: View {\n    @StateObject private var model = Y38Model()\n    var body: some View { Text(\"\\(model.n)\") }\n}\n")

pair("Y39", "observable", ".environment(_:) with a class that is not @Observable", D + "Y39.swift",
     "import SwiftUI\n\n@Observable final class Y39Model { var n = 0 }\n\nstruct Y39: View {\n    @State private var model = Y39Model()\n    var body: some View { Text(\"x\").environment(model) }\n}\n",
     "import SwiftUI\n\nfinal class Y39Model { var n = 0 }\n\nstruct Y39: View {\n    @State private var model = Y39Model()\n    var body: some View { Text(\"x\").environment(model) }\n}\n")

pair("Y40", "type", "onChange(of:) with a non-Equatable value", D + "Y40.swift",
     "import SwiftUI\n\nstruct Y40Item: Equatable { var n = 0 }\n\nstruct Y40: View {\n    @State private var item = Y40Item()\n    var body: some View { Text(\"x\").onChange(of: item) { } }\n}\n",
     "import SwiftUI\n\nstruct Y40Item { var n = 0 }\n\nstruct Y40: View {\n    @State private var item = Y40Item()\n    var body: some View { Text(\"x\").onChange(of: item) { } }\n}\n")

pair("Y41", "binding", "ForEach over values with a $binding closure parameter", D + "Y41.swift",
     "import SwiftUI\n\nstruct Y41Row: Identifiable { let id = UUID(); var name = \"\" }\n\nstruct Y41: View {\n    @State private var rows = [Y41Row()]\n    var body: some View {\n        ForEach($rows) { $row in TextField(\"Name\", text: $row.name) }\n    }\n}\n",
     "import SwiftUI\n\nstruct Y41Row: Identifiable { let id = UUID(); var name = \"\" }\n\nstruct Y41: View {\n    @State private var rows = [Y41Row()]\n    var body: some View {\n        ForEach(rows) { $row in TextField(\"Name\", text: $row.name) }\n    }\n}\n")

pair("Y42", "label", "FormatStyle .currency(\"EUR\") without code:", D + "Y42.swift",
     "import SwiftUI\n\nstruct Y42: View {\n    var body: some View { Text(24.9, format: .currency(code: \"EUR\")) }\n}\n",
     "import SwiftUI\n\nstruct Y42: View {\n    var body: some View { Text(24.9, format: .currency(\"EUR\")) }\n}\n")

pair("Y43", "nonexistent", "misspelled environment key path \\.calender", D + "Y43.swift",
     "import SwiftUI\n\nstruct Y43: View {\n    @Environment(\\.calendar) private var calendar\n    var body: some View { Text(calendar.identifier == .gregorian ? \"g\" : \"o\") }\n}\n",
     "import SwiftUI\n\nstruct Y43: View {\n    @Environment(\\.calender) private var calendar\n    var body: some View { Text(calendar.identifier == .gregorian ? \"g\" : \"o\") }\n}\n")

pair("Y44", "type", "navigationDestination(for:) with a non-Hashable type", D + "Y44.swift",
     "import SwiftUI\n\nstruct Y44Route: Hashable { var id = 0 }\n\nstruct Y44: View {\n    var body: some View {\n        NavigationStack { Text(\"x\").navigationDestination(for: Y44Route.self) { Text(\"\\($0.id)\") } }\n    }\n}\n",
     "import SwiftUI\n\nstruct Y44Route { var id = 0 }\n\nstruct Y44: View {\n    var body: some View {\n        NavigationStack { Text(\"x\").navigationDestination(for: Y44Route.self) { Text(\"\\($0.id)\") } }\n    }\n}\n")

pair("Y45", "nonexistent", "tabViewStyle(.paging) (it is .page)", D + "Y45.swift",
     "import SwiftUI\n\nstruct Y45: View {\n    var body: some View {\n        TabView { Text(\"a\"); Text(\"b\") }.tabViewStyle(.page(indexDisplayMode: .never))\n    }\n}\n",
     "import SwiftUI\n\nstruct Y45: View {\n    var body: some View {\n        TabView { Text(\"a\"); Text(\"b\") }.tabViewStyle(.paging)\n    }\n}\n")

pair("Y46", "await", "for await over an AsyncSequence in a synchronous function", D + "Y46.swift",
     "import Foundation\n\nenum Y46 {\n    static func watch() async {\n        for await _ in NotificationCenter.default.notifications(named: QuickLogQueue.didEnqueue) { break }\n    }\n}\n",
     "import Foundation\n\nenum Y46 {\n    static func watch() {\n        for await _ in NotificationCenter.default.notifications(named: QuickLogQueue.didEnqueue) { break }\n    }\n}\n")

pair("Y47", "target", "app-only type (AppState) referenced from Shared/ (widget target)", "Shared/Y47.swift",
     "import Foundation\n\nenum Y47 {\n    static func title(_ s: WidgetSnapshot) -> String { s.ticketName }\n}\n",
     "import Foundation\n\nenum Y47 {\n    @MainActor static func title(_ s: AppState) -> String { s.settings.homeStationID ?? \"\" }\n}\n")

pair("Y48", "widget", "containerBackground(_:) without for: .widget", "Widgets/Sources/Y48View.swift",
     "import WidgetKit\nimport SwiftUI\n\nstruct Y48View: View {\n    var body: some View { Text(\"x\").containerBackground(.fill.tertiary, for: .widget) }\n}\n",
     "import WidgetKit\nimport SwiftUI\n\nstruct Y48View: View {\n    var body: some View { Text(\"x\").containerBackground(.fill.tertiary) }\n}\n")

pair("Y49", "widget", "AppIntentTimelineProvider with the TimelineProvider method names", "Widgets/Sources/Y49Provider.swift",
     "import WidgetKit\nimport AppIntents\n\nstruct Y49Config: WidgetConfigurationIntent {\n    static var title: LocalizedStringResource = \"Y49\"\n}\n\nstruct Y49Provider: AppIntentTimelineProvider {\n    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: nil, isPreview: true) }\n    func snapshot(for configuration: Y49Config, in context: Context) async -> SnapshotEntry { placeholder(in: context) }\n    func timeline(for configuration: Y49Config, in context: Context) async -> Timeline<SnapshotEntry> {\n        Timeline(entries: [placeholder(in: context)], policy: .never)\n    }\n}\n",
     "import WidgetKit\nimport AppIntents\n\nstruct Y49Config: WidgetConfigurationIntent {\n    static var title: LocalizedStringResource = \"Y49\"\n}\n\nstruct Y49Provider: AppIntentTimelineProvider {\n    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: nil, isPreview: true) }\n    func getSnapshot(for configuration: Y49Config, in context: Context, completion: @escaping (SnapshotEntry) -> Void) { completion(placeholder(in: context)) }\n    func getTimeline(for configuration: Y49Config, in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {\n        completion(Timeline(entries: [placeholder(in: context)], policy: .never))\n    }\n}\n")

pair("Y50", "isolation", "UIKit main-actor API (UIDevice) used from a nonisolated static func", D + "Y50.swift",
     "import UIKit\n\nenum Y50 {\n    @MainActor static func model() -> String { UIDevice.current.model }\n}\n",
     "import UIKit\n\nenum Y50 {\n    static func model() -> String { UIDevice.current.model }\n}\n")

# Y50: UIDevice is NS_SWIFT_UI_ACTOR from an Objective-C header (imported as @preconcurrency), so in
# Swift 5 mode the nonisolated use is only a warning in Xcode -> the harness must NOT report an error.
for _p in P:
    if _p["id"] == "Y50":
        _p["expect"] = "noerror"
