import SwiftUI
import KlimaCore

/// Everything the story is built from – plain values, read from SwiftData by the view (`YearReviewStoryView`).
struct YearReviewInputs {
    var records: [TripRecord]
    var tickets: [TicketPeriod]
    /// The ticket the app treats as the active one (`Analytics.activeTicket`).
    var preferredTicket: TicketPeriod?
    var holderName: String
    var catalog: TariffCatalog
    var stations: (String) -> Station?
    var now: Date
}

/// Progress of the current page, kept apart from the store: only the progress bars read it, so the 30 Hz ticks of the
/// auto-advance never re-render the page.
@MainActor
@Observable
final class YearReviewClock {
    /// Seconds the current page has been shown (0 … `YearReviewStore.pageSeconds`).
    var elapsed: Double = 0
}

/// State of one story: the period, its pages, the current page and the auto-advance clock. Nothing is persisted.
@MainActor
@Observable
final class YearReviewStore {
    /// Auto-advance: every page stays this long (docs/YEAR_REVIEW.md).
    static let pageSeconds: Double = 6

    let request: YearReviewRequest
    let clock = YearReviewClock()

    private(set) var choices: [YearReviewPeriod] = []
    private(set) var review: YearReview?
    private(set) var holderName = ""
    private(set) var isLoaded = false
    var index = 0
    /// A finger rests on the page (long press): the clock pauses.
    var isHolding = false
    /// The last move went forward (the page enters from the trailing side).
    private(set) var movedForward = true
    /// Counts manual page changes (taps and buttons): the haptic trigger.
    private(set) var manualSteps = 0
    /// What the share page shows (format, style, names) – kept while you page back and forth.
    var shareOptions = YearReviewShareOptions()

    @ObservationIgnored private var inputs: YearReviewInputs?
    @ObservationIgnored private var selectedID: String?
    @ObservationIgnored private var played: Set<YearReviewPageKind> = []
    /// The break-even celebration plays once per story, however often the page is revisited.
    @ObservationIgnored private(set) var hasCelebrated = false

    init(request: YearReviewRequest) {
        self.request = request
    }

    // MARK: Pages

    var pages: [YearReview.Page] { review?.pages ?? [] }
    var pageCount: Int { pages.count }
    var current: YearReview.Page? { pages.indices.contains(index) ? pages[index] : nil }
    var isFirst: Bool { index <= 0 }
    var isLast: Bool { index >= pageCount - 1 }
    var period: YearReviewPeriod? { review?.period }

    // MARK: Loading

    /// (Re)builds the story from fresh data. The picked period and the current page survive a reload (a sync while the story
    /// is open), the page index is clamped.
    func reload(_ inputs: YearReviewInputs) {
        self.inputs = inputs
        holderName = inputs.holderName
        // Statistik can show an older ticket year than the active one: the story then opens on that ticket.
        let picked = request.ticket.flatMap { $0 == inputs.preferredTicket ? nil : $0 }
        let preferred = picked ?? inputs.preferredTicket
        choices = YearReviewPeriods.choices(tickets: inputs.tickets, trips: inputs.records, now: inputs.now, preferredTicket: preferred)
        let wanted: YearReviewPeriod
        if let selectedID, let match = choices.first(where: { $0.id == selectedID }) {
            wanted = match
        } else if let year = request.year {
            wanted = choices.first { $0.kind == .calendarYear && $0.year == year } ?? YearReviewPeriods.calendarYear(year)
        } else if picked != nil || request.startsOnTicketYear,
                  let ticket = YearReviewPeriods.currentTicket(in: inputs.tickets, preferred: preferred, now: inputs.now) {
            wanted = YearReviewPeriods.ticketPeriod(ticket)
        } else {
            wanted = YearReviewPeriods.defaultPeriod(tickets: inputs.tickets, trips: inputs.records, now: inputs.now,
                                                     preferredTicket: preferred)
        }
        build(wanted, resetPage: !isLoaded)
        isLoaded = true
    }

    /// The first page's period chips.
    func select(_ period: YearReviewPeriod) {
        guard period.id != selectedID else { return }
        build(period, resetPage: true)
        clock.elapsed = 0
    }

    var selectedPeriodID: String? { selectedID }

    private func build(_ period: YearReviewPeriod, resetPage: Bool) {
        guard let inputs else { return }
        selectedID = period.id
        let accounting = YearReviewPeriods.accountingPeriod(for: period, tickets: inputs.tickets, now: inputs.now)
        let tripsInPeriod = inputs.records.filter { period.contains($0.date) }
        // The same car comparison as Statistik › "Öffis vs. Auto" and the Jahresbericht (WorkCarCalc).
        let car = tripsInPeriod.isEmpty ? nil
            : WorkCarCalc.result(period: accounting, records: tripsInPeriod, catalog: inputs.catalog, now: inputs.now)
        review = YearReview.make(trips: inputs.records, tickets: inputs.tickets, car: car, period: period, now: inputs.now,
                                 stations: inputs.stations)
        index = resetPage ? 0 : min(max(index, 0), max(0, pageCount - 1))
        if resetPage { played = [] }
    }

    // MARK: Navigation

    func next(manual: Bool = false) {
        guard !isLast else { return }
        move(to: index + 1, manual: manual)
    }

    func back(manual: Bool = false) {
        guard !isFirst else {
            clock.elapsed = 0   // on the first page "back" starts it over
            return
        }
        move(to: index - 1, manual: manual)
    }

    func go(to kind: YearReviewPageKind) {
        guard let target = pages.firstIndex(where: { $0.kind == kind }) else { return }
        move(to: target, manual: false)
    }

    private func move(to target: Int, manual: Bool) {
        movedForward = target >= index
        clock.elapsed = 0
        withMotion(Motion.smooth) { index = target }
        if manual { manualSteps += 1 }
    }

    // MARK: Once-only entrances

    /// The page's numbers counted up (or its celebration played) already: revisiting it shows the final state at once.
    func hasPlayed(_ kind: YearReviewPageKind) -> Bool { played.contains(kind) }
    func markPlayed(_ kind: YearReviewPageKind) { played.insert(kind) }
    func markCelebrated() { hasCelebrated = true }

    // MARK: Auto-advance

    /// Runs while the story may advance on its own (see `YearReviewStoryView.driverKey`); cancelled and restarted by the
    /// view whenever the page, the finger or the scene changes. Keeps the elapsed time across pauses.
    func runClock() async {
        let start = ContinuousClock.now
        let base = clock.elapsed
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(33))
            if Task.isCancelled { return }
            let parts = (ContinuousClock.now - start).components
            let seconds = base + Double(parts.seconds) + Double(parts.attoseconds) / 1e18
            if seconds >= Self.pageSeconds {
                if isLast { clock.elapsed = Self.pageSeconds } else { next() }
                return
            }
            clock.elapsed = seconds
        }
    }
}
