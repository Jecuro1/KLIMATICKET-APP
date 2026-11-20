import SwiftUI
import KlimaCore

// MARK: data – the building blocks of Einstellungen › Daten & Sicherung (docs/DATA_HUB.md §6): the hero with the week of backups,
// the honest banner, a backup row, the change bars of the restore preview. Theme tokens and Motion only.

/// „Heute, 18:03“, „Gestern, 18:03“, „Mi., 18. Nov., 18:03“.
enum DataHubText {
    static func when(_ date: Date) -> String {
        "\(Format.relativeDay(date)), \(Format.time(date))"
    }

    /// The same inside a sentence: „von gestern, 18:03“.
    static func whenInline(_ date: Date) -> String {
        let day = Format.relativeDay(date)
        return "\(day == "Heute" || day == "Gestern" ? day.lowercased() : day), \(Format.time(date))"
    }

    /// A line of numbers and words that keeps every number with its word („12 Vorteile“ never breaks after the 12).
    static func keep(_ text: String) -> String { DataHubCounts.keepingUnits(text) }

    /// „Letzte Sicherung heute, 18:03“ / „Noch keine Sicherung“.
    static func lastBackup(_ file: DataHubBackupFile?) -> String {
        guard let file else { return "Noch keine Sicherung auf diesem iPhone" }
        let day = Format.relativeDay(file.date)
        let lower = day == "Heute" || day == "Gestern" ? day.lowercased() : "am \(day)"
        return "Letzte Sicherung \(lower), \(Format.time(file.date))"
    }

    static let banner = "Diese Sicherungen liegen auf diesem iPhone. Löschst du die App, sind sie weg. Kopiere sie in Dateien oder iCloud Drive."
    static let whereLine = "Dateien › Auf meinem iPhone › KlimaBilanz › Sicherungen"
    static let privacy = "Nichts verlässt dein iPhone, außer du teilst eine Datei. Sicherungen enthalten deine Tickets, Fahrten, Favoriten, Vorteile und Einstellungen – Anmeldung, Schlüssel und die Live-Daten-Zustimmung sind nie dabei."   // MARK: review-daten – all of what is in them
    /// MARK: review-daten – with a cloud account the rows are synced; „Nichts verlässt dein iPhone“ would be false then.
    static let privacySynced = "Deine Tickets, Fahrten, Favoriten und Vorteile werden mit deinem KlimaBilanz-Konto synchronisiert. Sicherungen und Exporte verlassen dein iPhone nur, wenn du eine Datei teilst – Anmeldung, Schlüssel und die Live-Daten-Zustimmung sind nie dabei."
    static let retention = "Behalten werden die Sicherungen der letzten 7 Tage, je eine der letzten 4 Wochen und 3 Monate. Sicherungen vor dem Löschen oder Wiederherstellen bleiben 30 Tage, die neueste immer."
}

// MARK: - Hero

/// The data on this iPhone and the last seven days of backups: a filled day had a backup.
struct DataHubHero: View {
    var counts: DataHubCounts
    var files: [DataHubBackupFile]
    var isAutoOn: Bool
    /// Signed in with a cloud account: the rows are synced, they do not only stay here (`// MARK: review-daten`).
    var syncsToAccount = false
    var now: Date = Date()

    @Environment(\.dynamicTypeSize) private var typeSize

    private var days: [(day: Date, has: Bool)] {
        let calendar = Calendar.vienna
        let today = calendar.startOfDay(for: now)
        let backed = Set(files.filter { !$0.isForeign }.map { calendar.startOfDay(for: $0.date) })
        return (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { ($0, backed.contains($0)) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            let header = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.s))
            header {
                Image(systemName: "externaldrive.fill.badge.checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Theme.ctaGradient, in: .rect(cornerRadius: 16, style: .continuous))
                    .symbolBounce(on: files.first?.name)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deine Daten")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(syncsToAccount ? "Auf diesem iPhone und in deinem KlimaBilanz-Konto" : "Bleiben auf diesem iPhone, bis du sie teilst")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                CountUpText(value: Double(counts.trips)) { DataHubFormat.integer(Int($0.rounded())) }
                    .font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Text(counts.trips == 1 ? "Fahrt" : "Fahrten")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(counts.line)
            Text(DataHubText.keep([DataHubFormat.count(counts.tickets, "Ticket", "Tickets"), DataHubFormat.count(counts.favorites, "Favorit", "Favoriten")]
                .joined(separator: " · ") + (counts.benefits > 0 ? " · " + DataHubFormat.count(counts.benefits, "Vorteil", "Vorteile") : "")))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .accessibilityHidden(true)
            weekStrip
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var weekStrip: some View {
        let entries = days
        let backedCount = entries.filter(\.has).count
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: 6) {
                ForEach(entries, id: \.day) { entry in
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(entry.has ? AnyShapeStyle(Theme.pine) : AnyShapeStyle(Theme.separator))
                            .frame(height: 10)
                            .overlay {
                                if !entry.has {
                                    Capsule().strokeBorder(Theme.textTertiary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                }
                            }
                        Text(DataHubWeekday.short(entry.day))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Calendar.vienna.isDateInToday(entry.day) ? Theme.textPrimary : Theme.textSecondary)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            // At accessibility sizes the line stands alone: beside the symbol its second line started under the symbol.
            let line = isAutoOn ? DataHubText.lastBackup(files.first(where: { !$0.isForeign })) : "Tägliche Sicherung ist aus"
            Group {
                if typeSize.isAccessibilitySize { Text(line) }
                else { Label(line, systemImage: isAutoOn ? "clock.arrow.circlepath" : "pause.circle") }
            }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isAutoOn && backedCount > 0 ? Theme.positiveText : Theme.summitText)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sicherungen an \(backedCount) der letzten 7 Tage. "
                            + (isAutoOn ? DataHubText.lastBackup(files.first(where: { !$0.isForeign })) : "Tägliche Sicherung ist aus."))
        .motionAnimation(Motion.smooth, value: backedCount)
    }
}

/// „Mo“ … „So“ for a day in Vienna.
enum DataHubWeekday {
    static func short(_ date: Date) -> String {
        let names = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        let weekday = Calendar.vienna.component(.weekday, from: date)
        return names[max(0, min(6, weekday - 1))]
    }
}

// MARK: - Banner

/// The honest banner: where the backups are and what deleting the app does to them. Never truncated – it wraps at every size.
struct DataHubBanner: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the symbol sits above the text, which then has the row's full width.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.s))
        layout {
            Image(systemName: "iphone.gen3")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.summitText)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(DataHubText.banner)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(DataHubText.whereLine)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.xxs)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Backup row

/// One backup: date, kind, size and what is in it, with Prüfen, Teilen and Wiederherstellen. For VoiceOver one element whose
/// actions are the three buttons.
struct DataHubBackupRow: View {
    var file: DataHubBackupFile
    var details: DataHubBackupDetails?
    var isChecked: Bool
    var onCheck: () -> Void
    var onRestore: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var title: String { DataHubText.when(file.date) }

    private var detailLine: String {
        var parts = [DataHubFormat.bytes(file.size)]
        if let details {
            if details.canRestore { parts.append(details.counts.line) } else { parts.append(details.problem?.message ?? "") }
        }
        return DataHubText.keep(parts.joined(separator: " · "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            let titleLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xxs))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs))
            titleLayout {
                Text(file.isForeign ? file.name : title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                if !typeSize.isAccessibilitySize { Spacer(minLength: Theme.Spacing.xs) }
                if file.kind.isSafety || file.isForeign {
                    SetPill(text: file.isForeign ? "Eigene Datei" : file.kind.title, symbol: file.isForeign ? "doc" : "shield.lefthalf.filled",
                            tint: Theme.summitText)
                }
            }
            Text(detailLine)
                .font(.footnote)
                .foregroundStyle(details?.canRestore == false ? Theme.negativeText : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            if isChecked, let details {
                // Like the hero's line: at accessibility sizes the verdict stands alone (the words say it, the colour too).
                Group {
                    if typeSize.isAccessibilitySize { Text(details.verdict.title) }
                    else { Label(details.verdict.title, systemImage: details.verdict.isDamaged ? "xmark.seal.fill"
                                 : (details.verdict == .missing ? "seal" : "checkmark.seal.fill")) }   // MARK: review-daten
                }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(details.verdict.isDamaged ? Theme.negativeText
                                     : (details.verdict == .missing ? Theme.summitText : Theme.positiveText))   // MARK: review-daten
                    .motionTransition(.pop)
            }
            actions
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .motionAnimation(Motion.snappy, value: isChecked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(file.isForeign ? file.name : title)\(file.kind.isSafety ? ", " + file.kind.title : ""). \(detailLine)"
                            + (isChecked ? ". \(details?.verdict.title ?? "")" : ""))
        .accessibilityActions {
            Button("Prüfen", action: onCheck)
            ShareLink("Teilen", item: file.url)
            if details?.canRestore != false { Button("Wiederherstellen", action: onRestore) }
        }
    }

    /// One line with symbols when it fits, then one line of words, then the three under each other – a button never hyphenates.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xs) { buttons(symbols: true) }
            HStack(spacing: Theme.Spacing.xs) { buttons(symbols: false) }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) { buttons(symbols: true, wraps: true) }
        }
        .font(.footnote.weight(.semibold))
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)   // at AX5 a fixed „Wiederherstellen“ was wider than the row
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(Theme.accent)
    }

    @ViewBuilder
    private func buttons(symbols: Bool, wraps: Bool = false) -> some View {
        Button(action: onCheck) { actionLabel("Prüfen", "checkmark.seal", symbols, wraps) }
        ShareLink(item: file.url, preview: SharePreview(file.name)) { actionLabel("Teilen", "square.and.arrow.up", symbols, wraps) }
        Button(action: onRestore) { actionLabel("Wiederherstellen", "arrow.counterclockwise", symbols, wraps) }
            .disabled(details?.canRestore == false)
    }

    /// In a line the label keeps its ideal width (so ViewThatFits can measure it); stacked it may wrap rather than leave the row.
    @ViewBuilder
    private func actionLabel(_ title: String, _ symbol: String, _ withSymbol: Bool, _ wraps: Bool) -> some View {
        let label = HStack(spacing: 4) {
            if withSymbol { Image(systemName: symbol).imageScale(.small) }
            Text(title).lineLimit(wraps ? nil : 1)
        }
        if wraps { label.fixedSize(horizontal: false, vertical: true) } else { label.fixedSize() }
    }
}

// MARK: - Change bars

/// One table of the restore preview: a bar split into new, changed, removed and unchanged rows, and the line in words.
struct DataHubDiffBar: View {
    var diff: BackupTableDiff
    @State private var shown = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var segments: [(Int, Color)] {
        [(diff.added, Theme.pine), (diff.changed, Theme.glacier), (diff.removed, Theme.negative),
         (diff.unchanged + diff.newerHere, Theme.textTertiary.opacity(0.35))]
    }

    var body: some View {
        let total = max(1, segments.reduce(0) { $0 + $1.0 })
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(diff.table.plural)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.Spacing.xs)
                // MARK: review-daten – the short form only where it fits beside the name (at AX5 „+12 · ~3“ broke in two lines);
                // the line under the bar says the same in words
                if diff.changes > 0 && !typeSize.isAccessibilitySize {
                    Text("+\(diff.added) · ~\(diff.changed)\(diff.removed > 0 ? " · −\(diff.removed)" : "")")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        if segment.0 > 0 {
                            Capsule()
                                .fill(segment.1)
                                .frame(width: max(4, (proxy.size.width - 6) * CGFloat(segment.0) / CGFloat(total) * (shown ? 1 : 0.02)))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            Text(DataHubText.keep(diff.line))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .onAppear { withMotion(Motion.gentle) { shown = true } }
    }
}

/// The legend under the bars.
struct DataHubDiffLegend: View {
    var body: some View {
        // MARK: review-daten – one line when it fits, else two (at accessibility sizes four in a line ran off the card)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                item("neu", Theme.pine)
                item("geändert", Theme.glacier)
                item("entfernt", Theme.negative)
                item("bleibt", Theme.textTertiary.opacity(0.35))
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.s) {
                    item("neu", Theme.pine)
                    item("geändert", Theme.glacier)
                }
                HStack(spacing: Theme.Spacing.s) {
                    item("entfernt", Theme.negative)
                    item("bleibt", Theme.textTertiary.opacity(0.35))
                }
            }
        }
        .font(.caption)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityHidden(true)
    }

    private func item(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
        }
    }
}
