import SwiftUI

struct NavigationChromeTitleView: View {
    let title: Text
    let subtitle: Text?
    var titleFont: Font = .system(size: 24, weight: .bold)
    var subtitleFont: Font = .system(size: 16, weight: .bold)

    var body: some View {
        VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 2) {
            title
                .font(titleFont)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)

            if let subtitle {
                subtitle
                    .font(subtitleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .accessibilityHidden(true)
    }
}
