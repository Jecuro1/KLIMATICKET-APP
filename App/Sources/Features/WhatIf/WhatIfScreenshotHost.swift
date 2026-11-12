import SwiftUI
import SwiftData
import KlimaCore

/// CI screenshot routes of „Was wäre wenn?“ (`-KBScreenshot <screen> -KBDemo YES`, demo data, no network):
/// - `whatIf` / `whatIfBottom`: „Meine Fahrten“ on the demo year (top, and scrolled to the ranking, scenarios and the footnote)
/// - `whatIfFilters` / `whatIfFiltersBottom`: the same with ×1,5, „Juli und August ohne Fahrten“ and „Nur ein Bundesland“ (top of the controls)
/// - `whatIfPrePurchase` / `whatIfPreBottom`: „Eigene Annahmen“ with the preset „Täglich pendeln“ (and its lower part)
/// - `whatIfWeekend`: „Eigene Annahmen“ with „Wochenend-Heimfahrt“ (the ticket pays off at once)
/// - `whatIfOccasional`: „Eigene Annahmen“ with „Gelegentlich“ (single tickets are cheaper)
/// - `whatIfEmpty`: „Eigene Annahmen“ without a route (the inviting card)
/// - `whatIfExtreme`: two routes at 60 trips a month
/// - `whatIfRoutes` / `whatIfControls`: the middle of „Eigene Annahmen“ (route card, ticket kind) and of „Meine Fahrten“ (slider, toggles)
/// - `whatIfAX5` / `whatIfAX5Mid` / `whatIfAX5Bottom`: „Eigene Annahmen“ at the largest accessibility text size
/// - `whatIfSaved`: three saved scenarios in the list
/// - `whatIfSheet`: the sheet as it opens from onboarding / the empty Ticket tab (own navigation bar)
struct WhatIfScreenshotHost: View {
    static let screens: Set<String> = [
        "whatIf", "whatIfBottom", "whatIfFilters", "whatIfFiltersBottom", "whatIfPrePurchase", "whatIfPreBottom", "whatIfWeekend",
        "whatIfOccasional", "whatIfEmpty", "whatIfExtreme", "whatIfAX5", "whatIfAX5Mid", "whatIfAX5Bottom", "whatIfSaved", "whatIfSheet",
        "whatIfRoutes", "whatIfControls",
    ]

    let screen: String

    @Environment(AppState.self) private var app

    var body: some View {
        content
            .dynamicTypeSize(screen.hasPrefix("whatIfAX5") ? .accessibility5 : .large)
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case "whatIfBottom":
            NavigationStack { WhatIfView(launch: .automatic, scenarios: sampleScenarios) }
                .defaultScrollAnchor(.bottom)
        case "whatIfFilters":
            NavigationStack { WhatIfView(launch: .historyFiltered, scenarios: []) }
        case "whatIfFiltersBottom":
            NavigationStack { WhatIfView(launch: .historyFiltered, scenarios: []) }
                .defaultScrollAnchor(.bottom)
        case "whatIfPrePurchase":
            NavigationStack { WhatIfView(launch: .preset("commute"), scenarios: []) }
        case "whatIfPreBottom":
            NavigationStack { WhatIfView(launch: .preset("commute"), scenarios: []) }
                .defaultScrollAnchor(.bottom)
        case "whatIfWeekend":
            NavigationStack { WhatIfView(launch: .preset("weekend"), scenarios: []) }
        case "whatIfOccasional":
            NavigationStack { WhatIfView(launch: .preset("occasional"), scenarios: []) }
        case "whatIfEmpty":
            NavigationStack { WhatIfView(launch: .empty, scenarios: []) }
        case "whatIfExtreme":
            NavigationStack { WhatIfView(launch: .extreme, scenarios: []) }
        case "whatIfAX5":
            NavigationStack { WhatIfView(launch: .preset("commute"), scenarios: []) }
        case "whatIfAX5Mid":
            NavigationStack { WhatIfView(launch: .preset("commute"), scenarios: []) }
                .defaultScrollAnchor(.center)
        case "whatIfRoutes":
            NavigationStack { WhatIfView(launch: .preset("commute"), scenarios: []) }
                .defaultScrollAnchor(UnitPoint(x: 0.5, y: 0.42))
        case "whatIfControls":
            NavigationStack { WhatIfView(launch: .automatic, scenarios: []) }
                .defaultScrollAnchor(UnitPoint(x: 0.5, y: 0.5))
        case "whatIfAX5Bottom":
            NavigationStack { WhatIfView(launch: .preset("commute"), scenarios: []) }
                .defaultScrollAnchor(.bottom)
        case "whatIfSaved":
            NavigationStack { WhatIfView(launch: .preset("weekend"), scenarios: sampleScenarios) }
                .defaultScrollAnchor(.bottom)
        case "whatIfSheet":
            Color.clear
                .ambientBackground()
                .sheet(isPresented: .constant(true)) { WhatIfSheet(launch: .preset("commute")) }
        default:
            NavigationStack { WhatIfView(launch: .automatic, scenarios: []) }
        }
    }

    /// Three scenarios as a user could have saved them: the inputs of three presets, with the headline they really give
    /// today (opened, they are calculated again).
    private var sampleScenarios: [WhatIfScenario] {
        let now = Date()
        let calculator = WhatIfCalculator(catalog: app.catalog, relations: app.relations, stations: app.stations)
        let names = [("commute", "Pendeln nach Wien"), ("weekend", "Heimfahrt Graz"), ("occasional", "Ausflüge")]
        return names.compactMap { id, name in
            guard let input = WhatIfPreset.preset(id: id)?.input(startDate: now) else { return nil }
            return WhatIfScenario(name: name, createdAt: now, usesHistory: false, input: input,
                                  savedHeadline: WhatIfText.scenarioHeadline(calculator.evaluate(input)))
        }
    }
}
