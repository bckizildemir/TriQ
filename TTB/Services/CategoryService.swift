import FirebaseAuth
import FirebaseFirestore
import Foundation

protocol CategoryReading {
    func fetchCategories(ids: [String]) async throws -> [Category]
}

final class CategoryService {
    private let db = Firestore.firestore()

    func listenToCategories(
        completion: @escaping (Result<[Category], Error>) -> Void
    ) -> ListenerRegistration {
        db.collection("categories")
            .order(by: "sortOrder")
            .addSnapshotListener { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let categories = snapshot?.documents.map { document in
                    Category.fromFirestore(document.data(), id: document.documentID)
                } ?? []

                completion(.success(categories))
            }
    }

    func fetchCategories() async throws -> [Category] {
        let snapshot = try await db.collection("categories")
            .order(by: "sortOrder")
            .getDocuments()

        return snapshot.documents.map { document in
            Category.fromFirestore(document.data(), id: document.documentID)
        }
    }

    func saveCategory(_ category: Category) async throws {
        try await db.collection("categories")
            .document(category.id)
            .setData(category.toFirestore(), merge: true)
    }

    func deleteCategory(id: String) async throws {
        try await db.collection("categories")
            .document(id)
            .delete()
    }

    func seedDefaultCategoriesIfNeeded(createdBy: String?) async throws {
        let batch = db.batch()
        var hasWork = false

        for category in Category.defaultCategories {
            let ref = db.collection("categories").document(category.id)
            let snapshot = try await ref.getDocument()
            guard !snapshot.exists else { continue }

            var seeded = category
            if let createdBy {
                seeded = Category(
                    id: category.id,
                    localizedNames: category.localizedNames,
                    iconSystemName: category.iconSystemName,
                    colorToken: category.colorToken,
                    sortOrder: category.sortOrder,
                    isActive: category.isActive,
                    isAnnounced: false,
                    createdAt: category.createdAt,
                    updatedAt: Date(),
                    createdBy: createdBy
                )
            } else {
                seeded = Category(
                    id: category.id,
                    localizedNames: category.localizedNames,
                    iconSystemName: category.iconSystemName,
                    colorToken: category.colorToken,
                    sortOrder: category.sortOrder,
                    isActive: category.isActive,
                    isAnnounced: false,
                    createdAt: category.createdAt
                )
            }

            batch.setData(seeded.toFirestore(), forDocument: ref, merge: true)
            hasWork = true
        }

        if hasWork {
            try await batch.commit()
        }
    }

    func fetchCategories(ids: [String]) async throws -> [Category] {
        let uniqueIDs = Array(Set(ids))
        guard !uniqueIDs.isEmpty else { return [] }

        var categories: [Category] = []
        for chunk in uniqueIDs.chunked(into: 10) {
            let snapshot = try await db.collection("categories")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()

            categories.append(
                contentsOf: snapshot.documents.map { document in
                    Category.fromFirestore(document.data(), id: document.documentID)
                }
            )
        }

        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }
}

extension CategoryService: CategoryReading {}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
