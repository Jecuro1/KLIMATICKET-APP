import SwiftUI
import SwiftData
import KlimaCore
import KlimaCloud

// MARK: data – the CI scenes of Daten & Sicherung (RootView's ScreenshotRouter, `// MARK: data`). Three real version-3 files made from
// the in-memory demo data (today, two days ago, a „vor dem Löschen“ nine days ago) in the temporary folder; nothing is written to
// Documents, nothing is sent, no system alert. `dataRoundTrip` exports the demo data and restores it into an empty store.

enum DataHubDemo {
    /// Demo settings for the files (a screenshot run has none of the person's): Look & Feel, the radar's display, Pendeln.
    static let settings: [String: BackupSettingValue] = [
        "theme.v1": .data(Data(#"{"palette":"glacier"}"#.utf8)),
        "radar.display.v1": .string("{}"),
        "commute.settings.v1": .data(Data("{}".utf8)),
        "appearance": .string("dark"),
    ]

    static var folder: URL { FileManager.default.temporaryDirectory.appending(path: "DataHubDemo", directoryHint: .isDirectory) }

    /// Writes the three demo files and hands them to the service. Each holds the demo data as it was on its day.
    @MainActor
    static func install(context: ModelContext, now: Date = Date()) -> [DataHubBackupFile] {
        try? FileManager.default.removeItem(at: folder)
        let minute = Calendar.vienna.date(bySetting: .second, value: 0, of: now) ?? now
        let plan: [(Date, BackupKind)] = [
            (minute.addingTimeInterval(-47 * 60), .daily),
            (Calendar.vienna.date(byAdding: .day, value: -2, to: minute)?.addingTimeInterval(-3 * 3600) ?? minute, .daily),
            (Calendar.vienna.date(byAdding: .day, value: -9, to: minute)?.addingTimeInterval(-5 * 3600) ?? minute, .beforeDelete),
        ]
        var files: [DataHubBackupFile] = []
        for (date, kind) in plan {
            guard let data = try? file(context: context, asOf: date),
                  let written = try? DataHubFolder.write(data, kind: kind, now: date, in: folder) else { continue }
            files.append(written)
        }
        let sorted = files.sorted { $0.date > $1.date }
        AutoBackupService.shared.installDemo(sorted)
        return sorted
    }

    /// The demo data as it stood at `date`: trips logged later are left out, `exportedAt` is that moment.
    static func file(context: ModelContext, asOf date: Date) throws -> Data {
        var file = try Backup.decodeFile(try Backup.exportV3(context: context, settings: settings))
        file.trips = file.trips.filter { $0.base.date <= date }
        file.exportedAt = date
        return try seal(file)
    }

    /// The restore scene: a backup from another iPhone with 12 trips this one does not have and 3 it has older.
    static func previewFile(context: ModelContext, now: Date = Date()) throws -> Data {
        var file = try Backup.decodeFile(try Backup.exportV3(context: context, settings: settings))
        let live = file.trips.filter { $0.base.deleted_at == nil }.sorted { $0.base.date > $1.base.date }
        for (index, row) in live.prefix(3).enumerated() {
            guard let at = file.trips.firstIndex(where: { $0.base.id == row.base.id }) else { continue }
            file.trips[at].base.updated_at = now.addingTimeInterval(Double(60 + index * 60))
            file.trips[at].base.note = "Auf dem anderen iPhone ergänzt"
        }
        var journeys: [String: String] = [:]   // MARK: review-daten – a copied leg joins a new journey, not one of this iPhone
        for (index, row) in live.dropFirst(3).prefix(12).enumerated() {
            var copy = row
            copy.base.id = UUID()
            if let journey = row.base.journey_id {
                copy.base.journey_id = journeys[journey] ?? UUID().uuidString
                journeys[journey] = copy.base.journey_id
            }
            copy.base.date = row.base.date.addingTimeInterval(-Double(index + 1) * 86_400 * 7)
            copy.base.created_at = now
            copy.base.updated_at = now
            file.trips.append(copy)
        }
        file.exportedAt = Calendar.vienna.date(byAdding: .day, value: -1, to: now) ?? now
        file.appVersion = "1.3.0"
        return try seal(file)
    }

    /// The name a file from the importer shows (yesterday, 21:40).
    static func previewName(now: Date = Date()) -> String {
        let yesterday = Calendar.vienna.date(byAdding: .day, value: -1, to: now) ?? now
        let at = Calendar.vienna.date(bySettingHour: 21, minute: 40, second: 0, of: yesterday) ?? yesterday
        return BackupFileName.make(date: at, kind: .daily)
    }

    private static func seal(_ file: BackupFile) throws -> Data {
        var file = file
        file.checksum = BackupChecksum.placeholder
        file.version = BackupFormat.currentVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let sealed = BackupChecksum.seal(try encoder.encode(file)) else { throw CocoaError(.fileWriteUnknown) }
        return sealed
    }

    /// A database copy like StoreLoader keeps before an update (only listed; its files are the demo backup).
    static func storeCopy(files: [DataHubBackupFile], now: Date = Date()) -> [DataHubStoreCopy] {
        guard let first = files.first else { return [] }
        return [DataHubStoreCopy(folder: folder.appending(path: "20261101-071500-update-b412"), files: [first.url], kind: "update",
                                 date: Calendar.vienna.date(byAdding: .day, value: -18, to: now), size: 1_843_200)]
    }

    // MARK: Round trip (CI)

    struct RoundTrip: Equatable {
        var source: DataHubCounts
        var restored: DataHubCounts
        var allRows: (Int, Int)
        /// MARK: review-daten – rows with local columns (price source, lines, a route's pattern) before and after.
        var localRows: (Int, Int)
        /// MARK: review-daten – the restored store, backed up again, gives the same rows column for column (not only the same counts).
        var rowsIdentical: Bool
        var verdict: BackupChecksum.Verdict
        var size: Int

        static func == (a: RoundTrip, b: RoundTrip) -> Bool {
            a.source == b.source && a.restored == b.restored && a.allRows == b.allRows && a.localRows == b.localRows
                && a.rowsIdentical == b.rowsIdentical && a.verdict == b.verdict && a.size == b.size
        }

        var isIdentical: Bool {
            source == restored && allRows.0 == allRows.1 && localRows.0 == localRows.1 && rowsIdentical && !verdict.isDamaged
        }
    }

    /// Exports the demo store with the app's own export and restores it into an empty in-memory store; counts per table must match,
    /// and a backup of the restored store must hold the same rows, column for column (`// MARK: review-daten`).
    @MainActor
    static func roundTrip(context: ModelContext) -> RoundTrip? {
        plantLocalColumns(context: context)
        guard let data = try? Backup.export(context: context) else { return nil }
        let empty = DataSchema.makeInMemoryContainer()
        guard (try? Backup.restoreChecked(data, context: empty.mainContext)) != nil else { return nil }
        func all(_ c: ModelContext) -> Int {
            ((try? c.fetchCount(FetchDescriptor<TripEntity>())) ?? 0) + ((try? c.fetchCount(FetchDescriptor<TicketEntity>())) ?? 0)
                + ((try? c.fetchCount(FetchDescriptor<FavoriteRouteEntity>())) ?? 0) + ((try? c.fetchCount(FetchDescriptor<BenefitEntity>())) ?? 0)
        }
        func local(_ c: ModelContext) -> Int {
            let trips = ((try? c.fetch(FetchDescriptor<TripEntity>())) ?? []).filter { !TripLocalColumns(entity: $0).isEmpty }.count
            return trips + ((try? c.fetch(FetchDescriptor<FavoriteRouteEntity>())) ?? []).filter { !$0.scheduleRaw.isEmpty }.count
        }
        let again = try? Backup.export(context: empty.mainContext)
        let original = canonical(data)
        let result = RoundTrip(source: Backup.counts(context: context), restored: Backup.counts(context: empty.mainContext),
                               allRows: (all(context), all(empty.mainContext)), localRows: (local(context), local(empty.mainContext)),
                               rowsIdentical: original != nil && again.flatMap(canonical) == original,
                               verdict: BackupChecksum.verify(data), size: data.count)
        LaunchTrace.mark(result.isIdentical ? "data.roundtrip.identical" : "data.roundtrip.DIFFERENT")
        return result
    }

    /// A backup without what differs between two writes of the same rows (time of writing, app version, checksum, row order).
    static func canonical(_ data: Data) -> Data? {
        guard var file = try? Backup.decodeFile(data) else { return nil }
        file.exportedAt = Date(timeIntervalSince1970: 0)
        file.appVersion = ""
        file.checksum = nil
        file.tickets.sort { $0.id.uuidString < $1.id.uuidString }
        file.trips.sort { $0.base.id.uuidString < $1.base.id.uuidString }
        file.favorites.sort { $0.id.uuidString < $1.id.uuidString }
        file.benefits = file.benefits?.sorted { $0.id.uuidString < $1.id.uuidString }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(file)
    }

    /// The demo year has no live price and no line names: the two newest trips get them (the scene's own in-memory store), so the
    /// round trip covers the block `local` as well as the saved route's pattern the demo already has.
    @MainActor
    static func plantLocalColumns(context: ModelContext) {
        var newest = FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        newest.fetchLimit = 2
        for (index, trip) in ((try? context.fetch(newest)) ?? []).enumerated() where trip.lineSummary.isEmpty {
            trip.lineSummary = index == 0 ? "Railjet Xpress 162" : "S 1"
            trip.journeyRef = index == 0 ? "demo-journey-ref" : ""
            if index == 0 {
                trip.priceSourceRaw = PriceSource.liveOebb.rawValue
                trip.priceProvider = "ÖBB"
                trip.priceProduct = "Standard-Ticket"
                trip.priceFetchedAt = trip.date.addingTimeInterval(-86_400)
            }
        }
        try? context.save()
    }
}

/// Routes the CI scenes.
struct DataHubScreenshotHost: View {
    static let screens: Set<String> = [
        "dataHub", "exportHub", "autoBackups", "backupPreview", "backupBanner", "dataAX5", "dataHubBottom", "dataRoundTrip",
        "dataSettingsRow", "backupRowsAX5",
    ]

    let screen: String
    @Environment(\.modelContext) private var context
    @State private var files: [DataHubBackupFile]?
    @State private var preview: DataHubRestorePreview?
    @State private var roundTrip: DataHubDemo.RoundTrip?

    var body: some View {
        ZStack {
            Color.clear
            if let files { content(files) }
        }
        .dynamicTypeSize(["dataAX5", "backupBanner", "backupRowsAX5"].contains(screen) ? .accessibility5 : .large)
        .onAppear {
            let made = DataHubDemo.install(context: context)
            if screen == "backupPreview", let data = try? DataHubDemo.previewFile(context: context),
               case .success(let built) = DataHubRestore.makePreview(data: data, title: DataHubDemo.previewName(), context: context) {
                preview = built
            }
            if screen == "dataRoundTrip" { roundTrip = DataHubDemo.roundTrip(context: context) }
            files = made
        }
    }

    @ViewBuilder
    private func content(_ files: [DataHubBackupFile]) -> some View {
        switch screen {
        case "exportHub":
            NavigationStack { DataHubExportView() }
        case "autoBackups", "backupBanner", "backupRowsAX5":
            NavigationStack {
                DataHubBackupsView(screenshotChecked: Set(files.prefix(1).map(\.name)), demoStoreCopies: DataHubDemo.storeCopy(files: files),
                                   screenshotScrollsToRows: screen == "backupRowsAX5")
            }
        case "backupPreview":
            if let preview { DataHubRestoreSheet(preview: preview) }
        case "dataHubBottom":
            NavigationStack { DataHubView(screenshotAnchor: .restore) }
        case "dataRoundTrip":
            NavigationStack { DataHubRoundTripScene(result: roundTrip) }
        case "dataSettingsRow":
            NavigationStack {
                List { SetDataSection() }   // Einstellungen › Daten as it is
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(Theme.Spacing.l)
                    .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
                    .scrollContentBackground(.hidden)
                    .background { SetBackdrop() }
                    .navigationTitle("Einstellungen")
                    .navigationBarTitleDisplayMode(.inline)
            }
        default:
            NavigationStack { DataHubView() }
        }
    }
}

/// The CI check made visible: the app's own backup of the demo store, restored into an empty store, table by table.
private struct DataHubRoundTripScene: View {
    var result: DataHubDemo.RoundTrip?

    var body: some View {
        List {
            Section {
                if let result {
                    row("Fahrten", result.source.trips, result.restored.trips)
                    row("Tickets", result.source.tickets, result.restored.tickets)
                    row("Favoriten", result.source.favorites, result.restored.favorites)
                    row("Vorteile", result.source.benefits, result.restored.benefits)
                    row("Alle Zeilen (mit gelöschten)", result.allRows.0, result.allRows.1)
                    row("Mit Preisquelle, Linie oder Muster", result.localRows.0, result.localRows.1)   // MARK: review-daten
                    Label(result.rowsIdentical ? "Jede Zeile gleich, Spalte für Spalte" : "Zeilen weichen ab",
                          systemImage: result.rowsIdentical ? "equal.circle.fill" : "notequal.circle.fill")
                        .foregroundStyle(result.rowsIdentical ? Theme.positiveText : Theme.negativeText)
                    Label(result.isIdentical ? "Identisch · \(result.verdict.title) · \(DataHubFormat.bytes(result.size))" : "Unterschied gefunden",
                          systemImage: result.isIdentical ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(result.isIdentical ? Theme.positiveText : Theme.negativeText)
                } else {
                    Text("Export oder Import fehlgeschlagen").foregroundStyle(Theme.negativeText)
                }
            } header: {
                SetSectionHeader(title: "Sichern → leerer Speicher → vergleichen")
            }
            .listRowBackground(Theme.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop() }
        .navigationTitle("Rundreise-Test")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ a: Int, _ b: Int) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(a) → \(b)")
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(a == b ? Theme.positiveText : Theme.negativeText)
        }
    }
}
