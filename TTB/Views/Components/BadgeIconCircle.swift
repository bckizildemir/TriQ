import SwiftUI

struct BadgeIconCircle: View {
  let badge: Badge
  let circleSize: CGFloat
  let symbolSize: CGFloat
  var context: BadgeVisualStyle.Context = .live
  var symbolWeight: Font.Weight = .medium
  var lineWidth: CGFloat = 1.5

  private var style: BadgeVisualStyle {
    BadgeVisualStyle(badge: badge, context: context)
  }

  var body: some View {
    Image(systemName: badge.icon)
      .symbolRenderingMode(.monochrome)
      .font(.system(size: symbolSize, weight: symbolWeight))
      .foregroundStyle(style.iconTint)
      .frame(width: circleSize, height: circleSize)
      .background {
        Circle()
          .fill(style.circleFill)
      }
      .overlay {
        Circle()
          .stroke(style.circleStroke, lineWidth: lineWidth)
      }
  }
}
