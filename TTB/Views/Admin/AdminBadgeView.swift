import SwiftUI

private enum AdminBadgeEditorSheet: Identifiable {
    case add
    case edit(String)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let badgeID):
            return "edit-\(badgeID)"
        }
    }
}

private enum AdminBadgeDestination: Hashable {
    case detail(String)
}

@MainActor
final class AdminBadgeViewModel: ObservableObject {
    @Published private(set) var badges: [Badge] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service: AdminBadgeService

    init(service: AdminBadgeService = AdminBadgeService()) {
        self.service = service
    }

    func loadBadges() async {
        isLoading = true
        defer { isLoading = false }

        do {
            badges = try await service.loadBadges()
            errorMessage = nil
        } catch {
            errorMessage = String(
                format: String(localized: "admin.badges.error.load"),
                locale: AppLocalization.currentLocale,
                error.localizedDescription
            )
        }
    }

    func deleteBadge(id: String) async -> Bool {
        do {
            try await service.deleteBadge(id: id)
            await loadBadges()
            return true
        } catch {
            errorMessage = String(
                format: String(localized: "admin.badges.error.delete"),
                locale: AppLocalization.currentLocale,
                error.localizedDescription
            )
            return false
        }
    }

    func saveBadge(_ badge: Badge) async -> Bool {
        do {
            try await service.saveBadge(badge)
            await loadBadges()
            return true
        } catch {
            errorMessage = String(
                format: String(localized: "admin.badges.error.save"),
                locale: AppLocalization.currentLocale,
                error.localizedDescription
            )
            return false
        }
    }

    func restoreDefaultBadges() async {
        do {
            _ = try await service.restoreDefaultBadges()
            await loadBadges()
        } catch {
            errorMessage = String(
                format: String(localized: "admin.badges.error.save"),
                locale: AppLocalization.currentLocale,
                error.localizedDescription
            )
        }
    }
}

struct AdminBadgeView: View {
    @EnvironmentObject private var categoryModel: CategoryModel
    @StateObject private var viewModel = AdminBadgeViewModel()

    @State private var editor: AdminBadgeEditorSheet?

    var body: some View {
        AdminAccessGuardView {
            Group {
                if viewModel.isLoading && viewModel.badges.isEmpty {
                    ProgressView(String(localized: "admin.badges.loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.badges.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(viewModel.badges) { badge in
                            NavigationLink(value: AdminBadgeDestination.detail(badge.id)) {
                                BadgeAdminRow(badge: badge)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.theme.background)
                }
            }
            .navigationTitle(String(localized: "admin.badges.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu(String(localized: "common.showMore"), systemImage: "ellipsis.circle") {
                        Button(String(localized: "admin.badges.add"), systemImage: "plus") {
                            editor = .add
                        }

                        Button(String(localized: "admin.badges.restoreDefaults"), systemImage: "arrow.counterclockwise") {
                            Task {
                                await viewModel.restoreDefaultBadges()
                            }
                        }
                    }
                }
            }
            .sheet(item: $editor) { editor in
                switch editor {
                case .add:
                    BadgeEditorSheet(
                        badge: nil,
                        onSave: { badge in
                            await viewModel.saveBadge(badge)
                        }
                    )
                    .environmentObject(categoryModel)

                case .edit(let badgeID):
                    Group {
                        if let badge = viewModel.badges.first(where: { $0.id == badgeID }) {
                            BadgeEditorSheet(
                                badge: badge,
                                onSave: { updatedBadge in
                                    await viewModel.saveBadge(updatedBadge)
                                }
                            )
                            .environmentObject(categoryModel)
                        } else {
                            ContentUnavailableView(
                                String(localized: "admin.badges.previewTitle"),
                                systemImage: "star.slash",
                                description: Text(String(localized: "admin.questions.missingBody"))
                            )
                        }
                    }
                }
            }
            .navigationDestination(for: AdminBadgeDestination.self) { destination in
                switch destination {
                case .detail(let badgeID):
                    Group {
                        if let badge = viewModel.badges.first(where: { $0.id == badgeID }) {
                            AdminBadgeDetailView(
                                badge: badge,
                                onEdit: {
                                    editor = .edit(badgeID)
                                },
                                onDelete: {
                                    await viewModel.deleteBadge(id: badgeID)
                                }
                            )
                            .environmentObject(categoryModel)
                        } else {
                            ContentUnavailableView(
                                String(localized: "admin.badges.previewTitle"),
                                systemImage: "star.slash",
                                description: Text(String(localized: "admin.questions.missingBody"))
                            )
                        }
                    }
                }
            }
            .alert(
                String(localized: "common.error.title"),
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .task {
                await viewModel.loadBadges()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "admin.badges.emptyTitle"), systemImage: "star.slash")
        } description: {
            Text(String(localized: "admin.badges.emptyBody"))
        } actions: {
            Button(String(localized: "admin.badges.restoreDefaults"), systemImage: "arrow.counterclockwise") {
                Task {
                    await viewModel.restoreDefaultBadges()
                }
            }

            Button(String(localized: "admin.badges.add"), systemImage: "plus") {
                editor = .add
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.theme.background)
    }
}

private struct BadgeAdminRow: View {
    @EnvironmentObject private var categoryModel: CategoryModel

    let badge: Badge

    var body: some View {
        HStack(spacing: 16) {
            BadgeIconCircle(
                badge: badge,
                circleSize: 52,
                symbolSize: 22,
                context: .adminPreview,
                lineWidth: 2
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(badge.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(badge.requirement)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    BadgeTypeTag(type: badge.type)

                    if let category = badge.category {
                        Text(categoryModel.title(for: category))
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct AdminBadgeDetailView: View {
    @EnvironmentObject private var categoryModel: CategoryModel
    @Environment(\.dismiss) private var dismiss

    let badge: Badge
    let onEdit: () -> Void
    let onDelete: () async -> Bool

    @State private var showingDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 20) {
                    BadgeIconCircle(
                        badge: badge,
                        circleSize: 92,
                        symbolSize: 42,
                        context: .adminPreview,
                        lineWidth: 2.5
                    )

                    VStack(spacing: 10) {
                        Text(badge.title)
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)

                        Text(badge.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.secondarySystemGroupedBackground))
                )

                VStack(alignment: .leading, spacing: 14) {
                    LabeledContent(String(localized: "admin.badges.form.requirement"), value: badge.requirement)

                    LabeledContent(String(localized: "admin.badges.form.type"), value: localizedTypeTitle)

                    if let category = badge.category {
                        LabeledContent(
                            String(localized: "admin.badges.form.category"),
                            value: categoryModel.title(for: category)
                        )
                    }

                    LabeledContent(
                        String(localized: "admin.badges.form.targetCount"),
                        value: "\(badge.targetCount)"
                    )
                }
                .font(.subheadline)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(.secondarySystemGroupedBackground))
                )

                VStack(spacing: 12) {
                    Button(String(localized: "common.edit"), systemImage: "pencil", action: onEdit)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)

                    Button(String(localized: "common.delete"), systemImage: "trash") {
                        showingDeleteConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .background(Color.theme.background)
        .navigationTitle(String(localized: "admin.badges.previewTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            String(localized: "common.delete"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                Task {
                    if await onDelete() {
                        dismiss()
                    }
                }
            }

            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "admin.badges.deleteMessage"))
        }
    }

    private var localizedTypeTitle: String {
        switch badge.type {
        case .total:
            return String(localized: "admin.badges.form.type.total")
        case .category:
            return String(localized: "admin.badges.form.type.category")
        case .streak:
            return String(localized: "admin.badges.form.type.streak")
        }
    }
}

private struct BadgeTypeTag: View {
    let type: BadgeType

    var body: some View {
        Text(typeTitle)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
            .foregroundStyle(foregroundColor)
    }

    private var typeTitle: String {
        switch type {
        case .total:
            return String(localized: "admin.badges.form.type.total")
        case .category:
            return String(localized: "admin.badges.form.type.category")
        case .streak:
            return String(localized: "admin.badges.form.type.streak")
        }
    }

    private var backgroundColor: Color {
        switch type {
        case .total:
            return Color.green.opacity(0.12)
        case .category:
            return Color.orange.opacity(0.12)
        case .streak:
            return Color.purple.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        switch type {
        case .total:
            return .green
        case .category:
            return .orange
        case .streak:
            return .purple
        }
    }
}

private struct BadgeEditorSheet: View {
    @EnvironmentObject private var categoryModel: CategoryModel
    @Environment(\.dismiss) private var dismiss

    let badge: Badge?
    let onSave: (Badge) async -> Bool

    @State private var badgeId = ""
    @State private var title = ""
    @State private var description = ""
    @State private var icon = "star.fill"
    @State private var requirement = ""
    @State private var targetCount = ""
    @State private var selectedType: BadgeType = .total
    @State private var category = Category.defaultCategories.first?.id ?? ""
    @State private var isSaving = false

    private var previewBadge: Badge {
        Badge(
            id: normalizedBadgeID.isEmpty ? "preview" : normalizedBadgeID,
            title: title.isEmpty ? String(localized: "admin.badges.form.preview") : title,
            description: description.isEmpty ? String(localized: "admin.badges.previewDescription") : description,
            icon: icon.isEmpty ? "star.fill" : icon,
            isLocked: true,
            requirement: requirement.isEmpty ? String(localized: "admin.badges.form.requirement") : requirement,
            progress: 0,
            targetCount: Int(targetCount) ?? 0,
            type: selectedType,
            category: selectedType == .category ? category : nil,
            titleLocalizations: [AppLocalization.currentLanguageCode: title],
            descriptionLocalizations: [AppLocalization.currentLanguageCode: description],
            requirementLocalizations: [AppLocalization.currentLanguageCode: requirement]
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "admin.badges.form.preview")) {
                    HStack(spacing: 16) {
                        BadgeIconCircle(
                            badge: previewBadge,
                            circleSize: 56,
                            symbolSize: 24,
                            context: .adminPreview,
                            lineWidth: 2
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(previewBadge.title)
                                .font(.headline)

                            Text(previewBadge.requirement)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(String(localized: "admin.badges.form.basic")) {
                    TextField(String(localized: "admin.badges.form.id"), text: $badgeId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(badge != nil)

                    TextField(String(localized: "admin.badges.form.title"), text: $title)

                    TextField(String(localized: "admin.badges.form.description"), text: $description, axis: .vertical)
                        .lineLimit(3...6)

                    TextField(String(localized: "admin.badges.form.icon"), text: $icon)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(String(localized: "admin.badges.form.requirements")) {
                    TextField(String(localized: "admin.badges.form.requirement"), text: $requirement, axis: .vertical)
                        .lineLimit(2...4)

                    TextField(String(localized: "admin.badges.form.targetCount"), text: $targetCount)
                        .keyboardType(.numberPad)

                    Picker(String(localized: "admin.badges.form.type"), selection: $selectedType) {
                        Text(String(localized: "admin.badges.form.type.total")).tag(BadgeType.total)
                        Text(String(localized: "admin.badges.form.type.category")).tag(BadgeType.category)
                        Text(String(localized: "admin.badges.form.type.streak")).tag(BadgeType.streak)
                    }

                    if selectedType == .category {
                        Picker(String(localized: "admin.badges.form.category"), selection: $category) {
                            ForEach(categoryModel.activeCategories) { category in
                                Text(category.displayName).tag(category.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle(badge == nil ? String(localized: "admin.badges.add") : String(localized: "admin.badges.edit"))
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
                            await saveBadge()
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .onAppear {
                configureInitialState()
            }
        }
    }

    private var normalizedBadgeID: String {
        let source = badge == nil ? badgeId : (badge?.id ?? badgeId)
        return source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !normalizedBadgeID.isEmpty
        && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !requirement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && Int(targetCount) != nil
    }

    private func configureInitialState() {
        if let badge {
            badgeId = badge.id
            title = badge.title
            description = badge.description
            icon = badge.icon
            requirement = badge.requirement
            targetCount = "\(badge.targetCount)"
            selectedType = badge.type
            category = badge.category ?? category
        } else if !categoryModel.activeCategories.contains(where: { $0.id == category }),
                  let firstCategory = categoryModel.activeCategories.first {
            category = firstCategory.id
        }
    }

    private func saveBadge() async {
        guard let parsedTargetCount = Int(targetCount) else { return }

        isSaving = true
        defer { isSaving = false }

        let badge = Badge(
            id: normalizedBadgeID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon.trimmingCharacters(in: .whitespacesAndNewlines),
            isLocked: true,
            requirement: requirement.trimmingCharacters(in: .whitespacesAndNewlines),
            progress: 0,
            targetCount: parsedTargetCount,
            type: selectedType,
            category: selectedType == .category ? category : nil,
            titleLocalizations: [AppLocalization.currentLanguageCode: title.trimmingCharacters(in: .whitespacesAndNewlines)],
            descriptionLocalizations: [AppLocalization.currentLanguageCode: description.trimmingCharacters(in: .whitespacesAndNewlines)],
            requirementLocalizations: [AppLocalization.currentLanguageCode: requirement.trimmingCharacters(in: .whitespacesAndNewlines)]
        )

        if await onSave(badge) {
            dismiss()
        }
    }

}

#Preview {
    NavigationStack {
        AdminBadgeView()
            .environmentObject(CategoryModel())
            .environmentObject(ProfileModel(userId: "preview"))
    }
}
