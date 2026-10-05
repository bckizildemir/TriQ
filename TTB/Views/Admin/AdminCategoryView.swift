import FirebaseAuth
import SwiftUI

private enum AdminCategoryEditorSheet: Identifiable {
    case add
    case edit(String)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let categoryID):
            return "edit-\(categoryID)"
        }
    }
}

struct AdminCategoryView: View {
    @EnvironmentObject private var categoryModel: CategoryModel

    @State private var editor: AdminCategoryEditorSheet?
    @State private var categoryPendingDelete: Category?
    @State private var alertMessage = ""
    @State private var showingAlert = false

    private let service = CategoryService()

    private var allCategories: [Category] {
        let categories = categoryModel.categories.isEmpty
            ? Category.defaultCategories
            : categoryModel.categories

        return categories.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

            return lhs.sortOrder < rhs.sortOrder
        }
    }

    var body: some View {
        AdminAccessGuardView {
            List {
                ForEach(allCategories) { category in
                    Button {
                        editor = .edit(category.id)
                    } label: {
                        AdminCategoryRow(category: category)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(String(localized: "common.delete"), systemImage: "trash", role: .destructive) {
                            categoryPendingDelete = category
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.theme.background)
            .navigationTitle(String(localized: "admin.categories.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu(String(localized: "common.showMore"), systemImage: "ellipsis.circle") {
                        Button(String(localized: "admin.categories.add"), systemImage: "plus") {
                            editor = .add
                        }

                        Button(String(localized: "admin.categories.seedDefaults"), systemImage: "square.stack.3d.up") {
                            Task {
                                await seedDefaults()
                            }
                        }
                    }
                }
            }
            .sheet(item: $editor) { editor in
                switch editor {
                case .add:
                    CategoryEditorSheet(category: nil) { category in
                        await saveCategory(category)
                    }

                case .edit(let categoryID):
                    Group {
                        if let category = allCategories.first(where: { $0.id == categoryID }) {
                            CategoryEditorSheet(category: category) { updatedCategory in
                                await saveCategory(updatedCategory)
                            }
                        } else {
                            ContentUnavailableView(
                                String(localized: "admin.categories.title"),
                                systemImage: "square.grid.2x2",
                                description: Text(String(localized: "admin.questions.missingBody"))
                            )
                        }
                    }
                }
            }
            .confirmationDialog(
                String(localized: "common.delete"),
                isPresented: Binding(
                    get: { categoryPendingDelete != nil },
                    set: { if !$0 { categoryPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(String(localized: "common.delete"), role: .destructive) {
                    Task {
                        await deleteSelectedCategory()
                    }
                }

                Button(String(localized: "common.cancel"), role: .cancel) {
                    categoryPendingDelete = nil
                }
            } message: {
                Text(String(localized: "admin.categories.deleteMessage"))
            }
            .alert(String(localized: "admin.categories.errorTitle"), isPresented: $showingAlert) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func seedDefaults() async {
        do {
            try await categoryModel.seedDefaultsIfNeeded()
            await categoryModel.refresh()
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }

    private func saveCategory(_ category: Category) async -> Bool {
        do {
            try await service.saveCategory(category)
            await categoryModel.refresh()
            return true
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
            return false
        }
    }

    private func deleteSelectedCategory() async {
        guard let category = categoryPendingDelete else { return }
        defer { categoryPendingDelete = nil }

        do {
            try await service.deleteCategory(id: category.id)
            await categoryModel.refresh()
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }
}

private struct AdminCategoryRow: View {
    let category: Category

    private var categoryColor: Color {
        category.colorToken.color
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: category.iconSystemName)
                .font(.title3)
                .foregroundStyle(categoryColor)
                .frame(width: 44, height: 44)
                .background(categoryColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text(category.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(category.id)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(category.isActive ? String(localized: "admin.categories.status.active") : String(localized: "admin.categories.status.inactive"))
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusBackground, in: Capsule())
                    .foregroundStyle(statusForeground)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var statusBackground: Color {
        category.isActive ? Color.green.opacity(0.12) : Color.orange.opacity(0.12)
    }

    private var statusForeground: Color {
        category.isActive ? .green : .orange
    }
}

private struct CategoryEditorSheet: View {
    let category: Category?
    let onSave: (Category) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var id = ""
    @State private var nameEN = ""
    @State private var nameTR = ""
    @State private var iconName = "square.grid.2x2"
    @State private var colorToken: CategoryColorToken = .systemBlue
    @State private var sortOrder = 0
    @State private var isActive = true
    @State private var isSaving = false

    private let colorColumns = [
        GridItem(.adaptive(minimum: 44), spacing: 14)
    ]

    private let iconColumns = [
        GridItem(.adaptive(minimum: 46), spacing: 12)
    ]

    private let iconOptions = [
        "list.bullet",
        "face.smiling",
        "bookmark.fill",
        "mappin",
        "gift.fill",
        "birthday.cake.fill",
        "graduationcap.fill",
        "backpack.fill",
        "pencil.and.ruler.fill",
        "doc.fill",
        "book.fill",
        "tray.fill",
        "creditcard.fill",
        "banknote.fill",
        "dumbbell.fill",
        "figure.run",
        "fork.knife",
        "wineglass.fill",
        "heart.text.square.fill",
        "house.fill",
        "building.2.fill",
        "briefcase.fill",
        "heart.fill",
        "person.2.fill",
        "calendar",
        "flag.fill",
        "paintbrush.fill",
        "brain.head.profile",
        "sparkles",
        "leaf.fill",
        "airplane",
        "car.fill",
        "gamecontroller.fill",
        "music.note"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: iconName)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(colorToken.color, in: Circle())
                            .shadow(color: colorToken.color.opacity(0.3), radius: 10, y: 4)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(nameEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? normalizedID : nameEN)
                                .font(.headline)
                                .foregroundStyle(colorToken.color)

                            Text(colorToken.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        String(
                            format: String(localized: "admin.categories.form.previewAccessibility"),
                            locale: AppLocalization.currentLocale,
                            colorToken.displayName
                        )
                    )
                }

                Section(String(localized: "admin.categories.form.identity")) {
                    TextField(String(localized: "admin.categories.form.id"), text: $id)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(category != nil)

                    TextField(String(localized: "admin.categories.form.title.en"), text: $nameEN)
                    TextField(String(localized: "admin.categories.form.title.tr"), text: $nameTR)
                    Stepper(
                        String(
                            format: String(localized: "admin.categories.form.sortOrder"),
                            locale: AppLocalization.currentLocale,
                            sortOrder
                        ),
                        value: $sortOrder,
                        in: 0...100
                    )
                    Toggle(String(localized: "admin.categories.form.active"), isOn: $isActive)
                }

                Section(String(localized: "admin.categories.form.color")) {
                    LazyVGrid(columns: colorColumns, spacing: 16) {
                        ForEach(CategoryColorToken.allCases, id: \.self) { token in
                            Button {
                                colorToken = token
                            } label: {
                                colorSwatch(token)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(token.displayName)
                            .accessibilityAddTraits(colorToken == token ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section(String(localized: "admin.categories.form.icon")) {
                    LazyVGrid(columns: iconColumns, spacing: 12) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                iconName = icon
                            } label: {
                                iconCell(icon)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(icon)
                            .accessibilityAddTraits(iconName == icon ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(
                category == nil
                ? String(localized: "admin.categories.add")
                : String(localized: "common.edit")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) {
                        Task {
                            await saveCategory()
                        }
                    }
                    .disabled(normalizedID.isEmpty || nameEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear {
                guard let category else { return }
                id = category.id
                nameEN = category.localizedNames["en"] ?? category.displayName
                nameTR = category.localizedNames["tr"] ?? category.displayName
                iconName = category.iconSystemName
                colorToken = category.colorToken
                sortOrder = category.sortOrder
                isActive = category.isActive
            }
        }
    }

    private func colorSwatch(_ token: CategoryColorToken) -> some View {
        Circle()
            .fill(token.color)
            .frame(width: 38, height: 38)
            .overlay {
                if colorToken == token {
                    Circle()
                        .stroke(Color(uiColor: .systemBackground), lineWidth: 4)
                    Circle()
                        .stroke(token.color, lineWidth: 2)
                        .padding(-5)
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
    }

    private func iconCell(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(iconName == icon ? .white : Color.primary.opacity(0.72))
            .frame(width: 44, height: 44)
            .background(
                Circle()
                    .fill(iconName == icon ? colorToken.color : Color(uiColor: .tertiarySystemGroupedBackground))
            )
            .overlay {
                Circle()
                    .stroke(iconName == icon ? colorToken.color.opacity(0.4) : Color.theme.border.opacity(0.16), lineWidth: 1)
            }
            .contentShape(Circle())
    }

    private var normalizedID: String {
        let source = category == nil ? id : (category?.id ?? id)
        return source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
    }

    private func saveCategory() async {
        isSaving = true
        defer { isSaving = false }

        let category = Category(
            id: normalizedID,
            localizedNames: [
                "en": nameEN.trimmingCharacters(in: .whitespacesAndNewlines),
                "tr": nameTR.trimmingCharacters(in: .whitespacesAndNewlines),
            ],
            iconSystemName: iconName.trimmingCharacters(in: .whitespacesAndNewlines),
            colorToken: colorToken,
            sortOrder: sortOrder,
            isActive: isActive,
            isAnnounced: self.category?.isAnnounced ?? false,
            createdAt: self.category?.createdAt ?? Date(),
            updatedAt: Date(),
            createdBy: self.category?.createdBy ?? Auth.auth().currentUser?.uid,
            announcedAt: self.category?.announcedAt,
            announcedInReleaseId: self.category?.announcedInReleaseId
        )

        if await onSave(category) {
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        AdminCategoryView()
            .environmentObject(CategoryModel())
            .environmentObject(ProfileModel(userId: "preview"))
    }
}
