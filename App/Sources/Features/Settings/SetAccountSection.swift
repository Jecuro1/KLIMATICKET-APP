import SwiftUI
import SwiftData
import UIKit
import KlimaCore

/// Profile card + "Konto" section: identity, provider, storage, sync status, sign-in, cloud setup, sign-out.
struct SetAccountSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }) private var trips: [TripEntity]

    @State private var isConfirmingSignOut = false
    @State private var showsConnect = false
    @State private var syncTrigger = 0

    /// The signed-in profile; CI screenshots show the demo ticket holder so the screen is fully populated.
    private var profile: UserProfile? {
        app.auth.profile ?? (LaunchMode.isScreenshot ? SetDemo.profile : nil)
    }

    private var isCloudActive: Bool { (profile?.isCloud ?? false) && app.auth.isCloudAvailable }

    private var snapshot: AnalyticsSnapshot? {
        guard let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) else { return nil }
        return Analytics.make(ticket: ticket, trips: trips, catalog: app.catalog)
    }

    private var hasAccountRows: Bool { profile != nil || !app.auth.isCloudAvailable }

    var body: some View {
        Section {
            SetProfileCard(profile: profile, isCloudActive: isCloudActive, snapshot: snapshot, onSignedIn: didSignIn)
                .listRowBackground(SetProfileCardBackground())
                .listRowInsets(EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18))
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
                syncStatusRow
                syncNowRow
            } else if app.auth.isCloudAvailable || profile.provider == .local {
                connectRow
                if showsConnect {
                    AuthButtonStack(onSignedIn: didSignIn)
                        .padding(.vertical, Theme.Spacing.xs)
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
        if profile != nil {
            signOutRow
        }
    }

    private var syncStatusRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            SetRowLabel(title: "Synchronisierung", subtitle: syncSubtitle, symbol: "icloud.fill", tint: Theme.glacier)
            Spacer(minLength: Theme.Spacing.xs)
            syncIndicator
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var syncIndicator: some View {
        switch app.sync.state {
        case .syncing:
            ProgressView()
        case .synced:
            Image(systemName: "checkmark.icloud.fill").foregroundStyle(Theme.positiveText)
        case .failed:
            Image(systemName: "exclamationmark.icloud.fill").foregroundStyle(Theme.negative)
        case .disabled:
            Image(systemName: "icloud.slash").foregroundStyle(Theme.textTertiary)
        case .idle:
            Image(systemName: "icloud").foregroundStyle(Theme.textSecondary)
        }
    }

    private var syncSubtitle: String {
        switch app.sync.state {
        case .disabled:
            return "Nicht eingerichtet"
        case .idle:
            return app.sync.lastSync.map { "Zuletzt \(SetFormat.relative($0))" } ?? "Bereit"
        case .syncing:
            return "Wird synchronisiert …"
        case .synced(let date):
            return "Synchronisiert \(SetFormat.relative(date))"
        case .failed(let message):
            return "Fehlgeschlagen · \(message)"
        }
    }

    private var syncNowRow: some View {
        Button {
            syncTrigger += 1
            Task { await app.sync.sync(context: context, auth: app.auth) }
        } label: {
            SetRowLabel(title: "Jetzt synchronisieren", symbol: "arrow.triangle.2.circlepath", tint: Theme.dusk)
        }
        .disabled(app.sync.state == .syncing)
        .settingsHaptic(.impact(weight: .light), trigger: syncTrigger, enabled: app.settings.hapticsEnabled)
    }

    private var connectRow: some View {
        Button {
            withAnimation(.snappy) { showsConnect.toggle() }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                SetRowLabel(title: "Mit Konto verbinden",
                            subtitle: app.auth.isCloudAvailable ? "Für Sync zwischen deinen Geräten" : "Apple, Google oder Microsoft",
                            symbol: "person.crop.circle.badge.plus", tint: Theme.glacier)
                Spacer(minLength: Theme.Spacing.xs)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .rotationEffect(.degrees(showsConnect ? 180 : 0))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityValue(showsConnect ? "Aufgeklappt" : "Zugeklappt")
    }

    private var signOutRow: some View {
        Button(role: .destructive) {
            isConfirmingSignOut = true
        } label: {
            Text("Abmelden")
                .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Abmelden?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { signOut() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Deine Fahrten bleiben auf diesem iPhone gespeichert.")
        }
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
        withAnimation(.snappy) { showsConnect = false }
        let name = app.auth.profile?.displayName
        app.showToast("checkmark.circle.fill", "Angemeldet", name.map { "Servus, \($0)!" })
        Task { await app.sync.sync(context: context, auth: app.auth) }
    }

    private func signOut() {
        Task {
            await app.auth.signOut()
            app.sync.resetSyncCursor()
            showsConnect = false
            app.showToast("rectangle.portrait.and.arrow.right", "Abgemeldet", "Deine Daten bleiben auf diesem iPhone")
        }
    }
}

// MARK: - Profile card

/// Soft brand wash behind the profile card row.
private struct SetProfileCardBackground: View {
    var body: some View {
        ZStack {
            Theme.surface
            LinearGradient(colors: [Theme.glacier.opacity(0.16), Theme.dusk.opacity(0.08), Theme.dawn.opacity(0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct SetProfileCard: View {
    var profile: UserProfile?
    var isCloudActive: Bool
    var snapshot: AnalyticsSnapshot?
    var onSignedIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            identity
            if profile == nil {
                AuthButtonStack(onSignedIn: onSignedIn)
                    .padding(.top, Theme.Spacing.xxs)
            } else if let snapshot {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 1)
                    .accessibilityHidden(true)
                SetProfileStats(snapshot: snapshot)
            }
        }
    }

    private var identity: some View {
        HStack(spacing: Theme.Spacing.m) {
            SetAvatar(initials: profile?.initials, size: 62)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile?.displayName ?? "Nicht angemeldet")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(detailLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                badges
                    .padding(.top, Theme.Spacing.xxs)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        guard let profile else { return "Melde dich an, um deine Fahrten zu sichern." }
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
        }
    }

    private var storageBadge: some View {
        SetPill(text: isCloudActive ? "Cloud-Sync aktiv" : "Nur auf diesem iPhone",
                symbol: isCloudActive ? "checkmark.icloud.fill" : "iphone",
                tint: isCloudActive ? Theme.positiveText : Theme.textSecondary)
    }
}

/// Initials on the brand gradient (glacier → dusk → alpenglow), like the dashboard avatar.
private struct SetAvatar: View {
    var initials: String?
    var size: CGFloat

    var body: some View {
        ZStack {
            if initials != nil {
                Circle()
                    .fill(LinearGradient(colors: [Theme.glacier, Theme.dusk, Theme.alpenglow],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .environment(\.colorScheme, .light)
            } else {
                Circle().fill(Theme.surfaceSecondary)
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
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
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
        case .apple: Image(systemName: "apple.logo")
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

    @ViewBuilder
    private var items: some View {
        stat(Format.percent(summary.amortizedFraction), "amortisiert", Theme.accentText)
        stat(Format.number(Double(summary.tripCount)), "Fahrten", Theme.textPrimary)
        stat(Format.kg(summary.co2SavedKg), "CO₂ gespart", Theme.positiveText)
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
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

// MARK: - Cloud setup page (summary of docs/SETUP.md §3)

private struct SetCloudSetupPage: View {
    @Environment(AppState.self) private var app
    @State private var copyTrigger = 0

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let detail: String
    }

    private let steps: [Step] = [
        Step(id: 1, title: "Supabase-Projekt anlegen",
             detail: "Erstelle ein kostenloses Projekt auf supabase.com."),
        Step(id: 2, title: "Datenbank vorbereiten",
             detail: "Führe im SQL Editor die Datei supabase/migrations/0001_init.sql aus. Sie legt die Tabellen samt Row Level Security an – jede:r sieht nur die eigenen Fahrten."),
        Step(id: 3, title: "Redirect-URL eintragen",
             detail: "Unter Authentication › URL Configuration › Redirect URLs: klimabilanz://auth-callback hinzufügen."),
        Step(id: 4, title: "Anbieter aktivieren",
             detail: "Apple: Bundle-ID com.knitelarlberg.klimabilanz als Client ID (braucht das Apple Developer Program).\nGoogle: OAuth-Client vom Typ „Web application“ mit der Redirect-URI https://<projekt>.supabase.co/auth/v1/callback.\nMicrosoft: App-Registrierung in Entra (beliebige Organisationen und persönliche Konten), gleiche Redirect-URI, als URL https://login.microsoftonline.com/common."),
        Step(id: 5, title: "Schlüssel hinterlegen",
             detail: "In GitHub unter Settings › Secrets and variables › Actions › Variables: SUPABASE_URL und SUPABASE_ANON_KEY (der öffentliche anon-Key) setzen."),
        Step(id: 6, title: "Neu bauen",
             detail: "Unter Actions › iOS › Run workflow einen neuen Build starten und installieren – danach sind Login und Sync aktiv."),
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
                    if let url = URL(string: "https://supabase.com") {
                        Link(destination: url) {
                            SetRowLabel(title: "supabase.com öffnen", symbol: "safari.fill", tint: Theme.pine)
                        }
                    }
                    Button {
                        UIPasteboard.general.string = AppConfig.authCallback
                        copyTrigger += 1
                        app.showToast("doc.on.doc.fill", "Redirect-URL kopiert", AppConfig.authCallback)
                    } label: {
                        SetRowLabel(title: "Redirect-URL kopieren", subtitle: AppConfig.authCallback,
                                    symbol: "doc.on.doc.fill", tint: Theme.glacier)
                    }
                    .settingsHaptic(.success, trigger: copyTrigger, enabled: app.settings.hapticsEnabled)
                }
                .listRowBackground(Theme.surface)
            } footer: {
                SetFooter(text: "„Mit Apple anmelden“ funktioniert auch ohne Cloud – Name und E-Mail bleiben dann nur auf diesem iPhone. Die ausführliche Anleitung steht in docs/SETUP.md.")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop(skyOpacity: 0.4, fadeEnd: 0.4) }
        .navigationTitle("Cloud einrichten")
        .navigationBarTitleDisplayMode(.large)
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            SetIconTile(symbol: "icloud.fill", tint: Theme.modeColor(.sBahn), size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Deine eigene Cloud")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Ohne Einrichtung läuft KlimaBilanz vollständig lokal. Für Konten mit Apple, Google oder Microsoft und den Abgleich zwischen deinen Geräten brauchst du ein eigenes, kostenloses Supabase-Projekt.")
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
