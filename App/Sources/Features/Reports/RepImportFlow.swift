import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import KlimaCore

/// "Fahrten importieren (CSV)": Datei wählen → Spalten zuordnen → Vorschau prüfen → Fertig (mit Rückgängig).
/// Presented as a large sheet from Einstellungen › Daten.
struct RepImportFlow: View {
    /// Screenshot/QA only: starts with the bundled sample file at the given step.
    var preset: RepImportPreset? = nil

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model: RepImportModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    RepImportSteps(model: model, onClose: { dismiss() })
                } else {
                    Theme.sheetBackground.ignoresSafeArea()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            guard model == nil else { return }
            let created = RepImportModel(app: app)
            preset?.apply(to: created, context: context)
            model = created
        }
    }
}

/// Pre-filled states for CI screenshots (sample CSV with a duplicate of the newest demo trip).
enum RepImportPreset {
    case pick, mapping, preview, problems, result

    @MainActor
    func apply(to model: RepImportModel, context: ModelContext) {
        guard self != .pick else { return }
        let trips = Repository(context: context, app: model.app).liveTrips()
        model.load(data: RepSampleData.csv(duplicating: trips.first), name: RepSampleData.fileName)
        guard self != .mapping else { return }
        model.buildPreview(existing: trips)
        if self == .problems { model.filter = .problems }
        if self == .result { model.performImport(context: context) }
    }
}

/// The step container: scrolling content, pale sky, bottom actions, toolbar and the file importer.
struct RepImportSteps: View {
    @Bindable var model: RepImportModel
    var onClose: () -> Void

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }) private var trips: [TripEntity]
    @State private var isPickingFile = false
    @State private var templateURL: URL?

    private var animates: Bool { !(reduceMotion || LaunchMode.isScreenshot) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                stepContent
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(model.step)
            .transition(animates ? AnyTransition.asymmetric(insertion: AnyTransition.move(edge: .trailing).combined(with: .opacity),
                                                            removal: AnyTransition.opacity)
                                 : AnyTransition.identity)
        }
        .scrollIndicators(.hidden)
        .background { SetBackdrop(skyOpacity: 0.5, fadeEnd: 0.42) }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationTitle("Fahrten importieren")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .fileImporter(isPresented: $isPickingFile,
                      allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .delimitedText, .plainText, .text]) { result in
            switch result {
            case .success(let url):
                go { model.load(url: url) }
            case .failure:
                break   // cancelled
            }
        }
        .onAppear { prepareTemplate() }
        .repHaptic(.selection, trigger: model.mappingRevision, enabled: app.settings.hapticsEnabled)
        .repHaptic(.success, trigger: model.importRevision, enabled: app.settings.hapticsEnabled)
        .repHaptic(.warning, trigger: model.undoRevision, enabled: app.settings.hapticsEnabled)
        .sensoryFeedback(trigger: model.loadError) { _, new in new != nil && app.settings.hapticsEnabled ? .error : nil }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .pick:
            RepImportPickStep(model: model)
        case .mapping:
            RepImportMappingStep(model: model)
        case .preview:
            RepImportPreviewStep(model: model)
        case .result:
            RepImportResultStep(model: model)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if model.step == .mapping || model.step == .preview {
                Button("Zurück", systemImage: "chevron.backward") { go { model.back() } }
            } else {
                Button("Schließen", systemImage: "xmark") { onClose() }
            }
        }
        if model.step == .mapping || model.step == .preview {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Abbrechen", systemImage: "xmark") { onClose() }
            }
        }
    }

    // MARK: Bottom actions

    @ViewBuilder
    private var bottomBar: some View {
        RepBottomBar {
            switch model.step {
            case .pick:
                Button {
                    isPickingFile = true
                } label: {
                    Label("CSV-Datei auswählen", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.primary)
                if let templateURL {
                    ShareLink(item: templateURL, preview: SharePreview("KlimaBilanz-Vorlage.csv")) {
                        Label("Vorlage für Excel & Numbers", systemImage: "tablecells")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glass)
                }
            case .mapping:
                Button {
                    go { model.buildPreview(existing: trips) }
                } label: {
                    Label("Vorschau ansehen", systemImage: "eye")
                }
                .buttonStyle(.primary)
                .disabled(!model.canPreview)
                if !model.canPreview {
                    Text(missingHint)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            case .preview:
                let count = model.toImport.count
                Button {
                    go { model.performImport(context: context) }
                } label: {
                    Text(count == 0 ? "Keine Fahrten zum Importieren" : "\(RepText.trips(count)) importieren · \(Format.euroPrecise(model.importValue))")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(.primary)
                .disabled(count == 0)
            case .result:
                Button("Fertig") { onClose() }
                    .buttonStyle(.primary)
                if !model.isUndone, !model.importedTrips.isEmpty {
                    Button(role: .destructive) {
                        go { model.undo(context: context) }
                    } label: {
                        Label("Import rückgängig machen", systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glass)
                    .tint(Theme.negative)
                }
            }
        }
    }

    private var missingHint: String {
        var missing: [String] = []
        if !model.hasDate { missing.append("Datum") }
        if !model.hasRoute { missing.append("Von & Nach") }
        if missing.isEmpty { return "In der Datei stehen keine Fahrten." }
        return "Ordne noch \(missing.joined(separator: " und ")) zu."
    }

    // MARK: Helpers

    private func go(_ change: () -> Void) {
        if animates {
            withAnimation(.smooth(duration: 0.35), change)
        } else {
            change()
        }
    }

    private func prepareTemplate() {
        guard templateURL == nil else { return }
        templateURL = try? Backup.temporaryFile(named: "KlimaBilanz-Vorlage.csv", data: Data(TripCSVExport.template().utf8))
    }
}

// MARK: - Step 1: pick a file

struct RepImportPickStep: View {
    let model: RepImportModel

    var body: some View {
        RepStepHeader(step: 1, total: 3, title: "Fahrten importieren",
                      message: "Hol deine bisherigen Fahrten aus Excel, Numbers, dem KlimaTicket Tracker oder einem KlimaBilanz-Export.")
            .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)

        RepCSVIllustration()

        if let error = model.loadError {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.negative)
                    .accessibilityHidden(true)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.negative.opacity(0.12), in: .rect(cornerRadius: Theme.Radius.tile, style: .continuous))
            .accessibilityElement(children: .combine)
        }

        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                RepFeatureRow(symbol: "wand.and.stars", tint: Theme.dusk, title: "Erkennt dein Format",
                              message: "Semikolon, Komma oder Tab · UTF-8 oder Windows-1252 · Datum als 9.10.2026 oder 2026-10-09.")
                RepFeatureRow(symbol: "eurosign", tint: Theme.pine, title: "Beträge exakt",
                              message: "„1,50“ bleibt € 1,50 – auch „1.234,50“, „13.40“ und „€ 13,40“ werden richtig gelesen.")
                RepFeatureRow(symbol: "tram.fill", tint: Theme.glacier, title: "Preise ergänzt",
                              message: "Fehlt ein Preis, schätzen wir den ÖBB-Normalpreis – genau wie beim Erfassen.")
                RepFeatureRow(symbol: "doc.on.doc.fill", tint: Theme.gold, title: "Nichts doppelt",
                              message: "Fahrten, die du schon hast (gleicher Tag, Strecke und Preis), erkennen wir vorab.")
            }
        }
    }
}

/// Mini spreadsheet → recognised trip: shows at a glance what the import does (and that "1,50" stays € 1,50).
struct RepCSVIllustration: View {
    private let header = ["Datum", "Von", "Nach", "Preis"]
    private let rows = [["09.10.", "Salzburg", "Wien", "65,90"], ["10.10.", "Linz", "Wels", "7.20"], ["11.10.", "Bregenz", "Dornbirn", "1,50"]]

    var body: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(spacing: Theme.Spacing.s) {
                grid
                Image(systemName: "arrow.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                recognised
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Beispiel: Aus der Zeile Bregenz, Dornbirn, 1,50 wird die Fahrt Bregenz nach Dornbirn um 1 Euro 50.")
    }

    private var grid: some View {
        VStack(spacing: 0) {
            line(header, isHeader: true, highlight: false)
            ForEach(rows.indices, id: \.self) { index in
                Rectangle().fill(Theme.separator).frame(height: 0.5)
                line(rows[index], isHeader: false, highlight: index == rows.count - 1)
            }
        }
        .background(Theme.surface, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.separator, lineWidth: 0.5))
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }

    private func line(_ cells: [String], isHeader: Bool, highlight: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(cells.indices, id: \.self) { i in
                Text(cells[i])
                    .font(isHeader ? .caption.weight(.semibold) : .caption.monospacedDigit())
                    .foregroundStyle(isHeader ? Theme.accentText : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: i == cells.count - 1 ? .trailing : .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background {
                        if highlight && i == cells.count - 1 {
                            Theme.pine.opacity(0.16)
                        }
                    }
            }
        }
        .background(isHeader ? Theme.glacier.opacity(0.10) : Color.clear)
    }

    private var recognised: some View {
        HStack(spacing: Theme.Spacing.s) {
            ModeIcon(mode: .bus, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Bregenz → Dornbirn")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Bus · 11. Okt.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            HStack(spacing: 4) {
                Text("€ 1,50")
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.positive)
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }
}
