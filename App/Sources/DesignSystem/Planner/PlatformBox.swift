import SwiftUI
import KlimaCore

/// „GL. 3“ / „STEIG F“ in a small rounded box (departure board, timeline). A changed platform is tinted dawn and says so.
struct PlatformBox: View {
    var platform: PlatformLabel
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            Text(platform.label.uppercased(with: Format.locale))
                .font(.system(size: compact ? 9 : 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(platform.changed ? Theme.summitText : Theme.textSecondary)
            Text(platform.display)
                .font(.system(size: compact ? 17 : 22, weight: .bold, design: .rounded))
                .foregroundStyle(platform.changed ? Theme.summitText : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(minWidth: compact ? 40 : 52, minHeight: compact ? 40 : 52)
        .padding(.horizontal, 4)
        .background(platform.changed ? Theme.dawn.opacity(0.16) : Theme.surfaceSecondary,
                    in: .rect(cornerRadius: compact ? 10 : 13, style: .continuous))
        .overlay {
            if platform.changed {
                RoundedRectangle(cornerRadius: compact ? 10 : 13, style: .continuous).strokeBorder(Theme.dawn.opacity(0.7), lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(platform.changed ? "\(platform.spoken), geändert" : platform.spoken)
    }
}
