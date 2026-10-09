import SwiftUI
import KlimaCore

/// App updates (version, status, check, auto-check, AltStore/SideStore source) and the tariff catalog state.
struct SetUpdatesSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL

    /// Owned by SettingsView, which presents the sheet at list level.
    @Binding var showsUpdateSheet: Bool

    @State private var isRefreshingTariffs = false
    /// A check started here failed (no toast for it: one error haptic and the status line says why).
    @State private var checkFailedTrigger = 0
    /// The available release as shown: mirrored from the service so its row folds in with a spring when a check
    /// finds it, instead of popping into the list.
    @State private var shownManifest: UpdateManifest?
    @State private var sparkleTrigger = 0

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
                if let manifest = shownManifest {
                    availableRow(manifest)
                        .motionTransition(.rise)
                }
                Toggle(isOn: $settings.autoUpdateCheck) {
                    SetRowLabel(title: "Automatisch prüfen", subtitle: "Beim Start und alle paar Stunden",
                                symbol: "clock.arrow.circlepath", tint: Theme.pine)
                        .setSymbolOnEnable(settings.autoUpdateCheck, .rotate)
                }
                .haptic(.selection, trigger: settings.autoUpdateCheck)
                if app.updates.showsSideloadOptions {
                    if !UpdateService.isDirectInstallCopy {   // MARK: ota – an ad-hoc copy needs no store source
                        sourceRow(title: "AltStore-Quelle hinzufügen", symbol: "plus.square.on.square",
                                  tint: Theme.modeColor(.sBahn), url: app.updates.altStoreSourceURL)
                        sourceRow(title: "SideStore-Quelle hinzufügen", symbol: "square.stack.3d.up.fill",
                                  tint: Theme.modeColor(.tram), url: app.updates.sideStoreSourceURL)
                    }
                    directInstallRow   // MARK: ota
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
        // On the always-present first row: mirrors the found release into `shownManifest`.
        .onChange(of: app.updates.availableManifest, initial: true) { old, new in
            guard shownManifest != new else { return }
            if old == new {
                shownManifest = new   // initial: the row is simply there
            } else {
                withMotion(Motion.smooth) { shownManifest = new }
            }
        }
    }

    /// The relative time ("geprüft vor 5 Minuten") moves on while Settings stays open. Each state morphs into the
    /// next: the clock turns into circling arrows while checking, then into the check or the arrow of a new version.
    private var statusLabel: some View {
        TimelineView(.everyMinute) { timeline in
            let status = currentStatus(now: timeline.date)
            HStack(spacing: 5) {
                Image(systemName: status.symbol)
                    .symbolReplaceTransition()
                    .setBusySymbol(isChecking)
                Text(status.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(status.color)
            .padding(.top, 2)
        }
        .motionAnimation(Motion.smooth, value: app.updates.state)
    }

    private var isChecking: Bool { app.updates.state == .checking }

    private func currentStatus(now: Date) -> Status {
        switch app.updates.state {
        case .notConfigured:
            return Status(text: "Update-Quelle nicht eingerichtet", symbol: "questionmark.circle", color: Theme.textSecondary)
        case .idle:
            let text = app.updates.lastCheck.map { "Zuletzt geprüft \(SetFormat.relative($0, now: now))" } ?? "Noch nicht geprüft"
            return Status(text: text, symbol: "clock", color: Theme.textSecondary)
        case .checking:
            return Status(text: "Suche nach Updates …", symbol: "arrow.triangle.2.circlepath", color: Theme.textSecondary)
        case .upToDate(let checkedAt):
            return Status(text: "Aktuell · geprüft \(SetFormat.relative(checkedAt, now: now))", symbol: "checkmark.circle.fill", color: Theme.positiveText)
        case .available(let manifest):
            return Status(text: "Version \(SetFormat.shortVersion(manifest.version)) ist verfügbar", symbol: "arrow.down.circle.fill", color: Theme.accentText)
        case .required(let manifest):
            return Status(text: "Update auf \(SetFormat.shortVersion(manifest.version)) erforderlich", symbol: "exclamationmark.triangle.fill", color: Theme.summitText)
        case .failed(let message):
            return Status(text: message, symbol: "exclamationmark.triangle.fill", color: Theme.negative)
        }
    }

    /// The arrow in the tile turns while the check runs. The result answers for itself: the sheet, the "aktuell"
    /// toast (with its haptic) or – on failure – one error haptic and the status line.
    private var checkRow: some View {
        Button {
            Task { await checkForUpdates() }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                SetRowLabel(title: "Nach Updates suchen", symbol: "arrow.clockwise", tint: Theme.glacier, isBusy: isChecking)
                Spacer(minLength: Theme.Spacing.xs)
                SetBusyIndicator(isBusy: isChecking)
            }
        }
        .disabled(isChecking || app.updates.state == .notConfigured)
        .haptic(.error, trigger: checkFailedTrigger)
        .accessibilityValue(isChecking ? "Wird geprüft" : "")
    }

    /// A found release folds into the list; its sparkles glint once to draw the eye.
    private func availableRow(_ manifest: UpdateManifest) -> some View {
        Button {
            showsUpdateSheet = true
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                SetRowLabel(title: "Version \(SetFormat.shortVersion(manifest.version)) ansehen",
                            subtitle: manifest.releaseNotes.first, symbol: "sparkles", tint: Theme.dawn)
                    .setSymbolEffect(.wiggle, trigger: sparkleTrigger)
                Spacer(minLength: Theme.Spacing.xs)
                SetPill(text: "Neu", tint: Theme.accentText)
            }
        }
        .task(id: manifest.version.description) {
            guard !MotionPolicy.isStatic else { return }
            try? await Task.sleep(for: .milliseconds(450))
            sparkleTrigger += 1
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

    // MARK: ota – Direkt installieren: the state for our own ad-hoc copy, otherwise the iPhone-only setup guide.
    private var directInstallRow: some View {
        Button {
            openURL(Copy.Updates.directInstallGuideURL)
        } label: {
            SetRowLabel(title: Copy.Updates.directInstallRowTitle,
                        subtitle: UpdateService.isDirectInstallCopy ? Copy.Updates.directInstallRowActive : Copy.Updates.directInstallRowGuide,
                        symbol: "arrow.down.app.fill", tint: Theme.pine)
        }
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
                .setSymbolEffect(.bounce, trigger: app.catalog.version)
            Spacer(minLength: Theme.Spacing.xs)
            SetPill(text: "v\(app.catalog.version)", tint: Theme.summitText)
                .numericValue(Double(app.catalog.version))
        }
        .motionAnimation(Motion.smooth, value: app.catalog.version)
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

    /// The arrows turn while the catalogue loads; the toast (and its haptic) reports the result.
    private var refreshTariffsRow: some View {
        Button {
            Task { await refreshTariffs() }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                SetRowLabel(title: "Tarife aktualisieren",
                            subtitle: hasTariffSource ? nil : "Keine Online-Quelle eingerichtet",
                            symbol: "arrow.triangle.2.circlepath", tint: Theme.glacier, isBusy: isRefreshingTariffs)
                Spacer(minLength: Theme.Spacing.xs)
                SetBusyIndicator(isBusy: isRefreshingTariffs)
            }
        }
        .disabled(isRefreshingTariffs || !hasTariffSource)
        .accessibilityValue(isRefreshingTariffs ? "Wird aktualisiert" : "")
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
        } else if case .failed = app.updates.state {
            checkFailedTrigger += 1
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
