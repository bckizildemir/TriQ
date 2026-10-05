import SwiftUI

enum AdminAccessState {
    case checking
    case granted
    case denied
}

struct AdminAccessGuardView<Content: View>: View {
    @EnvironmentObject private var profileModel: ProfileModel

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var accessState: AdminAccessState {
        if profileModel.isAdmin {
            return .granted
        }

        if profileModel.isLoading {
            return .checking
        }

        return .denied
    }

    var body: some View {
        Group {
            switch accessState {
            case .checking:
                ProgressView(String(localized: "common.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .granted:
                content

            case .denied:
                ContentUnavailableView(
                    String(localized: "admin.access.deniedTitle"),
                    systemImage: "lock.slash",
                    description: Text(String(localized: "admin.access.deniedBody"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
