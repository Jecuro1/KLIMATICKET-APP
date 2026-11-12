import SwiftUI
import UIKit
import CoreTransferable
import UniformTypeIdentifiers
import KlimaCore

// MARK: - PDF

/// A letter as a PDF, drawn on the device with `UIGraphicsPDFRenderer` (this file only – `RepPDFRenderer` stays as it is). The
/// text is real text (selectable and searchable in Files and Preview), the page is A4, the document has a title. Nothing is
/// sent anywhere and no letterhead or logo is drawn.
@MainActor
enum LetterPDF {
    static func data(for content: LetterContent) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: LetterLayout.pageWidth, height: LetterLayout.pageHeight)
        let format = UIGraphicsPDFRendererFormat()
        let author = content.signatureName == LetterFormat.blank ? "KlimaBilanz" : content.signatureName
        format.documentInfo = [
            kCGPDFContextTitle as String: content.documentTitle,
            kCGPDFContextAuthor as String: author,
            kCGPDFContextSubject as String: "Entwurf aus KlimaBilanz – keine Rechtsberatung",
            kCGPDFContextCreator as String: "KlimaBilanz \(AppConfig.appVersion)",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        return renderer.pdfData { context in
            var page = LetterPage(context: context)
            page.draw(content)
        }
    }

    /// Writes the PDF to the temporary directory and returns its URL.
    static func write(_ content: LetterContent, fileName: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Ticket-Schreiben", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fileName)
        try? FileManager.default.removeItem(at: url)
        try data(for: content).write(to: url, options: .atomic)
        return url
    }
}

/// Draws a letter onto PDF pages: the head at fixed places, then the text flowing from the top of the body area; a block
/// that does not fit starts a new page.
private struct LetterPage {
    let context: UIGraphicsPDFRendererContext
    private var y: CGFloat = 0

    init(context: UIGraphicsPDFRendererContext) {
        self.context = context
    }

    private static let drawOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    mutating func draw(_ content: LetterContent) {
        context.beginPage()
        let left = LetterLayout.left
        let width = LetterLayout.textWidth
        _ = text(content.senderLines.joined(separator: "\n"), size: LetterLayout.senderSize, x: left, y: LetterLayout.senderTop, width: width)
        _ = text(content.recipientLines.joined(separator: "\n"), size: LetterLayout.bodySize, x: left, y: LetterLayout.recipientTop, width: width)
        _ = text(content.dateLine, size: LetterLayout.bodySize, x: left, y: LetterLayout.dateTop, width: width, alignment: .right)
        let subjectHeight = text(content.subject, size: LetterLayout.subjectSize, weight: .bold, x: left, y: LetterLayout.subjectTop, width: width)

        // The text follows the subject (a long ticket number may wrap it to two lines).
        y = max(LetterLayout.bodyTop, LetterLayout.subjectTop + subjectHeight + LetterLayout.subjectGap)
        flow(content.salutation)
        for block in content.blocks {
            switch block {
            case .paragraph(let paragraph): flow(paragraph)
            case .facts(let facts): flowFacts(facts)
            case .bullets(let items): flow(items.map { "• \($0)" }.joined(separator: "\n"))
            }
        }
        // Closing, room for the signature, the typed name – kept together.
        let closingHeight = measure(content.closing, size: LetterLayout.bodySize, width: width)
        let nameHeight = measure(content.signatureName, size: LetterLayout.bodySize, width: width)
        ensureRoom(closingHeight + LetterLayout.signatureSpace + nameHeight)
        y += text(content.closing, size: LetterLayout.bodySize, x: left, y: y, width: width)
        y += LetterLayout.signatureSpace
        y += text(content.signatureName, size: LetterLayout.bodySize, x: left, y: y, width: width) + LetterLayout.blockGap
        if !content.enclosures.isEmpty {
            let list = content.enclosures.map { "• \($0)" }.joined(separator: "\n")
            ensureRoom(measure("Anlagen:", size: LetterLayout.bodySize, width: width) + measure(list, size: LetterLayout.bodySize, width: width))
            y += text("Anlagen:", size: LetterLayout.bodySize, weight: .bold, x: left, y: y, width: width)
            y += text(list, size: LetterLayout.bodySize, x: left, y: y, width: width)
        }
    }

    // MARK: Flow

    private mutating func flow(_ string: String) {
        let width = LetterLayout.textWidth
        ensureRoom(measure(string, size: LetterLayout.bodySize, width: width))
        y += text(string, size: LetterLayout.bodySize, x: LetterLayout.left, y: y, width: width) + LetterLayout.blockGap
    }

    private mutating func flowFacts(_ facts: [LetterContent.Fact]) {
        let indent = LetterLayout.factIndent
        let labelWidth = LetterLayout.factLabelWidth
        let valueWidth = LetterLayout.textWidth - indent - labelWidth
        let heights = facts.map { max(measure("\($0.label):", size: LetterLayout.bodySize, width: labelWidth),
                                      measure($0.value, size: LetterLayout.bodySize, width: valueWidth)) }
        ensureRoom(heights.reduce(0, +))
        for (fact, height) in zip(facts, heights) {
            _ = text("\(fact.label):", size: LetterLayout.bodySize, weight: .semibold, x: LetterLayout.left + indent, y: y, width: labelWidth)
            _ = text(fact.value, size: LetterLayout.bodySize, x: LetterLayout.left + indent + labelWidth, y: y, width: valueWidth)
            y += height + 1
        }
        y += LetterLayout.blockGap
    }

    private mutating func ensureRoom(_ height: CGFloat) {
        if y + height > LetterLayout.pageHeight - LetterLayout.bottom {
            context.beginPage()
            y = LetterLayout.top
        }
    }

    // MARK: Text

    private func attributed(_ string: String, size: CGFloat, weight: UIFont.Weight, alignment: NSTextAlignment) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineSpacing = LetterLayout.lineSpacing
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: string, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: UIColor.black,
            .paragraphStyle: style,
        ])
    }

    private func measure(_ string: String, size: CGFloat, weight: UIFont.Weight = .regular, width: CGFloat) -> CGFloat {
        let rect = attributed(string, size: size, weight: weight, alignment: .left)
            .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: Self.drawOptions, context: nil)
        return ceil(rect.height)
    }

    /// Draws `string` with its top left at (x, y) and returns the height it took.
    @discardableResult
    private func text(_ string: String, size: CGFloat, weight: UIFont.Weight = .regular, x: CGFloat, y: CGFloat, width: CGFloat,
                      alignment: NSTextAlignment = .left) -> CGFloat {
        let attributedString = attributed(string, size: size, weight: weight, alignment: alignment)
        let height = ceil(attributedString.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                        options: Self.drawOptions, context: nil).height)
        attributedString.draw(with: CGRect(x: x, y: y, width: width, height: height), options: Self.drawOptions, context: nil)
        return height
    }
}

// MARK: - Sharing and printing

/// The share item behind „Als PDF teilen“: the PDF is drawn only when a share target asks for it, not while the form is typed.
struct LetterPDFDocument: Transferable {
    var content: LetterContent
    var fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { document in
            let url = try await MainActor.run { try LetterPDF.write(document.content, fileName: document.fileName) }
            return SentTransferredFile(url)
        }
    }
}

/// AirPrint: the system print sheet with the same PDF.
@MainActor
enum LetterPrinter {
    static var isAvailable: Bool { UIPrintInteractionController.isPrintingAvailable }

    @discardableResult
    static func printLetter(_ content: LetterContent, jobName: String) -> Bool {
        let data = LetterPDF.data(for: content)
        guard UIPrintInteractionController.canPrint(data) else { return false }
        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = jobName
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.showsNumberOfCopies = true
        return controller.present(animated: true)
    }
}
