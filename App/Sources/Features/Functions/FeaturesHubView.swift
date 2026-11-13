import SwiftUI
import SwiftData
import KlimaCore

// MARK: funktionen – Einstellungen › Funktionen (docs/FUNCTIONS_HUB.md §2): „Was kann die App, was davon ist an, und was sendet
// sie?“. The mosaic of every feature, the Offline-Modus at the top, a note for everything that is hidden right now, the way to the
// Datenschutz-Überblick, and one row per feature – grouped, searchable, each with its switch, its state and „Was wird gesendet?“.

struct FeaturesHubView: View {
    /// Opened by a link to a hidden feature: the list scrolls to its row and lights it up.
    var focus: FeatureID? = nil
    /// Presented as a sheet (`FeatureLinkHost`): a „Fertig“ button.
    var isSheet = false
    /// CI scenes: a row the list scrolls to after the first frame.
    var screenshotAnchor: FeatureID? = nil

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @State private var query = ""
    @State private var highlighted: FeatureID?
    @State private var openPage: FeatureID?
    @State private var changeTick = 0

    private var center: FeatureCenter { .shared }

    var body: some View {
        let ctx = center.context(app: app)
        let settings = center.settings
        let notes = FeatureGate.hiddenNotes(settings: settings, context: ctx)
        ScrollViewReader { proxy in
            List {
                if query.isEmpty {
                    heroSection(settings: settings, context: ctx, hiddenCount: notes.count)
                    offlineSection(settings: settings)
                    if !notes.isEmpty { notesSection(notes, proxy: proxy) }
                    privacySection
                }
                ForEach(FeatureGroup.allCases) { group in
                    let rows = FeatureRegistry.features(in: group).filter(matches)
                    if !rows.isEmpty { groupSection(group, rows: rows, settings: settings, context: ctx) }
                }
                if !query.isEmpty && !FeatureRegistry.all.contains(where: matches) {
                    Section {
                        Text("Keine Funktion passt zu „\(query)“.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .listRowBackground(Theme.surface)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(Theme.Spacing.l)
            .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
            .scrollContentBackground(.hidden)
            .background { SetBackdrop() }
            .tint(Theme.accent)
            .navigationTitle("Funktionen")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Funktion suchen")
            .toolbar { toolbar }
            .revealScope()
            .motionAnimation(Motion.smooth, value: notes.map(\.id))
            .motionAnimation(Motion.smooth, value: settings.offlineMode)
            .haptic(.selection, trigger: changeTick)
            .navigationDestination(item: $openPage) { id in ownPage(id) }
            .task { await scrollToFocus(proxy) }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isSheet {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }.fontWeight(.semibold)
            }
        }
    }

    private func matches(_ descriptor: FeatureDescriptor) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return [descriptor.title, descriptor.line, descriptor.group.title].contains { $0.localizedStandardContains(needle) }
    }

    // MARK: Hero

    private func heroSection(settings: FeatureSettings, context: FeatureContext, hiddenCount: Int) -> some View {
        let statuses = FeatureID.allCases.map { FeatureGate.status($0, settings: settings, context: context) }
        return Section {
            FeatureHubHero(statuses: statuses, offlineMode: settings.offlineMode, hiddenCount: hiddenCount)
                .reveal(order: 0)
                .listRowBackground(Theme.surface)
        } footer: {
            SetFooter(text: "Was du hier ausschaltest, verschwindet aus der App – nicht grau, sondern weg. Darunter steht immer, was gerade ausgeblendet ist.")
        }
    }

    // MARK: Offline-Modus

    private func offlineSection(settings: FeatureSettings) -> some View {
        Section {
            FeatureOfflineCard(isOn: Binding(get: { center.offlineMode },
                                             set: { on in
                                                 withMotion(Motion.smooth) { center.setOfflineMode(on, app: app) }
                                             }))
                .reveal(order: 1)
                .listRowBackground(Theme.surface)
                .id("offline")
        } header: {
            SetSectionHeader(title: "Offline-Modus")
        } footer: {
            SetFooter(text: FeaturePrivacy.offlineConsent)
        }
    }

    // MARK: Hidden

    private func notesSection(_ notes: [FeatureHiddenNote], proxy: ScrollViewProxy) -> some View {
        Section {
            ForEach(notes) { note in
                Button {
                    withMotion(Motion.smooth) { proxy.scrollTo(note.id, anchor: .center) }
                    flash(note.id)
                } label: {
                    Label {
                        Text(note.text)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "eye.slash.fill")
                            .foregroundStyle(Theme.summitText)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Springt zur Funktion")
                .listRowBackground(Theme.surface)
                .motionTransition(.rise)
            }
        } header: {
            SetSectionHeader(title: notes.count == 1 ? "Gerade ausgeblendet" : "Gerade ausgeblendet · \(notes.count)")
        }
    }

    // MARK: Datenschutz

    private var privacySection: some View {
        Section {
            NavigationLink {
                FeaturePrivacyView()
            } label: {
                SetRowLabel(title: "Datenschutz-Überblick", subtitle: "Wer was bekommt, wann – und wie viele Live-Anfragen wirklich rausgingen",
                            symbol: "hand.raised.fill", tint: Theme.pine)
            }
            .listRowBackground(Theme.surface)
        } footer: {
            SetFooter(text: FeaturePrivacy.consentLine)
        }
    }

    // MARK: Groups

    private func groupSection(_ group: FeatureGroup, rows: [FeatureDescriptor], settings: FeatureSettings,
                              context: FeatureContext) -> some View {
        Section {
            ForEach(rows) { descriptor in
                let status = FeatureGate.status(descriptor.id, settings: settings, context: context)
                FeatureHubRow(descriptor: descriptor, status: status,
                              statusLine: FeatureGate.statusLine(descriptor.id, settings: settings, context: context),
                              dependency: enableableDependency(status, settings: settings),
                              onToggle: { on in toggle(descriptor.id, on) },
                              onEnableDependency: { dependency in toggle(dependency, true) },
                              onOpenPage: { openPage = descriptor.id })
                    .id(descriptor.id)
                    .listRowBackground(highlighted == descriptor.id ? Theme.accent.opacity(0.16) : Theme.surface)
            }
        } header: {
            SetSectionHeader(title: group.title)
        }
    }

    /// The feature it needs, when one tap there would bring this one back (not while the Offline-Modus holds it).
    private func enableableDependency(_ status: FeatureStatus, settings: FeatureSettings) -> FeatureID? {
        guard case .needs(let dependency)? = status.offReason, !settings.offlineMode,
              dependency.descriptor.control == .toggle else { return nil }
        return dependency
    }

    private func toggle(_ id: FeatureID, _ on: Bool) {
        withMotion(Motion.smooth) {
            center.set(id, on, app: app, tickets: tickets, context: context)
        }
        changeTick += 1
    }

    @ViewBuilder
    private func ownPage(_ id: FeatureID) -> some View {
        switch id {
        case .tripDetection:
            TripDetectSettingsView()
        default:
            FeatureSectionPage(title: id.title) { SetFollowNoticesSection() }
        }
    }

    // MARK: Focus

    private func scrollToFocus(_ proxy: ScrollViewProxy) async {
        guard let target = focus ?? screenshotAnchor else { return }
        try? await Task.sleep(for: .milliseconds(450))
        withMotion(Motion.smooth) { proxy.scrollTo(target, anchor: .center) }
        if focus != nil { flash(target) }
    }

    /// The row lights up for a moment (stays lit in screenshots).
    private func flash(_ id: FeatureID) {
        withMotion(Motion.smooth) { highlighted = id }
        guard !MotionPolicy.isStatic else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            if highlighted == id { withMotion(Motion.smooth) { highlighted = nil } }
        }
    }
}

/// A settings section on its own page (Live-Mitteilungen from the hub).
struct FeatureSectionPage<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        List { content }
            .listStyle(.insetGrouped)
            .listSectionSpacing(Theme.Spacing.l)
            .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
            .scrollContentBackground(.hidden)
            .background { SetBackdrop() }
            .tint(Theme.accent)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The Fahrplan's „aus“ card while the Offline-Modus is on (PlannerUnavailableView, `// MARK: funktionen`).
struct FeatureOfflinePlannerNotice: View {
    var onSettings: () -> Void
    @Environment(AppState.self) private var app

    var body: some View {
        PlannerNoticeCard(symbol: "wifi.slash", title: "Offline-Modus ist an",
                          message: "Solange er an ist, fragt KlimaBilanz nichts bei der ÖBB ab – kein Fahrplan, keine Live-Preise. Deine Fahrten und Normalpreise funktionieren weiter.",
                          actionTitle: "Offline-Modus beenden",
                          action: { withMotion(Motion.smooth) { FeatureCenter.shared.setOfflineMode(false, app: app) } },
                          tint: Theme.dawn)
    }
}
