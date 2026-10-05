import FirebaseFirestore
import SwiftUI

private struct ReleaseDraftCopy: Equatable {
    var titleEN = ""
    var titleTR = ""
    var bodyEN = ""
    var bodyTR = ""

    static let empty = ReleaseDraftCopy()

    var localizedTitle: [String: String] {
        localizedMap(en: titleEN, tr: titleTR)
    }

    var localizedBody: [String: String] {
        localizedMap(en: bodyEN, tr: bodyTR)
    }

    var hasRequiredFields: Bool {
        !titleEN.normalizedReleaseCopy.isEmpty
        && !bodyEN.normalizedReleaseCopy.isEmpty
    }

    private func localizedMap(en: String, tr: String) -> [String: String] {
        [
            "en": en.normalizedReleaseCopy,
            "tr": tr.normalizedReleaseCopy,
        ]
        .filter { !$0.value.isEmpty }
    }
}

@MainActor
final class AdminReleaseManagerModel: ObservableObject {
    @Published private(set) var publishedReleases: [ContentRelease] = []
    @Published private(set) var pendingCategories: [Category] = []
    @Published private(set) var pendingQuestions: [Question] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPublishing = false
    @Published private(set) var isSendingTestNotification = false
    @Published var errorMessage: String?
    @Published var testNotificationMessage: String?
    @Published var titleEN = ""
    @Published var titleTR = ""
    @Published var bodyEN = ""
    @Published var bodyTR = ""

    private let releaseService: any ContentReleaseServicing
    private var listener: (any ListenerRegistration)?
    private var hasStarted = false
    private var lastSuggestedCopy = ReleaseDraftCopy.empty

    init(releaseService: any ContentReleaseServicing = ContentReleaseService()) {
        self.releaseService = releaseService
    }

    deinit {
        listener?.remove()
    }

    func loadIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true
        listen()
        await refresh(forceSuggestedCopy: true)
    }

    func refresh(forceSuggestedCopy: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let fetchedCategories = releaseService.fetchPendingCategories()
            async let fetchedQuestions = releaseService.fetchEligibleQuestions()

            applyPendingContent(
                categories: try await fetchedCategories,
                questions: try await fetchedQuestions,
                forceSuggestedCopy: forceSuggestedCopy
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applySuggestedCopy() {
        guard hasPendingContent else {
            clearComposer()
            return
        }

        updateComposer(with: suggestedCopy(), force: true)
    }

    func publishPendingRelease() async {
        guard canSendUpdate else { return }

        isPublishing = true
        defer { isPublishing = false }

        do {
            let result = try await releaseService.publishPendingRelease(
                localizedTitle: draftCopy.localizedTitle,
                localizedBody: draftCopy.localizedBody
            )

            await refresh(forceSuggestedCopy: result.didPublish)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendTestNotification() async {
        guard canSendTestNotification else { return }

        isSendingTestNotification = true
        defer { isSendingTestNotification = false }

        do {
            let result = try await releaseService.sendTestNotification(
                localizedTitle: draftCopy.localizedTitle,
                localizedBody: draftCopy.localizedBody
            )

            errorMessage = nil
            testNotificationMessage = message(for: result)
        } catch {
            testNotificationMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func listen() {
        listener?.remove()
        listener = releaseService.listenToReleases { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let releases):
                    self?.publishedReleases = releases
                        .filter(\.isPublished)
                        .sorted(by: Self.sortPublishedReleases)
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var hasPendingContent: Bool {
        !pendingCategories.isEmpty || !pendingQuestions.isEmpty
    }

    private var canSendUpdate: Bool {
        hasPendingContent && draftCopy.hasRequiredFields
    }

    var canSendTestNotification: Bool {
        draftCopy.hasRequiredFields && !isSendingTestNotification
    }

    private var draftCopy: ReleaseDraftCopy {
        ReleaseDraftCopy(
            titleEN: titleEN,
            titleTR: titleTR,
            bodyEN: bodyEN,
            bodyTR: bodyTR
        )
    }

    private func applyPendingContent(
        categories: [Category],
        questions: [Question],
        forceSuggestedCopy: Bool
    ) {
        pendingCategories = categories
        pendingQuestions = questions

        guard hasPendingContent else {
            clearComposer()
            return
        }

        updateComposer(with: suggestedCopy(), force: forceSuggestedCopy)
    }

    private func suggestedCopy() -> ReleaseDraftCopy {
        let suggestion = releaseService.suggestedCopy(
            categoryIDs: pendingCategories.map(\.id),
            questions: pendingQuestions,
            categories: pendingCategories
        )

        return ReleaseDraftCopy(
            titleEN: suggestion.title["en"] ?? "",
            titleTR: suggestion.title["tr"] ?? "",
            bodyEN: suggestion.body["en"] ?? "",
            bodyTR: suggestion.body["tr"] ?? ""
        )
    }

    private func updateComposer(with suggestion: ReleaseDraftCopy, force: Bool) {
        if force || titleEN.isEmpty || titleEN == lastSuggestedCopy.titleEN {
            titleEN = suggestion.titleEN
        }
        if force || titleTR.isEmpty || titleTR == lastSuggestedCopy.titleTR {
            titleTR = suggestion.titleTR
        }
        if force || bodyEN.isEmpty || bodyEN == lastSuggestedCopy.bodyEN {
            bodyEN = suggestion.bodyEN
        }
        if force || bodyTR.isEmpty || bodyTR == lastSuggestedCopy.bodyTR {
            bodyTR = suggestion.bodyTR
        }

        lastSuggestedCopy = suggestion
    }

    private func clearComposer() {
        titleEN = ""
        titleTR = ""
        bodyEN = ""
        bodyTR = ""
        lastSuggestedCopy = .empty
    }

    private static func sortPublishedReleases(_ lhs: ContentRelease, _ rhs: ContentRelease) -> Bool {
        let lhsDate = lhs.publishedAt ?? lhs.createdAt
        let rhsDate = rhs.publishedAt ?? rhs.createdAt

        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        return lhs.id > rhs.id
    }

    private func message(for result: ContentReleaseNotificationSendResult) -> String {
        if result.attemptedCount == 0 {
            return String(localized: "admin.releases.testNotification.noDevice")
        }

        if result.successCount > 0 {
            return String(
                format: String(localized: "admin.releases.testNotification.sent"),
                locale: AppLocalization.currentLocale,
                result.successCount,
                result.failureCount
            )
        }

        return String(localized: "admin.releases.testNotification.failed")
    }
}

struct AdminReleaseManagerView: View {
    @StateObject private var model = AdminReleaseManagerModel()

    var body: some View {
        AdminAccessGuardView {
            List {
                pendingContentSection
                copySection

                Section(String(localized: "admin.releases.section.releases")) {
                    if model.publishedReleases.isEmpty && !model.isLoading {
                        ContentUnavailableView(
                            String(localized: "admin.releases.emptyTitle"),
                            systemImage: "megaphone",
                            description: Text(String(localized: "admin.releases.emptyBody"))
                        )
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(model.publishedReleases) { release in
                            PublishedReleaseRow(
                                release: release,
                                statusText: statusLine(for: release)
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.theme.background)
            .navigationTitle(String(localized: "admin.releases.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.refresh"), systemImage: "arrow.clockwise") {
                        Task {
                            await model.refresh()
                        }
                    }
                }
            }
            .alert(
                String(localized: "admin.releases.errorTitle"),
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .alert(
                String(localized: "admin.releases.testNotification.title"),
                isPresented: Binding(
                    get: { model.testNotificationMessage != nil },
                    set: { if !$0 { model.testNotificationMessage = nil } }
                )
            ) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(model.testNotificationMessage ?? "")
            }
            .overlay {
                if model.isLoading && model.publishedReleases.isEmpty {
                    ProgressView(String(localized: "common.loading"))
                }
            }
            .refreshable {
                await model.refresh()
            }
            .task {
                await model.loadIfNeeded()
            }
        }
    }

    private var pendingContentSection: some View {
        Section(String(localized: "admin.releases.section.eligible")) {
            releaseMetricRow

            if model.pendingCategories.isEmpty {
                Text(String(localized: "admin.releases.noCategories"))
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "admin.releases.form.categories"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(model.pendingCategories.prefix(3)) { category in
                    PendingCategoryRow(category: category)
                }
            }

            if model.pendingQuestions.isEmpty {
                Text(String(localized: "admin.releases.noQuestions"))
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "admin.releases.form.questions"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(model.pendingQuestions.prefix(5)) { question in
                    PendingQuestionRow(question: question)
                }
            }
        }
    }

    private var copySection: some View {
        Section(String(localized: "admin.releases.form.copy")) {
            TextField(String(localized: "admin.releases.form.title.en"), text: $model.titleEN)
            TextField(String(localized: "admin.releases.form.title.tr"), text: $model.titleTR)
            TextField(String(localized: "admin.releases.form.body.en"), text: $model.bodyEN, axis: .vertical)
                .lineLimit(2...4)
            TextField(String(localized: "admin.releases.form.body.tr"), text: $model.bodyTR, axis: .vertical)
                .lineLimit(2...4)

            Button(String(localized: "admin.releases.form.applySuggestedCopy")) {
                model.applySuggestedCopy()
            }
            .disabled(model.pendingCategories.isEmpty && model.pendingQuestions.isEmpty)

            Button {
                Task {
                    await model.sendTestNotification()
                }
            } label: {
                HStack {
                    if model.isSendingTestNotification {
                        ProgressView()
                    }

                    Label(String(localized: "admin.releases.testNotification.send"), systemImage: "bell.badge")
                }
            }
            .disabled(!model.canSendTestNotification || model.isPublishing)

            Button {
                Task {
                    await model.publishPendingRelease()
                }
            } label: {
                HStack {
                    if model.isPublishing {
                        ProgressView()
                            .tint(.white)
                    }

                    Spacer()

                    Label(String(localized: "admin.releases.publishNow"), systemImage: "paperplane.fill")
                        .font(.headline)

                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                (model.pendingCategories.isEmpty && model.pendingQuestions.isEmpty)
                || model.isPublishing
                || model.titleEN.normalizedReleaseCopy.isEmpty
                || model.bodyEN.normalizedReleaseCopy.isEmpty
            )
        }
    }

    private func statusLine(for release: ContentRelease) -> String {
        switch release.status {
        case .draft:
            return String(localized: "admin.releases.status.draft")
        case .scheduled:
            return String(
                format: String(localized: "admin.releases.status.scheduled"),
                locale: AppLocalization.currentLocale,
                release.scheduledAt?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "admin.releases.unknownDate")
            )
        case .published:
            return String(
                format: String(localized: "admin.releases.status.published"),
                locale: AppLocalization.currentLocale,
                release.publishedAt?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "admin.releases.unknownDate")
            )
        case .canceled:
            return String(localized: "admin.releases.status.canceled")
        }
    }

    private var releaseMetricRow: some View {
        ViewThatFits {
            HStack(spacing: 12) {
                ReleaseMetricCard(
                    title: String(localized: "admin.releases.unannouncedCategories"),
                    count: model.pendingCategories.count,
                    systemImage: "square.grid.2x2"
                )

                ReleaseMetricCard(
                    title: String(localized: "admin.releases.unannouncedQuestions"),
                    count: model.pendingQuestions.count,
                    systemImage: "questionmark.bubble"
                )
            }

            VStack(spacing: 12) {
                ReleaseMetricCard(
                    title: String(localized: "admin.releases.unannouncedCategories"),
                    count: model.pendingCategories.count,
                    systemImage: "square.grid.2x2"
                )

                ReleaseMetricCard(
                    title: String(localized: "admin.releases.unannouncedQuestions"),
                    count: model.pendingQuestions.count,
                    systemImage: "questionmark.bubble"
                )
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
    }
}

private struct ReleaseMetricCard: View {
    let title: String
    let count: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("\(count)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.theme.secondaryBackground)
        )
    }
}

private struct PendingCategoryRow: View {
    let category: Category

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.iconSystemName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            Text(category.displayName)
                .font(.body)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct PendingQuestionRow: View {
    @EnvironmentObject private var categoryModel: CategoryModel

    let question: Question

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.text)
                .font(.body)
                .foregroundStyle(.primary)

            Label(
                categoryModel.title(for: question.category),
                systemImage: categoryModel.iconName(for: question.category)
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct PublishedReleaseRow: View {
    let release: ContentRelease
    let statusText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(release.title.isEmpty ? String(localized: "admin.releases.untitled") : release.title)
                .font(.headline)

            if !release.body.isEmpty {
                Text(release.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ReleaseCountBadge(
                    count: release.categoryIds.count,
                    title: String(localized: "admin.releases.form.categories")
                )

                ReleaseCountBadge(
                    count: release.questionIds.count,
                    title: String(localized: "admin.releases.form.questions")
                )
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ReleaseCountBadge: View {
    let count: Int
    let title: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.caption.weight(.semibold))

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.theme.secondaryBackground)
        )
    }
}

private extension String {
    var normalizedReleaseCopy: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    NavigationStack {
        AdminReleaseManagerView()
            .environmentObject(CategoryModel())
            .environmentObject(QuestionModel())
            .environmentObject(ProfileModel(userId: "preview"))
    }
}
