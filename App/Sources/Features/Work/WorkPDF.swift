import SwiftUI
import KlimaCore

/// A4 PDF documents ("Dienstreise-Nachweis", "Öffi-Fahrtenbuch") rendered page by page with ImageRenderer.
/// Fixed print palette (no materials, no glass), vector text, paginated table with totals on the last page.
@MainActor
enum WorkPDF {
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    static let margin = CGSize(width: 44, height: 40)
    static let lineHeight: CGFloat = 18
    static let firstPageUnits = 28
    static let followPageUnits = 37
    static let summaryUnits = 13

    // MARK: Documents

    static func businessDocument(_ data: WorkTaxData) -> WorkPDFDocument {
        let business = data.business
        let rows = business.trips.enumerated().map { index, trip in
            WorkPDFRow(cells: [String(index + 1), shortDate(trip.date), route(trip), trip.mode.displayName,
                               Format.number(trip.totalKm), Format.euroPrecise(trip.totalValue)],
                       note: trip.note.isEmpty ? nil : trip.note)
        }
        var totals = [
            WorkPDFTotal(label: "Summe Einzelfahrscheine (\(WorkFormat.count(business.trips.count, "Dienstreise", "Dienstreisen")))",
                         value: Format.euroPrecise(business.total)),
            WorkPDFTotal(label: "Obergrenze: selbst bezahlter Ticketpreis", value: Format.euroPrecise(business.cap)),
            WorkPDFTotal(label: "Absetzbar", value: Format.euroPrecise(business.claimable), isEmphasized: true),
        ]
        if business.spansSeveralYears {
            totals += business.years.map { WorkPDFTotal(label: "davon Kalenderjahr \($0.year)", value: Format.euroPrecise($0.claimable)) }
        }
        var notes = [
            "Bewertet je Dienstreise mit dem Einzelfahrschein 2. Klasse ohne Sparschiene (Normalpreis je Richtung). Insgesamt absetzbar ist höchstens der selbst bezahlte Ticketpreis; ein steuerfreier Arbeitgeberzuschuss senkt diese Obergrenze (AK).",
            "Nur Fahrten, die der Arbeitgeber nicht als Reisekosten ersetzt hat.",
            "↔ = hin & retour: km und Einzelfahrschein für beide Richtungen.",
        ]
        if data.firstClassBusinessTrips > 0 { notes.append("In der 1. Klasse erfasste Fahrten sind zum Preis der 2. Klasse bewertet.") }
        if business.spansSeveralYears { notes.append("Das Ticketjahr reicht über den Jahreswechsel – die Obergrenze ist chronologisch auf die Kalenderjahre verteilt.") }
        return WorkPDFDocument(
            kind: .businessTrips,
            title: "Dienstreise-Nachweis",
            subtitle: "Dienstreisen mit dem eigenen KlimaTicket · Ticketjahr \(data.ticketYear)",
            meta: meta(data, includeEmployer: true),
            columns: [WorkPDFColumn(title: "Nr.", width: 26, alignment: .trailing), WorkPDFColumn(title: "Datum", width: 62),
                      WorkPDFColumn(title: "Strecke  (↔ hin & retour)", width: nil), WorkPDFColumn(title: "Verkehrsmittel", width: 74),
                      WorkPDFColumn(title: "km", width: 42, alignment: .trailing),
                      WorkPDFColumn(title: "Einzelfahrschein", width: 82, alignment: .trailing)],
            rows: rows, totals: totals, notes: notes, showsSignature: true)
    }

    static func logbookDocument(_ data: WorkTaxData, countsCommute: Bool) -> WorkPDFDocument {
        let summary = data.selfEmployed
        let rows = data.trips.enumerated().map { (index, trip) -> WorkPDFRow in
            let business = WorkTax.isBusinessUse(trip.category, role: .selfEmployed, countsCommute: countsCommute)
            var purpose = business ? "betrieblich" : "privat"
            if let category = trip.category { purpose += " · \(category.displayName)" }
            return WorkPDFRow(cells: [String(index + 1), shortDate(trip.date), route(trip), trip.mode.displayName,
                                      Format.number(trip.totalKm), purpose],
                              note: trip.note.isEmpty ? nil : trip.note, isHighlighted: business)
        }
        var totals = [
            WorkPDFTotal(label: "Betriebliche Kilometer", value: Format.km(summary.businessKm)),
            WorkPDFTotal(label: "Private Kilometer", value: Format.km(summary.privateKm)),
            WorkPDFTotal(label: "Betrieblicher Anteil", value: "\(Format.number(summary.businessShare * 100, decimals: 1)) %"),
            WorkPDFTotal(label: "Basis (Ticketpreis\(summary.firstClassUpgrade > 0 ? " + 1. Klasse" : "")\(summary.familySurcharge > 0 ? " − Familienaufschlag" : ""))",
                         value: Format.euroPrecise(summary.basis)),
            WorkPDFTotal(label: "50-%-Pauschale", value: Format.euroPrecise(summary.flatRateAmount),
                         isEmphasized: summary.recommended == .flatRate),
        ]
        totals.append(summary.logbookApplies
                      ? WorkPDFTotal(label: "Betrieblicher Anteil laut Fahrtenbuch", value: Format.euroPrecise(summary.logbookAmount),
                                     isEmphasized: summary.recommended == .logbook)
                      : WorkPDFTotal(label: "Fahrtenbuch-Methode (erst ab mehr als 50 % betrieblich)", value: "–"))
        var notes = [
            "Seit 2022 sind 50 % einer nicht übertragbaren Jahreskarte pauschal als Betriebsausgabe absetzbar (1. Klasse inklusive, Familienaufschlag ausgenommen). Bei mehr als 50 % betrieblicher Nutzung kann stattdessen der betriebliche Anteil laut Öffi-Fahrtenbuch angesetzt werden (WKO).",
        ]
        notes.append("↔ = hin & retour: km für beide Richtungen.")
        notes.append(countsCommute
                     ? "Betrieblich gezählt: Dienstreisen und Wege zur Betriebsstätte."
                     : "Betrieblich gezählt: nur Dienstreisen (Wege zur Betriebsstätte nicht eingerechnet).")
        return WorkPDFDocument(
            kind: .logbook,
            title: "Öffi-Fahrtenbuch",
            subtitle: "Betriebliche und private Fahrten mit dem KlimaTicket · Ticketjahr \(data.ticketYear)",
            meta: meta(data, includeEmployer: false),
            columns: [WorkPDFColumn(title: "Nr.", width: 26, alignment: .trailing), WorkPDFColumn(title: "Datum", width: 62),
                      WorkPDFColumn(title: "Strecke  (↔ hin & retour)", width: nil), WorkPDFColumn(title: "Verkehrsmittel", width: 70),
                      WorkPDFColumn(title: "km", width: 40, alignment: .trailing), WorkPDFColumn(title: "Zweck", width: 110)],
            rows: rows, totals: totals, notes: notes, showsSignature: false)
    }

    private static func meta(_ data: WorkTaxData, includeEmployer: Bool) -> [WorkPDFMeta] {
        let ticket = data.ticket
        var items: [WorkPDFMeta] = []
        let holder = ticket.holderName.trimmingCharacters(in: .whitespacesAndNewlines)
        items.append(WorkPDFMeta(label: "Name", value: holder.isEmpty ? "—" : holder))
        items.append(WorkPDFMeta(label: "Ticket", value: ticket.name))
        items.append(WorkPDFMeta(label: "Gültig", value: "\(Format.date(ticket.startDate, .long)) – \(Format.date(ticket.endDate, .long))"))
        if !ticket.ticketNumber.isEmpty { items.append(WorkPDFMeta(label: "Ticketnummer", value: ticket.ticketNumber)) }
        let full = ticket.price + ticket.addOnPrice
        items.append(WorkPDFMeta(label: ticket.addOnPrice > 0 ? "Preis inkl. Extras" : "Ticketpreis", value: Format.euroPrecise(full)))
        if includeEmployer {
            items.append(WorkPDFMeta(label: "Arbeitgeberzuschuss", value: Format.euroPrecise(data.job.employerContribution)))
            items.append(WorkPDFMeta(label: "Selbst bezahlt", value: Format.euroPrecise(data.job.ownShare)))
        } else if data.selfEmployed.familySurcharge > 0 {
            items.append(WorkPDFMeta(label: "Familienaufschlag (privat)", value: Format.euroPrecise(data.selfEmployed.familySurcharge)))
        }
        return items
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(Format.locale))
    }

    /// "St. Anton → Lech", round trips "St. Anton ↔ Innsbruck Hbf" (legend in the column title and the notes).
    private static func route(_ trip: WorkTaxTrip) -> String {
        "\(TripRow.short(trip.fromName)) \(trip.isRoundTrip ? "↔" : "→") \(TripRow.short(trip.toName))"
    }

    // MARK: Pagination

    static func paginate(_ document: WorkPDFDocument) -> [WorkPDFPageSpec] {
        var pages: [WorkPDFPageSpec] = []
        var current: [Int] = []
        var used = 0
        var capacity = firstPageUnits
        for (index, row) in document.rows.enumerated() {
            let units = row.note == nil ? 1 : 2
            if used + units > capacity, !current.isEmpty {
                pages.append(WorkPDFPageSpec(rowIndices: current, isFirst: pages.isEmpty, showsSummary: false))
                current = []
                used = 0
                capacity = followPageUnits
            }
            current.append(index)
            used += units
        }
        let fitsSummary = capacity - used >= summaryUnits + document.totals.count / 2
        pages.append(WorkPDFPageSpec(rowIndices: current, isFirst: pages.isEmpty, showsSummary: fitsSummary))
        if !fitsSummary {
            pages.append(WorkPDFPageSpec(rowIndices: [], isFirst: false, showsSummary: true))
        }
        return pages
    }

    // MARK: Rendering

    /// Writes the document to a temporary file and returns its URL (nil if the PDF context could not be created).
    static func write(_ document: WorkPDFDocument, named name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, [
            kCGPDFContextTitle as String: document.title,
            kCGPDFContextCreator as String: "KlimaBilanz",
        ] as CFDictionary) else { return nil }
        let pages = paginate(document)
        for (index, spec) in pages.enumerated() {
            let page = WorkPDFPage(document: document, spec: spec, pageNumber: index + 1, pageCount: pages.count)
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return url
    }
}

// MARK: - Document model

struct WorkPDFDocument {
    enum Kind { case businessTrips, logbook }

    var kind: Kind
    var title: String
    var subtitle: String
    var meta: [WorkPDFMeta]
    var columns: [WorkPDFColumn]
    var rows: [WorkPDFRow]
    var totals: [WorkPDFTotal]
    var notes: [String]
    var showsSignature: Bool
    var generatedAt = Date()
}

struct WorkPDFMeta: Identifiable {
    var id: String { label }
    var label: String
    var value: String
}

struct WorkPDFColumn: Identifiable {
    var id: String { title }
    var title: String
    /// nil = flexible.
    var width: CGFloat?
    var alignment: Alignment = .leading
}

struct WorkPDFRow {
    var cells: [String]
    var note: String?
    var isHighlighted = false
}

struct WorkPDFTotal: Identifiable {
    var id: String { label }
    var label: String
    var value: String
    var isEmphasized = false
}

struct WorkPDFPageSpec {
    var rowIndices: [Int]
    var isFirst: Bool
    var showsSummary: Bool
}

/// Fixed print colours (independent of the app appearance).
enum WorkPDFPalette {
    static let ink = Color(hex: "#0C1A2B")
    static let ink2 = Color(hex: "#4A5768")
    static let ink3 = Color(hex: "#8A94A3")
    static let rule = Color(hex: "#D9E0E8")
    static let zebra = Color(hex: "#F4F7FA")
    static let header = Color(hex: "#EAF2FB")
    static let accent = Color(hex: "#1D5FB0")
    static let pine = Color(hex: "#0A6B52")
    static let highlight = Color(hex: "#EAF6F1")
    static let brand = LinearGradient(colors: [Color(hex: "#3B8BE0"), Color(hex: "#7C79E6"), Color(hex: "#F08A5B")],
                                      startPoint: .leading, endPoint: .trailing)
}

// MARK: - Page view

struct WorkPDFPage: View {
    let document: WorkPDFDocument
    let spec: WorkPDFPageSpec
    let pageNumber: Int
    let pageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if spec.isFirst { firstHeader } else { followHeader }
            if !spec.rowIndices.isEmpty {
                table
                    .padding(.top, spec.isFirst ? 18 : 10)
            }
            if spec.showsSummary {
                summary
                    .padding(.top, 18)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, WorkPDF.margin.width)
        .padding(.vertical, WorkPDF.margin.height)
        .frame(width: WorkPDF.pageSize.width, height: WorkPDF.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .environment(\.locale, Format.locale)
    }

    // MARK: Header

    private var brandMark: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(WorkPDFPalette.brand)
                .frame(width: 16, height: 16)
                .overlay {
                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            Text("KlimaBilanz")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(WorkPDFPalette.ink)
        }
    }

    private var firstHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                brandMark
                Spacer()
                Text("Erstellt am \(WorkFormat.longDate(document.generatedAt))")
                    .font(.system(size: 8.5))
                    .foregroundStyle(WorkPDFPalette.ink3)
            }
            Capsule()
                .fill(WorkPDFPalette.brand)
                .frame(width: 44, height: 3)
                .padding(.top, 18)
            Text(document.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(WorkPDFPalette.ink)
                .padding(.top, 8)
            Text(document.subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(WorkPDFPalette.ink2)
                .padding(.top, 2)
            metaGrid
                .padding(.top, 14)
        }
    }

    private var metaGrid: some View {
        let pairs = stride(from: 0, to: document.meta.count, by: 2).map { index in
            Array(document.meta[index..<min(index + 2, document.meta.count)])
        }
        return Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                GridRow {
                    ForEach(pair) { item in metaItem(item) }
                    if pair.count == 1 { Color.clear.frame(height: 1) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkPDFPalette.zebra, in: .rect(cornerRadius: 8, style: .continuous))
    }

    private func metaItem(_ item: WorkPDFMeta) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.label.uppercased(with: Format.locale))
                .font(.system(size: 7, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(WorkPDFPalette.ink3)
            Text(item.value)
                .font(.system(size: 9.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(WorkPDFPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var followHeader: some View {
        HStack {
            brandMark
            Text("· \(document.title) (Fortsetzung)")
                .font(.system(size: 9))
                .foregroundStyle(WorkPDFPalette.ink2)
            Spacer()
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(WorkPDFPalette.rule).frame(height: 0.5) }
    }

    // MARK: Table

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(document.columns) { column in
                    cell(column.title, column: column)
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(WorkPDFPalette.ink2)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(WorkPDFPalette.header, in: .rect(cornerRadius: 5, style: .continuous))
            ForEach(Array(spec.rowIndices.enumerated()), id: \.element) { position, index in
                rowView(document.rows[index], zebra: position % 2 == 1)
            }
            Rectangle().fill(WorkPDFPalette.rule).frame(height: 0.5)
        }
    }

    private func rowView(_ row: WorkPDFRow, zebra: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Array(document.columns.enumerated()), id: \.offset) { index, column in
                    cell(index < row.cells.count ? row.cells[index] : "", column: column)
                        .font(.system(size: 8.5, weight: index == document.columns.count - 1 ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(index == 0 ? WorkPDFPalette.ink3 : WorkPDFPalette.ink)
                }
            }
            .frame(height: WorkPDF.lineHeight)
            if let note = row.note {
                Text("Anlass: \(note)")
                    .font(.system(size: 7.5))
                    .foregroundStyle(WorkPDFPalette.ink2)
                    .lineLimit(1)
                    .padding(.leading, 32 + 62 + 6)
                    .frame(height: WorkPDF.lineHeight - 4, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 6)
        .background(row.isHighlighted ? WorkPDFPalette.highlight : (zebra ? WorkPDFPalette.zebra : Color.white))
    }

    @ViewBuilder
    private func cell(_ text: String, column: WorkPDFColumn) -> some View {
        let label = Text(text).lineLimit(1).minimumScaleFactor(0.75)
        if let width = column.width {
            label.frame(width: width, alignment: column.alignment)
        } else {
            label.frame(maxWidth: .infinity, alignment: column.alignment)
        }
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(document.totals) { total in
                    HStack {
                        Text(total.label)
                            .font(.system(size: total.isEmphasized ? 10.5 : 9.5, weight: total.isEmphasized ? .bold : .regular))
                        Spacer()
                        Text(total.value)
                            .font(.system(size: total.isEmphasized ? 12 : 9.5, weight: total.isEmphasized ? .bold : .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(total.isEmphasized ? WorkPDFPalette.pine : WorkPDFPalette.ink)
                    .padding(.horizontal, 10)
                    .frame(height: total.isEmphasized ? 26 : 20)
                    .background(total.isEmphasized ? WorkPDFPalette.highlight : Color.clear)
                    .overlay(alignment: .bottom) { Rectangle().fill(WorkPDFPalette.rule).frame(height: 0.5) }
                }
            }
            .frame(maxWidth: 330)
            .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(document.notes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .top, spacing: 5) {
                        Circle().fill(WorkPDFPalette.accent).frame(width: 3, height: 3).padding(.top, 4)
                        Text(note)
                            .font(.system(size: 8))
                            .foregroundStyle(WorkPDFPalette.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if document.showsSignature {
                HStack(spacing: 28) {
                    signatureLine("Ort, Datum")
                    signatureLine("Unterschrift")
                }
                .padding(.top, 14)
            }
        }
    }

    private func signatureLine(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Rectangle().fill(WorkPDFPalette.ink3).frame(height: 0.5)
            Text(label)
                .font(.system(size: 7.5))
                .foregroundStyle(WorkPDFPalette.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .bottom) {
            Text("\(WorkFormat.disclaimer). Erstellt mit KlimaBilanz – kein amtliches Dokument.")
                .font(.system(size: 7))
                .foregroundStyle(WorkPDFPalette.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 16)
            Text("Seite \(pageNumber) von \(pageCount)")
                .font(.system(size: 7.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(WorkPDFPalette.ink2)
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(WorkPDFPalette.rule).frame(height: 0.5) }
    }
}
