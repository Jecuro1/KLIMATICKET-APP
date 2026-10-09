import SwiftUI
import KlimaCore

// MARK: - Cards

/// Frosted content card over the alpine sky (Material + specular rim + soft shadow).
/// Per HIG, Liquid Glass (`glassEffect`) is reserved for chrome – tab bar, toolbar, chips, floating controls;
/// content cards use this frosted recipe (cheaper to render, better legibility). `tint` adds a faint colour wash.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.l
    var cornerRadius: CGFloat = Theme.Radius.card
    var tint: Color? = nil
    var interactive: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frostedCard(cornerRadius: cornerRadius, tint: tint)
    }
}

extension View {
    /// The frosted card recipe used by GlassCard / StatTile.
    func frostedCard(cornerRadius: CGFloat = Theme.Radius.card, tint: Color? = nil) -> some View {
        modifier(FrostedCardModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

struct FrostedCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = colorScheme == .dark
        content
            .background {
                ZStack {
                    // The single shadow caster is the card's base shape – not the composited card with its text,
                    // symbols and charts (that forced an offscreen render of the whole card for every shadow). The
                    // base is opaque within the shape, so the shadow looks the same.
                    Group {
                        if reduceTransparency {
                            shape.fill(Theme.sheetBackground)
                        } else {
                            shape.fill(.regularMaterial)
                        }
                    }
                    .shadow(color: dark ? .black.opacity(0.45) : Color(red: 26 / 255, green: 52 / 255, blue: 96 / 255).opacity(0.14),
                            radius: dark ? 20 : 15, y: dark ? 12 : 8)
                    if !reduceTransparency {
                        shape.fill(dark ? Color(red: 30 / 255, green: 46 / 255, blue: 78 / 255).opacity(0.30) : Color.white.opacity(0.44))
                    }
                    if let tint { shape.fill(tint.opacity(dark ? 0.14 : 0.10)) }
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(stops: [.init(color: .white.opacity(colorScheme == .dark ? 0.42 : 0.95), location: 0),
                                           .init(color: .white.opacity(colorScheme == .dark ? 0.05 : 0.18), location: 0.32),
                                           .init(color: .white.opacity(0), location: 0.5),
                                           .init(color: .white.opacity(colorScheme == .dark ? 0.05 : 0.18), location: 0.7),
                                           .init(color: .white.opacity(colorScheme == .dark ? 0.20 : 0.55), location: 1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            }
    }
}

/// Opaque surface card (for dense content like charts where glass would hurt legibility).
struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.l
    var cornerRadius: CGFloat = Theme.Radius.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Shadow from the surface shape only (see FrostedCardModifier).
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
            }
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.separator, lineWidth: 0.5))
    }
}

// MARK: - Headers & labels

/// Uppercase kicker label ("FREITAG, 9. OKTOBER").
struct Kicker: View {
    var text: String
    var color: Color = Theme.textSecondary

    var body: some View {
        Text(text.uppercased(with: Locale(identifier: "de_AT")))
            .font(Theme.Typography.kicker)
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

/// Section title with optional trailing action ("Letzte Fahrten" · "Alle").
struct SectionHeader: View {
    var title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

// MARK: - Stats

/// Number + unit + label tile ("4.812 km · Kilometer").
struct StatTile: View {
    var value: String
    var unit: String? = nil
    var label: String
    var symbol: String
    var color: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.14), in: .circle)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.Typography.numberMedium)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedCard(cornerRadius: Theme.Radius.tile)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Transport mode

/// Rounded square with the mode's SF Symbol in its colour.
struct ModeIcon: View {
    var mode: TransportMode
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: mode.symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.gradients[mode] ?? Self.gradient(mode), in: .rect(cornerRadius: size * 0.31, style: .continuous))
            .accessibilityLabel(mode.displayName)
    }

    /// Built once per mode (stable values, so rows with the same mode diff as unchanged).
    private static let gradients: [TransportMode: LinearGradient] =
        Dictionary(uniqueKeysWithValues: TransportMode.allCases.map { ($0, gradient($0)) })

    private static func gradient(_ mode: TransportMode) -> LinearGradient {
        LinearGradient(colors: [Theme.modeColor(mode), Theme.modeColor(mode).mix(with: .black, by: 0.22)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Chips

/// Selectable capsule chip (filters, favourites, modes).
struct Chip: View {
    var title: String
    var symbol: String? = nil
    var isSelected: Bool = false
    var tint: Color = Theme.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.subheadline.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? tint : Theme.textPrimary)
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint(tint.opacity(0.22)).interactive() : .regular.interactive(), in: .capsule)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Buttons

/// Full-width primary call to action with brand gradient.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.ctaGradient.opacity(isEnabled ? 1 : 0.4), in: .capsule)
            .shadow(color: Theme.accent.opacity(isEnabled ? 0.35 : 0), radius: 16, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

// MARK: - Empty states

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent.gradient)
                .symbolEffect(.pulse, options: .repeat(2))
            Text(title)
                .font(Theme.Typography.title)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primary)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Toast

/// Top banner bound to `app.toast`.
struct ToastOverlay: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let toast = app.toast {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: toast.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.positive)
                    .symbolEffect(.bounce, value: toast.id)
                VStack(alignment: .leading, spacing: 1) {
                    Text(toast.title).font(.subheadline.weight(.semibold))
                    if let subtitle = toast.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, Theme.Spacing.xs)
            .transition(.move(edge: .top).combined(with: .opacity))
            .sensoryFeedback(.success, trigger: toast.id, condition: { _, _ in app.settings.hapticsEnabled })
            .onTapGesture { withAnimation { app.toast = nil } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
