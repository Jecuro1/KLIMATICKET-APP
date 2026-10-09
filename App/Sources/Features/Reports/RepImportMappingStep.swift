import SwiftUI
import KlimaCore

/// Step 2 – file facts (rows, delimiter, encoding, detected source), header toggle, delimiter override and the
/// column mapping with sample values; a checklist shows what is still missing.
struct RepImportMappingStep: View {
    @Bindable var model: RepImportModel

    var body: some View {
        RepStepHeader(step: 2, total: 3, title: "Spalten zuordnen",
                      message: "Wir haben deine Spalten erkannt. Tipp auf eine Zuordnung, um sie zu ändern.")
            .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)

        fileCard

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Kicker(text: "Spalten · \(model.columnCount)")
                .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(0..<model.columnCount, id: \.self) { column in
                        if column > 0 {
                            Rectangle().fill(Theme.separator).frame(height: 0.5)
                                .padding(.leading, 62)
                        }
                        RepColumnRow(model: model, column: column)
                    }
                }
                .padding(.vertical, Theme.Spacing.xxs)
            }
        }

        requirements
    }

    // MARK: File card

    private var fileCard: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    SetIconTile(symbol: "doc.text.fill", tint: Theme.glacier, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.file?.name ?? "Datei")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Text(metaLine)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let source = model.format.title {
                            RepBadge(text: "\(source) erkannt", symbol: "checkmark.seal.fill", tint: Theme.positiveText)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Rectangle().fill(Theme.separator).frame(height: 0.5)
                Toggle(isOn: Binding(get: { model.hasHeader }, set: { model.setHeader($0) })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Erste Zeile enthält Spaltennamen")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(model.hasHeader ? "Wird nicht importiert" : "Wird als Fahrt importiert")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .tint(Theme.accent)
                Rectangle().fill(Theme.separator).frame(height: 0.5)
                HStack {
                    Text("Trennzeichen")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: Theme.Spacing.xs)
                    delimiterMenu
                }
            }
        }
    }

    private var metaLine: String {
        guard let file = model.file else { return "" }
        return [RepText.rows(model.dataRowCount), model.delimiter.title, file.encoding.title, RepText.fileSize(file.byteCount)]
            .joined(separator: " · ")
    }

    private var delimiterMenu: some View {
        Menu {
            Picker("Trennzeichen", selection: Binding(get: { model.delimiterOverride }, set: { model.setDelimiter($0) })) {
                Text("Automatisch (\(model.detectedDelimiter.title))").tag(CSVImport.Delimiter?.none)
                ForEach(CSVImport.Delimiter.allCases) { delimiter in
                    Text("\(delimiter.title)  \(delimiter == .tab ? "⇥" : delimiter.rawValue)").tag(Optional(delimiter))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.delimiterOverride == nil ? "Automatisch · \(model.delimiter.title)" : model.delimiter.title)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accentText)
        }
        .accessibilityLabel("Trennzeichen")
        .accessibilityValue(model.delimiter.title)
    }

    // MARK: Requirements

    private var requirements: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Kicker(text: "Für den Import")
                RepRequirementRow(state: model.hasDate ? .ok : .missing, title: "Datum",
                                  detail: model.hasDate ? "Mit Uhrzeit, falls vorhanden" : "Ordne eine Spalte als Datum zu")
                RepRequirementRow(state: model.hasRoute ? .ok : .missing, title: "Strecke",
                                  detail: model.hasRoute ? (model.fields.contains(.route) && !model.fields.contains(.from) ? "Aus „Von – Nach“ gelesen" : "Von und Nach")
                                                         : "Von und Nach – oder eine Spalte „Salzburg – Wien“")
                RepRequirementRow(state: model.hasPrice ? .ok : .info, title: "Normalpreis",
                                  detail: model.hasPrice ? "Pro Richtung und Person" : "Fehlt – wir schätzen den ÖBB-Normalpreis, wo wir die Haltestellen kennen")
            }
        }
    }
}

/// One column: field tile, header + sample values, and the assignment menu (Ignorieren / Datum / Von …).
struct RepColumnRow: View {
    @Bindable var model: RepImportModel
    let column: Int

    var body: some View {
        let field = model.field(for: column)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                tile(field)
                labels
                Spacer(minLength: Theme.Spacing.xs)
                menu(field)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    tile(field)
                    labels
                }
                menu(field)
                    .padding(.leading, 44)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 10)
        .opacity(field == nil ? 0.78 : 1)
        .animation(.smooth(duration: 0.25), value: field)
    }

    private func tile(_ field: CSVImport.Field?) -> some View {
        SetIconTile(symbol: field?.symbolName ?? "minus", tint: field.map(RepFieldStyle.color) ?? Color(hex: "#94A3B8"), size: 32)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.headerTitle(column: column))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            let samples = model.samples(column: column)
            Text(samples.isEmpty ? "leer" : samples.joined(separator: " · "))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .layoutPriority(1)
    }

    private func menu(_ field: CSVImport.Field?) -> some View {
        Menu {
            Picker("Bedeutung", selection: Binding(get: { model.field(for: column) }, set: { model.setField($0, for: column) })) {
                Label("Ignorieren", systemImage: "minus.circle").tag(CSVImport.Field?.none)
                ForEach(CSVImport.Field.allCases) { option in
                    Label(menuTitle(option), systemImage: option.symbolName).tag(Optional(option))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(field.map(RepFieldStyle.shortTitle) ?? "Ignorieren")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(field == nil ? Theme.textSecondary : Theme.accentText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .accessibilityLabel("Spalte \(model.headerTitle(column: column))")
        .accessibilityValue(field?.title ?? "Ignorieren")
        .accessibilityHint("Legt fest, was in dieser Spalte steht")
    }

    /// "Datum · Spalte 3" when the field already belongs to another column (choosing it moves it here).
    private func menuTitle(_ option: CSVImport.Field) -> String {
        if let owner = model.fields.firstIndex(of: option), owner != column {
            return "\(option.title) · jetzt Spalte \(owner + 1)"
        }
        return option.title
    }
}

/// Checklist line: ✓ ok, ✕ missing, ⓘ optional/estimated.
struct RepRequirementRow: View {
    enum Status { case ok, missing, info }

    var state: Status
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(state == .ok ? "erledigt" : state == .missing ? "fehlt" : "optional")
    }

    private var symbol: String {
        switch state {
        case .ok: "checkmark.circle.fill"
        case .missing: "xmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .ok: Theme.positive
        case .missing: Theme.negative
        case .info: Theme.summit
        }
    }
}

/// Colours and short labels of the import fields.
enum RepFieldStyle {
    static func color(_ field: CSVImport.Field) -> Color {
        switch field {
        case .date, .time: Theme.glacier
        case .from: Theme.glacier
        case .to, .route: Theme.dawn
        case .price, .totalValue: Theme.pine
        case .mode: Theme.modeColor(.train)
        case .roundTrip: Theme.dusk
        case .category: Theme.gold
        case .note: Color(hex: "#64748B")
        case .distance, .totalDistance: Theme.modeColor(.sBahn)
        case .induced: Theme.alpenglow
        }
    }

    static func shortTitle(_ field: CSVImport.Field) -> String {
        switch field {
        case .date: "Datum"
        case .time: "Uhrzeit"
        case .from: "Von"
        case .to: "Nach"
        case .route: "Strecke"
        case .price: "Normalpreis"
        case .totalValue: "Wert gesamt"
        case .mode: "Verkehrsmittel"
        case .roundTrip: "Hin & Retour"
        case .category: "Kategorie"
        case .note: "Notiz"
        case .distance: "Distanz"
        case .totalDistance: "Distanz gesamt"
        case .induced: "Ohne Ticket"
        }
    }
}
