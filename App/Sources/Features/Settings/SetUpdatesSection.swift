import SwiftUI
import KlimaCore

/// App updates (version, status, check, auto-check, AltStore/SideStore source) and the tariff catalog state.
struct SetUpdatesSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL

    /// Owned by SettingsView, which presents the sheet at list level.
    @Binding var showsUpdateSheet: Bool

    @State private var isRefreshingTariffs = false
    @State private var checkTrigger = 0
    @State private var tariffTrigger = 0

    private struct Status {
        var text: String
        var symbol: String
        var color: Color
    }

    var body: some View {
        @Bindable var settings = app.settings
        Section {
            Group {
                versionRow
                checkRow
                if let manifest = app.updates.availableManifest {
                    availableRow(manifest)
                }
                Toggle(isOn: $settings.autoUpdateCheck) {
                    SetRowLabel(title: "Automatisch prüfen", subtitle: "Beim Start und alle paar Stunden",
                                symbol: "clock.arrow.circlepath", tint: Theme.pine)
                }
                if app.updates.showsSideloadOptions {
                    sourceRow(title: "AltStore-Quelle hinzufügen", symbol: "plus.square.on.square",
                              tint: Theme.modeColor(.sBahn), url: app.updates.altStoreSourceURL)
                    sourceRow(title: "SideStore-Quelle hinzufügen", symbol: "square.stack.3d.up.fill",
                              tint: Theme.modeColor(.tram), url: app.updates.sideStoreSourceURL)
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Updates")
        } footer: {
            SetFooter(text: app.updates.channelFooter)
        }

        Section {
            Group {
                tariffRow
                refreshTariffsRow
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Ticketpreise & Tarife")
        } footer: {
            SetFooter(text: "Ticketpreise und das Tarifmodell aktualisieren sich automatisch, sobald online neue Werte liegen – ohne App-Update.")
        }
    }

    // MARK: App version

    private var versionRow: some View {
        HStack(spacing: Theme.Spacing.m) {
            SetAppIconView(size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text("KlimaBilanz \(AppConfig.appVersion)")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Build \(AppConfig.buildNumber)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                statusLabel
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusLabel: some View {
        let status = currentStatus
        HStack(spacing: 5) {
            if isChecking {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: status.symbol)
            }
            Text(status.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(status.color)
        .padding(.top, 2)
    }

    private var isChecking: Bool { app.updates.state == .checking }

    private var currentStatus: Status {
        switch app.updates.state {
        case .notConfigured:
            return Status(text: "Update-Quelle nicht eingerichtet", symbol: "questionmark.circle", color: Theme.textSecondary)
        case .idle:
            let text = app.updates.lastCheck.map { "Zuletzt geprüft \(SetFormat.relative($0))" } ?? "Noch nicht geprüft"
            return Status(text: text, symbol: "clock", color: Theme.textSecondary)
        case .checking:
            return Status(text: "Suche nach Updates …", symbol: "arrow.triangle.2.circlepath", color: Theme.textSecondary)
        case .upToDate(let checkedAt):
            return Status(text: "Aktuell · geprüft \(SetFormat.relative(checkedAt))", symbol: "checkmark.circle.fill", color: Theme.positiveText)
        case .available(let manifest):
            return Status(text: "Version \(SetFormat.shortVersion(manifest.version)) ist verfügbar", symbol: "arrow.down.circle.fill", color: Theme.accentText)
        case .required(let manifest):
            return Status(text: "Update auf \(SetFormat.shortVersion(manifest.version)) erforderlich", symbol: "exclamationmark.triangle.fill", color: Theme.summitText)
        case .failed(let message):
            return Status(text: message, symbol: "exclamationmark.triangle.fill", color: Theme.negative)
        }
    }

    private var checkRow: some View {
        Button {
            checkTrigger += 1
            Task { await checkForUpdates() }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                SetRowLabel(title: "Nach Updates suchen", symbol: "arrow.clockwise", tint: Theme.glacier)
                Spacer(minLength: Theme.Spacing.xs)
                if isChecking {
                    ProgressView()
                }
            }
        }
        .disabled(isChecking || app.updates.state == .notConfigured)
        .settingsHaptic(.impact(weight: .light), trigger: checkTrigger, enabled: app.settings.hapticsEnabled)
    }

    private func availableRow(_ manifest: UpdateManifest) -> some View {
        Button {
            showsUpdateSheet = true
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                SetRowLabel(title: "Version \(SetFormat.shortVersion(manifest.version)) ansehen",
                            subtitle: manifest.releaseNotes.first, symbol: "sparkles", tint: Theme.dawn)
                Spacer(minLength: Theme.Spacing.xs)
                SetPill(text: "Neu", tint: Theme.accentText)
            }
        }
    }

    private func sourceRow(title: String, symbol: String, tint: Color, url: URL?) -> some View {
        Button {
            guard let url else { return }
            openURL(url) { accepted in
                // altstore:// / sidestore:// do nothing when the store isn't installed – say so instead of failing silently.
                if !accepted { app.showToast("exclamationmark.triangle.fill", "App nicht gefunden", "Installiere zuerst AltStore oder SideStore") }
            }
        } label: {
            SetRowLabel(title: title, subtitle: sourceSubtitle(available: url != nil), symbol: symbol, tint: tint)
        }
        .disabled(url == nil)
    }

    private func sourceSubtitle(available: Bool) -> String {
        if available { return Copy.Updates.sourceRowSubtitle }
        return app.updates.state == .notConfigured ? "Update-Quelle nicht eingerichtet" : "Verfügbar nach der ersten Update-Prüfung"
    }

    // MARK: Tariffs

    /// Whether an online source for the tariff catalog is configured (update manifest hint or AppConfig).
    private var hasTariffSource: Bool {
        app.updates.manifest?.tariffsURL.flatMap(URL.init(string:)) != nil || app.config.remoteTariffs != nil
    }

    private var tariffRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            SetRowLabel(title: "Tarif-Stand", subtitle: tariffSubtitle, symbol: "tag.fill", tint: Theme.dawn)
            Spacer(minLength: Theme.Spacing.xs)
            SetPill(text: "v\(app.catalog.version)", tint: Theme.summitText)
        }
        .accessibilityElement(children: .combine)
    }

    private var tariffSubtitle: String {
        var parts: [String] = []
        if let day = SetFormat.isoDay(app.catalog.updatedAt) {
            parts.append("Stand \(Format.date(day))")
        } else if !app.catalog.updatedAt.isEmpty {
            parts.append("Stand \(app.catalog.updatedAt)")
        }
        parts.append(SetFormat.count(app.catalog.products.count, "Ticketpreis", "Ticketpreise"))
        if let refreshed = app.tariffs.lastRefresh {
            parts.append("geprüft \(SetFormat.relative(refreshed))")
        }
        return parts.joined(separator: " · ")
    }

    private var refreshTariffsRow: some View {
        Button {
            tariffTrigger += 1
            Task { await refreshTariffs() }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                SetRowLabel(title: "Tarife aktualisieren",
                            subtitle: hasTariffSource ? nil : "Keine Online-Quelle eingerichtet",
                            symbol: "arrow.triangle.2.circlepath", tint: Theme.glacier)
                Spacer(minLength: Theme.Spacing.xs)
                if isRefreshingTariffs {
                    ProgressView()
                }
            }
        }
        .disabled(isRefreshingTariffs || !hasTariffSource)
        .settingsHaptic(.impact(weight: .light), trigger: tariffTrigger, enabled: app.settings.hapticsEnabled)
    }

    // MARK: Actions

    private func checkForUpdates() async {
        await app.updates.checkIfDue(force: true)
        if app.updates.isPresentingSheet {
            // Present from here – the root sheet cannot appear while settings are on screen.
            app.updates.isPresentingSheet = false
            showsUpdateSheet = true
        } else if case .upToDate = app.updates.state {
            app.showToast("checkmark.circle.fill", "KlimaBilanz ist aktuell", "Version \(AppConfig.appVersion)")
        }
    }

    private func refreshTariffs() async {
        isRefreshingTariffs = true
        let before = app.catalog.version
        let refreshedBefore = app.tariffs.lastRefresh
        let updated = await app.tariffs.refreshIfNeeded(manifestHint: app.updates.manifest, force: true)
        app.reloadCatalog()
        isRefreshingTariffs = false
        // `refreshIfNeeded` returns false both for "nothing newer" and for failures; only a successful download
        // moves `lastRefresh`, which tells the two apart.
        let reachedServer = app.tariffs.lastRefresh != refreshedBefore
        if updated || app.catalog.version > before {
            app.showToast("checkmark.circle.fill", "Tarife aktualisiert", "Tarif-Version \(app.catalog.version)")
        } else if reachedServer {
            app.showToast("checkmark.circle.fill", "Tarife sind aktuell", "Tarif-Version \(app.catalog.version)")
        } else {
            app.showToast("exclamationmark.triangle.fill", "Tarife nicht erreichbar", "Bitte später noch einmal versuchen")
        }
    }
}
