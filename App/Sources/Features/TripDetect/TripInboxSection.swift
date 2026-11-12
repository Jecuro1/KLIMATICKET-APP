import SwiftUI
import SwiftData
import KlimaCore

// MARK: tripdetect – "Fahrten-Vorschläge" on the Übersicht: the inbox of everything the trip detection proposes. The caller hides
// the section when it is empty and nothing is recording. Cards rise in and out; accepting plays the toast's success haptic.

struct TripInboxSection: View {
    var candidates: [TripCandidateEntity]
    /// Recording runs: the first row says so and opens the recording screen.
    var isRecording = false

    @State private var showsAll = false
    private let visibleCount = 2

    private var shown: [TripCandidateEntity] { showsAll ? candidates : Array(candidates.prefix(visibleCount)) }

    var body: some View {
        VStack(alignment: .leading, spacing: DashStyle.cardSpacing) {
            SectionHeader(title: "Fahrten-Vorschläge",
                          actionTitle: candidates.count > visibleCount ? (showsAll ? "Weniger" : "Alle \(candidates.count)") : nil,
                          action: { withMotion(Motion.smooth) { showsAll.toggle() } })
                .padding(.horizontal, DashStyle.headerInset)
            if isRecording { TripRecordingRow().motionTransition(.rise) }
            ForEach(shown) { candidate in
                TripCandidateCard(candidate: candidate)
                    .motionTransition(.rise)
            }
            Text("Nichts davon wird ohne dein Okay erfasst. Verworfene Strecken schlägt KlimaBilanz seltener vor.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, DashStyle.headerInset)
        }
        .motionAnimation(Motion.smooth, value: candidates.count)
    }
}

/// "Aufzeichnung läuft" with the running time – back to the recording screen.
struct TripRecordingRow: View {
    @State private var recorder = TripRecorder.shared

    var body: some View {
        Button { TripRecorderPresenter.shared.present() } label: {
            GlassCard(padding: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "record.circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.pine)
                        .breathing()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aufzeichnung läuft").font(.headline).foregroundStyle(Theme.textPrimary)
                        if let start = recorder.snapshot?.startedAt {
                            Text(timerInterval: start...start.addingTimeInterval(12 * 3600), countsDown: false)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: Theme.Spacing.xs)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .buttonStyle(.pressableCard)
    }
}

/// Presents the recording screen from anywhere (Fahrten tab, Übersicht, Einstellungen): `.tripRecorderHost()` on the root.
@Observable
@MainActor
final class TripRecorderPresenter {
    static let shared = TripRecorderPresenter()
    var isPresented = false

    func present() { isPresented = true }
}

extension View {
    /// The full-screen recording screen. Put on the app's root view, once.
    func tripRecorderHost() -> some View {
        modifier(TripRecorderHostModifier())
    }
}

private struct TripRecorderHostModifier: ViewModifier {
    @State private var presenter = TripRecorderPresenter.shared

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $presenter.isPresented) { TripRecordView() }
    }
}
