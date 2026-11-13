import SwiftUI
import MapKit
import KlimaCore

// MARK: radarcockpit – the Cockpit-Ansicht (docs/RADAR_COCKPIT.md): the camera follows one train, tilted in 3D, with the next stop, the arrival and the
// delay. Opened from the trip sheet of a train on the radar as a full-screen view; the radar below it is stopped while it is open. Three camera
// modes in a glass switcher (Verfolgen, Vogelperspektive, Frei); a finger on the map makes it Frei and "Zurück zum Zug" flies back.

struct CockpitView: View {
    @State private var model: CockpitModel
    private let launch: CockpitLaunch
    var onClose: () -> Void

    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("radar.mapStyle") private var styleRaw = RadarMapStyle.standard.rawValue
    @State private var alarmInput: ExitAlarmSheetInput?
    private let tracker = LiveFollowTracker.shared

    init(launch: CockpitLaunch, services: CockpitModel.Services, onClose: @escaping () -> Void) {
        self.launch = launch
        self.onClose = onClose
        _model = State(initialValue: CockpitModel(launch: launch, services: services))
    }

    private var mapStyle: RadarMapStyle { RadarMapStyle(rawValue: styleRaw) ?? .standard }
    private var isFollowed: Bool { tracker.target?.tripID == model.tripID }

    var body: some View {
        // The controls sit in the map's safe area (as on the radar): MapKit centres its camera in the part of the map that is left between
        // them, so the train is never under the HUD, at any text size. The map itself still draws edge to edge, under the glass.
        CockpitMap(model: model, style: mapStyle, scheme: mapStyle == .dark ? .dark : colorScheme, start: launch.startCamera)
            .overlay(alignment: .bottom) {
                // Above Apple's attribution, which sits at the bottom left of the map's safe area.
                if model.hud.offersReturn { returnButton.padding(.bottom, 34) }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: Theme.Spacing.xs) {
                    topBar
                    CockpitModeSwitcher(mode: model.hud.mode) { model.select($0) }
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    banners
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.bottom, Theme.Spacing.xs)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CockpitHUDCard(model: model, onAlarm: openAlarm, onFollow: startFollowing, isFollowing: isFollowed)
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.bottom, Theme.Spacing.xs)
            }
            .background(Theme.background.ignoresSafeArea())
            .motionAnimation(Motion.smooth, value: model.hud.offersReturn)
            .motionAnimation(Motion.smooth, value: model.hud.banner)
            .haptic(.selection, trigger: model.hud.mode)
            .task(id: scenePhase == .active) {
                model.setReduceMotion(reduceMotion)
                guard scenePhase == .active else { return }
                model.begin(reduceMotion: reduceMotion)
                await model.run()
            }
            .onChange(of: reduceMotion) { _, value in model.setReduceMotion(value) }
            .sheet(item: $alarmInput) { ExitAlarmSheet(input: $0) }
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            // A bar button: the glyph keeps its size in its circle, the large content viewer shows it big (long press).
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Cockpit schließen")
            .accessibilityShowsLargeContentViewer { Label("Schließen", systemImage: "xmark") }
            lineChip
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
    }

    /// The line and where it goes. Not a control: the train is the one the cockpit follows.
    private var lineChip: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let line = model.line { PlannerLinePlate(line: line, size: .s) }
            VStack(alignment: .leading, spacing: 0) {
                Text(model.hud.summary?.lineTitle ?? model.line.map { LinePresentation.title($0) } ?? "Zug")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                if let destination = model.hud.summary?.destination {
                    Text("nach \(destination)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }

    // MARK: Banners

    @ViewBuilder private var banners: some View {
        VStack(spacing: Theme.Spacing.xs) {
            switch model.hud.banner {
            case .waiting?:
                CockpitBanner(symbol: "dot.radiowaves.left.and.right", title: CockpitText.waitingTitle, detail: CockpitText.waitingDetail)
            case .lost(let detail)?:
                CockpitBanner(symbol: "location.slash", title: CockpitText.lostTitle, detail: detail, actionTitle: "Erneut versuchen") { model.refreshNow() }
            case .ended(let detail)?:
                CockpitBanner(symbol: "flag.checkered", title: CockpitText.endedTitle, detail: detail, actionTitle: "Schließen", action: onClose)
            case nil:
                EmptyView()
            }
            if model.hud.lowPower {
                CockpitBanner(symbol: "battery.25percent", title: "Stromspar-Modus",
                              detail: "Die Position aktualisiert sich nicht, solange der Stromspar-Modus an ist.",
                              actionTitle: "Jetzt aktualisieren") { model.refreshNow() }
            }
            if let note = model.hud.note, model.hud.banner == nil || !model.hud.lowPower {
                Text(note).radarHint()
            } else if model.hud.isStraightLine {
                // No polyline for this run: the lines on the map join the stops, and the map says so (docs/RADAR_COCKPIT.md §1).
                Text(CockpitText.straightLineNote).radarHint()
            }
        }
        .transition(.opacity)
    }

    // MARK: Return

    private var returnButton: some View {
        Button { model.returnToTrain() } label: {
            Label("Zurück zum Zug", systemImage: "location.fill")
                .font(.headline)
                .padding(.horizontal, 6)
                .frame(minHeight: 36)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.prominentTint)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    // MARK: Actions

    private func openAlarm() {
        guard let target = model.followVehicle.followTarget else { return }
        alarmInput = ExitAlarmSheetInput(target: target, stopovers: model.followVehicle.stopovers)
    }

    private func startFollowing() {
        guard let target = model.followVehicle.followTarget else { return }
        LiveFollowTracker.shared.start(target, live: app.live)
    }
}

// MARK: - Pieces

/// The glass switcher: the selection capsule glides between the modes. The titles are never cut: at the accessibility text sizes the three modes
/// are one menu.
struct CockpitModeSwitcher: View {
    var mode: CockpitCameraMode
    var onSelect: (CockpitCameraMode) -> Void

    @Namespace private var namespace
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            segments
            menu
        }
        .frame(maxWidth: .infinity)
    }

    private var segments: some View {
        HStack(spacing: 2) {
            ForEach(CockpitCameraMode.allCases, id: \.self) { option in
                let selected = option == mode
                Button {
                    guard option != mode else { return }
                    withMotion(Motion.snappy) { onSelect(option) }
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Theme.accent.opacity(colorScheme == .dark ? 0.28 : 0.15))
                                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(colorScheme == .dark ? 0.45 : 0.35), lineWidth: 1))
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.pressable(scale: 0.97))
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kameraansicht")
    }

    private var menu: some View {
        Menu {
            ForEach(CockpitCameraMode.allCases, id: \.self) { option in
                Button { onSelect(option) } label: {
                    if option == mode { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(mode.title).font(.headline)
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.bold))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("Kameraansicht")
        .accessibilityValue(mode.title)
    }
}

/// A note on a glass card above the HUD: the train is lost, the run has ended, the Stromspar-Modus pauses the updates.
struct CockpitBanner: View {
    var symbol: String
    var title: String
    var detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(symbol: String, title: String, detail: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        // The action sits under the words, so the words keep the width of the card ("Zuletzt gesehen vor 2 Min." on one line, not four).
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.footnote).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }
}
