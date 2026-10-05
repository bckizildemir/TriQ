import SwiftUI

extension Backport where Content == Any {
    struct ToolbarSpacer: ToolbarContent {
        private let placement: ToolbarItemPlacement

        init(placement: ToolbarItemPlacement = .automatic) {
            self.placement = placement
        }

        var body: some ToolbarContent {
            if #available(iOS 26.0, *) {
                SwiftUI.ToolbarSpacer(placement: placement)
            }
        }
    }
}
