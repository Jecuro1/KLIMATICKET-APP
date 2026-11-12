import SwiftUI
import KlimaCore

// Aussteige-Wecker: the block at the top of the "Live verfolgen" detail (docs/EXIT_ALARM.md §2, entry 1). The armed alarms of the
// followed run as cards, and one thin button that opens the shared sheet.

struct ExitAlarmFollowSection: View {
    let target: LiveFollowTarget
    let snapshot: LiveFollowSnapshot?
    /// Opens the shared sheet; with a stop id the sheet starts on that alarm ("Ändern"), with nil on a new one.
    let onOpen: (String?) -> Void
    private let service = ExitAlarmService.shared

    var body: some View {
        let alarms = service.book.active.filter { $0.spec.tripID == target.tripID }
        VStack(spacing: Theme.Spacing.s) {
            ForEach(alarms) { state in
                TimelineView(.periodic(from: .now, by: 10)) { context in
                    ExitAlarmCard(state: state, now: context.date, kind: service.alarmKind,
                                  locationAuthorization: service.locationAuthorization, showsActions: true,
                                  onEdit: { onOpen(state.spec.stopID) }, onCancel: { service.cancel(state.id) })
                }
                .motionTransition(.rise)
            }
            if alarms.count < ExitAlarmBook.capacity {
                Button { onOpen(nil) } label: {
                    GlassCard(padding: Theme.Spacing.m) {
                        HStack(spacing: Theme.Spacing.s) {
                            SetIconTile(symbol: "bell.badge.fill", tint: Theme.dawn, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alarms.isEmpty ? "Aussteige-Wecker" : "Weiteren Wecker stellen")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Weckt dich kurz vor deiner Haltestelle, auch im Schlaf.")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .buttonStyle(.pressableCard)
                .accessibilityHint("Öffnet die Auswahl von Halt und Zeitpunkt")
            }
        }
        .motionAnimation(Motion.smooth, value: alarms.map(\.id))
    }
}
