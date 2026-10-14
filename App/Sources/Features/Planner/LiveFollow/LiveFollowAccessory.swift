import SwiftUI
import KlimaCore

/// Shows the accessory only while a follow is active (the tab bar accessory slot is always there).
struct LiveFollowAccessoryHost: View {
    let tracker: LiveFollowTracker

    var body: some View {
        if tracker.target != nil {
            LiveFollowAccessory(tracker: tracker)
        }
    }
}

/// The follow in the tab bar accessory (iOS 26 `tabViewBottomAccessory`): one line of state, tap for every stop.
struct LiveFollowAccessory: View {
    let tracker: LiveFollowTracker
    @State private var showsDetail = false

    var body: some View {
        if let target = tracker.target {
            Button { showsDetail = true } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(target.lineName).font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
                        Text(headline).font(.footnote.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    delayBadge
                }
                .padding(.horizontal, Theme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showsDetail) { LiveFollowDetailSheet(tracker: tracker) }
            // A notification's "Details öffnen" opens the stop list.
            .onChange(of: tracker.detailRequest) { _, _ in showsDetail = true }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Zeigt alle Halte")
        }
    }

    /// The stage line, shared with the Live Activity and the notifications (FollowStageCopy).
    private var headline: String {
        if case .paused(let message) = tracker.status { return message }
        guard let s = tracker.snapshot else { return "Lade Fahrt …" }
        return FollowStageCopy.headline(FollowLiveState.make(from: s, now: Date()))
    }

    @ViewBuilder private var delayBadge: some View {
        if let minutes = tracker.snapshot?.delaySeconds.map({ Int((Double($0) / 60).rounded()) }) {
            Text(minutes > 0 ? "+\(minutes)" : "pünktlich")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(minutes >= 5 ? Theme.summitText : Theme.positiveText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((minutes >= 5 ? Theme.summit : Theme.positive).opacity(0.14), in: .capsule)
        }
    }
}

/// Every stop of the followed run with its realtime state, and the stop-follow controls.
struct LiveFollowDetailSheet: View {
    let tracker: LiveFollowTracker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if let snapshot = tracker.snapshot {
                        GlassCard(padding: Theme.Spacing.m) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                                ForEach(Array(snapshot.stopovers.enumerated()), id: \.offset) { index, stop in
                                    stopRow(stop, index: index, snapshot: snapshot)
                                }
                            }
                        }
                        if let updatedAt = tracker.updatedAt {
                            Text("Stand \(RealtimePresentation.time(updatedAt)) · aktualisiert, solange KlimaBilanz geöffnet ist.")
                                .font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    if case .paused(let message) = tracker.status {
                        Text(message).font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    Button(role: .destructive) {
                        tracker.stop()
                        dismiss()
                    } label: {
                        Label("Nicht mehr verfolgen", systemImage: "xmark.circle").frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(Theme.Spacing.cardGutter)
            }
            .ambientBackground(.standard, glow: 0.3)
            .navigationTitle(tracker.target?.lineName ?? "Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
        }
    }

    private func stopRow(_ stop: Stopover, index: Int, snapshot: LiveFollowSnapshot) -> some View {
        let event = stop.arrival ?? stop.departure
        let passed = snapshot.lastPassedIndex.map { index <= $0 } ?? false
        let isNext = snapshot.lastPassedIndex.map { index == $0 + 1 } ?? (index == 0)
        return HStack(spacing: Theme.Spacing.s) {
            Circle()
                .fill(passed ? Theme.positive : (isNext ? Theme.accent : Theme.textTertiary))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.location.name)
                    .font(.body.weight(isNext ? .semibold : .regular))
                    .foregroundStyle(passed ? Theme.textSecondary : Theme.textPrimary)
                if let platform = (stop.departure ?? stop.arrival)?.platform?.text {
                    Text("Gleis \(platform)").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if let event {
                Text(RealtimePresentation.label(event).text ?? RealtimePresentation.time(event.planned ?? Date()))
                    .font(.footnote.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(RealtimePresentation.label(event).state == .onTime ? Theme.positiveText : Theme.summitText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
