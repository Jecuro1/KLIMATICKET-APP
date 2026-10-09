import SwiftUI
import UIKit
import CoreGraphics
import KlimaCore

/// The pages of one report, in print order.
enum RepReportPage {
    case cover
    case analysis
    case table(lines: [ReportPagination.Line], isFirst: Bool, isLast: Bool)
}

/// A rendered report on disk (temporary directory) plus a cover thumbnail for the share sheet.
struct RepRenderedReport: Equatable {
    var url: URL
    var pageCount: Int
    var key: String
    var thumbnail: UIImage?

    static func == (a: RepRenderedReport, b: RepRenderedReport) -> Bool { a.url == b.url && a.key == b.key && a.pageCount == b.pageCount }
}

/// Renders the annual report into a multi-page A4 PDF: every page is a SwiftUI view drawn by `ImageRenderer`
/// straight into a PDF `CGContext` (vector text and shapes, no rasterising).
@MainActor
enum RepPDFRenderer {
    static func pages(for data: RepReportData) -> [RepReportPage] {
        var pages: [RepReportPage] = [.cover, .analysis]
        guard data.hasTrips else { return pages }
        var tables = ReportPagination.pages(trips: data.snapshot.trips,
                                            firstPageCapacity: RepTablePage.firstCapacity,
                                            pageCapacity: RepTablePage.pageCapacity,
                                            monthHeight: RepTablePage.monthHeight,
                                            tripHeight: RepTablePage.tripHeight)
        // Keep room for the total line on the last table page.
        if let last = tables.last {
            let capacity = tables.count == 1 ? RepTablePage.firstCapacity : RepTablePage.pageCapacity
            if height(of: last) + RepTablePage.totalHeight > capacity { tables.append([]) }
        }
        for (index, lines) in tables.enumerated() {
            pages.append(.table(lines: lines, isFirst: index == 0, isLast: index == tables.count - 1))
        }
        return pages
    }

    private static func height(of lines: [ReportPagination.Line]) -> Double {
        lines.reduce(0) { sum, line in
            if case .month = line { return sum + RepTablePage.monthHeight }
            return sum + RepTablePage.tripHeight
        }
    }

    /// The SwiftUI view of one page (also used by the in-app page previews).
    @ViewBuilder
    static func view(for page: RepReportPage, data: RepReportData, number: Int, count: Int, skyImage: UIImage? = nil) -> some View {
        switch page {
        case .cover:
            RepCoverPage(data: data, number: number, count: count, skyImage: skyImage)
        case .analysis:
            RepAnalysisPage(data: data, number: number, count: count)
        case .table(let lines, let isFirst, let isLast):
            RepTablePage(data: data, lines: lines, isFirst: isFirst, isLast: isLast, number: number, count: count)
        }
    }

    /// Writes the PDF and returns the rendered report, or nil when the file could not be created or the task was cancelled.
    /// Suspends briefly between pages so the UI (spinner, sheet transition) stays responsive.
    static func render(_ data: RepReportData, key: String) async -> RepRenderedReport? {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Jahresbericht", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: data.fileName)
        try? FileManager.default.removeItem(at: url)

        let pages = pages(for: data)
        var mediaBox = CGRect(origin: .zero, size: RepPrint.pageSize)
        let info: [String: Any] = [
            kCGPDFContextTitle as String: data.title,
            kCGPDFContextCreator as String: "KlimaBilanz \(AppConfig.appVersion)",
            kCGPDFContextAuthor as String: data.holderName.isEmpty ? "KlimaBilanz" : data.holderName,
            kCGPDFContextSubject as String: "\(data.ticketName) · \(data.validityText) – keine offizielle Auswertung",
        ]
        guard let pdf = CGContext(url as CFURL, mediaBox: &mediaBox, info as CFDictionary) else { return nil }
        let sky = skyImage(data)
        for (index, page) in pages.enumerated() {
            let content = view(for: page, data: data, number: index + 1, count: pages.count, skyImage: sky)
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(RepPrint.pageSize)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
            try? await Task.sleep(for: .milliseconds(8))
        }
        pdf.closePDF()
        guard !Task.isCancelled, FileManager.default.fileExists(atPath: url.path()) else { return nil }
        return RepRenderedReport(url: url, pageCount: pages.count, key: key, thumbnail: thumbnail(data, count: pages.count))
    }

    /// The cover's soft sky as a 3× bitmap (see `RepCoverSky.backdropImage`).
    static func skyImage(_ data: RepReportData) -> UIImage? {
        let content = RepCoverSkyBackdrop(data: data)
            .frame(width: RepPrint.pageSize.width, height: RepCoverPage.skyHeight)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: RepPrint.pageSize.width, height: RepCoverPage.skyHeight)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Small raster image of the cover (share sheet preview).
    static func thumbnail(_ data: RepReportData, count: Int) -> UIImage? {
        let renderer = ImageRenderer(content: RepCoverPage(data: data, number: 1, count: count))
        renderer.proposedSize = ProposedViewSize(RepPrint.pageSize)
        renderer.scale = 0.5
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
