import SwiftUI
import SwiftData
import KlimaCore

/// CI screenshots of the year story (`-KBScreenshot <name> -KBDemo YES`: demo data, no network, every animation in its end
/// state). The numbered screens follow the story as specified: yearReview = page 1 (Intro), yearReview2 = Ersparnis,
/// 3 = Strecke, 4 = Lieblingsroute, 5 = Rhythmus, 6 = Unterwegs, 7 = Klima, 8 = Abschluss (share); a page the demo data does not
/// have falls back to the first page.
struct YearReviewScreenshotHost: View {
    static let screens: Set<String> = [
        "yearReview", "yearReview2", "yearReview3", "yearReview4", "yearReview5", "yearReview6", "yearReview7", "yearReview8",
        "yearReviewPurpose", "yearReviewShare", "yearReviewShareNames", "yearReviewShareSummit", "yearReviewSharePortrait",
        "yearReviewEmpty", "yearReviewAX5", "yearReviewAX5Share", "yearReviewCards",
    ]

    let screen: String

    var body: some View {
        if screen == "yearReviewCards" {
            YearReviewCardsPreview()
        } else {
            YearReviewStoryView(request: YearReviewRequest(year: nil, source: .link), setup: setup) {}
                .dynamicTypeSize(screen.hasPrefix("yearReviewAX5") ? .accessibility5 : .large)
        }
    }

    private var setup: YearReviewScreenshotSetup {
        var setup = YearReviewScreenshotSetup()
        switch screen {
        case "yearReview2", "yearReviewAX5": setup.page = .savings
        case "yearReview3": setup.page = .distance
        case "yearReview4": setup.page = .favoriteRoute
        case "yearReview5": setup.page = .rhythm
        case "yearReview6": setup.page = .onTheRoad
        case "yearReviewPurpose": setup.page = .purpose
        case "yearReview7": setup.page = .climate
        case "yearReview8", "yearReviewShare", "yearReviewAX5Share": setup.page = .finale
        case "yearReviewShareNames":
            setup.page = .finale
            setup.share.showsDetails = true
        case "yearReviewShareSummit":
            setup.page = .finale
            setup.share.style = .summit
        case "yearReviewSharePortrait":
            setup.page = .finale
            setup.share.format = .portrait
        case "yearReviewEmpty": setup.forceEmpty = true
        default: break
        }
        return setup
    }
}

/// Both entry cards on the sky (the seasonal one as if it were December).
private struct YearReviewCardsPreview: View {
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date) private var trips: [TripEntity]

    var body: some View {
        let year = trips.last.map { Calendar.vienna.component(.year, from: $0.date) } ?? 2026
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                YearReviewSeasonalCard(trips: trips, seasonOverride: year)
                YearReviewEntryCard()
                    .padding(.horizontal, Theme.Spacing.cardGutter)
            }
            .padding(.top, 80)
        }
        .ambientBackground()
    }
}
