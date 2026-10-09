import SwiftUI
import UIKit
import KlimaCore

/// Everything the front of the pass shows – a plain value, so the tilting front never touches SwiftData.
struct TktCardFace: Equatable {
    var title: String
    var kicker: String
    var holder: String
    var validFrom: Date
    var validUntil: Date
    var number: String
    var theme: TicketTheme
    /// Amortisation on the stub; nil shows the ticket number instead (e.g. a ticket that has not started yet).
    var amortizedFraction: Double? = nil
    /// "€ 1.050 von € 1.400"
    var valueText: String? = nil
}

extension TktCardFace {
    init(ticket: TicketEntity, summary: SavingsSummary?) {
        self.init(title: ticket.name,
                  kicker: TktText.passKicker(name: ticket.name, variant: ticket.variant, family: ticket.family, states: ticket.states),
                  holder: ticket.holderName,
                  validFrom: ticket.startDate,
                  validUntil: ticket.endDate,
                  number: ticket.ticketNumber,
                  theme: TicketTheme.from(ticket.themeRaw),
                  // Pre-rounded so the stub's `Format.percent` never shows "100 %" before the break-even.
                  amortizedFraction: summary.map { TktText.displayFraction($0.amortizedFraction) },
                  // Same whole-euro figures as the Übersicht hero ("€ 1.050 von € 1.400", never the price before the summit).
                  valueText: summary.map { "\(SummitFigures.euro($0.shownTotalEuro)) von \(SummitFigures.euro($0.ticketPrice))" })
    }
}

/// The signature pass (DS `TicketCard`) with tilt-driven foil and a back side with the photo of the real ticket (or the
/// "Foto deines Tickets hinzufügen" placeholder) and the legal note "Begleitkarte · kein Fahrschein".
///
/// Handled like a real card: it is dealt onto the screen once (tips in from a slight tilt), swivels under a sideways drag
/// – the holographic foil sliding with it – and turns over when let go past the edge or flicked; a tap turns it too.
/// Vertical drags keep scrolling the page. One light haptic per turn. Reduce Motion: no swivel, the faces cross-fade.
struct TktCardStack: View {
    let ticket: TicketEntity
    let face: TktCardFace
    var isImportingPhoto: Bool
    /// A sheet of the Ticket tab (edit, photo picker) covers the pass – the tilt pauses.
    var isCovered: Bool = false
    var onAddPhoto: () -> Void
    var onRemovePhoto: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Resting angle in degrees (multiples of 180; odd multiples show the back). CI route `ticketBack` opens turned.
    @State private var turns: Double = LaunchMode.screenshotScreen == "ticketBack" ? 180 : 0
    /// Live swivel of a sideways drag, added to `turns`.
    @State private var dragAngle: Double = 0
    @State private var cardWidth: CGFloat = 360
    @State private var photo: UIImage?
    @State private var flipCount = 0
    @State private var confirmsRemoval = false
    /// The pass is dealt onto the screen once (also when another ticket year takes its place).
    @State private var isDealt = MotionPolicy.isStatic

    private var isFlipped: Bool { Int((abs(turns) / 180).rounded()) % 2 == 1 }

    var body: some View {
        let hasPhoto = ticket.photoData != nil
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            flipCard(hasPhoto: hasPhoto)
                .overlay { importOverlay }
                .rotation3DEffect(.degrees(isDealt || reduceMotion ? 0 : 16), axis: (x: 1, y: 0, z: 0),
                                  anchor: .bottom, perspective: 0.6)
                .popoverTip(KBTips.TicketFlip(), arrowEdge: .top)
            footnote
        }
        .task(id: photoToken) { await loadPhoto() }
        .onAppear(perform: deal)
        .onChange(of: hasPhoto) { wasPresent, isPresent in
            // A freshly imported photo turns the pass around so you see it right away.
            if isPresent && !wasPresent && !isFlipped { flip() }
        }
        .haptic(.tap, trigger: flipCount)
        .confirmationDialog("Foto entfernen?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Foto entfernen", role: .destructive) { onRemovePhoto() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das Foto deines Tickets wird von diesem iPhone gelöscht.")
        }
    }

    // MARK: Card

    @ViewBuilder
    private func flipCard(hasPhoto: Bool) -> some View {
        let angle = turns + dragAngle
        // The foil slides with the swivel while the front faces you (−1 … 1, like tilting the phone).
        let swivel = isFlipped ? 0 : max(-1, min(1, sin(dragAngle * .pi / 180) * 1.6))
        let front = TktTiltFront(face: face, hasPhoto: hasPhoto, tiltActive: !isFlipped && !isCovered, swivel: swivel,
                                 onOriginal: {
            if hasPhoto { flip() } else { onAddPhoto() }
        })
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Doppeltippen dreht die Karte um.")
        .accessibilityAction { flip() }
        .accessibilityAction(named: hasPhoto ? "Ticket-Foto anzeigen" : "Foto deines Tickets hinzufügen") {
            if hasPhoto { flip() } else { onAddPhoto() }
        }

        let back = TktCardBack(theme: face.theme, photo: photo, onAdd: onAddPhoto,
                               onRemove: { confirmsRemoval = true }, onFlipBack: { flip() })

        TktFlipContainer(angle: angle, reduceMotion: reduceMotion, front: front, back: back)
            .contentShape(TicketShape(notchY: TktStyle.passNotchY))
            .onTapGesture { flip() }
            .gesture(TktSwivelGesture(isEnabled: !reduceMotion, onChange: swivel(by:), onEnd: release(at:velocity:)))
            .onGeometryChange(for: CGFloat.self, of: { proxy in proxy.size.width }, action: { width in
                cardWidth = max(width, 1)
            })
            .accessibilityIgnoresInvertColors()
    }

    @ViewBuilder
    private var importOverlay: some View {
        if isImportingPhoto {
            ProgressView()
                .controlSize(.large)
                .padding(Theme.Spacing.l)
                .glassEffect(.regular, in: .circle)
                .motionTransition(.pop)
                .accessibilityLabel("Foto wird geladen")
        }
    }

    /// "ⓘ Begleitkarte · kein Fahrschein" + a quiet flip affordance.
    private var footnote: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Label("Begleitkarte · kein Fahrschein", systemImage: "info.circle")
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: Theme.Spacing.xs)
            Button { flip() } label: {
                Label {
                    Text(isFlipped ? "Vorderseite" : "Umdrehen")
                        .contentTransition(.opacity)
                } icon: {
                    Image(systemName: isFlipped ? "arrow.uturn.backward" : "hand.tap")
                        .symbolReplaceTransition()
                }
                .padding(.vertical, Theme.Spacing.xxs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(isFlipped ? "Vorderseite der Karte zeigen" : "Karte umdrehen")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, Theme.Spacing.xxs)
    }

    // MARK: Actions

    private var photoToken: String {
        "\(ticket.id.uuidString)-\(ticket.photoData?.count ?? -1)"
    }

    private func deal() {
        guard !isDealt else { return }
        if reduceMotion {
            isDealt = true
        } else {
            withAnimation(Motion.reveal.delay(Motion.Stagger.delay(1))) { isDealt = true }
        }
    }

    /// Tap / button / accessibility: turns the card over (back the way it came).
    private func flip() {
        turn(by: isFlipped ? -180 : 180)
    }

    private func turn(by delta: Double) {
        flipCount += 1
        KBTips.used(KBTips.TicketFlip())
        withMotion(Motion.bouncy) {
            turns += delta
            dragAngle = 0
        }
    }

    /// The card follows the finger: half its width swivels it edge-on (90°).
    private func swivel(by translation: CGFloat) {
        dragAngle = Double(translation / cardWidth) * 180
    }

    /// Let go past the edge – or flicked – it turns over in that direction; otherwise it springs back.
    private func release(at translation: CGFloat, velocity: CGFloat) {
        let projected = Double((translation + velocity * 0.18) / cardWidth) * 180
        if abs(projected) > 75 {
            turn(by: projected > 0 ? 180 : -180)
        } else {
            withMotion(Motion.release) { dragAngle = 0 }
        }
    }

    private func loadPhoto() async {
        guard let data = ticket.photoData, let image = UIImage(data: data) else {
            photo = nil
            return
        }
        let prepared = await image.byPreparingForDisplay()
        photo = prepared ?? image
    }
}

// MARK: - Swivel gesture

/// Sideways pan on the pass (UIKit, so it only begins when the finger moves more sideways than up/down – a vertical
/// drag keeps scrolling the page). Reports the horizontal translation and, on release, the velocity (points, global).
private struct TktSwivelGesture: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var onChange: (CGFloat) -> Void
    var onEnd: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = context.converter.translation(in: .global)?.x ?? 0
        switch recognizer.state {
        case .began, .changed:
            onChange(translation)
        case .ended:
            onEnd(translation, context.converter.velocity(in: .global)?.x ?? 0)
        default:
            onEnd(0, 0)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Only a clearly sideways drag starts the swivel.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.3
        }
    }
}

// MARK: - Flip container

/// Animatable 3D flip at any angle: the front shows while it faces you (−90° … 90° mod 360), the counter-rotated back
/// otherwise. The card shrinks a little while edge-on. With Reduce Motion the faces cross-fade instead.
private struct TktFlipContainer<Front: View, Back: View>: View, Animatable {
    var angle: Double
    var reduceMotion: Bool
    var front: Front
    var back: Back

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let normalized = angle.truncatingRemainder(dividingBy: 360) + (angle < 0 ? 360 : 0)
        let showsBack = normalized > 90 && normalized < 270
        let lift = abs(sin(angle * .pi / 180))
        // Reduce Motion: 1 when the front faces you, 0 when the back does.
        let frontShare = (1 + cos(angle * .pi / 180)) / 2
        front
            .opacity(reduceMotion ? frontShare : (showsBack ? 0 : 1))
            .accessibilityHidden(showsBack)
            .overlay {
                back
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                    .opacity(reduceMotion ? 1 - frontShare : (showsBack ? 1 : 0))
                    .allowsHitTesting(showsBack)
                    .accessibilityHidden(!showsBack)
            }
            .rotation3DEffect(.degrees(reduceMotion ? 0 : angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .scaleEffect(reduceMotion ? 1 : 1 - 0.06 * lift)
    }
}

// MARK: - Front (tilt)

/// Owns the motion manager so that only this small view re-renders at 30 Hz while the device tilts (and inside it only the
/// foil and the seal – see `TicketCard`). The sensor runs only while the pass can be seen: not flipped, not scrolled away,
/// not under a sheet (the Ticket tab's own or an app-level one), not in Low Power Mode.
private struct TktTiltFront: View {
    var face: TktCardFace
    var hasPhoto: Bool
    var tiltActive: Bool
    /// Sideways swivel of a drag (−1 … 1): the foil and seal follow it like a tilt.
    var swivel: Double = 0
    var onOriginal: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set by RootView while an app-level sheet (trip editor, Einstellungen, update) is up.
    @Environment(\.ambientSkyPaused) private var isCoveredByAppSheet
    @State private var tilt = MotionTilt()
    @State private var isRunning = false
    @State private var isOnScreen = true

    var body: some View {
        TicketCard(title: face.title, subtitle: face.kicker, holder: face.holder,
                   validFrom: face.validFrom, validUntil: face.validUntil, ticketNumber: face.number,
                   theme: face.theme, roll: roll, pitch: pitch, hasPhoto: hasPhoto,
                   amortizedFraction: face.amortizedFraction, valueText: face.valueText, onOriginal: onOriginal)
            .onScrollVisibilityChange(threshold: 0.05) { visible in isOnScreen = visible }
            .onAppear { updateMotion() }
            .onDisappear { stopMotion() }
            .onChange(of: shouldRun) { _, _ in updateMotion() }
    }

    /// Off with Reduce Motion, in screenshot mode and in Low Power Mode (synthesis §8.15), and while nobody can see it.
    private var shouldRun: Bool {
        tiltActive && isOnScreen && !isCoveredByAppSheet && !reduceMotion && !LaunchMode.isScreenshot
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// Screenshot mode shows a fixed, flattering foil position.
    private var roll: Double {
        if LaunchMode.isScreenshot { return 0.35 }
        return reduceMotion ? 0 : max(-1, min(1, tilt.roll + swivel))
    }

    private var pitch: Double {
        if LaunchMode.isScreenshot { return 0.12 }
        return reduceMotion ? 0 : tilt.pitch
    }

    private func updateMotion() {
        if shouldRun && !isRunning {
            tilt.start()
            isRunning = true
        } else if !shouldRun && isRunning {
            stopMotion()
        }
    }

    private func stopMotion() {
        guard isRunning else { return }
        tilt.stop()
        isRunning = false
    }
}

// MARK: - Back

/// Back of the pass: the photo of the real ticket, or an invitation to add one. Same outline (notches) as the front.
private struct TktCardBack: View {
    var theme: TicketTheme
    var photo: UIImage?
    var onAdd: () -> Void
    var onRemove: () -> Void
    var onFlipBack: () -> Void

    var body: some View {
        let shape = TicketShape(notchY: TktStyle.passNotchY)
        ZStack {
            background
            if let photo {
                photoLayer(photo)
            } else {
                placeholder
            }
        }
        .foregroundStyle(theme.ink)
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.22), lineWidth: 1))
        .shadow(color: theme.colors[1].opacity(0.32), radius: 24, y: 16)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Vorderseite zeigen") { onFlipBack() }
    }

    private var background: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: theme.colors.reversed(), startPoint: .topLeading, endPoint: .bottomTrailing)
            TopoLines()
                .stroke(theme.ink.opacity(0.1), lineWidth: 0.8)
                .scaleEffect(x: -1, y: 1)
            // Magnetic-stripe band – instantly reads as "the back of a card".
            Rectangle()
                .fill(Color.black.opacity(0.26))
                .frame(height: 34)
                .padding(.top, Theme.Spacing.l)
        }
        .accessibilityHidden(true)
    }

    // MARK: Placeholder

    private var placeholder: some View {
        ViewThatFits(in: .vertical) {
            placeholderContent(compact: false)
            placeholderContent(compact: true)
        }
        .padding(.top, 62)
        .padding(.bottom, Theme.Spacing.m)
        .padding(.horizontal, Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholderContent(compact: Bool) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            if !compact {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(theme.ink.opacity(0.14), in: .circle)
                    .accessibilityHidden(true)
            }
            Text("Foto deines Tickets hinzufügen")
                .font(.headline)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
            if !compact {
                Text("Für den schnellen Blick. Bei Kontrollen zählt immer dein Original-Ticket.")
                    .font(.footnote)
                    .opacity(0.8)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onAdd) {
                Label("Foto auswählen", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.xs + 2)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.top, Theme.Spacing.xxs)
        }
    }

    // MARK: Photo

    private func photoLayer(_ image: UIImage) -> some View {
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel("Foto deines Original-Tickets")
            }
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomLeading) { photoCaption }
            .overlay(alignment: .topTrailing) { photoActions }
    }

    private var photoCaption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Begleitkarte · kein Fahrschein", systemImage: "info.circle")
                .font(.caption.weight(.semibold))
            Text("Bei Kontrollen zählt immer dein Original-Ticket.")
                .font(.caption2)
                .opacity(0.85)
        }
        .foregroundStyle(Color.white)
        .padding(Theme.Spacing.m)
        .accessibilityElement(children: .combine)
    }

    private var photoActions: some View {
        GlassEffectContainer(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                circleButton("arrow.triangle.2.circlepath", label: "Foto ersetzen", action: onAdd)
                circleButton("trash", label: "Foto entfernen", action: onRemove)
            }
        }
        .padding(Theme.Spacing.s)
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}
