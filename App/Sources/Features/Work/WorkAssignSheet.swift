import SwiftUI
import SwiftData
import KlimaCore

/// "Fahrten zuordnen": quickly mark the trips of a ticket year as Arbeitsweg or Dienstreise (menu or swipe).
struct WorkAssignSheet: View {
    let period: TicketPeriod

    enum Filter: String, CaseIterable, Identifiable {
        case open, work, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .open: "Ohne Zweck"
            case .work: "Arbeit"
            case .all: "Alle"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse)
    private var trips: [TripEntity]
    @State private var filter: Filter = .open
    @State private var changeCount = 0

    private var periodTrips: [TripEntity] { trips.filter { period.contains($0.date) } }

    private var visibleTrips: [TripEntity] {
        switch filter {
        case .open: periodTrips.filter { $0.category == nil }
        case .work: periodTrips.filter { $0.category?.isWorkRelated == true }
        case .all: periodTrips
        }
    }

    private var months: [(key: Date, trips: [TripEntity])] {
        let cal = Calendar.vienna
        let grouped = Dictionary(grouping: visibleTrips) { cal.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if visibleTrips.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(months, id: \.key) { month in
                        Section {
                            ForEach(month.trips) { trip in
                                WorkAssignRow(trip: trip) { category in assign(category, to: trip) }
                                    .listRowBackground(Theme.surface)
                            }
                        } header: {
                            SetSectionHeader(title: Format.monthYear(month.key))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background { SetBackdrop(skyOpacity: 0.35, fadeEnd: 0.35) }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Anzeigen", selection: $filter.animation(.snappy)) {
                    ForEach(Filter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.vertical, Theme.Spacing.xs)
            }
            .navigationTitle("Fahrten zuordnen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sensoryFeedback(.selection, trigger: changeCount) { _, _ in app.settings.hapticsEnabled }
        }
        .presentationDragIndicator(.visible)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: filter == .open ? "checkmark.seal.fill" : "tag")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(filter == .open ? Theme.positive : Theme.accent)
            Text(filter == .open ? "Alles zugeordnet" : "Noch nichts zugeordnet")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(filter == .open
                 ? "Jede Fahrt dieses Ticketjahres hat einen Zweck. Unter „Alle“ kannst du ihn ändern."
                 : "Wähle bei einer Fahrt „Arbeitsweg“ oder „Dienstreise“ – oder wisch nach rechts.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }

    private func assign(_ category: TripCategory?, to trip: TripEntity) {
        withAnimation(.snappy) {
            Repository(context: context, app: app).workSetCategory(category, for: trip)
        }
        changeCount += 1
    }
}

/// One trip with its purpose menu and swipe shortcuts.
private struct WorkAssignRow: View {
    let trip: TripEntity
    var onAssign: (TripCategory?) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ModeIcon(mode: trip.mode, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(TripRow.short(trip.fromName)) \(trip.isRoundTrip ? "↔" : "→") \(TripRow.short(trip.toName))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(Format.weekdayDayMonth(trip.date)) · \(Format.time(trip.date))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(trip.fromName) nach \(trip.toName)\(trip.isRoundTrip ? ", hin und retour" : "")")
            .accessibilityValue("\(Format.date(trip.date, .long)), \(Format.time(trip.date))")
            Spacer(minLength: Theme.Spacing.xs)
            Menu {
                Picker("Zweck", selection: Binding(get: { trip.category }, set: { onAssign($0) })) {
                    Label(TripCategory.commute.displayName, systemImage: TripCategory.commute.symbolName)
                        .tag(Optional(TripCategory.commute))
                    Label(TripCategory.business.displayName, systemImage: TripCategory.business.symbolName)
                        .tag(Optional(TripCategory.business))
                    Section("Privat") {
                        ForEach(TripCategory.allCases.filter { !$0.isWorkRelated }) { category in
                            Label(category.displayName, systemImage: category.symbolName).tag(Optional(category))
                        }
                    }
                    Label("Kein Zweck", systemImage: "circle.dashed").tag(TripCategory?.none)
                }
            } label: {
                pill
            }
            .accessibilityLabel("Zweck")
            .accessibilityValue(trip.category?.displayName ?? "Kein Zweck")
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onAssign(trip.category == .business ? nil : .business)
            } label: {
                Label(TripCategory.business.displayName, systemImage: TripCategory.business.symbolName)
            }
            .tint(Theme.dusk)
            Button {
                onAssign(trip.category == .commute ? nil : .commute)
            } label: {
                Label(TripCategory.commute.displayName, systemImage: TripCategory.commute.symbolName)
            }
            .tint(Theme.glacier)
        }
    }

    private var pill: some View {
        let category = trip.category
        let tint = WorkAssignRow.tint(for: category)
        return HStack(spacing: 4) {
            Image(systemName: category?.symbolName ?? "plus")
                .font(.caption.weight(.bold))
                .foregroundStyle(category == nil ? Theme.accentText : tint)
            Text(category?.displayName ?? "Zuordnen")
                .font(.caption.weight(.semibold))
                .foregroundStyle(category == nil ? Theme.accentText : Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((category == nil ? Theme.accent : tint).opacity(0.13), in: .capsule)
        .overlay {
            if category == nil {
                Capsule().strokeBorder(Theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .contentTransition(.symbolEffect(.replace))
    }

    static func tint(for category: TripCategory?) -> Color {
        switch category {
        case .commute: Theme.glacier
        case .business: Theme.dusk
        default: Theme.textSecondary
        }
    }
}
