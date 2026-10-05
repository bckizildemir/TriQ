import SwiftUI

/// Horizontally scrolling row of category pills, styled after the App Store's
/// category chips. Tapping a chip pushes the same destination as a section's
/// "View All" button so the categories stay reachable without scrolling the feed.
struct CategoryChipsRow<Destination: View>: View {
    let categories: [Category]
    var horizontalInset: CGFloat = 16
    @ViewBuilder var destination: (Category) -> Destination

    private var chipSpacing: CGFloat { 8 }

    var body: some View {
        ScrollView(.horizontal) {
            glassGroupedChips
                // Chips align with the surrounding page margins while still being able
                // to scroll edge-to-edge underneath them.
                .padding(.horizontal, horizontalInset)
                .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .padding(.horizontal, -horizontalInset)
    }

    /// The chips share one `GlassEffectContainer` so their glass samples the same
    /// backdrop and blends as a single row instead of as unrelated pills.
    @ViewBuilder
    private var glassGroupedChips: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: chipSpacing) {
                chips
            }
        } else {
            chips
        }
    }

    private var chips: some View {
        HStack(spacing: chipSpacing) {
            ForEach(categories) { category in
                NavigationLink {
                    destination(category)
                } label: {
                    CategoryChipLabel(category: category)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-category-chip-\(category.id)")
                .accessibilityLabel(Text(category.displayName))
                .accessibilityHint(Text(String(localized: "main.home.categoryChipHint")))
            }
        }
    }
}

private struct CategoryChipLabel: View {
    let category: Category

    private var accentColor: Color {
        category.colorToken.color
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: category.iconSystemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 18)

            Text(category.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .fixedSize(horizontal: true, vertical: false)
        .categoryChipBackground(accentColor: accentColor)
    }
}

private struct CategoryChipBackgroundModifier: ViewModifier {
    let accentColor: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                // Interactive: each chip is a tappable link, so it should react to
                // touch. The tint stays low-opacity so the glass keeps refracting
                // the feed behind it instead of reading as a solid color pill.
                .glassEffect(
                    .regular.tint(accentColor.opacity(0.10)).interactive(),
                    in: .capsule
                )
        } else {
            content
                .background(accentColor.opacity(0.14), in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(accentColor.opacity(0.28), lineWidth: 1)
                }
                .contentShape(Capsule())
        }
    }
}

private extension View {
    func categoryChipBackground(accentColor: Color) -> some View {
        modifier(CategoryChipBackgroundModifier(accentColor: accentColor))
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CategoryChipsRow(categories: Category.defaultCategories.filter { $0.id != "Daily" }) { category in
                    Text(category.displayName)
                }

                Text(verbatim: "Today's Questions")
                    .font(.title2.bold())
            }
            .padding(.horizontal)
        }
        .background(Color.theme.background)
    }
}
