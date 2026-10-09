import SwiftUI
import SwiftData
import KlimaCore

/// CI screenshot routes of the Ratgeber (`-KBScreenshot <screen> -KBDemo YES`):
/// `advisor` (top), `advisorCancel` (Kündigungsrechner), `advisorExtras` (1. Klasse + Familie), `advisorJob`
/// (Jobticket with employer contribution) and `ticketEdit` (edit sheet, new fields).
struct AdvScreenshotHost: View {
    let screen: String

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @State private var isReady = false
    @State private var showsEditor = true

    var body: some View {
        Group {
            if isReady, let ticket = tickets.first {
                if screen == "ticketEdit" {
                    MainTabView()
                        .sheet(isPresented: $showsEditor) {
                            TktEditSheet(ticket: ticket, initial: TktDraft(ticket: ticket), scrollTarget: AdvEditAnchor.renewal)
                        }
                } else {
                    NavigationStack {
                        AdvisorView(ticket: ticket, initialSection: initialSection)
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
            default:
                AdvDemoData.enrich(context: context)
            }
            isReady = true
        }
    }

    private var initialSection: AdvSection? {
        switch screen {
        case "advisorCancel": .cancellation
        case "advisorExtras": .firstClass
        case "advisorJob": .jobticket
        default: nil
        }
    }
}
