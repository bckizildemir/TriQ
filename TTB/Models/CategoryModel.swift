import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftUI

@MainActor
final class CategoryModel: ObservableObject {
    @Published private(set) var categories: [Category] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service: CategoryService?
    private var listener: ListenerRegistration?

    init(service: CategoryService = CategoryService()) {
        self.service = service
        listen()
    }

    init(localCategories: [Category]) {
        service = nil
        categories = localCategories
        isLoading = false
    }

    /// `isolated` so the cleanup can read the main-actor listener handles. Below iOS 18.4 the
    /// compiler links a main-actor back-deploy shim, so this needs no deployment-target change.
    isolated deinit {
        listener?.remove()
    }

    #if DEBUG
    /// Puts the given registration where the Firestore listener lives, so a test can see `deinit`
    /// remove it without a live `CategoryService`.
    func installListenerForTesting(_ registration: any ListenerRegistration) {
        listener = registration
    }
    #endif

    var activeCategories: [Category] {
        // Deliberately left un-decorated: `displayName` only resolves localized text on the rare
        // equal-`sortOrder` tie-break, and it is cheap now that `AppLocalization` memoizes the
        // preferred-language list. Hoisting the names into a decorated array measured *slower*
        // (3 ms -> 16 ms per 100 calls) because copying the extra structs cost more than it saved.
        let fetched = categories
            .filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.sortOrder < rhs.sortOrder
            }

        return fetched.isEmpty ? Category.defaultCategories : fetched
    }

    func category(for id: String) -> Category {
        categories.first(where: { $0.id == id }) ?? Category.fallbackCategory(for: id)
    }

    func title(for id: String) -> String {
        category(for: id).displayName
    }

    func iconName(for id: String) -> String {
        category(for: id).iconSystemName
    }

    func colorToken(for id: String) -> CategoryColorToken {
        category(for: id).colorToken
    }

    func color(for id: String) -> Color {
        colorToken(for: id).color
    }

    func refresh() async {
        guard let service else { return }

        do {
            categories = try await service.fetchCategories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func seedDefaultsIfNeeded() async throws {
        guard let service else { return }
        try await service.seedDefaultCategoriesIfNeeded(
            createdBy: Auth.auth().currentUser?.uid
        )
    }

    private func listen() {
        guard let service else { return }
        isLoading = true
        listener?.remove()
        listener = service.listenToCategories { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let categories):
                    self.categories = categories
                    self.errorMessage = nil
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
