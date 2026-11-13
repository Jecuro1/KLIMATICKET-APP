import SwiftUI
import WidgetKit
import KlimaCore

// MARK: smartwidgets – the small Live Activity family as the Apple Watch Smart Stack shows it (docs/WIDGETS_SMARTSTACK.md §5),
// drawn with the extension's own views (`RideSmallActivityView`, `FollowSmallActivityView`) on a plain watch-shaped stage.
// A paired watch cannot be captured in CI, so this page is the preview (CI scene `liveActivitySmall`). Demo values from
// the current clock, no network, no Live Activity.

struct WidWatchActivityShowcase: View {
    /// Built once, so the running timers keep their start.
    @State private var now = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header
                    featured
                    states
                    footnote
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.m)
            }
            .scrollIndicators(.hidden)
            .background { AmbientBackground() }
            .navigationTitle("Apple Watch")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Kicker(text: "Live-Aktivität")
            Text("Am Handgelenk")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Läuft „Unterwegs“ oder „Live verfolgen“, zeigt deine gekoppelte Apple Watch die Fahrt im Smart Stack – ganz ohne eigene Watch-App.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One watch with the followed train in front.
    private var featured: some View {
        WidWatchFrame(time: now) {
            FollowSmallActivityView(attributes: follow, state: followStates[0].state, isStale: false)
        }
        .frame(maxWidth: .infinity)
    }

    private var states: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("So sieht es unterwegs aus")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 172), spacing: Theme.Spacing.s, alignment: .top)],
                      alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(followStates.indices.dropFirst(), id: \.self) { index in
                    card(followStates[index].title) {
                        FollowSmallActivityView(attributes: follow, state: followStates[index].state,
                                                isStale: followStates[index].isStale)
                    }
                }
                card("Unterwegs · eigene Fahrt") {
                    RideSmallActivityView(attributes: ride, state: rideState, isStale: false)
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            WidWatchCard { content() }
        }
    }

    private var footnote: some View {
        Label {
            Text("Ab watchOS 11 mit gekoppeltem iPhone. Ob und wann die Watch die Aktivität zeigt, entscheidet watchOS. Auf dem iPhone bleiben Sperrbildschirm und Dynamic Island wie bisher.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Demo data

    private var follow: FollowActivityAttributes {
        FollowActivityAttributes(tripID: "demo-watch", lineName: "RJX 66", boardingName: "Salzburg Hbf",
                                 alightName: "Wien Hauptbahnhof",
                                 plannedDeparture: now.addingTimeInterval(14 * 60), plannedArrival: now.addingTimeInterval(166 * 60),
                                 startedAt: now.addingTimeInterval(-10 * 60))
    }

    private var followStates: [(title: String, state: FollowLiveState, isStale: Bool)] {
        [
            ("Vor der Abfahrt", FollowLiveState(stage: .beforeDeparture, nextStopName: "Salzburg Hbf",
                                                nextStopTime: now.addingTimeInterval(17 * 60), delayMinutes: 3,
                                                platform: "5", updatedAt: now), false),
            ("Unterwegs", FollowLiveState(stage: .riding, nextStopName: "Linz Hbf", nextStopTime: now.addingTimeInterval(40 * 60),
                                          delayMinutes: 6, platform: "11", progress: 0.4, updatedAt: now), false),
            ("Daten älter", FollowLiveState(stage: .riding, nextStopName: "Linz Hbf", nextStopTime: now.addingTimeInterval(40 * 60),
                                            delayMinutes: 6, platform: "11", progress: 0.4,
                                            updatedAt: now.addingTimeInterval(-23 * 60)), true),
            ("Umstieg", FollowLiveState(stage: .transfer, delayMinutes: 6, progress: 1, transferStation: "Wien Hbf",
                                        transferDeparture: now.addingTimeInterval(12 * 60), updatedAt: now), false),
            ("Fällt aus", FollowLiveState(stage: .cancelled, updatedAt: now), false),
        ]
    }

    private var ride: RideActivityAttributes {
        RideActivityAttributes(rideID: UUID(), fromName: "St. Anton am Arlberg", toName: "Innsbruck Hauptbahnhof",
                               modeRaw: TransportMode.train.rawValue, isRoundTrip: false, lineLabel: nil,
                               ticketName: "KlimaTicket Ö Klassik", startedAt: now.addingTimeInterval(-(42 * 60 + 17)),
                               climb: [0, 0.2, 0.4, 0.6, 0.72])
    }

    private var rideState: RideActivityAttributes.ContentState {
        RideActivityAttributes.ContentState(valueEUR: 23.5, payoff: nil)
    }
}

/// A watch face in plain shapes (no device artwork): black screen, rounded corners, the time on top and one Smart Stack
/// card.
struct WidWatchFrame<Content: View>: View {
    var time: Date
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Text(verbatim: RealtimePresentation.time(time))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .padding(.trailing, 6)
                .accessibilityHidden(true)
            WidWatchCard { content }
            // The next card of the stack peeks out below (empty: only the Live Activity is real here).
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .frame(width: 160, height: 70)
                .frame(maxWidth: .infinity)
                .mask {
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                }
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(width: 214, height: 252, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 48, style: .continuous).fill(Color.black))
        .overlay {
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 6)
        }
        .shadow(color: Color.black.opacity(0.3), radius: 18, y: 10)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vorschau: Apple Watch, Smart Stack")
    }
}

/// One Smart Stack card at the size of the small family (about 176 × 84 pt on a 45 mm watch).
struct WidWatchCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(width: 176, height: 84, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.background))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
            }
            .environment(\.colorScheme, .dark)
    }
}
