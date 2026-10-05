import SwiftUI

struct BadgeGridItem: View {
    let badge: Badge
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: badge.icon)
                    .font(.system(size: 24))
                    .foregroundColor(badge.isLocked ? .gray.opacity(0.8) : .primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(badge.isLocked ? Color.gray.opacity(0.1) : Color.accentColor.opacity(0.2))
                    )
                
                Text(badge.title)
                    .font(.caption)
                    .foregroundColor(badge.isLocked ? .gray.opacity(0.8) : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 32)
                
                if !badge.isLocked {
                    Text(String(localized: "badge.status.unlocked"))
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    ProgressView(value: badge.progress)
                        .frame(height: 4)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                format: String(localized: badge.isLocked ? "badge.accessibility.locked" : "badge.accessibility.unlocked"),
                locale: AppLocalization.currentLocale,
                badge.title
            )
        )
        .accessibilityHint(badge.description)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Preview
struct BadgeGridItem_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            BadgeGridItem(
                badge: Badge(
                    id: "1",
                    title: "First Answer",
                    description: "Answer your first question",
                    icon: "1.circle",
                    isLocked: false,
                    requirement: "Answer 1 question",
                    progress: 1.0
                ),
                onTap: {}
            )
            .previewLayout(.sizeThatFits)
            .padding()
            
            BadgeGridItem(
                badge: Badge(
                    id: "2",
                    title: "Getting Started",
                    description: "Answer 5 questions",
                    icon: "star.fill",
                    isLocked: true,
                    requirement: "Answer 5 questions",
                    progress: 0.4
                ),
                onTap: {}
            )
            .previewLayout(.sizeThatFits)
            .padding()
            .preferredColorScheme(.dark)
        }
    }
}
