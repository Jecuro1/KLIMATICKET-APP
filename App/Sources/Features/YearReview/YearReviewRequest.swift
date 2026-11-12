import SwiftUI
import KlimaCore

// "Dein Jahr" (docs/YEAR_REVIEW.md): how the story is opened and presented. One request value in `AppState`, one
// full-screen cover in `RootView` (`.yearReviewHost()`), four ways in: the Statistik card, the seasonal card on the
// Übersicht (1 Dec – 31 Jan), the deep link klimabilanz://year[/2026] and the tap on the Jahresrückblick widget.

/// What opens the story. `year` nil = the default period (`YearReviewPeriods.defaultPeriod`).
struct YearReviewRequest: Identifiable, Equatable {
    /// The entry the story zooms out of (`nil` for links, which have no card to grow from).
    enum Source: Hashable {
        case statistics
        case overview
        case link
    }

    let id = UUID()
    var year: Int?
    var source: Source = .link
}

/// Zoom ids of the two entry cards (both can be alive at once: two tabs).
enum YearReviewZoom {
    static func id(for source: YearReviewRequest.Source) -> String { "yearReview.\(source)" }
}

extension EnvironmentValues {
    /// The namespace the entry cards and the cover share for the zoom (`YearReviewHostModifier`).
    @Entry var yearReviewZoom: Namespace.ID? = nil
}

extension AppState {
    /// Opens the story. App-level sheets that are up (Einstellungen, Gipfelbuch, an optional update) close first and the
    /// story follows once they are gone (a cover cannot be presented over a sheet); an open trip editor keeps its
    /// unsaved input and is never covered; a required update is never covered either.
    func presentYearReview(year: Int? = nil, source: YearReviewRequest.Source = .link) {
        guard yearReviewRequest == nil, tripDraft == nil else { return }
        if updates.isPresentingSheet && updates.isRequired { return }
        let request = YearReviewRequest(year: year, source: source)
        guard isShowingSettings || isShowingAchievements || updates.isPresentingSheet else {
            yearReviewRequest = request
            return
        }
        isShowingSettings = false
        isShowingAchievements = false
        updates.isPresentingSheet = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))   // the sheet's dismissal animation
            if self.yearReviewRequest == nil, self.tripDraft == nil { self.yearReviewRequest = request }
        }
    }

    /// "klimabilanz://year" · "klimabilanz://year/2026" (a path that is no sensible year opens the default period).
    func handleYearReviewLink(_ url: URL) {
        let year = Int(url.lastPathComponent).flatMap { (2000...2100).contains($0) ? $0 : nil }
        presentYearReview(year: year, source: .link)
    }

    /// "Fahrt erfassen" from the empty story: the story closes, the editor follows (a sheet cannot open under a cover).
    func closeYearReviewAndAddTrip() {
        yearReviewRequest = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            if self.yearReviewRequest == nil { self.presentAddTrip() }
        }
    }
}

/// Presents the story as a full-screen cover over everything (RootView) and shares the zoom namespace with the cards.
struct YearReviewHostModifier: ViewModifier {
    @Environment(AppState.self) private var app
    @Namespace private var zoom

    func body(content: Content) -> some View {
        @Bindable var app = app
        content
            .environment(\.yearReviewZoom, zoom)
            .fullScreenCover(item: $app.yearReviewRequest) { request in
                YearReviewStoryView(request: request) { app.yearReviewRequest = nil }
                    .modifier(YearReviewZoomDestination(source: request.source, namespace: zoom))
            }
    }
}

private struct YearReviewZoomDestination: ViewModifier {
    let source: YearReviewRequest.Source
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if source == .link {
            content
        } else {
            content.zoomDestination(id: YearReviewZoom.id(for: source), in: namespace)
        }
    }
}

extension View {
    /// MARK: yearreview – the story's full-screen cover and zoom namespace (put once on RootView).
    func yearReviewHost() -> some View {
        modifier(YearReviewHostModifier())
    }
}
