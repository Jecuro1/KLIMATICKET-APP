import SwiftUI
import KlimaCore

/// Navigation targets inside the catalogue sheet.
enum PerkCatalogRoute: Hashable {
    case partner(PerkPartner)
    case custom
}

/// "Vorteil erfassen": the bundled Vorteilswelt catalogue with search and category chips. Picking a partner pushes
/// the editor prefilled with its typical saving; "Eigener Vorteil" covers anything that is not listed.
struct PerkCatalogSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var path: [PerkCatalogRoute] = []
    @State private var query = ""
    @State private var category: PerkCategory?
    @State private var selectionTick = 0

    private let catalog = PerkCatalogStore.shared

    var body: some View {
        NavigationStack(path: $path) {
            list
                .navigationTitle("Vorteil erfassen")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: Text("Partner, Ort oder Rabatt"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) {
                            dismiss()
                        }
                        .accessibilityLabel("Schließen")
                    }
                }
                .navigationDestination(for: PerkCatalogRoute.self) { route in
                    switch route {
                    case .partner(let partner):
                        PerkEditorView(mode: .new(partner), showsCloseButton: false) { dismiss() }
                    case .custom:
                        PerkEditorView(mode: .custom, showsCloseButton: false) { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .perkHaptic(.selection, trigger: selectionTick, enabled: app.settings.hapticsEnabled)
    }

    // MARK: List

    private var list: some View {
        let results = catalog.search(query, category: category)
        return List {
            if query.isEmpty {
                Section {
                    customRow
                }
            }
            if results.isEmpty {
                Section {
                    noResults
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else if category == nil && query.isEmpty {
                ForEach(PerkCategory.catalogCases) { section in
                    let partners = results.filter { $0.category == section }
                    if !partners.isEmpty {
                        Section {
                            ForEach(partners) { partner in row(partner) }
                        } header: {
                            sectionHeader(section, count: partners.count)
                        }
                    }
                }
            } else {
                Section {
                    ForEach(results) { partner in row(partner) }
                } header: {
                    Text(resultsTitle(results.count))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .textCase(nil)
                }
            }
            Section {
                EmptyView()
            } footer: {
                footer
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.m)
        .scrollContentBackground(.hidden)
        .background { PerkSheetBackdrop() }
        // Category chips stay put under the search field while the catalogue scrolls beneath them.
        .safeAreaBar(edge: .top) { chips }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: category)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Chip(title: "Alle", isSelected: category == nil, tint: Theme.accentText) {
                        select(nil)
                    }
                    ForEach(PerkCategory.catalogCases) { item in
                        Chip(title: item.displayName, symbol: item.symbolName, isSelected: category == item, tint: Theme.accentText) {
                            select(category == item ? nil : item)
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
        .contentMargins(.horizontal, Theme.Spacing.cardGutter, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Nach Kategorie filtern")
    }

    private func row(_ partner: PerkPartner) -> some View {
        Button {
            path.append(.partner(partner))
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                PerkIconTile(partner: partner, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(partner.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Text(partner.benefit)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                    Text(partner.regionName)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                .alignmentGuide(.listRowSeparatorLeading) { dimensions in dimensions[.leading] }
                Spacer(minLength: Theme.Spacing.xs)
                Text(PerkFormat.typical(partner.typicalSavingEUR))
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.positiveText)
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(PerkRowBackground())
        .listRowSeparatorTint(Theme.separator)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(partner.name)
        .accessibilityValue("\(partner.benefit). \(partner.regionLongName). Typisch \(Format.euroPrecise(partner.typicalSavingEUR)) gespart")
        .accessibilityHint("Öffnet das Formular zum Erfassen")
        .accessibilityAddTraits(.isButton)
    }

    private var customRow: some View {
        Button {
            path.append(.custom)
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                PerkIconTile(symbol: "square.and.pencil", category: .custom, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Eigener Vorteil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Gästekarte, Verbund-Aktion oder ein Rabatt, der hier fehlt")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                .alignmentGuide(.listRowSeparatorLeading) { dimensions in dimensions[.leading] }
                Spacer(minLength: Theme.Spacing.xs)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(PerkRowBackground())
        .accessibilityHint("Öffnet ein leeres Formular")
    }

    private func sectionHeader(_ category: PerkCategory, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: category.symbolName)
                .foregroundStyle(PerkStyle.tint(category))
            Text(category.displayName)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: Theme.Spacing.xs)
            Text("\(count)")
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
        }
        .font(.footnote.weight(.semibold))
        .textCase(nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.displayName), \(count) Angebote")
        .accessibilityAddTraits(.isHeader)
    }

    private var noResults: some View {
        ContentUnavailableView {
            Label("Nichts gefunden", systemImage: "magnifyingglass")
                .foregroundStyle(Theme.textPrimary)
        } description: {
            Text(query.isEmpty ? "In dieser Kategorie gibt es noch keine Angebote." : "Kein Vorteil passt zu „\(query)“.")
                .foregroundStyle(Theme.textSecondary)
        } actions: {
            Button("Als eigenen Vorteil erfassen") { path.append(.custom) }
                .buttonStyle(.glass)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(footerText)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: PerkCatalogStore.sourceURL) {
                Label("Alle Vorteile auf klimaticket.at", systemImage: "arrow.up.right.square")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
            }
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private var footerText: String {
        let asOf = PerkCatalogStore.asOfText.map { "Stand \($0). " } ?? ""
        return "\(asOf)Richtwerte sind typische Ersparnisse – du kannst jeden Betrag anpassen. Bedingungen und Codes laut Partner, Angaben ohne Gewähr."
    }

    private func resultsTitle(_ count: Int) -> String {
        count == 1 ? "1 Angebot" : "\(count) Angebote"
    }

    private func select(_ item: PerkCategory?) {
        guard item != category else { return }
        category = item
        selectionTick += 1
    }
}
