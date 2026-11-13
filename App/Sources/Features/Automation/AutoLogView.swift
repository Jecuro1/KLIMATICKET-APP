import SwiftUI
import KlimaCore

// MARK: automation – „Zuletzt ausgelöst“ (docs/AUTOMATION.md §5): the last 30 things the rules did, by day – shown in the app,
// sent as a notice, delivered by iOS as planned, or taken back because the day got a trip. On this device only.

struct AutoLogView: View {
    @State private var confirmsClear = false
    @State private var clearTick = 0

    private var store: AutoStore { .shared }

    var body: some View {
        List {
            if store.log.entries.isEmpty {
                Section {
                    EmptyStateView(symbol: "clock.arrow.circlepath", title: "Noch nichts ausgelöst",
                                   message: "Sobald eine Regel sich meldet oder eine geplante Mitteilung abgesagt wird, steht es hier – mit dem Grund.")
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.entries) { entry in
                        AutoLogRow(entry: entry)
                            .listRowBackground(Theme.surface)
                    }
                } header: {
                    SetSectionHeader(title: dayTitle(group.day))
                }
            }
            if !store.log.entries.isEmpty {
                Section {} footer: {
                    SetFooter(text: "Nur auf diesem iPhone, höchstens \(AutoLog.limit) Einträge. Was iOS bei geschlossener App zustellt, erscheint hier beim nächsten Öffnen.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.m)
        .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop(skyOpacity: 0.4) }
        .navigationTitle("Zuletzt ausgelöst")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.log.entries.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Leeren") { confirmsClear = true }
                }
            }
        }
        .revealScope()
        .haptic(.warning, trigger: clearTick)
        .confirmationDialog("Protokoll leeren?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Leeren", role: .destructive) {
                clearTick += 1
                withMotion(Motion.smooth) { store.clearLog() }
            }
        } message: {
            Text("Die Regeln bleiben, nur ihr Protokoll auf diesem iPhone geht.")
        }
    }

    private struct DayGroup {
        let day: Date
        let entries: [AutoLogEntry]
    }

    private var days: [DayGroup] {
        let calendar = Calendar.vienna
        let grouped = Dictionary(grouping: store.log.entries) { calendar.startOfDay(for: $0.at) }
        return grouped.keys.sorted(by: >).map { DayGroup(day: $0, entries: grouped[$0] ?? []) }
    }

    private func dayTitle(_ day: Date) -> String {
        let now = store.now()
        switch AutoTextDay.distance(from: now, to: day) {
        case 0: return "Heute"
        case -1: return "Gestern"
        default:
            let weekday = AutoClock.weekday(day, calendar: .vienna).shortName
            return "\(weekday), \(AutoText.dateText(day, calendar: .vienna))"
        }
    }
}

/// Calendar days between two moments in Vienna (the log's day headers).
enum AutoTextDay {
    static func distance(from now: Date, to date: Date) -> Int {
        let calendar = Calendar.vienna
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }
}

/// One thing a rule did: how it reached you, what it said, which rule and why.
struct AutoLogRow: View {
    let entry: AutoLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: channelSymbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(channelTint)
                .frame(width: 34, height: 34)
                .background(channelTint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title)
                        .font(.headline)
                        .foregroundStyle(entry.channel == .cancelled ? Theme.textSecondary : Theme.textPrimary)
                        .strikethrough(entry.channel == .cancelled, color: Theme.textTertiary)
                    Spacer(minLength: Theme.Spacing.xs)
                    Text(AutoClock.clockText(AutoClock.minuteOfDay(entry.at, calendar: .vienna)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(entry.ruleName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                Text(entry.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                SetPill(text: channelTitle, symbol: nil, tint: channelTextTint)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var channelTitle: String {
        switch entry.channel {
        case .inApp: "in der App gezeigt"
        case .notification: "als Mitteilung gesendet"
        case .delivered: "geplant, von iOS zugestellt"
        case .cancelled: "abgesagt"
        }
    }

    private var channelSymbol: String {
        switch entry.channel {
        case .inApp: "iphone.gen3.radiowaves.left.and.right"
        case .notification: "bell.badge.fill"
        case .delivered: "calendar.badge.checkmark"
        case .cancelled: "xmark.circle"
        }
    }

    private var channelTint: Color {
        switch entry.channel {
        case .inApp: Theme.glacier
        case .notification: Theme.dusk
        case .delivered: Theme.pine
        case .cancelled: Theme.textSecondary
        }
    }

    /// Text-safe variant of the tint for the small pill.
    private var channelTextTint: Color {
        switch entry.channel {
        case .inApp: Theme.accentText
        case .notification: Theme.textSecondary
        case .delivered: Theme.positiveText
        case .cancelled: Theme.textSecondary
        }
    }
}
