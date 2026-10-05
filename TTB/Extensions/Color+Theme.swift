import SwiftUI

extension Color {
    static let theme = ColorTheme()
}

struct ColorTheme {
    let background = Color("Background")
    let secondaryBackground = Color("SecondaryBackground")
    let accent = Color("Accent")
    let text = Color("Text")
    let secondaryText = Color("SecondaryText")
    let border = Color("Border")
}
