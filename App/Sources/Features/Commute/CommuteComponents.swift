import SwiftUI
import KlimaCore

// MARK: commute – the pieces of the Pendel-Modus card (docs/COMMUTE.md §4): route title, countdown, connection row with its
// delay badge and platform, the disruption banner, the age of the data, the quick actions, skeleton and notices. Colours only
// through Theme tokens; a delay is never colour alone (the badge always carries „+5“, „pünktlich“ or „Ausfall“).

/// „St. Anton → Innsbruck“ – wraps instead of truncating at large text sizes.
struct CommuteRouteTitle: View {
    var from: String
    var to: String
    var font: Font = .system(.title3, design: .rounded, weight: .bold)

    var body: some View {
        Text("\(TripRow.short(from)) \(Image(systemName: "arrow.right")) \(TripRow.short(to))")
            .font(font)
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("\(TripRow.short(from)) nach \(TripRow.short(to))")
    }
}

/// The minutes to the next departure as a big rolling number: „12 Min.“, „1:05 Std.“, „jetzt“. Next to the route at regular
/// sizes (number over unit), on one baseline under it at accessibility sizes. The plan's time says so to VoiceOver; on screen
/// the card's plan line says it.
struct CommuteCountdown: View {
    var target: Date
    var now: Date
    /// The plan's time (no live data).
    var isPlan: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let seconds = target.timeIntervalSince(now)
        let minutes = max(0, Int((seconds / 60).rounded(.down)))
        let layout = typeSize.isAccessibilitySize ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
                                                  : AnyLayout(VStackLayout(alignment: .trailing, spacing: 0))
        layout {
            Text(value(minutes))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(minutes <= 2 ? Theme.summitText : Theme.textPrimary)
                .contentTransition(.numericText(countsDown: true))
                .motionAnimation(Motion.number, value: minutes)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption(minutes))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(minutes))
    }

    private func value(_ minutes: Int) -> String {
        if minutes == 0 { return "jetzt" }
        if minutes < 60 { return "\(minutes)" }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    private func caption(_ minutes: Int) -> String {
        if minutes == 0 { return isPlan ? "laut Plan" : "Abfahrt" }
        return minutes < 60 ? "Min." : "Std."
    }

    private func spoken(_ minutes: Int) -> String {
        let base: String
        if minutes == 0 {
            base = "Abfahrt jetzt"
        } else if minutes < 60 {
            base = "Abfahrt in \(CommuteSpeech.minutes(minutes))"
        } else {
            let h = minutes / 60, m = minutes % 60
            base = "Abfahrt in \(h == 1 ? "1 Stunde" : "\(h) Stunden")" + (m > 0 ? " und \(CommuteSpeech.minutes(m))" : "")
        }
        return isPlan ? base + ", laut Plan" : base
    }
}

// MARK: - Badge

/// „pünktlich“ (pine), „+2“ (neutral), „+5“ (amber from 3), „+12“ (red from 10), „Ausfall“ (red), „Fahrplan“ (no realtime).
struct CommuteDelayBadge: View {
    var row: CommuteRow
    var large = false

    var body: some View {
        Text(row.badgeText ?? "Fahrplan")
            .font(.system(large ? .subheadline : .caption, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Self.text(row.severity))
            .padding(.horizontal, large ? 9 : 7)
            .padding(.vertical, large ? 3 : 2)
            .background(Self.fill(row.severity), in: .capsule)
            .overlay { Capsule().strokeBorder(Self.stroke(row.severity), lineWidth: 1) }
            .fixedSize()
            .accessibilityHidden(true)
    }

    static func text(_ severity: CommuteSeverity) -> Color {
        switch severity {
        case .scheduled, .slight: Theme.textSecondary
        case .onTime: Theme.positiveText
        case .late: Theme.summitText
        case .veryLate, .cancelled: Theme.negativeText
        }
    }

    static func tint(_ severity: CommuteSeverity) -> Color {
        switch severity {
        case .scheduled, .slight: Theme.textTertiary
        case .onTime: Theme.positive
        case .late: Theme.dawn
        case .veryLate, .cancelled: Theme.negative
        }
    }

    static func fill(_ severity: CommuteSeverity) -> Color {
        severity == .scheduled || severity == .slight ? Theme.surfaceSecondary : tint(severity).opacity(0.16)
    }

    static func stroke(_ severity: CommuteSeverity) -> Color {
        severity == .scheduled || severity == .slight ? .clear : tint(severity).opacity(0.5)
    }
}

// MARK: - Connection row

/// One connection: planned time (struck through when cancelled) with its badge, the line and where it goes, the arrival,
/// and the platform (a changed one is tinted and marked). VoiceOver reads it as one sentence.
struct CommuteConnectionRow: View {
    var row: CommuteRow
    var destination: String
    var now: Date
    var isAlternative = false
    var isFirst = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(alignment: .center, spacing: Theme.Spacing.s) {
                        timeColumn
                        Spacer(minLength: 0)
                        if let platform = row.platform, !row.isCancelled { platformBox(platform) }
                    }
                    lineColumn
                }
            } else {
                HStack(alignment: .center, spacing: Theme.Spacing.s) {
                    timeColumn.frame(minWidth: 66, alignment: .leading)
                    lineColumn.frame(maxWidth: .infinity, alignment: .leading)
                    if let platform = row.platform, !row.isCancelled { platformBox(platform) }
                }
            }
        }
        .padding(.vertical, isFirst ? 10 : 8)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.timeText)
                .font(.system(isFirst ? .title2 : .headline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(row.isCancelled ? Theme.textSecondary : Theme.textPrimary)
                .strikethrough(row.isCancelled, color: Theme.negativeText)
                .lineLimit(1)
            CommuteDelayBadge(row: row)
        }
    }

    private var lineColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let line = row.line {
                    PlannerLinePlate(line: line, size: .s)
                        .opacity(row.isCancelled ? 0.55 : 1)
                }
                Text(row.direction ?? destination)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(row.isCancelled ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(0.85)
            }
            // At accessibility sizes the arrival line wraps freely and „Alternative“ gets a line of its own.
            let sublineLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                             : AnyLayout(HStackLayout(spacing: 6))
            sublineLayout {
                Text(subline)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
                if isAlternative {
                    Text("Alternative")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.positiveText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.positive.opacity(0.15), in: .capsule)
                        .fixedSize()
                        .motionTransition(.rise)
                }
            }
        }
    }

    private func platformBox(_ platform: PlatformLabel) -> some View {
        PlatformBox(platform: platform, compact: true)
            .overlay(alignment: .topTrailing) {
                if platform.changed {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(Theme.dawn, in: .circle)
                        .offset(x: 5, y: -5)
                        .accessibilityHidden(true)
                }
            }
    }

    /// „an 08:29 · direkt“ · „an 08:31 (+2) · 1 Umstieg“ · „fällt aus“.
    private var subline: String {
        if row.isCancelled { return "fällt aus" }
        var parts: [String] = []
        if let arrival = row.plannedArrival {
            var text = "an \(RealtimePresentation.time(arrival))"
            if let real = row.realtimeArrival {
                let delay = Int((real.timeIntervalSince(arrival) / 60).rounded(.toNearestOrEven))
                if delay > 0 { text += " (+\(delay))" }
            }
            parts.append(text)
        }
        parts.append(row.changes == 0 ? "direkt" : (row.changes == 1 ? "1 Umstieg" : "\(row.changes) Umstiege"))
        return parts.joined(separator: " · ")
    }

    private var spoken: String {
        var text = CommuteStatus.spoken(row, destination: destination)
        if isAlternative { text += ", Alternative" }
        return text
    }
}

// MARK: - Disruption

/// „Dein Zug fällt aus – nächste Verbindung 07:58, Gleis 3“ in a red band with the symbol; the second half on its own line.
struct CommuteDisruptionBanner: View {
    var advice: CommuteAdvice

    var body: some View {
        let parts = advice.headline.components(separatedBy: " – ")
        let title = parts.first ?? advice.headline
        let detail = parts.dropFirst().joined(separator: " – ")
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: advice.reason == .cancelled ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.negative)
                .symbolEffect(.bounce, value: advice.affected.id)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.negativeText)
                if !detail.isEmpty {
                    Text(detail.prefix(1).uppercased() + detail.dropFirst())
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.s)
        .background(Theme.negative.opacity(0.12), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.negative.opacity(0.4), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(advice.headline)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Data age

/// „● Stand 07:31 · Echtzeit · aktualisiert beim Öffnen“. Demo runs say „Demo-Daten“ instead of „Echtzeit“.
struct CommuteDataAgeLine: View {
    var fetchedAt: Date?
    var hasRealtime: Bool
    var isOffline: Bool
    var isDemo: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if fetchedAt != nil, hasRealtime, !isOffline {
                LiveDot(state: .onTime, size: 6)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var text: String {
        var line = CommuteStatus.dataAge(fetchedAt: fetchedAt, hasRealtime: hasRealtime, isOffline: isOffline)
        if isDemo { line = line.replacingOccurrences(of: "· Echtzeit", with: "· Demo-Daten") }
        return line + " · aktualisiert beim Öffnen"
    }
}

// MARK: - Actions

struct CommuteActionItem: Identifiable {
    var title: String
    var symbol: String
    var isPrimary = false
    var isEnabled = true
    var action: () -> Void

    var id: String { title }
}

/// The quick actions: side by side as icon-over-label tiles of one height, one under the other at accessibility sizes (there the
/// labels stop growing at AX2, so „Verbindung“ is never split inside the word).
struct CommuteActionGrid: View {
    var items: [CommuteActionItem]

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var tapTick = 0

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(items) { item in button(item, stacked: true) }
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            } else {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(items) { item in button(item, stacked: false) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .haptic(.tap, trigger: tapTick)
    }

    private func button(_ item: CommuteActionItem, stacked: Bool) -> some View {
        Button {
            tapTick += 1
            item.action()
        } label: {
            Group {
                if stacked {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: item.symbol).font(.body.weight(.semibold)).frame(minWidth: 24)
                        Text(item.title).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, Theme.Spacing.s)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                } else {
                    VStack(spacing: 5) {
                        Image(systemName: item.symbol).font(.system(size: 18, weight: .semibold))
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity)
                }
            }
            .foregroundStyle(item.isPrimary ? Theme.onAccent : Theme.textPrimary)
            .background(item.isPrimary ? AnyShapeStyle(Theme.prominentTint) : AnyShapeStyle(Theme.surfaceSecondary),
                        in: .rect(cornerRadius: 16, style: .continuous))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.pressable)
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.45)
        .accessibilityLabel(item.title)
    }
}

// MARK: - Loading and notices

/// Three quiet placeholder rows while the first answer loads (they breathe, unless Reduce Motion is on).
struct CommuteRowsSkeleton: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: Theme.Spacing.s) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).frame(width: 56, height: index == 0 ? 26 : 18)
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).frame(width: 150, height: 13)
                        RoundedRectangle(cornerRadius: 5, style: .continuous).frame(width: 96, height: 10)
                    }
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 10, style: .continuous).frame(width: 40, height: 40)
                }
                .foregroundStyle(Theme.surfaceSecondary)
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .breathing()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verbindungen werden geladen")
    }
}

/// A one-line notice in the card („Keine Verbindung …“, „Offline …“).
struct CommuteNotice: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}
