import SwiftUI
import KlimaCore

// Störungen (docs/OEBB_LIVE.md §R4): the HAFAS HIM messages, filtered by mode (server side), line and Bundesland
// (on device). Every request is one user action or one pull-to-refresh.

@MainActor
@Observable
final class DisruptionsModel {
    enum Load: Equatable { case idle, loading, loaded, failed(String) }

    /// `.all` = every mode (no server filter).
    var products: ProductMask = .all
    var line = ""
    var region: AustrianRegion?
    private(set) var remarks: [Remark] = []
    private(set) var load: Load = .idle
    private(set) var fetchedAt: Date?

    var filter: DisruptionFilter {
        DisruptionFilter(products: products, line: line, region: region)
    }

    func visible(now: Date) -> [Remark] { filter.apply(remarks, now: now) }

    func reload(live: LiveDataService, now: Date = Date()) async {
        if live.isDemo {
            remarks = DemoScotty.disruptions(now: now)
            fetchedAt = now
            load = .loaded
            return
        }
        guard let service = live.timetable else { return }
        load = .loading
        do {
            remarks = try await service.remarks(filter.query(now: now))
            fetchedAt = now
            load = .loaded
        } catch is CancellationError {
            return
        } catch {
            load = .failed(LiveMessage.text(for: error))
        }
    }
}

struct DisruptionsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model = DisruptionsModel()

    var body: some View {
        NavigationStack {
            Group {
                if let reason = app.live.timetableUnavailable {
                    ScrollView {
                        PlannerUnavailableView(reason: reason, onSettings: {})
                            .padding(Theme.Spacing.cardGutter)
                    }
                } else {
                    content
                }
            }
            .ambientBackground(.standard, glow: 0.3)
            .navigationTitle("Störungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { regionMenu }
                ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } }
            }
            .searchable(text: Binding(get: { model.line }, set: { model.line = $0 }), prompt: "Linie, z. B. S 45")
            .task(id: model.products) { await model.reload(live: app.live) }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.s) {
                modeChips
                    .padding(.horizontal, -Theme.Spacing.cardGutter)
                if let fetchedAt = model.fetchedAt {
                    Text("Stand \(RealtimePresentation.time(fetchedAt))").font(.caption).foregroundStyle(Theme.textTertiary)
                }
                switch model.load {
                case .failed(let message):
                    PlannerNoticeCard(symbol: "wifi.exclamationmark", title: "Störungen nicht geladen", message: message,
                                      actionTitle: "Erneut versuchen") { Task { await model.reload(live: app.live) } }
                case .loading where model.remarks.isEmpty:
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Spacing.xl)
                default:
                    rows
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.vertical, Theme.Spacing.s)
        }
        .refreshable { await model.reload(live: app.live) }
        .motionAnimation(Motion.smooth, value: model.line)
    }

    @ViewBuilder private var rows: some View {
        let items = model.visible(now: Date())
        if items.isEmpty && model.load == .loaded {
            EmptyStateView(symbol: "checkmark.seal", title: "Keine Störungen",
                           message: model.line.isEmpty && model.region == nil
                               ? "Im gewählten Verkehrsmittel gibt es gerade nichts Neues."
                               : "Für diesen Filter gibt es gerade keine Meldung. Probier einen anderen Filter.")
        } else {
            ForEach(items, id: \.id) { remark in
                NavigationLink {
                    DisruptionDetailView(remark: remark)
                } label: {
                    DisruptionCard(remark: remark)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var modeChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.xs) {
                Chip(title: "Alle", isSelected: model.products == .all) { model.products = .all }
                ForEach(RadarMode.allCases) { mode in
                    Chip(title: mode.title, symbol: mode.symbol, isSelected: model.products == mode.products) {
                        model.products = mode.products
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.vertical, Theme.Spacing.xxs)
        }
        .scrollIndicators(.hidden)
    }

    private var regionMenu: some View {
        Menu {
            Picker("Bundesland", selection: Binding(get: { model.region }, set: { model.region = $0 })) {
                Text("Ganz Österreich").tag(AustrianRegion?.none)
                ForEach(AustrianRegion.allCases) { region in
                    Text(region.title).tag(AustrianRegion?.some(region))
                }
            }
        } label: {
            Label("Bundesland", systemImage: model.region == nil ? "map" : "map.fill")
        }
        .accessibilityValue(model.region?.title ?? "Ganz Österreich")
    }
}

/// One message: title, the first lines of text, affected lines and validity.
struct DisruptionCard: View {
    let remark: Remark

    var body: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.summit)
                        .accessibilityHidden(true)
                    Text(remark.title ?? "Störung")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                }
                if !remark.text.isEmpty {
                    Text(remark.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                }
                if !remark.affectedLines.isEmpty {
                    LineChips(lines: remark.affectedLines)
                }
                if let until = remark.validUntil {
                    Text("Gilt bis \(Format.date(until))")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Affected lines as small capsules (text, never colour alone).
struct LineChips: View {
    let lines: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(lines.prefix(4), id: \.self) { line in
                Text(line)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.surfaceSecondary, in: .capsule)
            }
            if lines.count > 4 {
                Text("+\(lines.count - 4)").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

struct DisruptionDetailView: View {
    let remark: Remark

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text(remark.title ?? "Störung")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                if !remark.affectedLines.isEmpty {
                    LineChips(lines: remark.affectedLines)
                }
                GlassCard {
                    Text(remark.text.isEmpty ? "Keine weiteren Angaben." : remark.text)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                GlassCard(padding: Theme.Spacing.m) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        if let from = remark.validFrom {
                            Label("Gilt ab \(Format.date(from))", systemImage: "calendar")
                        }
                        if let until = remark.validUntil {
                            Label("Gilt bis \(Format.date(until))", systemImage: "calendar.badge.clock")
                        }
                        if let modified = remark.modifiedAt {
                            Label("Zuletzt geändert \(Format.date(modified))", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                }
                Text("Quelle: ÖBB-Fahrplanauskunft. KlimaBilanz prüft die Meldungen nicht selbst.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Spacing.cardGutter)
        }
        .ambientBackground(.standard, glow: 0.3)
        .navigationTitle("Störung")
        .navigationBarTitleDisplayMode(.inline)
    }
}
