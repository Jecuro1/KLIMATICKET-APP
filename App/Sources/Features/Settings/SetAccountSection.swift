import SwiftUI
import SwiftData
import UIKit
import KlimaCore

/// Profile card + "Konto" section: identity, provider, storage, sync status, sign-in, cloud setup.
/// Sign-out and account deletion live in their own section at the end of the list (`SetSignOutSection`).
struct SetAccountSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }) private var trips: [TripEntity]

    /// The screen header ("SERVUS, LENA" · "Einstellungen") sits above the profile card as this section's header.
    var screenHeader: SetScreenHeader? = nil

    @State private var showsConnect = false

    /// The signed-in profile; CI screenshots show the demo ticket holder so the screen is fully populated.
    private var profile: UserProfile? {
        app.auth.profile ?? (LaunchMode.isScreenshot ? SetDemo.profile : nil)
    }

    private var isCloudActive: Bool { (profile?.isCloud ?? false) && app.auth.isCloudAvailable }

    /// Memoised (AnalyticsMemo): the dashboard behind the sheet asks for the same period, so this is a cache hit.
    private var snapshot: AnalyticsSnapshot? {
        guard let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) else { return nil }
        return Analytics.make(ticket: ticket, trips: trips, catalog: app.catalog)
    }

    private var hasAccountRows: Bool { profile != nil || !app.auth.isCloudAvailable }

    /// Without the Cloudflare backend only native Sign in with Apple (signed builds) works – the web flows all need the cloud.
    private var canSignIn: Bool { app.auth.isCloudAvailable || AppConfig.supportsNativeAppleSignIn }

    var body: some View {
        Section {
            SetProfileCard(profile: profile, isCloudActive: isCloudActive, canSignIn: canSignIn, snapshot: snapshot,
                           onSignedIn: didSignIn)
                .reveal(order: 1)
                .listRowBackground(SetProfileCardBackground())
                .listRowInsets(EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18))
                .onChange(of: app.auth.profile?.id) { _, _ in
                    // Signed out or the account was deleted (from the section at the end of the list).
                    showsConnect = false
                }
        } header: {
            if let screenHeader {
                screenHeader
            }
        }
        if hasAccountRows {
            Section {
                Group {
                    accountRows
                }
                .listRowBackground(Theme.surface)
            } header: {
                SetSectionHeader(title: "Konto")
            } footer: {
                SetFooter(text: footerText)
            }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var accountRows: some View {
        if let profile {
            if isCloudActive {
                SetSyncRows()
            } else if app.auth.isCloudAvailable || (profile.provider == .local && AppConfig.supportsNativeAppleSignIn) {
                connectRow
                if showsConnect {
                    AuthButtonStack(onSignedIn: didSignIn)
                        .padding(.vertical, Theme.Spacing.xs)
                        .motionTransition(.rise)
                }
            }
        }
        if !app.auth.isCloudAvailable {
            NavigationLink {
                SetCloudSetupPage()
            } label: {
                SetRowLabel(title: "Cloud-Sync einrichten", subtitle: "Konten & Abgleich zwischen deinen Geräten",
                            symbol: "icloud.fill", tint: Theme.modeColor(.sBahn))
            }
        }
    }

    private var connectRow: some View {
        Button {
            withMotion(Motion.smooth) { showsConnect.toggle() }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                SetRowLabel(title: "Mit Konto verbinden",
                            subtitle: app.auth.isCloudAvailable ? "Für Sync zwischen deinen Geräten" : "Mit Apple – Daten bleiben auf diesem iPhone",
                            symbol: "person.crop.circle.badge.plus", tint: Theme.glacier)
                Spacer(minLength: Theme.Spacing.xs)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .rotationEffect(.degrees(showsConnect ? 180 : 0))
                    .accessibilityHidden(true)
            }
        }
        .haptic(.tap, trigger: showsConnect)
        .accessibilityValue(showsConnect ? "Aufgeklappt" : "Zugeklappt")
    }

    private var footerText: String {
        if isCloudActive {
            return "Deine Fahrten werden verschlüsselt mit deiner persönlichen Cloud-Datenbank abgeglichen – nur du hast Zugriff."
        }
        if !app.auth.isCloudAvailable {
            return "Ohne Cloud bleiben alle Daten ausschließlich auf diesem iPhone. Sichere sie ab und zu unter „Daten“."
        }
        return "Mit einem Konto sind deine Fahrten auf all deinen Geräten gesichert."
    }

    // MARK: Actions

    private func didSignIn() {
        withMotion(Motion.smooth) { showsConnect = false }
        let name = app.auth.profile?.displayName
        app.showToast("checkmark.circle.fill", "Angemeldet", name.map { "Servus, \($0)!" })
        Task { await app.sync.sync(context: context, auth: app.auth) }
    }
}

// MARK: - Sync rows

/// "Synchronisierung", "Jetzt synchronisieren" and – after a `426` – "Nach Update suchen". Its own view, so only these
/// rows follow the sync state (idle → syncing → synced on every pass) – the profile card and its bilanz stay put.
private struct SetSyncRows: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Results of a sync started here ("Jetzt synchronisieren"): one haptic each, and the cloud check hops.
    @State private var syncedTrigger = 0
    @State private var failedTrigger = 0

    private var isSyncing: Bool { app.sync.state == .syncing }

    var body: some View {
        statusRow
        syncNowRow
        if app.sync.requiresAppUpdate {
            updateRow
        }
    }

    /// The relative time ("vor 5 Minuten") moves on while Settings stays open.
    private var statusRow: some View {
        TimelineView(.everyMinute) { timeline in
            HStack(spacing: Theme.Spacing.s) {
                SetRowLabel(title: "Synchronisierung", subtitle: subtitle(now: timeline.date), symbol: "icloud.fill",
                            tint: Theme.glacier)
                Spacer(minLength: Theme.Spacing.xs)
                indicator
            }
        }
        .motionAnimation(Motion.snappy, value: app.sync.state)
        .accessibilityElement(children: .combine)
    }

    /// The state symbol morphs from one to the next (cloud → turning arrows → cloud with check) and the check hops
    /// after a sync started here. Reduce Motion / screenshots: a plain spinner while syncing.
    @ViewBuilder
    private var indicator: some View {
        if isSyncing && (reduceMotion || MotionPolicy.isStatic) {
            ProgressView()
        } else {
            Image(systemName: indicatorSymbol)
                .foregroundStyle(indicatorColor)
                .symbolReplaceTransition()
                .setBusySymbol(isSyncing)
                .setSymbolEffect(.bounce, trigger: syncedTrigger)
                .setSymbolEffect(.wiggle, trigger: failedTrigger)
        }
    }

    private var indicatorSymbol: String {
        switch app.sync.state {
        case .syncing: "arrow.triangle.2.circlepath"
        case .synced: "checkmark.icloud.fill"
        case .failed: "exclamationmark.icloud.fill"
        case .disabled: "icloud.slash"
        case .idle: "icloud"
        }
    }

    private var indicatorColor: Color {
        switch app.sync.state {
        case .syncing: Theme.glacier
        case .synced: Theme.positiveText
        case .failed: Theme.negative
        case .disabled: Theme.textTertiary
        case .idle: Theme.textSecondary
        }
    }

    private func subtitle(now: Date) -> String {
        // RootView asks right after Settings closes (it closes them for this) – until then nothing is synced.
        if app.sync.isPaused { return "Pausiert · Kontowechsel offen" }
        switch app.sync.state {
        case .disabled:
            return "Nicht eingerichtet"
        case .idle:
            return app.sync.lastSync.map { "Zuletzt \(SetFormat.relative($0, now: now))" } ?? "Bereit"
        case .syncing:
            return "Wird synchronisiert …"
        case .synced(let date):
            return "Synchronisiert \(SetFormat.relative(date, now: now))"
        case .failed(let message):
            return "Fehlgeschlagen · \(message)"
        }
    }

    /// The tile's arrows turn while the sync runs; the result is one haptic (success or error), no toast.
    private var syncNowRow: some View {
        Button {
            Task {
                await app.sync.sync(context: context, auth: app.auth)
                switch app.sync.state {
                case .synced: syncedTrigger += 1
                case .failed: failedTrigger += 1
                default: break
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                SetRowLabel(title: "Jetzt synchronisieren", symbol: "arrow.triangle.2.circlepath", tint: Theme.dusk,
                            isBusy: isSyncing)
                Spacer(minLength: Theme.Spacing.xs)
                SetBusyIndicator(isBusy: isSyncing)
            }
        }
        .disabled(isSyncing)
        .haptic(.success, trigger: syncedTrigger)
        .haptic(.error, trigger: failedTrigger)
        .accessibilityValue(isSyncing ? "Wird synchronisiert" : "")
    }

    /// The server no longer accepts this app version (`426`): offer the update right here.
    private var updateRow: some View {
        Button {
            Task { await app.updates.checkIfDue(force: true) }
        } label: {
            SetRowLabel(title: "Nach Update suchen", subtitle: "Diese Version wird vom Server nicht mehr unterstützt",
                        symbol: "arrow.down.app.fill", tint: Theme.accent)
        }
    }
}

// MARK: - Profile card

/// Background of the profile card row: the same calm `Theme.surface` as every other group (one surface language
/// per screen), lit only by a faint glacier glow behind the avatar so the card still reads as the screen's hero.
private struct SetProfileCardBackground: View {
    var body: some View {
        ZStack {
            Theme.surface
            RadialGradient(colors: [Theme.glacier.opacity(0.11), Theme.glacier.opacity(0)],
                           center: UnitPoint(x: 0.1, y: 0.18), startRadius: 0, endRadius: 210)
        }
    }
}

private struct SetProfileCard: View {
    var profile: UserProfile?
    var isCloudActive: Bool
    var canSignIn: Bool
    var snapshot: AnalyticsSnapshot?
    var onSignedIn: () -> Void

    /// Signing in (or out) morphs the card in place: the avatar takes the initials, the badges change, the sign-in
    /// buttons fold away and the bilanz rises in – one smooth transaction instead of a jump.
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            identity
            if profile == nil {
                if canSignIn {
                    AuthButtonStack(onSignedIn: onSignedIn)
                        .padding(.top, Theme.Spacing.xxs)
                        .motionTransition(.rise)
                }
            } else if let snapshot {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                    SetProfileStats(snapshot: snapshot)
                }
                .motionTransition(.rise)
            }
        }
        .motionAnimation(Motion.smooth, value: profile?.id)
        .motionAnimation(Motion.smooth, value: isCloudActive)
    }

    private var identity: some View {
        HStack(spacing: Theme.Spacing.m) {
            SetAvatar(initials: profile?.initials, size: 62)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile?.displayName ?? "Nicht angemeldet")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .contentTransition(.interpolate)
                Text(detailLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .contentTransition(.opacity)
                badges
                    .padding(.top, Theme.Spacing.xxs)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        guard let profile else {
            return canSignIn ? "Melde dich an, um deine Fahrten zu sichern." : "Ohne Konto – alle Daten bleiben auf diesem iPhone."
        }
        if let email = profile.email, !email.isEmpty { return email }
        return profile.provider == .local ? "Lokales Profil" : "Angemeldet mit \(profile.provider.displayName)"
    }

    private var badges: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                providerBadge
                storageBadge
            }
            VStack(alignment: .leading, spacing: 6) {
                providerBadge
                storageBadge
            }
        }
    }

    @ViewBuilder
    private var providerBadge: some View {
        if let profile {
            SetProviderBadge(provider: profile.provider)
                .motionTransition(.pop)
        }
    }

    /// "Lokal gespeichert" → "Cloud-Sync aktiv": the symbol morphs (iPhone → cloud with check) and hops once.
    private var storageBadge: some View {
        SetPill(text: isCloudActive ? "Cloud-Sync aktiv" : "Lokal gespeichert",
                symbol: isCloudActive ? "checkmark.icloud.fill" : "iphone",
                tint: isCloudActive ? Theme.positiveText : Theme.textSecondary)
            .symbolReplaceTransition()
            .setSymbolOnEnable(isCloudActive)
    }
}

/// Initials on the brand gradient (glacier → dusk → alpenglow), like the dashboard avatar.
private struct SetAvatar: View {
    var initials: String?
    var size: CGFloat

    var body: some View {
        // Signing in: the gradient blooms in behind the placeholder and the initials pop in (`.pop`); signing out
        // reverses it. Cross-fades under Reduce Motion.
        ZStack {
            Circle().fill(Theme.surfaceSecondary)
            if initials != nil {
                Circle()
                    .fill(LinearGradient(colors: [Theme.glacier, Theme.dusk, Theme.alpenglow],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .environment(\.colorScheme, .light)
                    .motionTransition(.opacity.combined(with: .scale(scale: 0.4)))
            }
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.38), Color.white.opacity(0)],
                                     center: .topLeading, startRadius: 0, endRadius: size))
            if let initials {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .motionTransition(.pop)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .motionTransition(.pop)
            }
        }
        .frame(width: size, height: size)
        .overlay { Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1) }
        .shadow(color: Theme.dusk.opacity(initials == nil ? 0 : 0.32), radius: 10, y: 5)
        .accessibilityHidden(true)
    }
}

private struct SetProviderBadge: View {
    var provider: AuthProvider

    var body: some View {
        HStack(spacing: 5) {
            logo
            Text(provider.displayName)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.surfaceSecondary, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Angemeldet mit \(provider.displayName)")
    }

    @ViewBuilder
    private var logo: some View {
        switch provider {
        case .apple: Image(systemName: "applelogo")
        case .google: GoogleLogo(size: 12)
        case .microsoft: MicrosoftLogo(size: 11)
        case .local: Image(systemName: "iphone")
        }
    }
}

/// "KLIMATICKET Ö KLASSIK · NOCH 143 TAGE" + "73 % amortisiert · 87 Fahrten · 612 kg CO₂ gespart".
private struct SetProfileStats: View {
    var snapshot: AnalyticsSnapshot

    private var summary: SavingsSummary { snapshot.summary }

    private var caption: String {
        let remaining = summary.daysRemaining > 0 ? "noch \(Format.days(summary.daysRemaining))" : "abgelaufen"
        return "\(snapshot.ticket.name) · \(remaining)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Kicker(text: caption)
                .lineLimit(2)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Theme.Spacing.s) { items }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) { items }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The card's hero figure (amortisiert) counts in once when Settings opens; the others roll on every change
    /// (a trip logged from a widget while Settings is open, a restored backup).
    @ViewBuilder
    private var items: some View {
        stat("amortisiert", Theme.accentText) {
            // The final figure reserves the width: the row never re-lays out (or flips to the stacked layout) while
            // the count runs.
            Text(Format.percent(summary.amortizedFraction))
                .hidden()
                .overlay(alignment: .leading) {
                    CountUpText(value: summary.amortizedFraction, delay: 0.15) { Format.percent($0) }
                }
        }
        stat("Fahrten", Theme.textPrimary) {
            Text(Format.number(Double(summary.tripCount)))
                .numericValue(Double(summary.tripCount))
        }
        stat("CO₂ gespart", Theme.positiveText) {
            Text(Format.kg(summary.co2SavedKg))
                .numericValue(summary.co2SavedKg)
        }
    }

    private func stat<Value: View>(_ label: String, _ color: Color, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value()
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Abmelden

/// Sign-out (and, with an active cloud account, account deletion) in their own last section above the brand footer –
/// rare, destructive actions kept away from "Cloud-Sync einrichten" and the sync rows at the top.
struct SetSignOutSection: View {
    @Environment(AppState.self) private var app

    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?

    /// Same source as the profile card: CI screenshots show the demo ticket holder.
    private var profile: UserProfile? {
        app.auth.profile ?? (LaunchMode.isScreenshot ? SetDemo.profile : nil)
    }

    private var isCloudActive: Bool { (profile?.isCloud ?? false) && app.auth.isCloudAvailable }

    var body: some View {
        if let profile {
            Section {
                Group {
                    signOutRow
                    if isCloudActive {
                        deleteAccountRow
                    }
                }
                .listRowBackground(Theme.surface)
            } footer: {
                SetFooter(text: footerText(for: profile))
            }
        }
    }

    private func footerText(for profile: UserProfile) -> String {
        let keeps = "Deine Fahrten bleiben auf diesem iPhone."
        if profile.provider == .local {
            return "Lokales Profil „\(profile.displayName)“. \(keeps)"
        }
        let identity = profile.email.flatMap { $0.isEmpty ? nil : $0 } ?? profile.displayName
        return "Angemeldet als \(identity) mit \(profile.provider.displayName). \(keeps)"
    }

    private var signOutRow: some View {
        Button(role: .destructive) {
            isConfirmingSignOut = true
        } label: {
            // Text-safe red (≥ 4.5 : 1 on the row surface); the role keeps the destructive semantics.
            Text("Abmelden")
                .frame(maxWidth: .infinity)
                .foregroundStyle(Theme.negativeText)
        }
        .confirmationDialog("Abmelden?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { signOut() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Deine Fahrten bleiben auf diesem iPhone gespeichert.")
        }
    }

    /// App Store guideline 5.1.1(v): an account created in the app must be deletable in the app.
    private var deleteAccountRow: some View {
        Button(role: .destructive) {
            isConfirmingDelete = true
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                if app.auth.isDeletingAccount { ProgressView().controlSize(.small) }
                Text("Konto löschen")
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Theme.negativeText)
        }
        .disabled(app.auth.isDeletingAccount)
        .confirmationDialog("Konto endgültig löschen?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Konto löschen", role: .destructive) { deleteAccount() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dein Konto und alle Daten in der Cloud werden gelöscht. Die Fahrten auf diesem iPhone bleiben erhalten.")
        }
        .alert("Löschen fehlgeschlagen", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    // MARK: Actions

    private func deleteAccount() {
        Task {
            do {
                try await app.auth.deleteAccount()
                app.showToast("person.crop.circle.badge.xmark", "Konto gelöscht", "Deine Fahrten bleiben auf diesem iPhone")
            } catch {
                deleteError = error.localizedDescription
            }
        }
    }

    private func signOut() {
        Task {
            await app.auth.signOut()
            app.sync.resetSyncCursor()
            app.showToast("rectangle.portrait.and.arrow.right", "Abgemeldet", "Deine Daten bleiben auf diesem iPhone")
        }
    }
}

// MARK: - Cloud setup page (summary of docs/SETUP.md §3)

private struct SetCloudSetupPage: View {
    private struct Step: Identifiable {
        let id: Int
        let title: String
        let detail: String
    }

    private static let guideURL = URL(string: "https://github.com/Jecuro1/KLIMATICKET-APP/blob/main/docs/SETUP.md")
    private static let dashboardURL = URL(string: "https://dash.cloudflare.com")

    private let steps: [Step] = [
        Step(id: 1, title: "Cloudflare-Konto & Subdomain",
             detail: "Melde dich auf dash.cloudflare.com an (kostenlos). Unter Workers & Pages einmal eine workers.dev-Subdomain festlegen, z. B. „marcel“, und rechts die Account ID kopieren."),
        Step(id: 2, title: "API-Token erstellen",
             detail: "My Profile › API Tokens › Create Token › Custom token „KlimaBilanz GitHub Deploy“ mit genau vier Rechten: Account · Workers Scripts · Edit, Account · D1 · Edit, Account · Account Settings · Read und User · User Details · Read. Kein IP-Filter – den Token gleich kopieren."),
        Step(id: 3, title: "GitHub-Secrets hinterlegen",
             detail: "Im Repository unter Settings › Secrets and variables › Actions › Secrets: CLOUDFLARE_API_TOKEN und CLOUDFLARE_ACCOUNT_ID anlegen."),
        Step(id: 4, title: "Backend bereitstellen",
             detail: "Actions › Backend › Run workflow: legt die Datenbank „klimabilanz“ in der EU, den Worker und seinen Schlüssel an. Die Zusammenfassung des Laufs zeigt die Worker-Adresse und die Callback-URLs für die Anmeldeanbieter."),
        Step(id: 5, title: "Anmeldeanbieter einrichten",
             detail: "Google (kostenlos): OAuth-Client „Web application“ mit der Google-Callback-URL → Secrets GOOGLE_CLIENT_ID und GOOGLE_CLIENT_SECRET.\nMicrosoft (kostenlos): App-Registrierung in Entra für Organisations- und private Konten, Plattform „Web“ mit der Microsoft-Callback-URL → MICROSOFT_CLIENT_ID und MICROSOFT_CLIENT_SECRET.\nApple (nur mit dem kostenpflichtigen Apple Developer Program): Services ID mit der Apple-Callback-URL und ein Sign-in-with-Apple-Schlüssel → APPLE_SERVICES_ID, APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY und APPLE_BUNDLE_ID.\nDanach Actions › Backend noch einmal starten."),
        Step(id: 6, title: "App neu bauen",
             detail: "Actions › iOS › Run workflow: Der neue Build bekommt die Worker-Adresse automatisch. Installieren – danach sind Anmeldung und Abgleich aktiv."),
    ]

    var body: some View {
        List {
            Section {
                intro
                    .listRowBackground(SetProfileCardBackground())
            }
            Section {
                Group {
                    ForEach(steps) { step in
                        stepRow(step)
                    }
                }
                .listRowBackground(Theme.surface)
            } header: {
                SetSectionHeader(title: "In sechs Schritten")
            }
            Section {
                Group {
                    if let url = Self.dashboardURL {
                        Link(destination: url) {
                            SetRowLabel(title: "dash.cloudflare.com öffnen", symbol: "safari.fill", tint: Theme.pine)
                        }
                    }
                    if let url = Self.guideURL {
                        Link(destination: url) {
                            SetRowLabel(title: "Anleitung öffnen", subtitle: "Schritt für Schritt, mit allen Details (docs/SETUP.md)",
                                        symbol: "book.fill", tint: Theme.glacier)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            } footer: {
                SetFooter(text: footerText)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop(skyOpacity: 0.4, fadeEnd: 0.4) }
        .navigationTitle("Cloud einrichten")
        .navigationBarTitleDisplayMode(.large)
    }

    private var footerText: String {
        let local = AppConfig.supportsNativeAppleSignIn
            ? "„Mit Apple anmelden“ funktioniert auch ohne Cloud – Name und E-Mail bleiben dann nur auf diesem iPhone."
            : "Bis dahin funktioniert KlimaBilanz vollständig ohne Konto – alle Daten bleiben auf diesem iPhone."
        return "\(local) Kosten: keine – die kostenlosen Cloudflare-Pläne reichen bei Weitem."
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            SetIconTile(symbol: "icloud.fill", tint: Theme.modeColor(.sBahn), size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Deine eigene Cloud")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Ohne Einrichtung läuft KlimaBilanz vollständig lokal. Für Konten mit Apple, Google oder Microsoft und den Abgleich zwischen deinen Geräten brauchst du dein eigenes, kostenloses Cloudflare-Konto – die Daten liegen dort in der EU.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func stepRow(_ step: Step) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Text(Format.number(Double(step.id)))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 28, height: 28)
                .background(Theme.ctaGradient, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(step.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Schritt \(step.id): \(step.title)")
        .accessibilityValue(step.detail)
    }
}
