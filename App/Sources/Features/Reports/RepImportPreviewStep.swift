import SwiftUI
import KlimaCore

/// Step 3 – one summary card (value to be imported, status pills that filter the list, duplicate option) and the row
/// preview with every problem spelled out ("Zeile 7: Datum „31.02.2026“ nicht erkannt").
struct RepImportPreviewStep: View {
    @Bindable var model: RepImportModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let previewLimit = 250

    var body: some View {
        RepStepHeader(step: 3, total: 3, title: "Vorschau prüfen",
                      message: "Zeilen mit Fehlern lassen wir aus – die kannst du später von Hand erfassen.")
            .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)

        summaryCard

        Picker("Anzeigen", selection: $model.filter) {
            ForEach(RepImportModel.PreviewFilter.allCases) { filter in
                Text(title(for: filter)).tag(filter)
            }
        }
        .pickerStyle(.segmented)

        rows
    }

    // MARK: Summary

    private var problemCount: Int { model.candidates.filter { $0.status != .ready || !$0.warnings.isEmpty }.count }

    private var summaryCard: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker(text: "Fahrtenwert")
                        Text(Format.euroPrecise(model.importValue))
                            .font(Theme.Typography.priceNumeral)
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText(value: model.importValue))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: Theme.Spacing.xs)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(RepText.trips(model.toImport.count))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText(value: Double(model.toImport.count)))
                        if model.estimatedCount > 0 {
                            RepBadge(text: model.estimatedCount == 1 ? "1 Preis geschätzt" : "\(model.estimatedCount) Preise geschätzt",
                                     symbol: "wand.and.stars", tint: Theme.accentText)
                        }
                    }
                    .padding(.top, 2)
                }
                .animation(.smooth, value: model.importValue)

                pillLayout {
                    RepStatusPill(value: model.readyCandidates.count, label: "bereit", symbol: "checkmark", tint: Theme.pine,
                                  isSelected: model.filter == .ready) { toggleFilter(.ready) }
                    RepStatusPill(value: model.duplicateCount, label: "doppelt",
                                  symbol: "doc.on.doc.fill", tint: Theme.gold, isSelected: model.filter == .problems) { toggleFilter(.problems) }
                    RepStatusPill(value: model.invalidCount, label: "Fehler", symbol: "exclamationmark", tint: Theme.negative,
                                  isSelected: model.filter == .problems) { toggleFilter(.problems) }
                }

                if model.duplicateCount > 0 {
                    Rectangle().fill(Theme.separator).frame(height: 0.5)
                    Toggle(isOn: $model.skipDuplicates) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Duplikate überspringen")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Gleicher Tag, gleiche Strecke, gleicher Preis")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tint(Theme.accent)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Three pills side by side; stacked at accessibility text sizes.
    private var pillLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.xs))
    }

    private func toggleFilter(_ filter: RepImportModel.PreviewFilter) {
        withAnimation(.smooth(duration: 0.25)) {
            model.filter = model.filter == filter ? .all : filter
        }
    }

    private func title(for filter: RepImportModel.PreviewFilter) -> String {
        switch filter {
        case .all: "Alle \(model.candidates.count)"
        case .ready: "Bereit \(model.readyCandidates.count)"
        case .problems: problemCount == 0 ? "Probleme" : "Probleme \(problemCount)"
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var rows: some View {
        let list = model.filteredCandidates
        if list.isEmpty {
            GlassCard {
                VStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: model.filter == .problems ? "checkmark.seal.fill" : "tray")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(model.filter == .problems ? Theme.positive : Theme.textTertiary)
                        .accessibilityHidden(true)
                    Text(model.filter == .problems ? "Keine Probleme – alles sauber." : "Hier ist nichts.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.m)
            }
        } else {
            GlassCard(padding: Theme.Spacing.xs) {
                LazyVStack(spacing: 2) {
                    ForEach(list.prefix(Self.previewLimit)) { candidate in
                        RepPreviewRow(candidate: candidate, skipsDuplicates: model.skipDuplicates)
                    }
                }
            }
            if list.count > Self.previewLimit {
                Text("… und \(RepText.rows(list.count - Self.previewLimit)) mehr – sie werden genauso übernommen.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Count pill in the preview summary ("✓ 9 bereit"); tapping filters the list.
struct RepStatusPill: View {
    var value: Int
    var label: String
    var symbol: String
    var tint: Color
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background((value == 0 ? Theme.textTertiary : tint).gradient, in: .circle)
                    .environment(\.colorScheme, .light)
                Text("\(value)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(value == 0 ? Theme.textTertiary : Theme.textPrimary)
                    .contentTransition(.numericText(value: Double(value)))
                Text(label)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background((value == 0 ? Theme.textTertiary : tint).opacity(isSelected ? 0.22 : 0.10), in: .capsule)
            .overlay(Capsule().strokeBorder(tint.opacity(isSelected ? 0.5 : 0), lineWidth: 1))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(value == 0)
        .accessibilityLabel("\(value) \(label)")
        .accessibilityHint("Zeigt nur diese Zeilen")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One previewed CSV row: mode icon with status badge, date + line number, route, details and the problem (if any).
struct RepPreviewRow: View {
    let candidate: RepImportCandidate
    var skipsDuplicates: Bool

    private var isSkipped: Bool {
        candidate.status == .invalid || (candidate.status == .duplicate && skipsDuplicates)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            ModeIcon(mode: candidate.mode, size: 36)
                .saturation(isSkipped ? 0.1 : 1)
                .opacity(isSkipped ? 0.55 : 1)
                .overlay(alignment: .bottomTrailing) { statusBadge.offset(x: 5, y: 5) }
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                // Date line carries the value on the right, so the route below gets the full width.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Group {
                        Text(candidate.date.map(Format.weekdayDayMonth) ?? "ohne Datum")
                            .foregroundStyle(Theme.textSecondary)
                        Text("· Zeile \(candidate.line)")
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    Spacer(minLength: Theme.Spacing.xs)
                    if candidate.status != .invalid {
                        Text(Format.euroPrecise(candidate.totalValue))
                            .font(Theme.Typography.numberSmall)
                            .foregroundStyle(isSkipped ? Theme.textTertiary : Theme.textPrimary)
                            .strikethrough(isSkipped, color: Theme.textTertiary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
                Text(routeText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSkipped ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if candidate.status != .invalid {
                    details
                }
                ForEach(messages, id: \.text) { message in
                    Label {
                        Text(message.text)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: message.symbol)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(message.color)
                    .labelStyle(RepCompactLabelStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, 10)
        .background(rowTint, in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var routeText: String {
        let from = candidate.fromName.isEmpty ? "?" : TripRow.short(candidate.fromName)
        let to = candidate.toName.isEmpty ? "?" : TripRow.short(candidate.toName)
        return "\(from) → \(to)"
    }

    private var details: some View {
        HStack(spacing: 6) {
            Text(detailText)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if candidate.isRoundTrip {
                RepBadge(text: "H+R", tint: Theme.textSecondary)
            }
            if candidate.isFareEstimated {
                RepBadge(text: "geschätzt", symbol: "wand.and.stars", tint: Theme.accentText)
            }
        }
    }

    private var detailText: String {
        var parts = [candidate.mode.displayName]
        if let via = ViaText.subtitle(candidate.via) { parts.append(via) }   // MARK: via
        if candidate.distanceKm > 0 { parts.append(Format.km(candidate.totalDistanceKm)) }
        if let category = candidate.category { parts.append(category.displayName) }
        return parts.joined(separator: " · ")
    }

    private struct Message { var text: String; var symbol: String; var color: Color }

    private var messages: [Message] {
        var list: [Message] = candidate.errors.map { Message(text: $0, symbol: "xmark.octagon.fill", color: Theme.negative) }
        if let duplicate = candidate.duplicateNote {
            list.append(Message(text: skipsDuplicates ? "\(duplicate) · wird übersprungen" : duplicate,
                                symbol: "doc.on.doc.fill", color: Theme.summitText))
        }
        list += candidate.warnings.map { Message(text: $0, symbol: "exclamationmark.triangle.fill", color: Theme.summitText) }
        return list
    }

    private var badgeStyle: (symbol: String, tint: Color) {
        switch candidate.status {
        case .ready: return candidate.warnings.isEmpty ? ("checkmark", Theme.pine) : ("exclamationmark", Theme.summit)
        case .duplicate: return ("doc.on.doc.fill", Theme.gold)
        case .invalid: return ("xmark", Theme.negative)
        }
    }

    private var statusBadge: some View {
        let style = badgeStyle
        return Image(systemName: style.symbol)
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 17, height: 17)
            .background(style.tint, in: .circle)
            .overlay(Circle().strokeBorder(Theme.sheetBackground, lineWidth: 2))
            .environment(\.colorScheme, .light)
    }

    private var rowTint: Color {
        switch candidate.status {
        case .invalid: Theme.negative.opacity(0.08)
        case .duplicate: Theme.gold.opacity(0.10)
        case .ready: candidate.warnings.isEmpty ? Color.clear : Theme.summit.opacity(0.07)
        }
    }

    private var accessibilityText: String {
        var parts = ["Zeile \(candidate.line)"]
        if let date = candidate.date { parts.append(Format.date(date, .long)) }
        parts.append(ViaText.spoken(from: candidate.fromName, via: candidate.via, to: candidate.toName))   // MARK: via
        if candidate.status != .invalid {
            parts.append(candidate.mode.displayName)
            parts.append(Format.euroPrecise(candidate.totalValue) + (candidate.isFareEstimated ? ", geschätzt" : ""))
            if candidate.isRoundTrip { parts.append("hin und retour") }
        }
        parts += messages.map(\.text)
        return parts.joined(separator: ", ")
    }
}

/// Icon + text with a tight gap, icon aligned to the first line.
struct RepCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}
