import SwiftUI

private struct NavigationChromeTitleModifier: ViewModifier {
    let semanticTitle: String
    let visualTitle: Text
    let visualSubtitle: Text?
    var titleFont: Font = .system(size: 24, weight: .bold)
    var subtitleFont: Font = .system(size: 16, weight: .bold)

    func body(content: Content) -> some View {
        content
            .navigationTitle(semanticTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(placement: .title) {
                    NavigationChromeTitleView(
                        title: visualTitle,
                        subtitle: visualSubtitle,
                        titleFont: titleFont,
                        subtitleFont: subtitleFont
                    )
                }
            }
    }
}

extension View {
    func navigationChromeTitle(
        semanticTitle: String,
        visualTitle: Text,
        visualSubtitle: Text? = nil,
        titleFont: Font = .system(size: 24, weight: .bold),
        subtitleFont: Font = .system(size: 16, weight: .bold)
    ) -> some View {
        modifier(
            NavigationChromeTitleModifier(
                semanticTitle: semanticTitle,
                visualTitle: visualTitle,
                visualSubtitle: visualSubtitle,
                titleFont: titleFont,
                subtitleFont: subtitleFont
            )
        )
    }
}
