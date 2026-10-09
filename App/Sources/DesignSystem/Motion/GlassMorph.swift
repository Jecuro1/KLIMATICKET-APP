import SwiftUI

/// Liquid Glass that morphs (docs/MOTION.md §7): controls in one `GlassEffectContainer` share a namespace, so glass
/// shapes that appear, disappear or change size melt into each other instead of popping. Glass stays reserved for
/// controls (DESIGN.md §2) – never for content cards.
///
///     GlassMorphGroup(spacing: 12) { ns in
///         HStack(spacing: 12) {
///             if isExpanded {
///                 Button { … } label: { Image(systemName: "star.fill") }
///                     .morphingGlass(in: .circle, id: "favorite", namespace: ns)
///             }
///             Button { withMotion(Motion.bouncy) { isExpanded.toggle() } } label: { … }
///                 .morphingGlass(.regular.tint(Theme.accent.opacity(0.3)), in: .circle, id: "main", namespace: ns)
///         }
///     }
struct GlassMorphGroup<Content: View>: View {
    var spacing: CGFloat = Theme.Spacing.s
    @ViewBuilder var content: (Namespace.ID) -> Content
    @Namespace private var namespace

    init(spacing: CGFloat = Theme.Spacing.s, @ViewBuilder content: @escaping (Namespace.ID) -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content(namespace)
        }
    }
}

extension View {
    /// Interactive glass in `shape` that morphs with its siblings in the same `GlassMorphGroup`.
    func morphingGlass<S: Shape, ID: Hashable & Sendable>(_ glass: Glass = .regular.interactive(), in shape: S, id: ID,
                                                         namespace: Namespace.ID) -> some View {
        glassEffect(glass, in: shape)
            .glassEffectID(id, in: namespace)
    }

    /// Several separate controls rendered as one glass shape at rest (e.g. "Woche | Monat | Jahr").
    func unitedGlass<S: Shape, ID: Hashable & Sendable>(_ glass: Glass = .regular.interactive(), in shape: S, union: ID,
                                                       namespace: Namespace.ID) -> some View {
        glassEffect(glass, in: shape)
            .glassEffectUnion(id: union, namespace: namespace)
    }
}

/// A glass segmented control whose selection capsule glides between the options (matched geometry) with
/// `Motion.snappy`, plus a selection haptic. For 2–5 short options (modes, ranges, ticket years); the system `Picker`
/// stays right for forms.
///
///     GlassSegmentedPicker(selection: $range, options: StatsRange.allCases) { Text($0.title) }
struct GlassSegmentedPicker<Value: Hashable, Label: View>: View {
    @Binding var selection: Value
    var options: [Value]
    var tint: Color = Theme.accent
    @ViewBuilder var label: (Value) -> Label

    @Namespace private var namespace
    @Environment(\.colorScheme) private var colorScheme

    init(selection: Binding<Value>, options: [Value], tint: Color = Theme.accent, @ViewBuilder label: @escaping (Value) -> Label) {
        _selection = selection
        self.options = options
        self.tint = tint
        self.label = label
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .haptic(.selection, trigger: selection)
    }

    private func segment(_ option: Value) -> some View {
        let isSelected = option == selection
        return Button {
            guard option != selection else { return }
            withMotion(Motion.snappy) { selection = option }
        } label: {
            label(option)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(selectionFill)
                            .overlay(Capsule().strokeBorder(tint.opacity(colorScheme == .dark ? 0.45 : 0.3), lineWidth: 1))
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 6, y: 2)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.pressable(scale: 0.97))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var selectionFill: Color {
        colorScheme == .dark ? tint.opacity(0.28) : Color.white.opacity(0.92)
    }
}
