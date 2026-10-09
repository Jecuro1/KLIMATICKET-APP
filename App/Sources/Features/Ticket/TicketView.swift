import SwiftUI
import SwiftData
import PhotosUI
import KlimaCore

/// Tab 4 „Ticket“ – the ticket wallet (DESIGN.md §5.5, final mock `docs/design/final/04-ticket-*.jpg`).
///
/// Top → bottom: eyebrow „AKTIV · TICKETJAHR 2026/27“ + large title (share + ellipsis in the toolbar), the signature pass
/// (tilt foil, tap flips to the photo of the real ticket), „Gültigkeit“ with the break-even flag, renewal card (≤ 45 days),
/// reminders, monthly payment, details, edit/delete and the ticket history (tap = show that ticket app-wide).
struct TicketView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse)
    private var trips: [TripEntity]

    /// Drives the staggered entrance; already true in screenshot mode (end state immediately).
    @State private var appeared = LaunchMode.isScreenshot
    @State private var showsInlineTitle = false
    @State private var editRequest: TktEditRequest?
    @State private var pendingDeletion: TicketEntity?
    @State private var showsDeleteDialog = false
    @State private var showsPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isImportingPhoto = false
    @State private var deleteCount = 0

    private static let topID = "tkt-top"

    var body: some View {
        let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID)
        let snapshot = ticket.map { Analytics.make(ticket: $0, trips: trips, catalog: app.catalog) }

        NavigationStack {
            Group {
                if let ticket, let snapshot {
                    wallet(ticket: ticket, snapshot: snapshot)
                } else {
                    emptyState
                }
            }
            .navigationTitle(AppTab.ticket.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent(ticket: ticket, snapshot: snapshot) }
        }
        .sheet(item: $editRequest) { request in
            TktEditSheet(ticket: request.ticket, initial: request.draft)
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
        .confirmationDialog("Ticket löschen?", isPresented: $showsDeleteDialog, titleVisibility: .visible,
                            presenting: pendingDeletion) { doomed in
            Button("Ticket löschen", role: .destructive) { delete(doomed) }
            Button("Abbrechen", role: .cancel) {}
        } message: { doomed in
            Text(deleteMessage(for: doomed))
        }
        .sensoryFeedback(.warning, trigger: deleteCount) { _, _ in app.settings.hapticsEnabled }
        .sensoryFeedback(.selection, trigger: app.settings.selectedTicketID) { _, _ in app.settings.hapticsEnabled }
        .onAppear {
            if !appeared { appeared = true }
        }
    }

    // MARK: Wallet

    private func wallet(ticket: TicketEntity, snapshot: AnalyticsSnapshot) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                walletSections(ticket: ticket, snapshot: snapshot, proxy: proxy)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onScrollGeometryChange(for: Bool.self, of: { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 52
            }, action: { _, isPastHeader in
                withAnimation(.easeInOut(duration: 0.2)) { showsInlineTitle = isPastHeader }
            })
            .ambientBackground(.standard, glow: 0.45 + 0.5 * snapshot.summary.progressClamped)
        }
    }

    private func walletSections(ticket: TicketEntity, snapshot: AnalyticsSnapshot, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(ticket: ticket)
                .id(Self.topID)
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.top, Theme.Spacing.xxs)
                .tktEntrance(0, visible: appeared)

            // ZStack: while switching tickets the outgoing and incoming pass overlap instead of being stacked in the
            // VStack for the length of the transition (which pushed everything below down by a whole card).
            ZStack {
                TktCardStack(ticket: ticket,
                             face: face(for: ticket, summary: snapshot.summary),
                             isImportingPhoto: isImportingPhoto,
                             onAddPhoto: { showsPhotoPicker = true },
                             onRemovePhoto: { removePhoto(from: ticket) })
                    .id(ticket.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.m)
            .tktEntrance(1, visible: appeared, lift: true)

            statusCards(ticket: ticket, summary: snapshot.summary, proxy: proxy)
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.s)

            detailSections(ticket: ticket, snapshot: snapshot, proxy: proxy)
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, TktStyle.sectionSpacing)
        }
        .padding(.bottom, Theme.Spacing.xxl)
    }

    private func header(ticket: TicketEntity) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: headerKicker(for: ticket))
            Text(AppTab.ticket.title)
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusCards(ticket: TicketEntity, summary: SavingsSummary, proxy: ScrollViewProxy) -> some View {
        VStack(spacing: TktStyle.cardSpacing) {
            TktValidityCard(start: ticket.startDate, end: ticket.endDate, summary: summary)
                .tktEntrance(2, visible: appeared)
            if needsRenewal(ticket, summary: summary) {
                TktRenewalCard(ticket: ticket, followUp: followUp(of: ticket), daysRemaining: summary.daysRemaining,
                               onRenew: { renew(ticket) },
                               onShow: { next in select(next, proxy: proxy) })
                    .tktEntrance(3, visible: appeared)
            }
            if !ticket.isExpired {
                TktReminderCard(ticket: ticket)
                    .tktEntrance(3, visible: appeared)
            }
            TktPaymentCard(ticket: ticket, totalValue: summary.totalValue)
                .tktEntrance(4, visible: appeared)
            // MARK: benefits
            PerkSummaryCard()
                .tktEntrance(4, visible: appeared)
            // MARK: advisor
            AdvEntryLink(ticket: ticket, trips: trips, scrollProxy: proxy)
                .tktEntrance(4, visible: appeared)
        }
    }

    private func detailSections(ticket: TicketEntity, snapshot: AnalyticsSnapshot, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: TktStyle.cardSpacing) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SectionHeader(title: "Details")
                    .padding(.horizontal, TktStyle.headerInset)
                TktDetailsCard(ticket: ticket, summary: snapshot.summary, records: snapshot.trips,
                               product: app.catalog.product(id: ticket.productID))
            }
            TktActionsCard(onEdit: { edit(ticket) }, onDelete: { requestDelete(ticket) })
            TktHistorySection(items: historyItems(active: ticket, summary: snapshot.summary),
                              selectedID: ticket.id,
                              onSelect: { selected in select(selected, proxy: proxy) },
                              onAdd: { newTicket(basedOn: ticket) })
                .padding(.top, TktStyle.sectionSpacing - TktStyle.cardSpacing)
        }
        .tktEntrance(5, visible: appeared)
    }

    // MARK: Empty state

    /// Fallback – RootView normally shows onboarding when there is no ticket.
    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: 2) {
                    Kicker(text: "Begleitkarte")
                    Text(AppTab.ticket.title)
                        .font(Theme.Typography.heroTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, Theme.Spacing.screen)
                EmptyStateView(symbol: "ticket",
                               title: "Welches Ticket hast du?",
                               message: "Wähle dein KlimaTicket – dann siehst du, ab wann es sich rentiert.",
                               actionTitle: "Ticket hinzufügen") {
                    newTicket(basedOn: nil)
                }
                .frostedCard()
                .padding(.horizontal, Theme.Spacing.cardGutter)
            }
            .padding(.top, Theme.Spacing.xxs)
        }
        .ambientBackground(.standard, glow: 0.4)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(ticket: TicketEntity?, snapshot: AnalyticsSnapshot?) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(AppTab.ticket.title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .opacity(showsInlineTitle ? 1 : 0)
                .accessibilityHidden(!showsInlineTitle)
        }
        // iOS 26 wraps custom toolbar views in a shared glass capsule – it would stay visible as an empty pill while the
        // title is faded out (same as Übersicht and Statistik).
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
            shareButton(ticket: ticket, snapshot: snapshot)
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            actionsMenu(ticket: ticket)
        }
    }

    @ViewBuilder
    private func shareButton(ticket: TicketEntity?, snapshot: AnalyticsSnapshot?) -> some View {
        if let ticket, let snapshot {
            ShareLink(item: sharePass(ticket: ticket, summary: snapshot.summary),
                      preview: SharePreview("Meine Ticket-Bilanz", image: Image(systemName: "ticket.fill"))) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Bilanz teilen")
        } else {
            Button {} label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(true)
            .accessibilityLabel("Bilanz teilen")
        }
    }

    private func actionsMenu(ticket: TicketEntity?) -> some View {
        Menu {
            if let ticket {
                Button("Ticket bearbeiten", systemImage: "pencil") { edit(ticket) }
                Button(ticket.photoData == nil ? "Foto des Tickets hinzufügen" : "Foto des Tickets ersetzen",
                       systemImage: "photo.on.rectangle") {
                    showsPhotoPicker = true
                }
            }
            if tickets.count > 1 {
                Picker(selection: selectionBinding) {
                    ForEach(tickets) { item in
                        Text("\(item.name) · \(TktText.ticketYear(start: item.startDate, end: item.endDate))")
                            .tag(Optional(item.id))
                    }
                } label: {
                    Label("Ticketjahr wechseln", systemImage: "calendar")
                }
                .pickerStyle(.menu)
            }
            Button("Neues Ticketjahr anlegen", systemImage: "plus") { newTicket(basedOn: ticket) }
            if let ticket {
                Divider()
                Button("Ticket löschen", systemImage: "trash", role: .destructive) { requestDelete(ticket) }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Ticket-Aktionen")
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID)?.id },
            set: { newID in
                withAnimation(.smooth(duration: 0.45)) { app.settings.selectedTicketID = newID }
                Repository(context: context, app: app).refreshWidgets()
            }
        )
    }

    // MARK: Derived

    private func headerKicker(for ticket: TicketEntity) -> String {
        let year = "Ticketjahr \(TktText.ticketYear(start: ticket.startDate, end: ticket.endDate))"
        let now = Date()
        if now < ticket.startDate { return "Ab \(Format.dayMonth(ticket.startDate)) · \(year)" }
        if now > ticket.endDate { return "Abgelaufen · \(year)" }
        return "Aktiv · \(year)"
    }

    /// A ticket that has not started yet shows its number on the stub instead of 0 %.
    private func face(for ticket: TicketEntity, summary: SavingsSummary) -> TktCardFace {
        TktCardFace(ticket: ticket, summary: Date() < ticket.startDate ? nil : summary)
    }

    private func needsRenewal(_ ticket: TicketEntity, summary: SavingsSummary) -> Bool {
        let now = Date()
        guard now >= ticket.startDate else { return false }
        return now > ticket.endDate || summary.daysRemaining <= 45
    }

    /// The next ticket year after `ticket`, if one was already created.
    private func followUp(of ticket: TicketEntity) -> TicketEntity? {
        tickets
            .filter { $0.id != ticket.id && $0.startDate > ticket.startDate }
            .min { $0.startDate < $1.startDate }
    }

    private func historyItems(active: TicketEntity, summary: SavingsSummary) -> [TktHistoryItem] {
        tickets.map { item in
            let itemSummary = item.id == active.id ? summary : Analytics.make(ticket: item, trips: trips, catalog: app.catalog).summary
            return TktHistoryItem(ticket: item, summary: itemSummary)
        }
    }

    private func sharePass(ticket: TicketEntity, summary: SavingsSummary) -> TktSharePass {
        let verdict: String
        if summary.isPaidOff {
            verdict = "Mein Ticket hat sich rentiert: \(TktText.signedEuro(summary.net))"
        } else {
            verdict = "Mein Ticket ist zu \(TktText.percent(summary.amortizedFraction)) amortisiert"
        }
        let tripText = summary.tripCount == 1 ? "1 Fahrt" : "\(summary.tripCount) Fahrten"
        let value = "\(Format.euro(summary.totalValue, decimals: 0)) von \(Format.euro(summary.ticketPrice, decimals: 0))"
        let detail = "\(value) · \(tripText) · \(Format.kg(summary.co2SavedKg)) CO₂ gespart"
        return TktSharePass(face: face(for: ticket, summary: summary), verdict: verdict, detail: detail)
    }

    private func deleteMessage(for ticket: TicketEntity) -> String {
        let year = TktText.ticketYear(start: ticket.startDate, end: ticket.endDate)
        let base = "„\(ticket.name)“ (\(year)) wird entfernt. Deine Fahrten bleiben erhalten."
        return tickets.count <= 1 ? base + " Danach legst du ein neues Ticket an." : base
    }

    // MARK: Actions

    private func select(_ ticket: TicketEntity, proxy: ScrollViewProxy) {
        withAnimation(.smooth(duration: 0.45)) {
            app.settings.selectedTicketID = ticket.id
            proxy.scrollTo(Self.topID, anchor: .top)
        }
        Repository(context: context, app: app).refreshWidgets()
    }

    private func edit(_ ticket: TicketEntity) {
        editRequest = TktEditRequest(ticket: ticket, draft: TktDraft(ticket: ticket))
    }

    private func newTicket(basedOn ticket: TicketEntity?) {
        editRequest = TktEditRequest(ticket: nil, draft: TktDraft.newTicket(basedOn: ticket, catalog: app.catalog))
    }

    private func renew(_ ticket: TicketEntity) {
        let repo = Repository(context: context, app: app)
        let previousSelection = app.settings.selectedTicketID
        let next = withAnimation(.smooth(duration: 0.45)) { () -> TicketEntity in
            let created = repo.renewTicket(ticket)
            // `addTicket` selects the follow-up app-wide; while this ticket still runs it stays on screen and the
            // renewal card turns into "Folgeticket angelegt · Anzeigen".
            TktSelection.keepRunningTicket(repo: repo, app: app, added: created,
                                           previousSelection: previousSelection, running: ticket)
            return created
        }
        app.showToast("ticket.fill", "Folgeticket angelegt", "gültig ab \(Format.date(next.startDate, .long))")
    }

    private func requestDelete(_ ticket: TicketEntity) {
        pendingDeletion = ticket
        showsDeleteDialog = true
    }

    private func delete(_ ticket: TicketEntity) {
        let name = ticket.name
        let isLast = tickets.count <= 1
        withAnimation(.smooth(duration: 0.4)) {
            Repository(context: context, app: app).deleteTicket(ticket)
        }
        deleteCount += 1
        pendingDeletion = nil
        if !isLast { app.showToast("trash.fill", "Ticket gelöscht", name) }
    }

    private func removePhoto(from ticket: TicketEntity) {
        ticket.photoData = nil
        Repository(context: context, app: app).updateTicket(ticket)
        app.showToast("photo", "Foto entfernt")
    }

    /// Loads the picked image, downsizes it off the main actor and stores it on the active ticket.
    private func importPhoto(_ item: PhotosPickerItem) async {
        guard let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) else { return }
        withAnimation(.smooth(duration: 0.25)) { isImportingPhoto = true }
        defer {
            withAnimation(.smooth(duration: 0.25)) { isImportingPhoto = false }
            photoItem = nil
        }
        guard let raw = try? await item.loadTransferable(type: Data.self) else {
            app.showToast("exclamationmark.triangle.fill", "Foto konnte nicht geladen werden")
            return
        }
        let processed = await Task.detached(priority: .userInitiated) { TktPhoto.prepared(raw) }.value
        guard let processed else {
            app.showToast("exclamationmark.triangle.fill", "Foto konnte nicht gelesen werden")
            return
        }
        ticket.photoData = processed
        Repository(context: context, app: app).updateTicket(ticket)
        app.showToast("photo.fill", "Ticket-Foto gespeichert", "Bleibt nur auf diesem iPhone")
    }
}
