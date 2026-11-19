import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import KlimaCore

// MARK: data – Einstellungen › Daten & Sicherung (docs/DATA_HUB.md §6): what is on this iPhone, the week of backups, Exportieren,
// Tägliche Sicherung, Jetzt sichern, the list of backups with the honest banner, and Wiederherstellen with a preview first.

struct DataHubView: View {
    /// CI scenes: scroll to a section after the first frame.
    var screenshotAnchor: DataHubAnchor? = nil

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }) private var trips: [TripEntity]
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }) private var favorites: [FavoriteRouteEntity]
    @Query(filter: #Predicate<BenefitEntity> { $0.deletedAt == nil }) private var benefits: [BenefitEntity]

    @State private var isImporting = false
    @State private var isPreparing = false
    @State private var preview: DataHubRestorePreview?

    private var service: AutoBackupService { .shared }

    private var counts: DataHubCounts {
        DataHubCounts(trips: DataHubCounts.tripCount(trips.map { $0.journeyID?.uuidString }), tickets: tickets.count,
                      favorites: favorites.count, benefits: benefits.count)
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    DataHubHero(counts: counts, files: service.files, isAutoOn: service.isEnabled)
                        .reveal(order: 0)
                        .listRowBackground(Theme.surface)
                } footer: {
                    SetFooter(text: DataHubText.privacy)
                }
                exportSection
                backupSection
                    .id(DataHubAnchor.backups)
                restoreSection
                    .id(DataHubAnchor.restore)
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(Theme.Spacing.l)
            .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
            .scrollContentBackground(.hidden)
            .background { SetBackdrop() }
            .tint(Theme.accent)
            .navigationTitle("Daten & Sicherung")
            .navigationBarTitleDisplayMode(typeSize.isAccessibilitySize ? .inline : .large)   // the long title would be cut
            .revealScope()
            .motionAnimation(Motion.smooth, value: service.files.map(\.name))
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): open(url)
                case .failure: app.showToast("exclamationmark.triangle.fill", "Import abgebrochen", "Die Datei konnte nicht geöffnet werden.")
                }
            }
            .sheet(item: $preview) { preview in
                DataHubRestoreSheet(preview: preview)
            }
            .task {
                await service.refresh()
                guard let screenshotAnchor else { return }
                try? await Task.sleep(for: .milliseconds(450))
                proxy.scrollTo(screenshotAnchor, anchor: .top)
            }
        }
    }

    // MARK: Sections

    private var exportSection: some View {
        Section {
            NavigationLink {
                DataHubExportView()
            } label: {
                SetRowLabel(title: "Exportieren", subtitle: "Komplettsicherung, Tabellen, Kalender und Text – für ein Ticketjahr, ein Kalenderjahr oder alles",
                            symbol: "square.and.arrow.up.on.square.fill", tint: Theme.glacier)
            }
            .listRowBackground(Theme.surface)
            RepReportSettingsRow()
                .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Exportieren")
        }
    }

    private var backupSection: some View {
        Section {
            Toggle(isOn: Binding(get: { service.isEnabled }, set: { on in withMotion(Motion.smooth) { service.isEnabled = on } })) {
                SetRowLabel(title: "Tägliche Sicherung", subtitle: "Einmal am Tag, wenn du die App verlässt und sich etwas geändert hat",
                            symbol: "clock.arrow.circlepath", tint: Theme.pine)
            }
            .listRowBackground(Theme.surface)
            Button(action: backupNow) {
                HStack(spacing: Theme.Spacing.s) {
                    SetRowLabel(title: "Jetzt sichern", subtitle: service.isWriting ? "Wird gesichert …" : "Eine Sicherung sofort, in Dateien",
                                symbol: "externaldrive.fill.badge.plus", tint: Theme.dusk, isBusy: service.isWriting, busyStyle: .pulse)
                    Spacer(minLength: Theme.Spacing.xs)
                    SetBusyIndicator(isBusy: service.isWriting)
                }
                .motionAnimation(Motion.snappy, value: service.isWriting)
            }
            .disabled(service.isWriting || counts.isEmpty)
            .listRowBackground(Theme.surface)
            NavigationLink {
                DataHubBackupsView()
            } label: {
                SetRowLabel(title: "Sicherungen ansehen", subtitle: listSubtitle, symbol: "folder.fill", tint: Theme.gold)
            }
            .listRowBackground(Theme.surface)
            DataHubBanner()
                .listRowBackground(Theme.summitText.opacity(0.08))
        } header: {
            SetSectionHeader(title: "Sicherungen")
        } footer: {
            SetFooter(text: DataHubText.retention)
        }
    }

    private var restoreSection: some View {
        Section {
            Button { isImporting = true } label: {
                HStack(spacing: Theme.Spacing.s) {
                    SetRowLabel(title: "Aus Datei wiederherstellen …", subtitle: isPreparing ? "Datei wird gelesen …" : "Du siehst vorher, was sich ändert",
                                symbol: "arrow.down.doc.fill", tint: Theme.dusk, isBusy: isPreparing, busyStyle: .pulse)
                    Spacer(minLength: Theme.Spacing.xs)
                    SetBusyIndicator(isBusy: isPreparing)
                }
            }
            .disabled(isPreparing)
            .listRowBackground(Theme.surface)
            RepImportSettingsRow()
                .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Wiederherstellen")
        } footer: {
            SetFooter(text: BackupDiff.rule + " Vorher legt KlimaBilanz eine Sicherung an.")
        }
    }

    private var listSubtitle: String {
        let own = service.files
        guard !own.isEmpty else { return "Noch keine – die erste entsteht, wenn du die App verlässt" }
        let size = own.reduce(0) { $0 + $1.size }
        return DataHubText.keep("\(DataHubFormat.count(own.count, "Sicherung", "Sicherungen")) · \(DataHubFormat.bytes(size))")
    }

    // MARK: Actions

    private func backupNow() {
        Task {
            do {
                let file = try await service.backupNow(container: context.container)
                app.showToast("checkmark.circle.fill", "Gesichert", "\(file.name) liegt in Dateien › KlimaBilanz › Sicherungen")
            } catch {
                app.showToast("exclamationmark.triangle.fill", "Sichern fehlgeschlagen", "Ist der Speicher voll?", haptic: .warning)
            }
        }
    }

    private func open(_ url: URL) {
        isPreparing = true
        Task {
            let result = await DataHubRestore.preview(url: url, title: url.lastPathComponent, container: context.container)
            isPreparing = false
            switch result {
            case .success(let made): preview = made
            case .failure(let failure):
                app.showToast("exclamationmark.triangle.fill", "Nicht wiederherstellbar", failure.message, haptic: .warning)
            }
        }
    }
}

enum DataHubAnchor: Hashable {
    case backups, restore
}
