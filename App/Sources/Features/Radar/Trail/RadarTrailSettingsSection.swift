import SwiftUI
import KlimaCore

// MARK: radar2-radartrail – „Spuren“ at the end of the Darstellung page (docs/RADAR_TRAILS.md §4): Aus / Ausgewählte und meine / Alle im Ausschnitt and
// the length. Applies at once; „Aus“ forgets every recorded position and stops recording. Kept per device under `radar.trail.v1`.

struct RadarTrailSettingsSection: View {
    let trail: RadarTrailModel

    private var mode: Binding<RadarTrailSetting.Mode> {
        Binding(get: { trail.setting.mode }, set: { mode in
            withMotion(Motion.smooth) { trail.update(RadarTrailSetting(mode: mode, minutes: trail.setting.minutes)) }
        })
    }

    private var minutes: Binding<Int> {
        Binding(get: { trail.setting.minutes }, set: { minutes in
            trail.update(RadarTrailSetting(mode: trail.setting.mode, minutes: minutes))
        })
    }

    var body: some View {
        if RadarTrailModel.isAvailable { section }
    }

    private var section: some View {
        Section {
            Picker(RadarTrailText.modeTitle, selection: mode) {
                ForEach(RadarTrailSetting.Mode.allCases) { mode in
                    Label(mode.title, systemImage: Self.symbol(mode)).tag(mode)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if trail.setting.mode != .off {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(RadarTrailText.lengthTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                    Picker(RadarTrailText.lengthTitle, selection: minutes) {
                        ForEach(RadarTrailSetting.lengths, id: \.self) { length in
                            Text(RadarTrailText.length(length))
                                .accessibilityLabel(RadarTrailText.spokenLength(length))
                                .tag(length)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 2)
                .motionTransition(.rise)
            }
        } header: {
            Text(RadarTrailText.sectionTitle)
        } footer: {
            Text(RadarTrailText.footer)
        }
        .haptic(.selection, trigger: trail.setting)
    }

    static func symbol(_ mode: RadarTrailSetting.Mode) -> String {
        switch mode {
        case .off: "eye.slash"
        case .mine: "hand.tap"
        case .all: "viewfinder"
        }
    }
}
