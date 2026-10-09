import SwiftUI
import SwiftData
import KlimaCore

/// CI screenshot routes of the Ratgeber (`-KBScreenshot <screen> -KBDemo YES`):
/// `advisor` (top), `advisorRenewal` (Verlängern + Erinnerung), `advisorCancel` (Kündigungsrechner),
/// `advisorCancelChart` (Erstattung je Monat + außerordentlich), `advisorExtras` (1. Klasse), `advisorFamily`
/// (Familien-Bilanz), `advisorJob` (Jobticket with employer contribution), `ticketEdit` (edit sheet, new fields) and
/// `ticketAdvisor` (Ticket tab scrolled to the Ratgeber entry).
struct AdvScreenshotHost: View {
    static let screens: Set<String> = [
        "advisor", "advisorRenewal", "advisorCancel", "advisorCancelChart", "advisorExtras", "advisorFamily",
        "advisorJob", "ticketEdit", "ticketAdvisor",
    ]

    let screen: String

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @State private var isReady = false
    @State private var showsEditor = true

    var body: some View {
        Group {
            if isReady, let ticket = tickets.first {
                switch screen {
                case "ticketEdit":
                    MainTabView()
                        .sheet(isPresented: $showsEditor) {
                            TktEditSheet(ticket: ticket, initial: TktDraft(ticket: ticket), scrollTarget: AdvEditAnchor.renewal)
                        }
                case "ticketAdvisor":
                    MainTabView()
                default:
                    NavigationStack {
                        AdvisorView(ticket: ticket, initialAnchor: initialAnchor)
                    }
                }
            } else {
                Color.clear.ambientBackground()
            }
        }
        .onAppear {
            guard !isReady else { return }
            switch screen {
            case "advisorJob":
                AdvDemoData.enrich(context: context, employerContribution: 500)
            case "ticketEdit":
                AdvDemoData.enrich(context: context, employerContribution: 400, addOns: [.vorteilsabo])
                app.selectedTab = .ticket
            case "ticketAdvisor":
                AdvDemoData.enrich(context: context)
                app.selectedTab = .ticket
            default:
                AdvDemoData.enrich(context: context)
            }
            isReady = true
        }
    }

    private var initialAnchor: AdvAnchor? {
        switch screen {
        case "advisorRenewal": .section(.renewal)
        case "advisorCancel": .section(.cancellation)
        case "advisorCancelChart": .cancellationChart
        case "advisorExtras": .section(.firstClass)
        case "advisorFamily": .section(.family)
        case "advisorJob": .section(.jobticket)
        default: nil
        }
    }
}
