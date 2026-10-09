import SwiftUI
import UIKit
import KlimaCore

/// Detail of one Gipfelbuch entry: large medallion with a tilt-driven shine (device motion + drag, tap to spin),
/// tier, progress, date-agnostic copy and sharing as a rendered image card.
struct AchDetailSheet: View {
    let achievement: Achievement
    let ticketYear: String

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    @State private var tilt = MotionTilt()
    @State private var drag: CGSize = .zero
    @State private var spin: Double = 0
    @State private var spinTick = 0
    @State private var bounceTick = 0
    @State private var appeared = LaunchMode.isScreenshot
    @State private var shareImage: Image?

    private let medalSize: CGFloat = 172

    private var tier: Achievement.Tier { achievement.tier }
    private var isUnlocked: Bool { achievement.isUnlocked }
    private var progress: Double { min(max(achievement.progress, 0), 1) }
    private var tierName: String { AchTierStyle.name(tier) }
    private var animatesMotion: Bool { !reduceMotion && !LaunchMode.isScreenshot }
    /// Final state from the first frame when nothing animates (Reduce Motion / screenshots) – otherwise
    /// ProgressRail's own `.animation(_:value:)` would still sweep 0 → p when `appeared` flips in `onAppear`.
    /// `appeared` itself stays the haptic trigger.
    private var revealed: Bool { appeared || !animatesMotion }

    /// Device tilt plus finger drag, −1.5…1.5.
    private var roll: Double { clamp(tilt.roll + Double(drag.width) / 110) }
    private var pitch: Double { clamp(tilt.pitch - Double(drag.height) / 110) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    stage
                    titleBlock
                    infoCard
                    shareButton
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background { backdrop }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Schließen")
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.sheetBackground)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: appeared) { _, newValue in
            newValue && isUnlocked && app.settings.hapticsEnabled
        }
        .sensoryFeedback(.impact(weight: .light), trigger: spinTick) { _, _ in
            app.settings.hapticsEnabled
        }
        .onAppear {
            if animatesMotion {
                tilt.start()
                withAnimation(.spring(duration: 0.7, bounce: 0.35).delay(0.08)) { appeared = true }
            } else {
                appeared = true
            }
        }
        .onDisappear {
            // Unconditional: Reduce Motion may have changed since onAppear; stop() is a no-op when not started.
            tilt.stop()
        }
        .task {
            // Let the zoom transition settle, then render the share card and bounce the symbol once.
            if !LaunchMode.isScreenshot { try? await Task.sleep(for: .milliseconds(380)) }
            renderShareImage()
            if animatesMotion { bounceTick += 1 }
        }
    }

    // MARK: Stage

    private var stage: some View {
        ZStack {
            if isUnlocked { rays }
            Ellipse()
                .fill(Color.black.opacity(0.16))
                .frame(width: medalSize * 0.62, height: medalSize * 0.09)
                .blur(radius: 7)
                .offset(x: roll * 10, y: medalSize * 0.6)
                .accessibilityHidden(true)
            AchMedallion(achievement: achievement,
                         size: medalSize,
                         ringProgress: revealed ? progress : 0,
                         roll: roll,
                         pitch: pitch,
                         bounceTick: bounceTick,
                         showsPercentBadge: false)
                .rotation3DEffect(.degrees(roll * 18 + spin), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .rotation3DEffect(.degrees(-pitch * 14), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                .scaleEffect(revealed ? 1 : 0.6)
                .opacity(revealed ? 1 : 0)
                .contentShape(.circle)
                .gesture(dragGesture)
                .onTapGesture(perform: spinMedal)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Medaille \(achievement.title)")
                .accessibilityValue(medalVoiceOverValue)
                .accessibilityAddTraits(.isImage)
        }
        .frame(maxWidth: .infinity)
        .frame(height: medalSize + 80)
        .padding(.top, Theme.Spacing.xs)
    }

    private var medalVoiceOverValue: String {
        isUnlocked ? "\(tierName), erreicht" : "\(tierName), \(AchFormat.percent(progress)) geschafft"
    }

    /// Soft sunburst behind an unlocked medallion (static; parallax with tilt only).
    private var rays: some View {
        Circle()
            .fill(Theme.tierGradient(tier))
            .mask {
                AngularGradient(colors: Self.rayColors, center: .center, angle: .degrees(roll * 10))
            }
            .mask {
                RadialGradient(colors: [Color.black, Color.black.opacity(0)], center: .center,
                               startRadius: medalSize * 0.3, endRadius: medalSize * 0.92)
            }
            .frame(width: medalSize * 1.85, height: medalSize * 1.85)
            .opacity(revealed ? 0.5 : 0)
            .accessibilityHidden(true)
    }

    private static let rayColors: [Color] = (0..<28).map { $0 % 2 == 0 ? Color.black : Color.black.opacity(0) }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in drag = value.translation }
            .onEnded { _ in
                withAnimation(.spring(duration: 0.6, bounce: 0.45)) { drag = .zero }
            }
    }

    private func spinMedal() {
        guard !reduceMotion else { return }
        withAnimation(.spring(duration: 1.1, bounce: 0.22)) { spin += 360 }
        spinTick += 1
    }

    private func clamp(_ value: Double) -> Double { min(max(value, -1.5), 1.5) }

    // MARK: Text

    private var statusKicker: String {
        isUnlocked ? "\(tierName) · Erreicht" : "\(tierName) · \(AchFormat.percent(progress)) geschafft"
    }

    private var titleBlock: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Kicker(text: statusKicker)
            Text(achievement.title)
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Text(achievement.detail)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
    }

    private var message: String {
        if isUnlocked {
            return "Erreicht im Ticketjahr \(ticketYear). Dieser Gipfel ist fix in deinem Gipfelbuch eingetragen – jede weitere Fahrt ist Kür."
        }
        if progress >= 0.75 { return "Fast oben – nur noch ein kurzes Stück bis zu diesem Gipfel." }
        if progress >= 0.5 { return "Mehr als die Hälfte geschafft. Jede Fahrt bringt dich näher." }
        if progress > 0 { return "Der Aufstieg hat begonnen – bleib dran, jede Fahrt zählt." }
        return "Noch unberührt – vielleicht schon bei deiner nächsten Fahrt?"
    }

    /// How to get there (locked only).
    private var hint: String? {
        switch achievement.id {
        case "first-trip": "Tippe unten auf „+“ und erfasse deine erste Fahrt."
        case "night-owl": "Erfasse eine Fahrt, die nach 22 Uhr beginnt."
        case "early-bird": "Erfasse eine Fahrt zwischen 5 und 7 Uhr früh."
        case "streak-7": "Sei an sieben Tagen hintereinander mit den Öffis unterwegs."
        case "modes-4": "Zug, S-Bahn, Bus, Bim, U-Bahn, Seilbahn – vier verschiedene zählen."
        case "states-5", "states-9": "Jede Fahrt sammelt die Bundesländer, durch die sie führt."
        case "co2-500", "co2-1000": "Gezählt wird die Ersparnis gegenüber derselben Strecke allein im Auto."
        case "quarter", "half", "break-even", "double": "Zählt die Normalpreise deiner Fahrten im Vergleich zum Ticketpreis."
        default: nil
        }
    }

    // MARK: Info card

    private var infoCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                statsRow
                if !isUnlocked {
                    ProgressRail(progress: revealed ? progress : 0,
                                 leadingLabel: achievement.progressLabel,
                                 trailingLabel: "noch \(AchFormat.remainingPercent(progress))",
                                 height: 8)
                }
                messageRow(symbol: isUnlocked ? "checkmark.seal.fill" : "mountain.2.fill",
                           color: isUnlocked ? Theme.positive : Theme.accent,
                           text: message)
                if !isUnlocked, let hint {
                    messageRow(symbol: "lightbulb.fill", color: Theme.gold, text: hint)
                }
                if achievement.id.hasPrefix("states-") {
                    AtlasAchievementLink()
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            stat(label: "Stufe") {
                HStack(spacing: 6) {
                    AchTierCoin(tier: tier, size: 18)
                    Text(tierName)
                }
            }
            Rectangle()
                .fill(Theme.separator)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            if isUnlocked {
                stat(label: "Status") {
                    Label {
                        Text("Erreicht")
                    } icon: {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.positive)
                    }
                }
            } else {
                stat(label: "Fortschritt") {
                    Text(AchFormat.percent(progress))
                        .contentTransition(.numericText(value: progress))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func stat<Value: View>(label: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Kicker(text: label)
            value()
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func messageRow(symbol: String, color: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Sharing

    private var shareLabel: some View {
        Label(isUnlocked ? "Erfolg teilen" : "Fortschritt teilen", systemImage: "square.and.arrow.up")
    }

    private var shareText: String {
        isUnlocked
            ? "Neuer Gipfel in meinem KlimaBilanz-Gipfelbuch: „\(achievement.title)“ – \(achievement.detail)."
            : "Auf dem Weg zu „\(achievement.title)“: \(AchFormat.percent(progress)) geschafft – mit KlimaBilanz."
    }

    @ViewBuilder
    private var shareButton: some View {
        if let shareImage {
            ShareLink(item: shareImage,
                      message: Text(shareText),
                      preview: SharePreview(achievement.title, image: shareImage)) {
                shareLabel
            }
            .buttonStyle(.primary)
        } else {
            Button {} label: { shareLabel }
                .buttonStyle(.primary)
                .disabled(true)
        }
    }

    private func renderShareImage() {
        guard shareImage == nil else { return }
        let renderer = ImageRenderer(content: AchShareCard(achievement: achievement, ticketYear: ticketYear))
        renderer.scale = max(displayScale, 3)
        if let uiImage = renderer.uiImage {
            shareImage = Image(uiImage: uiImage)
        }
    }

    // MARK: Backdrop

    private var backdrop: some View {
        ZStack(alignment: .top) {
            Theme.sheetBackground
            Circle()
                .fill(Theme.tierGradient(tier))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .opacity(isUnlocked ? 0.42 : 0.14)
                .offset(y: -30)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Share card

/// Fixed-size "Blaue Stunde" card rendered with ImageRenderer for sharing. Uses no materials or glass
/// (not supported by ImageRenderer) and pins dark appearance so it looks identical from light and dark mode.
struct AchShareCard: View {
    let achievement: Achievement
    let ticketYear: String

    private var isUnlocked: Bool { achievement.isUnlocked }
    private var tierName: String { AchTierStyle.name(achievement.tier) }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                brandRow
                Spacer(minLength: Theme.Spacing.s)
                AchMedallion(achievement: achievement, size: 150, showsPercentBadge: false)
                Spacer(minLength: Theme.Spacing.l)
                Kicker(text: isUnlocked ? "\(tierName) · Erreicht" : "\(tierName) · \(AchFormat.percent(achievement.progress)) geschafft")
                Text(achievement.title)
                    .font(Theme.Typography.heroTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, Theme.Spacing.xxs)
                Text(achievement.detail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.top, Theme.Spacing.xxs)
                Spacer(minLength: Theme.Spacing.m)
                footer
            }
            .padding(Theme.Spacing.l)
        }
        .frame(width: 360, height: 480)
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
    }

    private var brandRow: some View {
        HStack {
            Label("KlimaBilanz", systemImage: "mountain.2.fill")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Kicker(text: "Gipfelbuch")
        }
    }

    private var footer: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if !isUnlocked {
                ProgressRail(progress: achievement.progress, height: 6)
            }
            Text(ticketYear.isEmpty ? "Mit dem KlimaTicket unterwegs" : "Mit dem KlimaTicket unterwegs · Ticketjahr \(ticketYear)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var background: some View {
        ZStack {
            Theme.background
            LinearGradient(colors: [Theme.dusk.opacity(0.32), Theme.background.opacity(0)], startPoint: .top, endPoint: .center)
            Circle()
                .fill(Theme.tierGradient(achievement.tier))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .opacity(isUnlocked ? 0.5 : 0.22)
                .offset(y: -60)
            VStack {
                Spacer()
                ZStack {
                    RidgeShape(peakX: 0.72, peakY: 0.3, seed: 3, roughness: 0.6)
                        .fill(Theme.glacier.opacity(0.14))
                    RidgeShape(peakX: 0.22, peakY: 0.5, seed: 11, roughness: 0.5)
                        .fill(Theme.dusk.opacity(0.18))
                }
                .frame(height: 190)
            }
        }
    }
}
