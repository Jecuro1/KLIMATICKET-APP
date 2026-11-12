import SwiftUI
import KlimaCore

// MARK: - Page geometry

/// The A4 page of a letter in PDF points – shared by the on-screen paper and the PDF, so both put the same text in the same
/// places (DIN 5008 spirit: sender top left, address window at 53 mm, date on the right, subject, text).
enum LetterLayout {
    static let pageWidth: CGFloat = 595.28
    static let pageHeight: CGFloat = 841.89
    static let left: CGFloat = 70.87      // 25 mm
    static let right: CGFloat = 56.69     // 20 mm
    static let top: CGFloat = 56.69       // 20 mm
    static let bottom: CGFloat = 56.69
    static var textWidth: CGFloat { pageWidth - left - right }

    static let senderTop: CGFloat = 56.69
    static let recipientTop: CGFloat = 150
    static let dateTop: CGFloat = 238
    static let subjectTop: CGFloat = 268
    /// The text starts here when the subject has one line, lower when it has two.
    static let bodyTop: CGFloat = 298
    /// Space between the subject and the salutation.
    static let subjectGap: CGFloat = 16

    static let senderSize: CGFloat = 9.5
    static let bodySize: CGFloat = 10.5
    static let subjectSize: CGFloat = 11
    static let lineSpacing: CGFloat = 2.5
    static let blockGap: CGFloat = 8
    static let signatureSpace: CGFloat = 42
    static let factIndent: CGFloat = 12
    static let factLabelWidth: CGFloat = 138
}

// MARK: - On-screen paper

/// The letter as a sheet of paper: the real text (VoiceOver reads it paragraph by paragraph, nothing is an image), drawn on a
/// white A4 page scaled to `width`. Empty fields show as orange blank lines.
struct LetterPaper: View {
    var content: LetterContent
    var width: CGFloat

    private var scale: CGFloat { width / LetterLayout.pageWidth }

    var body: some View {
        page
            .frame(width: LetterLayout.pageWidth, height: LetterLayout.pageHeight, alignment: .topLeading)
            .background(Color.white)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: LetterLayout.pageHeight * scale, alignment: .topLeading)
            .clipShape(.rect(cornerRadius: 6, style: .continuous))
            .environment(\.colorScheme, .light)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Brief, Vorschau")
    }

    private var page: some View {
        ZStack(alignment: .topLeading) {
            lines(content.senderLines, size: LetterLayout.senderSize)
                .offset(x: LetterLayout.left, y: LetterLayout.senderTop)
            lines(content.recipientLines, size: LetterLayout.bodySize)
                .offset(x: LetterLayout.left, y: LetterLayout.recipientTop)
            paperText(content.dateLine, size: LetterLayout.bodySize)
                .frame(width: LetterLayout.textWidth, alignment: .trailing)
                .offset(x: LetterLayout.left, y: LetterLayout.dateTop)
            VStack(alignment: .leading, spacing: LetterLayout.blockGap) {
                // The subject may take two lines (a long ticket number): the text below follows it.
                paperText(content.subject, size: LetterLayout.subjectSize, weight: .bold)
                    .frame(width: LetterLayout.textWidth, alignment: .leading)
                    .padding(.bottom, LetterLayout.subjectGap - LetterLayout.blockGap)
                paperText(content.salutation, size: LetterLayout.bodySize)
                ForEach(Array(content.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
                VStack(alignment: .leading, spacing: 0) {
                    paperText(content.closing, size: LetterLayout.bodySize)
                    Color.clear.frame(height: LetterLayout.signatureSpace)
                    paperText(content.signatureName, size: LetterLayout.bodySize)
                }
                if !content.enclosures.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        paperText("Anlagen:", size: LetterLayout.bodySize, weight: .bold)
                        ForEach(content.enclosures, id: \.self) { item in
                            paperText("• \(item)", size: LetterLayout.bodySize)
                        }
                    }
                }
            }
            .frame(width: LetterLayout.textWidth, alignment: .leading)
            .offset(x: LetterLayout.left, y: LetterLayout.subjectTop)
        }
        .frame(width: LetterLayout.pageWidth, height: LetterLayout.pageHeight, alignment: .topLeading)
    }

    private func lines(_ lines: [String], size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                paperText(line, size: size)
            }
        }
        .frame(width: LetterLayout.textWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func blockView(_ block: LetterContent.Block) -> some View {
        switch block {
        case .paragraph(let text):
            paperText(text, size: LetterLayout.bodySize)
                .frame(width: LetterLayout.textWidth, alignment: .leading)
        case .facts(let facts):
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        paperText("\(fact.label):", size: LetterLayout.bodySize, weight: .semibold)
                            .frame(width: LetterLayout.factLabelWidth, alignment: .leading)
                        paperText(fact.value, size: LetterLayout.bodySize)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.leading, LetterLayout.factIndent)
            .frame(width: LetterLayout.textWidth, alignment: .leading)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 1) {
                ForEach(items, id: \.self) { item in paperText("• \(item)", size: LetterLayout.bodySize) }
            }
        }
    }

    /// Text on the page: fixed point size (a page does not follow Dynamic Type), blank lines of empty fields in orange.
    private func paperText(_ string: String, size: CGFloat, weight: Font.Weight = .regular) -> some View {
        Text(Self.attributed(string))
            .font(.system(size: size, weight: weight))
            .foregroundStyle(Color.black)
            .lineSpacing(LetterLayout.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The text with every blank line of an empty field marked – the orange gap is what is still missing.
    static func attributed(_ string: String) -> AttributedString {
        var result = AttributedString()
        let parts = string.components(separatedBy: LetterFormat.blank)
        for (index, part) in parts.enumerated() {
            result += AttributedString(part)
            if index < parts.count - 1 {
                var gap = AttributedString(LetterFormat.blank)
                gap.foregroundColor = Color(light: "#D9622B", dark: "#D9622B")
                result += gap
            }
        }
        return result
    }
}
