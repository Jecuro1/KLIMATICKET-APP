import SwiftUI
import KlimaCore

// MARK: radar2-mine – „Linie merken“ in the trip sheet (docs/RADAR_MINE.md §2, through `Radar2TripRows`): remembers the vehicle's line (its mode, title
// and coarsely the area, never the trip), or forgets it again. Nothing for a vehicle outside the radar's five modes (rail replacement, ships …).

struct RadarMineTripRow: View {
    let vehicle: RadarVehicle
    let mine: RadarMineModel

    @State private var note: String?

    var body: some View {
        if RadarMineEntry.isShown, let key = RadarLineKey(vehicle: vehicle) {
            let remembered = mine.remembers(vehicle)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Button {
                    let result = withMotion(Motion.bouncy) { mine.toggleRemember(vehicle) }
                    note = result == .full ? RadarMineText.full : nil
                    switch result {
                    case .added: AccessibilityNotification.Announcement(RadarMineText.rememberedToast(key.title)).post()
                    case .removed: AccessibilityNotification.Announcement(RadarMineText.forgottenToast(key.title)).post()
                    case .full: AccessibilityNotification.Announcement(RadarMineText.full).post()
                    case .notALine: break
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: remembered ? "star.fill" : "star")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(remembered ? Theme.gold : Theme.accentText)
                            .symbolReplaceTransition()
                            .symbolBounce(on: remembered)
                        Text(remembered ? RadarMineText.remembered : RadarMineText.remember)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: Theme.Spacing.xs)
                        Text(key.title)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .frame(minHeight: 50)
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable)
                .glassEffect(remembered ? .regular.tint(Theme.gold.opacity(0.22)).interactive() : .regular.interactive(),
                             in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .haptic(.selection, trigger: remembered)
                .accessibilityLabel(remembered ? RadarMineText.rememberedSpoken(key.title) : RadarMineText.rememberSpoken(key.title))
                .accessibilityAddTraits(remembered ? .isSelected : [])
                if let note {
                    Text(note)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.summitText)
                        .fixedSize(horizontal: false, vertical: true)
                        .motionTransition(.drop)
                }
                if key.mode == .rail {
                    Text(RadarMineText.trainFootnote)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .motionAnimation(Motion.smooth, value: note)
        }
    }
}
