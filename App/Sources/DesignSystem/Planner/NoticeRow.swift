import SwiftUI
import KlimaCore

/// One notice („Andere Zuggarnitur – weniger Sitzplätze 1. Kl.“, „Starker Reisetag“, a disruption) with an icon by
/// severity. `compact` is the one-line card variant; the full variant shows the text and an optional „Details“ action.
struct NoticeRow: View {
    var notice: Notice
    var compact = true
    var onDetails: (() -> Void)? = nil

    var body: some View {
        if compact {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: Self.symbol(notice.severity))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Self.tint(notice.severity))
                Text(notice.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Self.tint(notice.severity))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: Self.symbol(notice.severity))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Self.tint(notice.severity))
                    Text(notice.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let text = notice.text {
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let onDetails {
                    Button(action: onDetails) {
                        Text("Details").font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 5)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Self.tint(notice.severity).opacity(0.10), in: .rect(cornerRadius: Theme.Radius.formGroup, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }

    static func symbol(_ severity: NoticeSeverity) -> String {
        switch severity {
        case .info: "info.circle.fill"
        case .crowd: "person.2.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }

    static func tint(_ severity: NoticeSeverity) -> Color {
        switch severity {
        case .info: Theme.accentText
        case .crowd, .warning: Theme.summitText
        case .critical: Theme.negativeText
        }
    }
}
