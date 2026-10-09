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
                  valueText: summary.map { "\(Format.euro($0.totalValue, decimals: 0)) von \(Format.euro($0.ticketPrice, decimals: 0))" })
    }
}

/// The signature pass (DS `TicketCard`) with tilt-driven foil, tap-to-flip (3D) to the back side with the photo of the
/// real ticket (or the "Foto deines Tickets hinzufügen" placeholder) and the legal note "Begleitkarte · kein Fahrschein".
struct TktCardStack: View {
    let ticket: TicketEntity
    let face: TktCardFace
    var isImportingPhoto: Bool
    var onAddPhoto: () -> Void
    var onRemovePhoto: () -> Void

    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFlipped = false
    @State private var photo: UIImage?
    @State private var flipCount = 0
    @State private var confirmsRemoval = false

    var body: some View {
        let hasPhoto = ticket.photoData != nil
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            flipCard(hasPhoto: hasPhoto)
                .overlay { importOverlay }
            footnote
        }
        .task(id: photoToken) { await loadPhoto() }
        .onChange(of: hasPhoto) { wasPresent, isPresent in
            // A freshly imported photo turns the pass around so you see it right away.
            if isPresent && !wasPresent && !isFlipped { flip() }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: flipCount) { _, _ in app.settings.hapticsEnabled }
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
        let front = TktTiltFront(face: face, hasPhoto: hasPhoto, tiltActive: !isFlipped, onOriginal: {
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

        TktFlipContainer(angle: isFlipped ? 180 : 0, reduceMotion: reduceMotion, front: front, back: back)
            .contentShape(TicketShape(notchY: TktStyle.passNotchY))
            .onTapGesture { flip() }
            .accessibilityIgnoresInvertColors()
    }

    @ViewBuilder
    private var importOverlay: some View {
        if isImportingPhoto {
            ProgressView()
                .controlSize(.large)
                .padding(Theme.Spacing.l)
                .glassEffect(.regular, in: .circle)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
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
                Label(isFlipped ? "Vorderseite" : "Umdrehen", systemImage: isFlipped ? "arrow.uturn.backward" : "hand.tap")
                    .contentTransition(.opacity)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

    private func flip() {
        flipCount += 1
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.75, bounce: 0.2)
        withAnimation(animation) { isFlipped.toggle() }
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

// MARK: - Flip container

/// Animatable 3D flip: the front is visible up to 90°, the (counter-rotated) back from 90° on.
/// With Reduce Motion the faces simply crossfade.
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
        let showsBack = angle >= 90
        let lift = abs(sin(angle * .pi / 180))
        front
            .opacity(frontOpacity)
            .accessibilityHidden(showsBack)
            .overlay {
                back
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                    .opacity(backOpacity)
                    .allowsHitTesting(showsBack)
                    .accessibilityHidden(!showsBack)
            }
            .rotation3DEffect(.degrees(reduceMotion ? 0 : angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .scaleEffect(reduceMotion ? 1 : 1 - 0.06 * lift)
    }

    private var frontOpacity: Double {
        if reduceMotion { return min(max(1 - angle / 180, 0), 1) }
        return angle < 90 ? 1 : 0
    }

    private var backOpacity: Double {
        if reduceMotion { return min(max(angle / 180, 0), 1) }
        return angle >= 90 ? 1 : 0
    }
}

// MARK: - Front (tilt)

/// Owns the motion manager so that only this small view re-renders at 30 Hz while the device tilts.
private struct TktTiltFront: View {
    var face: TktCardFace
    var hasPhoto: Bool
    var tiltActive: Bool
    var onOriginal: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = MotionTilt()
    @State private var isRunning = false

    var body: some View {
        TicketCard(title: face.title, subtitle: face.kicker, holder: face.holder,
                   validFrom: face.validFrom, validUntil: face.validUntil, ticketNumber: face.number,
                   theme: face.theme, roll: roll, pitch: pitch, hasPhoto: hasPhoto,
                   amortizedFraction: face.amortizedFraction, valueText: face.valueText, onOriginal: onOriginal)
            .onAppear { updateMotion() }
            .onDisappear { stopMotion() }
            .onChange(of: shouldRun) { _, _ in updateMotion() }
    }

    /// Off with Reduce Motion, in screenshot mode and in Low Power Mode (synthesis §8.15).
    private var shouldRun: Bool {
        tiltActive && !reduceMotion && !LaunchMode.isScreenshot && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// Screenshot mode shows a fixed, flattering foil position.
    private var roll: Double {
        if LaunchMode.isScreenshot { return 0.35 }
        return reduceMotion ? 0 : tilt.roll
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
