import FirebaseAuth
import SwiftUI

private enum AdminQuestionSheet: Identifiable {
    case add
    case edit(String)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let questionID):
            return "edit-\(questionID)"
        }
    }
}

private enum AdminQuestionDestination: Hashable {
    case detail(String)
}

private enum AdminQuestionFilter: String, CaseIterable, Identifiable {
    case pending
    case approved
    case rejected
    case seeded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending:
            return "Pending"
        case .approved:
            return "Approved"
        case .rejected:
            return "Rejected"
        case .seeded:
            return "Seeded"
        }
    }
}

struct AdminQuestionView: View {
    @EnvironmentObject private var categoryModel: CategoryModel

    /// Owned here rather than injected, because `ProfileView` builds this screen inside a
    /// `navigationDestination` that SwiftUI re-evaluates on every parent update. A store handed in from
    /// there would be replaced on each pass and lose the corpus it just fetched.
    @StateObject private var moderation = QuestionModerationStore(service: QuestionService())

    @State private var searchText = ""
    @State private var editor: AdminQuestionSheet?
    @State private var selectedFilter: AdminQuestionFilter = .pending
    @State private var rejectingQuestion: Question?
    @State private var deletingQuestion: Question?
    @State private var alertMessage = ""
    @State private var showingError = false

    // `allQuestions` re-sorts the whole corpus on every read. Sort only the questions that survive
    // filtering, and count over the unsorted cache — one pass instead of the four full sorts a single
    // body evaluation used to trigger (twice for the list, once for the category count, once for the
    // total).
    private var filteredQuestions: [Question] {
        let questions = moderation.questions.filter(matchesSelectedFilter)

        let matching: [Question]
        if searchText.isEmpty {
            matching = questions
        } else {
            matching = questions.filter { question in
                question.text.localizedCaseInsensitiveContains(searchText)
                || categoryModel.title(for: question.category).localizedCaseInsensitiveContains(searchText)
            }
        }

        return matching.sorted { $0.createdAt > $1.createdAt }
    }

    private var uniqueCategories: [String] {
        Array(Set(moderation.questions.map(\.category)))
    }

    private var searchPlaceholder: String {
        String(
            format: String(localized: "admin.questions.search"),
            locale: AppLocalization.currentLocale,
            uniqueCategories.count,
            moderation.questions.count
        )
    }

    private func matchesSelectedFilter(_ question: Question) -> Bool {
        switch selectedFilter {
        case .pending:
            return question.source == .userCreated && question.moderationStatus == .pending
        case .approved:
            return question.source == .userCreated && question.moderationStatus == .approved
        case .rejected:
            return question.source == .userCreated && question.moderationStatus == .rejected
        case .seeded:
            return question.source == .seeded
        }
    }

    var body: some View {
        AdminAccessGuardView {
            Group {
                List {
                    Section {
                        Picker("Question status", selection: $selectedFilter) {
                            ForEach(AdminQuestionFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowBackground(Color.clear)

                    if filteredQuestions.isEmpty {
                        emptyState
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredQuestions) { question in
                            NavigationLink(value: AdminQuestionDestination.detail(question.id)) {
                                AdminQuestionRow(question: question)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if question.source == .userCreated && question.moderationStatus == .pending {
                                    Button("Approve") {
                                        Task { await approveQuestion(question) }
                                    }
                                    .tint(.green)

                                    Button("Reject") {
                                        rejectingQuestion = question
                                    }
                                    .tint(.orange)
                                }

                                Button("Delete", role: .destructive) {
                                    deletingQuestion = question
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.theme.background)
            }
            .navigationTitle(String(localized: "admin.questions.title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: searchPlaceholder)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "admin.questions.add"), systemImage: "plus") {
                        editor = .add
                    }
                }
            }
            .task {
                await refresh()
            }
            .sheet(item: $editor) { editor in
                switch editor {
                case .add:
                    AddQuestionView(moderation: moderation)
                        .environmentObject(categoryModel)

                case .edit(let questionID):
                    Group {
                        if let question = moderation.question(withID: questionID) {
                            EditQuestionView(moderation: moderation, question: question)
                                .environmentObject(categoryModel)
                        } else {
                            ContentUnavailableView(
                                String(localized: "admin.questions.missingTitle"),
                                systemImage: "questionmark.bubble",
                                description: Text(String(localized: "admin.questions.missingBody"))
                            )
                        }
                    }
                }
            }
            .sheet(item: $rejectingQuestion) { question in
                RejectQuestionView(question: question) { reason in
                    await rejectQuestion(question, reason: reason)
                }
            }
            .confirmationDialog(
                String(localized: "admin.questions.delete"),
                isPresented: Binding(
                    get: { deletingQuestion != nil },
                    set: { isPresented in
                        if !isPresented {
                            deletingQuestion = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button(String(localized: "common.delete"), role: .destructive) {
                    guard let deletingQuestion else { return }
                    Task { await deleteQuestion(deletingQuestion) }
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "admin.questions.deleteMessage"))
            }
            .alert(String(localized: "common.error.title"), isPresented: $showingError) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .navigationDestination(for: AdminQuestionDestination.self) { destination in
                switch destination {
                case .detail(let questionID):
                    AdminQuestionDetailView(
                        questionID: questionID,
                        onEdit: {
                            editor = .edit(questionID)
                        }
                    )
                    .environmentObject(categoryModel)
                    .environmentObject(moderation)
                }
            }
        }
    }

    private var emptyState: some View {
        Group {
            if searchText.isEmpty {
                ContentUnavailableView(
                    String(localized: "admin.questions.emptyTitle"),
                    systemImage: "questionmark.bubble",
                    description: Text(String(localized: "admin.questions.emptyBody"))
                )
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.theme.background)
    }

    /// The refresh failure now reaches this screen's own alert. `refreshAdminQuestions` used to write it
    /// into `QuestionModel.error`, which nothing here reads — `CategoryQuestionsView` alerts on that.
    private func refresh() async {
        do {
            try await moderation.refresh()
        } catch {
            presentError(error)
        }
    }

    private func approveQuestion(_ question: Question) async {
        do {
            try await moderation.approve(question)
        } catch {
            presentError(error)
        }
    }

    private func rejectQuestion(_ question: Question, reason: String?) async {
        do {
            try await moderation.reject(question, reason: reason)
        } catch {
            presentError(error)
        }
    }

    private func deleteQuestion(_ question: Question) async {
        do {
            try await moderation.delete(question)
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        alertMessage = error.localizedDescription
        showingError = true
    }
}

private struct AdminQuestionRow: View {
    @EnvironmentObject private var categoryModel: CategoryModel

    let question: Question

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question.text)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Label(categoryModel.title(for: question.category), systemImage: categoryModel.iconName(for: question.category))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(question.moderationStatus.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusTint.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusTint)

                if let username = question.creatorAttributionUsername {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let createdBy = question.createdBy, !createdBy.isEmpty {
                    Text(createdBy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text(question.trioCreatedAtString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var statusTint: Color {
        switch question.moderationStatus {
        case .pending:
            return .orange
        case .approved:
            return .green
        case .rejected:
            return .red
        }
    }
}

private struct AdminQuestionDetailView: View {
    @EnvironmentObject private var categoryModel: CategoryModel
    @EnvironmentObject private var moderation: QuestionModerationStore
    @Environment(\.dismiss) private var dismiss

    let questionID: String
    let onEdit: () -> Void

    @State private var showingDeleteConfirmation = false
    @State private var showingRejectSheet = false
    @State private var alertMessage = ""
    @State private var showingError = false

    private var question: Question? {
        moderation.question(withID: questionID)
    }

    var body: some View {
        Group {
            if let question {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(question.text)
                                .font(.title3.bold())
                                .foregroundStyle(.primary)

                            Label(categoryModel.title(for: question.category), systemImage: categoryModel.iconName(for: question.category))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            LabeledContent("Source", value: question.source.rawValue)
                                .font(.subheadline)

                            LabeledContent("Moderation", value: question.moderationStatus.rawValue.capitalized)
                                .font(.subheadline)

                            if let username = question.creatorAttributionUsername {
                                LabeledContent("Creator", value: "@\(username)")
                                    .font(.subheadline)
                            }

                            if let createdBy = question.createdBy, !createdBy.isEmpty {
                                LabeledContent(String(localized: "admin.questions.createdBy"), value: createdBy)
                                    .font(.subheadline)
                            }

                            if let moderatedBy = question.moderatedBy, !moderatedBy.isEmpty {
                                LabeledContent("Moderated by", value: moderatedBy)
                                    .font(.subheadline)
                            }

                            if let moderatedAt = question.moderatedAt {
                                LabeledContent("Moderated", value: moderatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                            }

                            if let rejectionReason = question.rejectionReason, !rejectionReason.isEmpty {
                                LabeledContent("Rejection reason", value: rejectionReason)
                                    .font(.subheadline)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )

                        VStack(spacing: 12) {
                            if question.source == .userCreated {
                                moderationActions(for: question)
                            }

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
                .navigationTitle(String(localized: "admin.questions.details"))
                .navigationBarTitleDisplayMode(.inline)
                .confirmationDialog(
                    String(localized: "admin.questions.delete"),
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "common.delete"), role: .destructive) {
                        Task {
                            await deleteQuestion(question)
                        }
                    }

                    Button(String(localized: "common.cancel"), role: .cancel) {}
                } message: {
                    Text(String(localized: "admin.questions.deleteMessage"))
                }
                .sheet(isPresented: $showingRejectSheet) {
                    RejectQuestionView(question: question) { reason in
                        await rejectQuestion(question, reason: reason)
                    }
                }
                .alert(String(localized: "common.error.title"), isPresented: $showingError) {
                    Button(String(localized: "common.ok"), role: .cancel) {}
                } message: {
                    Text(alertMessage)
                }
            } else {
                ContentUnavailableView(
                    String(localized: "admin.questions.missingTitle"),
                    systemImage: "questionmark.bubble",
                    description: Text(String(localized: "admin.questions.missingBody"))
                )
            }
        }
    }

    @ViewBuilder
    private func moderationActions(for question: Question) -> some View {
        if question.moderationStatus != .approved {
            Button("Approve", systemImage: "checkmark.circle") {
                Task { await approveQuestion(question) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .frame(maxWidth: .infinity)
        }

        if question.moderationStatus != .rejected {
            Button("Reject", systemImage: "xmark.circle") {
                showingRejectSheet = true
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .frame(maxWidth: .infinity)
        }

        if question.moderationStatus == .approved {
            Button(
                question.isFeaturedOnHome ? "Remove from Home" : "Feature on Home",
                systemImage: question.isFeaturedOnHome ? "house.slash" : "house"
            ) {
                Task {
                    await setFeaturedPlacement(
                        question.isFeaturedOnHome ? .none : .home,
                        for: question
                    )
                }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
    }

    private func approveQuestion(_ question: Question) async {
        do {
            try await moderation.approve(question)
        } catch {
            presentError(error)
        }
    }

    private func rejectQuestion(_ question: Question, reason: String?) async {
        do {
            try await moderation.reject(question, reason: reason)
        } catch {
            presentError(error)
        }
    }

    private func setFeaturedPlacement(_ placement: QuestionFeaturedPlacement, for question: Question) async {
        do {
            try await moderation.setFeaturedPlacement(placement, for: question)
        } catch {
            presentError(error)
        }
    }

    private func deleteQuestion(_ question: Question) async {
        do {
            try await moderation.delete(question)
            dismiss()
        } catch {
            alertMessage = String(
                format: String(localized: "admin.questions.error.delete"),
                locale: AppLocalization.currentLocale,
                error.localizedDescription
            )
            showingError = true
        }
    }

    private func presentError(_ error: Error) {
        alertMessage = error.localizedDescription
        showingError = true
    }
}

private struct RejectQuestionView: View {
    @Environment(\.dismiss) private var dismiss

    let question: Question
    let onReject: (String?) async -> Void

    @State private var reason = ""
    @State private var isRejecting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    Text(question.text)
                }

                Section("Reason") {
                    TextField("Optional reason", text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Reject Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                    .disabled(isRejecting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Reject") {
                        Task {
                            isRejecting = true
                            await onReject(reason.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
                            isRejecting = false
                            dismiss()
                        }
                    }
                    .disabled(isRejecting)
                }
            }
        }
    }
}

struct AddQuestionView: View {
    @EnvironmentObject private var categoryModel: CategoryModel
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var moderation: QuestionModerationStore

    @State private var questionText = ""
    @State private var selectedCategory = Category.defaultCategories.first?.id ?? ""
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "admin.questions.details")) {
                    TextField(String(localized: "admin.questions.field.text"), text: $questionText, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel(String(localized: "admin.questions.field.textAccessibility"))

                    Picker(String(localized: "admin.questions.field.category"), selection: $selectedCategory) {
                        ForEach(categoryModel.activeCategories) { category in
                            Text(category.displayName)
                                .tag(category.id)
                        }
                    }
                    .accessibilityLabel(String(localized: "admin.questions.field.categoryAccessibility"))
                }
            }
            .navigationTitle(String(localized: "admin.questions.add"))
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
                            await submitQuestion()
                        }
                    }
                    .disabled(questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
            .alert(String(localized: "common.error.title"), isPresented: $showAlert) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                if !categoryModel.activeCategories.contains(where: { $0.id == selectedCategory }),
                   let firstCategory = categoryModel.activeCategories.first {
                    selectedCategory = firstCategory.id
                }
            }
        }
    }

    private func submitQuestion() async {
        guard let currentUser = Auth.auth().currentUser else {
            alertMessage = String(localized: "question.error.notAuthenticated")
            showAlert = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        let trimmedText = questionText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let newQuestion = Question(
                id: UUID().uuidString,
                text: trimmedText,
                category: selectedCategory,
                localizedTexts: [AppLocalization.currentLanguageCode: trimmedText],
                languageCode: AppLocalization.currentLanguageCode,
                source: .seeded,
                answers: Array(repeating: "", count: 3),
                isFavorite: false,
                createdAt: Date(),
                createdBy: currentUser.uid,
                isAnnounced: false
            )

            try await moderation.add(newQuestion)
            dismiss()
        } catch {
            alertMessage = String(
                format: String(localized: "admin.questions.error.add"),
                locale: AppLocalization.currentLocale,
                error.localizedDescription
            )
            showAlert = true
        }
    }
}

struct EditQuestionView: View {
    @EnvironmentObject private var categoryModel: CategoryModel
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var moderation: QuestionModerationStore

    let question: Question

    @State private var questionText = ""
    @State private var selectedCategory = ""
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "admin.questions.details")) {
                    TextField(String(localized: "admin.questions.field.text"), text: $questionText, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel(String(localized: "admin.questions.field.textAccessibility"))

                    Picker(String(localized: "admin.questions.field.category"), selection: $selectedCategory) {
                        ForEach(categoryModel.activeCategories) { category in
                            Text(category.displayName)
                                .tag(category.id)
                        }
                    }
                    .accessibilityLabel(String(localized: "admin.questions.field.categoryAccessibility"))
                }
            }
            .navigationTitle(String(localized: "admin.questions.edit"))
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
                            await submitEditedQuestion()
                        }
                    }
                    .disabled(questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
            .alert(String(localized: "common.error.title"), isPresented: $showAlert) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                questionText = question.text
                selectedCategory = question.category
            }
        }
    }

    private func submitEditedQuestion() async {
        isLoading = true
        defer { isLoading = false }

        let trimmedText = questionText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await moderation.edit(
                question,
                newText: trimmedText,
                newCategory: selectedCategory,
                languageCode: AppLocalization.currentLanguageCode
            )
            dismiss()
        } catch {
            alertMessage = String(
                format: String(localized: "admin.questions.error.edit"),
                locale: AppLocalization.currentLocale,
                error.localizedDescription
            )
            showAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        AdminQuestionView()
            .environmentObject(CategoryModel())
            .environmentObject(ProfileModel(userId: "preview"))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
