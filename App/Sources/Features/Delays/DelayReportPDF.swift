import SwiftUI
import UIKit
import KlimaCore

// MARK: delaydiary – „Nachweis als PDF“ (docs/DELAY_DIARY.md §6)

/// What the PDF says besides the rows: the ticket, optionally the holder, when it was made.
struct DelayReportHead {
    var ticketName: String
    /// „2026/27“ – also in the file name.
    var yearLabel: String
    var validFrom: Date
    var validTo: Date
    /// nil: the name stays off the PDF.
    var holderName: String?
    var createdAt: Date
}

/// The report drawn as an A4 PDF with `UIGraphicsPDFRenderer`: real text (selectable, searchable), a title in the document
/// info, no logo. Title, ticket, intro, the caveat in a box, then per month its counts and a table of the late Fahrten (Datum,
/// Strecke, Zug, Verspätung, Quelle). No amount of money anywhere. Nothing is sent: the share sheet is the only way out.
@MainActor
enum DelayReportPDF {
    static let pageWidth: CGFloat = 595.2
    static let pageHeight: CGFloat = 841.8
    static let margin: CGFloat = 48
    static let footerHeight: CGFloat = 28

    static func data(_ report: DelayReport, head: DelayReportHead) -> Data { render(report, head: head).data }

    /// The PDF and how many pages it has.
    static func render(_ report: DelayReport, head: DelayReportHead) -> (data: Data, pages: Int) {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: DelayDiaryText.reportTitle,
            kCGPDFContextAuthor as String: head.holderName ?? "KlimaBilanz",
            kCGPDFContextSubject as String: "Persönliche Aufzeichnung – keine amtlichen Pünktlichkeitswerte",
            kCGPDFContextCreator as String: "KlimaBilanz \(AppConfig.appVersion)",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), format: format)
        var pages = 0
        let data = renderer.pdfData { context in
            var page = DelayReportPage(context: context)
            page.draw(report, head: head)
            pages = page.pageCount
        }
        return (data, max(pages, 1))
    }

    static var folder: URL { FileManager.default.temporaryDirectory.appending(path: "Verspaetungen", directoryHint: .isDirectory) }

    /// Removes the written PDFs (when the sheet closes – the share sheet has copied what it took by then).
    static func removeFiles() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Writes the PDF to the temporary directory; returns its URL and page count.
    static func write(_ report: DelayReport, head: DelayReportHead) throws -> (url: URL, pages: Int) {
        let folder = Self.folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let label = head.yearLabel.replacingOccurrences(of: "/", with: "-")
        let url = folder.appending(path: "Verspaetungs-Tagebuch-\(label).pdf")
        try? FileManager.default.removeItem(at: url)
        let rendered = render(report, head: head)
        try rendered.data.write(to: url, options: .atomic)
        return (url, rendered.pages)
    }

    /// „1. Mai – 31. Mai 2026“
    static func span(_ start: Date, _ end: Date) -> String {
        "\(Format.date(start, .long)) – \(Format.date(end, .long))"
    }
}

/// Draws the report onto PDF pages; a block that does not fit starts a new page (table rows repeat the header there).
@MainActor
private struct DelayReportPage {
    let context: UIGraphicsPDFRendererContext
    private var y: CGFloat = 0
    private var pageNumber = 0
    var pageCount: Int { pageNumber }

    init(context: UIGraphicsPDFRendererContext) {
        self.context = context
    }

    private static let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
    private var left: CGFloat { DelayReportPDF.margin }
    private var width: CGFloat { DelayReportPDF.pageWidth - 2 * DelayReportPDF.margin }
    private var bottom: CGFloat { DelayReportPDF.pageHeight - DelayReportPDF.margin - DelayReportPDF.footerHeight }

    /// Column x offsets and widths: Datum, Strecke, Zug, Verspätung, Quelle.
    private var columns: [(x: CGFloat, width: CGFloat, alignment: NSTextAlignment)] {
        let w = width
        let date = w * 0.19, route = w * 0.37, train = w * 0.17, minutes = w * 0.13
        let source = w - date - route - train - minutes
        var x = left
        var result: [(CGFloat, CGFloat, NSTextAlignment)] = []
        for (columnWidth, alignment) in [(date, NSTextAlignment.left), (route, .left), (train, .left), (minutes, .right), (source, .left)] {
            result.append((x, columnWidth, alignment))
            x += columnWidth
        }
        return result.map { (x: $0.0, width: $0.1, alignment: $0.2) }
    }

    mutating func draw(_ report: DelayReport, head: DelayReportHead) {
        newPage()
        y += text(DelayDiaryText.reportTitle, size: 18, weight: .bold, x: left, y: y, width: width) + 6
        var meta = ["\(head.ticketName) · gültig \(DelayReportPDF.span(head.validFrom, head.validTo))"]
        if let holder = head.holderName { meta.append("Inhaberin bzw. Inhaber: \(holder)") }
        meta.append("Erstellt am \(Format.date(head.createdAt, .long))")
        y += text(meta.joined(separator: "\n"), size: 10, color: .darkGray, x: left, y: y, width: width) + 12
        y += text(DelayDiaryText.reportIntro(threshold: report.threshold, scope: report.scope, hasLive: report.hasLive), size: 10.5, x: left, y: y, width: width) + 10
        caveatBox()
        summary(report)
        for month in report.months {
            monthBlock(month, threshold: report.threshold)
        }
    }

    // MARK: Blocks

    private mutating func caveatBox() {
        let inset: CGFloat = 10
        let height = measure(DelayDiaryText.reportCaveat, size: 10.5, weight: .semibold, width: width - 2 * inset) + 2 * inset
        ensureRoom(height + 12)
        let rect = CGRect(x: left, y: y, width: width, height: height)
        let cg = context.cgContext
        let box = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        cg.addPath(box)
        cg.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor)
        cg.fillPath()
        cg.addPath(box)
        cg.setStrokeColor(UIColor(white: 0.55, alpha: 1).cgColor)
        cg.setLineWidth(0.8)
        cg.strokePath()
        _ = text(DelayDiaryText.reportCaveat, size: 10.5, weight: .semibold, x: left + inset, y: y + inset, width: width - 2 * inset)
        y += height + 14
    }

    private mutating func summary(_ report: DelayReport) {
        // review-delaydiary: „dieser Monate“ – the share of the chosen months, not the year's on the screen.
        let line = DelayDiaryText.reportSummary(months: report.months.count, trips: report.tripCount, recorded: report.recordedCount,
                                                late: report.lateCount, threshold: report.threshold, share: report.onTimeShare)
        ensureRoom(measure(line, size: 10.5, weight: .semibold, width: width) + 10)
        y += text(line, size: 10.5, weight: .semibold, x: left, y: y, width: width) + 14
    }

    private mutating func monthBlock(_ month: DelayReportMonth, threshold: Int) {
        let title = "Gültigkeitsmonat \(month.index + 1) · \(DelayReportPDF.span(month.start, month.end))"
        let counts = "\(DelayDiaryText.monthSummary(trips: month.tripCount, recorded: month.recordedCount, late: month.lateCount)) · persönlich: \(DelayDiaryText.shareLine(month.onTimeShare))"
        let headHeight = measure(title, size: 12, weight: .bold, width: width) + measure(counts, size: 9.5, width: width) + 8
        // Keep the heading with the table header and at least one row.
        ensureRoom(headHeight + 40)
        y += text(title, size: 12, weight: .bold, x: left, y: y, width: width) + 2
        y += text(counts, size: 9.5, color: .darkGray, x: left, y: y, width: width) + 6
        if month.rows.isEmpty {
            y += text(DelayDiaryText.noLateLine(threshold: threshold, recorded: month.recordedCount), size: 10, color: .darkGray,
                      x: left, y: y, width: width) + 14
            return
        }
        tableHeader()
        for row in month.rows {
            let cells = [
                "\(Format.weekdayDayMonth(row.date)) \(Calendar.vienna.component(.year, from: row.date))\n\(Format.time(row.date))",
                row.route,
                row.lineOrMode,
                DelayDiaryText.minutes(row.minutes),
                DelayDiaryText.sourceName(row.source),
            ]
            let height = zip(cells, columns).map { measure($0.0, size: 9.5, width: $0.1.width - 6) }.max() ?? 12
            if y + height + 6 > bottom {
                newPage()
                tableHeader()
            }
            for (cell, column) in zip(cells, columns) {
                _ = text(cell, size: 9.5, x: column.x, y: y, width: column.width - 6, alignment: column.alignment)
            }
            y += height + 4
            line(color: UIColor(white: 0.85, alpha: 1))
            y += 4
        }
        y += 10
    }

    private mutating func tableHeader() {
        let titles = ["Datum", "Strecke", "Linie", "Verspätung", "Quelle"]
        for (title, column) in zip(titles, columns) {
            _ = text(title, size: 9, weight: .semibold, color: .darkGray, x: column.x, y: y, width: column.width - 6, alignment: column.alignment)
        }
        y += 14
        line(color: UIColor(white: 0.6, alpha: 1))
        y += 5
    }

    // MARK: Pages

    private mutating func newPage() {
        context.beginPage()
        pageNumber += 1
        y = DelayReportPDF.margin
        let footer = "KlimaBilanz · persönliche Aufzeichnung, keine amtlichen Pünktlichkeitswerte · Seite \(pageNumber)"
        _ = text(footer, size: 8, color: .gray, x: left, y: DelayReportPDF.pageHeight - DelayReportPDF.margin - 10, width: width, alignment: .center)
    }

    private mutating func ensureRoom(_ height: CGFloat) {
        if y + height > bottom { newPage() }
    }

    private func line(color: UIColor) {
        let cg = context.cgContext
        cg.move(to: CGPoint(x: left, y: y))
        cg.addLine(to: CGPoint(x: left + width, y: y))
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(0.5)
        cg.strokePath()
    }

    // MARK: Text

    private func attributed(_ string: String, size: CGFloat, weight: UIFont.Weight, color: UIColor, alignment: NSTextAlignment) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineSpacing = 1.5
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: string, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
    }

    private func measure(_ string: String, size: CGFloat, weight: UIFont.Weight = .regular, width: CGFloat) -> CGFloat {
        ceil(attributed(string, size: size, weight: weight, color: .black, alignment: .left)
            .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: Self.options, context: nil).height)
    }

    /// Draws `string` with its top left at (x, y) and returns the height it took.
    private func text(_ string: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = .black, x: CGFloat, y: CGFloat,
                      width: CGFloat, alignment: NSTextAlignment = .left) -> CGFloat {
        let attributedString = attributed(string, size: size, weight: weight, color: color, alignment: alignment)
        let height = ceil(attributedString.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                        options: Self.options, context: nil).height)
        attributedString.draw(with: CGRect(x: x, y: y, width: width, height: height), options: Self.options, context: nil)
        return height
    }
}
