import SwiftUI
import KlimaCore

/// Step 5 – renewal reminders (30 / 7 / 1 Tage vorher): a preview banner, the concrete dates and a toggle.
/// Permission is requested when the user continues (see OnboardingFlow).
struct OnbRemindersStep: View {
    @Bindable var model: OnboardingModel
    @Environment(AppState.self) private var app
    @State private var bannerVisible = LaunchMode.isScreenshot

    var body: some View {
        OnbPage(kicker: OnboardingModel.Step.notifications.kicker,
                title: "Erinnerungen",
                subtitle: "Wir sagen dir rechtzeitig Bescheid, bevor dein Ticket abläuft – damit du nahtlos verlängern kannst.") {
            notificationPreview
            scheduleCard
            Label("Nur lokale Mitteilungen auf deinem iPhone – du kannst sie jederzeit in den Einstellungen ändern.",
                  systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.xxs)
        }
        .onAppear {
            guard !bannerVisible else { return }
            bannerVisible = true
        }
        .sensoryFeedback(.selection, trigger: model.remindersEnabled) { _, _ in app.settings.hapticsEnabled }
    }

    private var remindersBinding: Binding<Bool> {
        Binding(
            get: { model.remindersEnabled },
            set: { isOn in withAnimation(.smooth(duration: 0.35)) { model.remindersEnabled = isOn } }
        )
    }

    /// What a reminder will look like on the lock screen.
    private var notificationPreview: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            OnbBrandMark(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("KlimaBilanz")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: Theme.Spacing.xs)
                    Text("09:00")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("Noch 7 Tage gültig")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(model.ticketName) läuft bald ab – denk an die Verlängerung.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frostedCard(cornerRadius: Theme.Radius.formGroup)
        .opacity(model.remindersEnabled ? 1 : 0.5)
        .onbEntrance(bannerVisible, delay: 0.1, offset: -18, scale: 0.96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Beispiel-Mitteilung")
        .accessibilityValue("Noch 7 Tage gültig. \(model.ticketName) läuft bald ab – denk an die Verlängerung.")
    }

    private var scheduleCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Toggle(isOn: remindersBinding) {
                    OnbToggleLabel(symbol: "bell.badge.fill", tint: Theme.dawn,
                                   title: "Verlängerung erinnern", subtitle: "30, 7 und 1 Tag vor Ablauf")
                }
                .tint(Theme.accent)
                OnbDivider(inset: 0)
                timeline
                    .opacity(model.remindersEnabled ? 1 : 0.4)
                    .saturation(model.remindersEnabled ? 1 : 0)
            }
        }
    }

    private var timeline: some View {
        let previews = model.reminderPreviews
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(previews) { item in
                OnbTimelineRow(symbol: "bell.fill",
                               tint: item.offset == 1 ? Theme.alpenglow : Theme.dawn,
                               title: item.offset == 1 ? "1 Tag vorher" : "\(item.offset) Tage vorher",
                               detail: Format.date(item.date, .long),
                               isFirst: item.id == previews.first?.id,
                               isLast: false)
            }
            OnbTimelineRow(symbol: "flag.fill", tint: Theme.summit, title: "Ablauf deines Tickets",
                           detail: Format.date(model.endDate, .long), isFirst: previews.isEmpty, isLast: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One stop on the vertical reminder timeline (icon on a connecting rail, title + date).
private struct OnbTimelineRow: View {
    var symbol: String
    var tint: Color
    var title: String
    var detail: String
    var isFirst: Bool
    var isLast: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Theme.separator)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 28, height: 28)
                    .background(tint, in: .circle)
                Rectangle()
                    .fill(isLast ? Color.clear : Theme.separator)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 32)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, Theme.Spacing.xs)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
