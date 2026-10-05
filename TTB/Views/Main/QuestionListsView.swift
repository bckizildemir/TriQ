import SwiftUI

struct QuestionListsContentView: View {
    @EnvironmentObject private var authModel: AuthModel
    @EnvironmentObject private var questionListStore: QuestionListStore
    @EnvironmentObject private var sharedQuestionListStore: SharedQuestionListStore
    @EnvironmentObject private var questionModel: QuestionModel

    private enum ListScope: String, CaseIterable, Identifiable {
        case mine
        case shared

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mine:
                return "Lists"
            case .shared:
                return "Shared"
            }
        }
    }

    @State private var editorMode: QuestionListEditorView.Mode?
    @State private var listToDelete: QuestionList?
    @State private var selectedScope: ListScope = .mine
    @State private var activeDetailSheet: QuestionListDetailSheet?
    @State private var isShowingDeleteAlert = false
    @State private var isShowingErrorAlert = false

    private let presentExternalDetailSheet: ((QuestionListDetailSheet) -> Void)?

    init(presentDetailSheet: ((QuestionListDetailSheet) -> Void)? = nil) {
        presentExternalDetailSheet = presentDetailSheet
    }

    var body: some View {
        VStack(spacing: 0) {
            if canManageLists {
                Picker("Question list scope", selection: $selectedScope) {
                    ForEach(ListScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            content
        }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "questionLists.title"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if canManageLists {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer()

                        Button {
                            editorMode = .create
                        } label: {
                            Label(String(localized: "questionLists.create"), systemImage: "plus")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityLabel(String(localized: "questionLists.create"))
                    }
                }
            }
            .sheet(item: $editorMode) { mode in
                NavigationStack {
                    QuestionListEditorView(mode: mode)
                }
            }
            .modifier(
                QuestionListDetailSheetPresenter(
                    activeSheet: $activeDetailSheet,
                    isEnabled: presentExternalDetailSheet == nil
                )
            )
            .onChange(of: listToDelete?.id) { _, newValue in
                isShowingDeleteAlert = newValue != nil
            }
            .onChange(of: questionListStore.error) { _, newValue in
                isShowingErrorAlert = newValue != nil
            }
            .alert(
                String(localized: "questionLists.delete.title"),
                isPresented: $isShowingDeleteAlert
            ) {
                Button(String(localized: "common.cancel"), role: .cancel) { listToDelete = nil }
                Button(String(localized: "common.delete"), role: .destructive, action: deleteSelectedList)
            } message: {
                Text(String(localized: "questionLists.delete.message"))
            }
            .alert(
                String(localized: "common.error.title"),
                isPresented: $isShowingErrorAlert,
                actions: {
                    Button(String(localized: "common.ok")) { questionListStore.error = nil }
                },
                message: {
                    if let error = questionListStore.error {
                        Text(error)
                    }
                }
            )
    }

    @ViewBuilder
    private var content: some View {
        if authModel.isAnonymous {
            guestState
        } else if selectedScope == .shared {
            QuestionListSharesHubView()
        } else if questionListStore.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if questionListStore.lists.isEmpty {
            emptyState
        } else {
            listsView
        }
    }

    private var canManageLists: Bool {
        authModel.isAuthenticated && !authModel.isAnonymous
    }

    private var guestState: some View {
        ContentUnavailableView {
            Label(String(localized: "questionLists.guest.title"), systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text(String(localized: "questionLists.guest.body"))
        }
        .padding()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "questionLists.empty.title"), systemImage: "list.bullet.rectangle.portrait")
        } description: {
            Text(String(localized: "questionLists.empty.body"))
        }
        .padding()
    }

    private var listsView: some View {
        List {
            if !questionListStore.lists.isEmpty {
                Section("Question Lists") {
                    ForEach(questionListStore.lists) { list in
                        NavigationLink {
                            QuestionListDetailView(
                                listID: list.id,
                                presentSheet: presentDetailSheet
                            )
                        } label: {
                            QuestionListRowView(list: list)
                        }
                        .accessibilityIdentifier("question-list-row-\(list.id)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(String(localized: "common.delete"), systemImage: "trash", role: .destructive) {
                                listToDelete = list
                            }

                            Button(String(localized: "common.edit"), systemImage: "pencil") {
                                editorMode = .edit(list)
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func deleteSelectedList() {
        guard let list = listToDelete else { return }
        listToDelete = nil
        Task {
            do {
                try await questionListStore.deleteList(list)
            } catch {
                questionListStore.error = error.localizedDescription
            }
        }
    }

    private func presentDetailSheet(_ sheet: QuestionListDetailSheet) {
        if let presentExternalDetailSheet {
            presentExternalDetailSheet(sheet)
        } else {
            activeDetailSheet = sheet
        }
    }
}

private struct QuestionListDetailSheetPresenter: ViewModifier {
    @EnvironmentObject private var questionListStore: QuestionListStore

    @Binding var activeSheet: QuestionListDetailSheet?
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .sheet(item: $activeSheet) { sheet in
                    if let list = questionListStore.lists.first(where: { $0.id == sheet.listID }) {
                        switch sheet {
                        case .picker:
                            QuestionListQuestionPickerView(list: list)
                        case .share:
                            QuestionListShareSheet(list: list)
                                .presentationDetents([.height(360)])
                                .presentationDragIndicator(.visible)
                        }
                    } else {
                        ContentUnavailableView {
                            Label(String(localized: "questionLists.detail.missing"), systemImage: "exclamationmark.triangle")
                        }
                    }
                }
        } else {
            content
        }
    }
}

private struct QuestionListRowView: View {
    let list: QuestionList

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(questionCountText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var questionCountText: String {
        String(
            format: String(localized: "questionLists.row.count"),
            locale: AppLocalization.currentLocale,
            list.questionIds.count
        )
    }
}

struct QuestionListDetailView: View {
    @EnvironmentObject private var categoryModel: CategoryModel
    @EnvironmentObject private var questionListStore: QuestionListStore
    @EnvironmentObject private var sharedQuestionListStore: SharedQuestionListStore
    @EnvironmentObject private var questionModel: QuestionModel

    let listID: String
    let presentSheet: (QuestionListDetailSheet) -> Void

    @State private var presentedQuestion: ExpandedQuestionState?

    private var list: QuestionList? {
        questionListStore.lists.first { $0.id == listID }
    }

    private var questions: [Question] {
        guard let list else { return [] }
        return questionListStore.questions(in: list, using: questionModel)
    }

    var body: some View {
        content
            .background(Color.theme.background)
            .navigationTitle(list?.name ?? String(localized: "questionLists.detail.title"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        guard let list else { return }
                        presentSheet(.share(listID: list.id))
                    } label: {
                        Label("Share List", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("question-list-detail-share-button")
                    .disabled(list == nil || questions.isEmpty)

                    Button {
                        guard let list else { return }
                        presentSheet(.picker(listID: list.id))
                    } label: {
                        Label(String(localized: "questionLists.addQuestions"), systemImage: "plus")
                    }
                    .accessibilityIdentifier("question-list-detail-add-button")
                    .disabled(list == nil)
                }
            }
            .fullScreenCover(item: $presentedQuestion) { expandedState in
                QuestionDetailModalShell(
                    expandedState: expandedState,
                    model: questionModel
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        if list == nil {
            ContentUnavailableView {
                Label(String(localized: "questionLists.detail.missing"), systemImage: "exclamationmark.triangle")
            }
        } else if questions.isEmpty {
            emptyState
        } else {
            questionCards
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "questionLists.detail.empty.title"), systemImage: "bookmark")
        } description: {
            Text(String(localized: "questionLists.detail.empty.body"))
        } actions: {
            Button {
                guard let list else { return }
                presentSheet(.picker(listID: list.id))
            } label: {
                Label(String(localized: "questionLists.addQuestions"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var questionCards: some View {
        List {
            ForEach(questions) { question in
                QuestionCard(
                    question: question,
                    model: questionModel,
                    headerStyle: .plain,
                    sourceID: "questionList.\(listID)",
                    onTap: {
                        presentedQuestion = ExpandedQuestionState(
                            question: question,
                            headerStyle: .plain
                        )
                    },
                    showImages: true,
                    showsShareButton: true,
                    presentationStyle: .pagedFeed,
                    categoryColor: categoryModel.color(for: question.category)
                )
                .padding(.vertical, 8)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(String(localized: "questionLists.removeQuestion"), systemImage: "bookmark.slash", role: .destructive) {
                        remove(question)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func remove(_ question: Question) {
        guard let list else { return }
        Task {
            do {
                try await questionListStore.setQuestion(question.id, in: list, isIncluded: false)
            } catch {
                questionListStore.error = error.localizedDescription
            }
        }
    }
}

enum QuestionListDetailSheet: Identifiable {
    case picker(listID: String)
    case share(listID: String)

    var listID: String {
        switch self {
        case .picker(let listID), .share(let listID):
            return listID
        }
    }

    var id: String {
        switch self {
        case .picker(let listID):
            return "picker-\(listID)"
        case .share(let listID):
            return "share-\(listID)"
        }
    }
}

/// A dismiss button that can refuse its own tap for a moment after the sheet appears.
///
/// The delay is for one UI test harness, where a tap can land before the simulator finishes
/// presenting the sheet. It arrives as an environment value rather than as a launch-argument check,
/// so this production view no longer knows that a harness exists. The app installs zero.
struct SimulatorSafeSheetDismissButton<Label: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sheetDismissDelay) private var sheetDismissDelay
    @State private var isDismissEnabled = false

    private let label: () -> Label

    private var shouldDelayDismiss: Bool {
        sheetDismissDelay > .zero
    }

    init(@ViewBuilder label: @escaping () -> Label) {
        self.label = label
    }

    var body: some View {
        Button {
            guard !shouldDelayDismiss || isDismissEnabled else { return }
            dismiss()
        } label: {
            label()
        }
        .disabled(shouldDelayDismiss && !isDismissEnabled)
        .task {
            guard shouldDelayDismiss else {
                isDismissEnabled = true
                return
            }
            isDismissEnabled = false
            try? await Task.sleep(for: sheetDismissDelay)
            guard !Task.isCancelled else { return }
            isDismissEnabled = true
        }
    }
}

struct QuestionListEditorView: View {
    enum Mode: Identifiable {
        case create
        case edit(QuestionList)

        var id: String {
            switch self {
            case .create:
                return "create"
            case .edit(let list):
                return "edit-\(list.id)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var questionListStore: QuestionListStore

    let mode: Mode

    @State private var name: String
    @State private var isSaving = false
    @FocusState private var isNameFocused: Bool

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
        case .edit(let list):
            _name = State(initialValue: list.name)
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            QuestionListNameField(name: $name, isFocused: $isNameFocused)
                .padding(.top, 24)

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(navigationTitle)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label(String(localized: "common.cancel"), systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(String(localized: "common.cancel"))
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: save) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Label(primaryButtonTitle, systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                }
                .disabled(!canSave)
                .accessibilityLabel(primaryButtonTitle)
            }
        }
        .onAppear {
            isNameFocused = true
        }
        .alert(
            String(localized: "common.error.title"),
            isPresented: Binding(
                get: { questionListStore.error != nil },
                set: { if !$0 { questionListStore.error = nil } }
            ),
            actions: {
                Button(String(localized: "common.ok")) { questionListStore.error = nil }
            },
            message: {
                if let error = questionListStore.error {
                    Text(error)
                }
            }
        )
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !normalizedName.isEmpty && !isSaving
    }

    private var navigationTitle: String {
        switch mode {
        case .create:
            return String(localized: "questionLists.create.title")
        case .edit:
            return String(localized: "questionLists.edit.title")
        }
    }

    private var primaryButtonTitle: String {
        switch mode {
        case .create:
            return String(localized: "questionLists.create")
        case .edit:
            return String(localized: "common.save")
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true

        Task {
            do {
                switch mode {
                case .create:
                    _ = try await questionListStore.createList(named: normalizedName)
                    dismiss()
                case .edit(let list):
                    try await questionListStore.updateList(list, name: normalizedName)
                    dismiss()
                }
            } catch {
                questionListStore.error = error.localizedDescription
            }
            isSaving = false
        }
    }
}

private struct QuestionListNameField: View {
    @Binding var name: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        TextField(String(localized: "questionLists.name.placeholder"), text: $name, axis: .vertical)
            .font(.body)
            .foregroundStyle(.primary)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .focused(isFocused)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(minHeight: 64, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.theme.border.opacity(0.16), lineWidth: 1)
            }
    }
}

struct QuestionListQuestionPickerView: View {
    @EnvironmentObject private var categoryModel: CategoryModel
    @EnvironmentObject private var questionListStore: QuestionListStore
    @EnvironmentObject private var questionModel: QuestionModel

    let list: QuestionList

    @State private var searchText = ""
    @State private var selectedCategory: String?

    private var currentList: QuestionList {
        questionListStore.lists.first { $0.id == list.id } ?? list
    }

    // Reads `questions` rather than `allQuestions`, which re-sorts the whole corpus on every access —
    // including on every keystroke in the search field. The displayed order is unchanged: the public
    // question cache is already built newest-first in `QuestionModel.updatePublicQuestions()`, which
    // is exactly the order `allQuestions` was producing.
    private var categories: [String] {
        Array(Set(questionModel.questions.map(\.category))).sorted()
    }

    private var filteredQuestions: [Question] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return questionModel.questions.filter { question in
            let matchesCategory = selectedCategory == nil || question.category == selectedCategory
            guard matchesCategory else { return false }
            return trimmedSearch.isEmpty || question.text.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryFilter

                List(filteredQuestions) { question in
                    Button {
                        toggle(question)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(question.text)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)

                                Text(categoryModel.title(for: question.category))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: currentList.questionIds.contains(question.id) ? "checkmark.circle.fill" : "plus.circle")
                                .font(.title3)
                                .foregroundStyle(currentList.questionIds.contains(question.id) ? Color.green : Color.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .navigationTitle(String(localized: "questionLists.picker.title"))
            .accessibilityIdentifier("question-list-picker-sheet")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SimulatorSafeSheetDismissButton {
                        Label(String(localized: "common.done"), systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel(String(localized: "common.done"))
                }
            }
            .searchable(text: $searchText, prompt: String(localized: "questionLists.picker.search"))
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton(title: String(localized: "questionLists.picker.all"), category: nil)

                ForEach(categories, id: \.self) { category in
                    categoryButton(title: categoryModel.title(for: category), category: category)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color.theme.background)
    }

    private func categoryButton(title: String, category: String?) -> some View {
        Button {
            selectedCategory = category
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(selectedCategory == category ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ question: Question) {
        let isIncluded = !currentList.questionIds.contains(question.id)
        Task {
            do {
                try await questionListStore.setQuestion(question.id, in: currentList, isIncluded: isIncluded)
            } catch {
                questionListStore.error = error.localizedDescription
            }
        }
    }
}

struct QuestionListsView: View {
    var body: some View {
        NavigationStack {
            QuestionListsContentView()
        }
    }
}

struct QuestionListSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var questionListStore: QuestionListStore

    let question: Question

    @State private var isCreatingList = false
    @State private var newListName = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                if questionListStore.lists.isEmpty && !isCreatingList {
                    Section {
                        ContentUnavailableView {
                            Label(String(localized: "questionLists.empty.title"), systemImage: "list.bullet.rectangle.portrait")
                        } description: {
                            Text(String(localized: "questionLists.sheet.empty.body"))
                        } actions: {
                            Button(String(localized: "questionLists.create")) {
                                isCreatingList = true
                            }
                        }
                    }
                }

                if isCreatingList {
                    Section {
                        TextField(String(localized: "questionLists.name.placeholder"), text: $newListName)
                            .textInputAutocapitalization(.sentences)

                        Button(action: createAndAdd) {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text(String(localized: "questionLists.createAndAdd"))
                            }
                        }
                        .disabled(normalizedNewListName.isEmpty || isSaving)
                    }
                } else {
                    Section {
                        Button {
                            isCreatingList = true
                        } label: {
                            Label(String(localized: "questionLists.create"), systemImage: "plus")
                        }
                    }
                }

                if !questionListStore.lists.isEmpty {
                    Section {
                        ForEach(questionListStore.lists) { list in
                            Button {
                                toggle(list)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(list.name)
                                            .foregroundStyle(.primary)
                                        Text(
                                            String(
                                                format: String(localized: "questionLists.row.count"),
                                                locale: AppLocalization.currentLocale,
                                                list.questionIds.count
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: list.questionIds.contains(question.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(list.questionIds.contains(question.id) ? Color.green : Color.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "questionLists.sheet.title"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) {
                        dismiss()
                    }
                }
            }
        }
        .alert(
            String(localized: "common.error.title"),
            isPresented: Binding(
                get: { questionListStore.error != nil },
                set: { if !$0 { questionListStore.error = nil } }
            ),
            actions: {
                Button(String(localized: "common.ok")) {
                    questionListStore.error = nil
                }
            },
            message: {
                if let error = questionListStore.error {
                    Text(error)
                }
            }
        )
    }

    private var normalizedNewListName: String {
        newListName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createAndAdd() {
        guard !normalizedNewListName.isEmpty else { return }
        isSaving = true
        Task {
            do {
                let list = try await questionListStore.createList(named: normalizedNewListName)
                try await questionListStore.setQuestion(question.id, in: list, isIncluded: true)
                isCreatingList = false
                newListName = ""
            } catch {
                questionListStore.error = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func toggle(_ list: QuestionList) {
        let isIncluded = !list.questionIds.contains(question.id)
        Task {
            do {
                try await questionListStore.setQuestion(question.id, in: list, isIncluded: isIncluded)
            } catch {
                questionListStore.error = error.localizedDescription
            }
        }
    }
}
