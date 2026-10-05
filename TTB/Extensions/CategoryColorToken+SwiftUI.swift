import SwiftUI
import UIKit

extension CategoryColorToken {
    var color: Color {
        Color(uiColor: uiColor)
    }

    var uiColor: UIColor {
        switch self {
        case .systemRed:
            .systemRed
        case .systemOrange:
            .systemOrange
        case .systemYellow:
            .systemYellow
        case .systemGreen:
            .systemGreen
        case .systemMint:
            .systemMint
        case .systemTeal:
            .systemTeal
        case .systemCyan:
            .systemCyan
        case .systemBlue:
            .systemBlue
        case .systemIndigo:
            .systemIndigo
        case .systemPurple:
            .systemPurple
        case .systemPink:
            .systemPink
        case .systemBrown:
            .systemBrown
        case .systemGray:
            .systemGray
        }
    }

    var displayName: String {
        switch self {
        case .systemRed:
            String(localized: "admin.categories.color.red")
        case .systemOrange:
            String(localized: "admin.categories.color.orange")
        case .systemYellow:
            String(localized: "admin.categories.color.yellow")
        case .systemGreen:
            String(localized: "admin.categories.color.green")
        case .systemMint:
            String(localized: "admin.categories.color.mint")
        case .systemTeal:
            String(localized: "admin.categories.color.teal")
        case .systemCyan:
            String(localized: "admin.categories.color.cyan")
        case .systemBlue:
            String(localized: "admin.categories.color.blue")
        case .systemIndigo:
            String(localized: "admin.categories.color.indigo")
        case .systemPurple:
            String(localized: "admin.categories.color.purple")
        case .systemPink:
            String(localized: "admin.categories.color.pink")
        case .systemBrown:
            String(localized: "admin.categories.color.brown")
        case .systemGray:
            String(localized: "admin.categories.color.gray")
        }
    }
}
