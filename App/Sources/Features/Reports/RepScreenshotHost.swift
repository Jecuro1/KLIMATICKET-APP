import SwiftUI
import SwiftData
import KlimaCore

/// CI screenshot routes of this module (`-KBScreenshot <screen> -KBDemo YES`):
/// - `importPick` / `importMapping` / `importPreview` / `importResult`: the CSV import sheet over Einstellungen (sample file)
/// - `importEntry`: the Einstellungen › Daten section with the two new rows
/// - `report`: the Jahresbericht preview sheet over Statistik (`reportPDF2`/`reportPDF3`: scrolled to page 2/3 of the real PDF)
/// - `reportPage1` … `reportPage4`: one printed page, scaled to the screen width (layout QA)
struct RepScreenshotHost: View {
    let screen: String

    static let screens: Set<String> = ["importPick", "importMapping", "importPreview", "importProblems", "importResult", "importEntry", "report", "reportPDF2", "reportPDF3",
                                       "reportPage1", "reportPage2", "reportPage3", "reportPage4"]

    @Environment(AppState.self) private var app
    @State private var isPresenting = false

    var body: some View {
        content
            .task {
                guard !screen.hasPrefix("reportPage"), screen != "importEntry" else { return }
                try? await Task.sleep(for: .milliseconds(600))
                isPresenting = true
            }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case "importPick", "importMapping", "importPreview", "importProblems", "importResult":
            NavigationStack { SettingsView() }
                .sheet(isPresented: $isPresenting) {
                    RepImportFlow(preset: preset)
                }
        case "importEntry":
            NavigationStack {
                List {
                    SetDataSection()
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background { SetBackdrop() }
                .navigationTitle("Einstellungen")
            }
        case "report", "reportPDF2", "reportPDF3":
            MainTabView()
                .onAppear { app.selectedTab = .stats }
                .sheet(isPresented: $isPresenting) {
                    RepReportSheet(previewPage: screen == "reportPDF2" ? 1 : screen == "reportPDF3" ? 2 : 0)
                }
        default:
            RepPagePreview(pageNumber: Int(screen.dropFirst("reportPage".count)) ?? 1)
        }
    }
}

extension RepScreenshotHost {
    fileprivate var preset: RepImportPreset {
        switch screen {
        case "importPick": .pick
        case "importMapping": .mapping
        case "importPreview": .preview
        case "importProblems": .problems
        default: .result
        }
    }
}

/// One printed page scaled to the screen width (QA of the PDF layout in the simulator screenshots).
struct RepPagePreview: View {
    let pageNumber: Int

    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date) private var trips: [TripEntity]
    @Query(filter: #Predicate<BenefitEntity> { $0.deletedAt == nil }) private var benefits: [BenefitEntity]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color(hex: "#59606B").ignoresSafeArea()
                if let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) {
                    let data = RepReportData.make(ticket: ticket, trips: trips, benefits: benefits, catalog: app.catalog)
                    let pages = RepPDFRenderer.pages(for: data)
                    let index = min(max(pageNumber - 1, 0), pages.count - 1)
                    let scale = geo.size.width / RepPrint.pageSize.width
                    RepPDFRenderer.view(for: pages[index], data: data, number: index + 1, count: pages.count)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: geo.size.width, height: RepPrint.pageSize.height * scale, alignment: .topLeading)
                        .padding(.top, max(0, (geo.size.height - RepPrint.pageSize.height * scale) / 2))
                }
            }
        }
        .ignoresSafeArea()
    }
}
