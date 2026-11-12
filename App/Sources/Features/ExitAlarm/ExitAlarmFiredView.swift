import SwiftUI
import UIKit
import KlimaCore

// Aussteige-Wecker: the full-screen "Aussteigen!" moment (docs/EXIT_ALARM.md §4). It appears when an alarm rang and waits for the
// user: haptic, the stop in big letters, the platform when it is known, "Quittieren" and "5 Min später". The same screen says
// "Vorbeigefahren" when the stop was passed. The background is the dark fern gradient with a dawn glow, so white text always reads.

struct ExitAlarmFiredView: View {
    /// The alarm that rang; nil for the test alarm of Settings.
    let state: ExitAlarmState?
    var isTest = false
    var now: Date = Date()
    var onAcknowledge: () -> Void = {}
    var onSnooze: () -> Void = {}

    @State private var pulse = 0
    @Environment(\.scenePhase) private var scenePhase

    private var isPassed: Bool { state?.passedAt != nil }
    private var title: String { isTest ? "Test" : (state.map(ExitAlarmPresentation.firedTitle) ?? "Aussteigen!") }
    private var stopName: String { state?.spec.stopName ?? "Aussteige-Wecker" }

    var body: some View {
        ZStack {
            background
            VStack(spacing: Theme.Spacing.l) {
                Spacer(minLength: Theme.Spacing.xl)
                bell
                VStack(spacing: Theme.Spacing.xs) {
                    Text(title.uppercased(with: Format.locale))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.78))
                    Text(stopName)
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .lineLimit(3)
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    if isPassed {
                        Text("Du bist an \(stopName) vorbeigefahren.")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }
                }
                .reveal(.focus)
                details
                Spacer(minLength: Theme.Spacing.m)
                actions
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, Theme.Spacing.l)
        }
        .preferredColorScheme(.dark)
        .haptic(.warning, trigger: pulse)
        .task {
            // A firm tap every 1.6 seconds while the screen is up (it follows Einstellungen › Haptik; silent in screenshots).
            while !Task.isCancelled {
                pulse += 1
                try? await Task.sleep(for: .seconds(1.6))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var background: some View {
        ZStack {
            Theme.fernTile
            RadialGradient(colors: [Theme.dawn.opacity(0.8), Theme.alpenglow.opacity(0.3), .clear],
                           center: .init(x: 0.5, y: 0.3), startRadius: 10, endRadius: 520)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var bell: some View {
        ZStack {
            Circle().fill(.white.opacity(0.14)).frame(width: 132, height: 132)
            Image(systemName: isPassed ? "arrow.uturn.backward.circle.fill" : "bell.and.waves.left.and.right.fill")
                .font(.system(size: 60, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
                .modifier(RingingSymbol())
        }
        .pulsingHalo(Theme.dawn, scale: 2.1, period: 1.8)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var details: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let state, !isPassed {
                HStack(spacing: Theme.Spacing.s) {
                    if let platform = state.spec.platform, !platform.isEmpty {
                        capsule("Gleis \(platform)", symbol: "signpost.right.fill")
                    }
                    capsule(state.spec.lineName, symbol: "tram.fill")
                }
                if let arrival = state.timetableArrival {
                    let delay = state.delaySeconds.map { Int((Double($0) / 60).rounded()) } ?? 0
                    Text("Ankunft \(ExitAlarmPresentation.timeText(arrival))" + (delay > 0 ? " · +\(delay) Min" : ""))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.82))
                }
            } else if isTest {
                Text("So klingt und sieht dein Aussteige-Wecker aus.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func capsule(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white.opacity(0.16), in: .capsule)
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.s) {
            Button(action: onAcknowledge) {
                Label(isPassed || isTest ? "Verstanden" : "Quittieren", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.primary)
            if !isPassed && !isTest {
                Button(action: onSnooze) {
                    Label("5 Min später", systemImage: "zzz")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glass)
            }
        }
    }
}

/// The bell shakes while it is visible and Reduce Motion is off (a continuous effect, so `ContinuousMotionReader` decides).
private struct RingingSymbol: ViewModifier {
    func body(content: Content) -> some View {
        ContinuousMotionReader { isRunning in
            content.symbolEffect(.variableColor.iterative.reversing, isActive: isRunning)
        }
    }
}

/// The content of the full-screen window: whatever rings now (an alarm or the test).
struct ExitAlarmFiredContainer: View {
    private let service = ExitAlarmService.shared

    var body: some View {
        if let state = service.attention {
            ExitAlarmFiredView(state: state, now: Date(),
                               onAcknowledge: { service.acknowledge(state.id) },
                               onSnooze: { service.snooze(state.id) })
        } else if service.testRang {
            ExitAlarmFiredView(state: nil, isTest: true, onAcknowledge: { service.acknowledgeTest() })
        } else {
            Color.clear
        }
    }
}

// MARK: Window

/// Shows the full-screen moment in a window of its own, above sheets and everything else, while an alarm waits. SwiftUI cannot
/// present over every sheet; a ringing alarm must not hide behind one.
@MainActor
final class ExitAlarmWindow {
    static let shared = ExitAlarmWindow()
    private var window: UIWindow?

    /// Call after any change of the service and when the scene becomes active.
    func update() {
        let service = ExitAlarmService.shared
        let shouldShow = !service.isSimulated && (service.attention != nil || service.testRang)
        if shouldShow { show() } else { hide() }
    }

    private func show() {
        guard window == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level.alert + 1
        let host = UIHostingController(rootView: ExitAlarmFiredContainer())
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
    }

    private func hide() {
        guard let window else { return }
        window.isHidden = true
        self.window = nil
    }
}
