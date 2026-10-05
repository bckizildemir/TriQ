import SwiftUI
import UIKit

struct SharedQuestionListSheetView: View {
    let shareCode: String

    @EnvironmentObject private var authModel: AuthModel
    @EnvironmentObject private var deepLinkRouter: AppDeepLinkRouter
    @EnvironmentObject private var sharedQuestionListStore: SharedQuestionListStore
    @Environment(\.dismiss) private var dismiss

    @State private var preview: QuestionListSharePreview?
    @State private var isLoading = true
    @State private var isAccepting = false
    @State private var errorMessage: String?
    @State private var showingGuestUpgrade = false

    var body: some View {
        previewContent
        .task(id: shareCode) {
            await loadPreview()
        }
        .sheet(isPresented: $showingGuestUpgrade) {
            GuestUpgradeView()
                .environmentObject(authModel)
        }
    }

    private var previewContent: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView(String(localized: "common.loading"))
                } else if let preview {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    VStack(spacing: 8) {
                        Text(preview.listName)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)

                        Text("\(UserHandleFormatter.handle(preview.ownerDisplayName)) shared \(preview.questionCount) questions.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Text(preview.includeOwnerAnswers ? "Answers are included after you accept." : "This list was shared as empty questions.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: accept) {
                        ZStack {
                            Label("Accept List", systemImage: "checkmark.circle")
                                .opacity(isAccepting ? 0 : 1)

                            if isAccepting {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .frame(minWidth: 148, minHeight: 22)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAccepting || !canAccept)
                    .accessibilityIdentifier("shared-list-accept-button")

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("shared-list-accept-error")
                    }

                    if !canAccept {
                        Text("Sign in with a permanent account to accept shared question lists.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if authModel.isAnonymous {
                            Button("Create Account") {
                                showingGuestUpgrade = true
                            }
                        }
                    }
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text(errorMessage ?? "Shared list could not be loaded.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Shared List")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.close")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var canAccept: Bool {
        authModel.isAuthenticated && !authModel.isAnonymous
    }

    private func loadPreview() async {
        isLoading = true
        errorMessage = nil
        preview = nil
        do {
            let loadedPreview = try await sharedQuestionListStore.previewShare(shareCode: shareCode)
            preview = loadedPreview
            if loadedPreview.isAccepted {
                try await routeToAcceptedShare(shareId: loadedPreview.shareId)
            }
        } catch {
            errorMessage = QuestionListShareService.userFacingMessage(for: error)
        }
        isLoading = false
    }

    private func accept() {
        guard canAccept else {
            errorMessage = "Sign in with a permanent account to accept shared question lists."
            return
        }
        isAccepting = true
        errorMessage = nil
        Task { @MainActor in
            defer { isAccepting = false }
            do {
                let shareId = try await sharedQuestionListStore.acceptShare(
                    shareCode: shareCode,
                    currentUserId: authModel.currentUserId
                )
                try await routeToAcceptedShare(shareId: shareId)
            } catch {
                errorMessage = QuestionListShareService.userFacingMessage(for: error)
            }
        }
    }

    private func routeToAcceptedShare(shareId: String) async throws {
        try await sharedQuestionListStore.loadAcceptedShare(
            shareId: shareId,
            currentUserId: authModel.currentUserId
        )
        deepLinkRouter.sharedQuestionList = nil
        dismiss()
        deepLinkRouter.requestAcceptedQuestionListShareDetail(shareId: shareId)
    }
}

struct QuestionListShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authModel: AuthModel
    @EnvironmentObject private var sharedQuestionListStore: SharedQuestionListStore

    let list: QuestionList

    @State private var includeOwnerAnswers = true
    @State private var isCreating = false
    @State private var result: QuestionListShareCreationResult?
    @State private var activityPayload: QuestionListShareActivityPayload?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Include my text answers", isOn: $includeOwnerAnswers)
                    Text("The list questions are snapshotted now. If answers are included, only your current text answers are shared.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                } footer: {
                    Text("One link can be accepted by up to \(QuestionListShare.defaultRecipientCap) permanent-account recipients. Empty lists can be shared and filled in later.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Share List")
            .accessibilityIdentifier("question-list-share-sheet")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SimulatorSafeSheetDismissButton {
                        Label(String(localized: "common.cancel"), systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel(String(localized: "common.cancel"))
                    .accessibilityIdentifier("question-list-share-dismiss-button")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: shareList) {
                        if isCreating {
                            ProgressView()
                        } else {
                            Label("Share List", systemImage: "square.and.arrow.up")
                                .labelStyle(.iconOnly)
                        }
                    }
                    .disabled(isCreating)
                    .accessibilityLabel("Share List")
                    .accessibilityIdentifier("question-list-share-toolbar-share-button")
                    .background(QuestionListShareActivityAnchor(payload: $activityPayload))
                }
            }
        }
    }

    private var currentSenderDisplayName: String {
        guard let result else { return "TTB user" }
        if let ownerDisplayName = sharedQuestionListStore.ownedShare(withID: result.shareId)?.ownerDisplayName {
            return ownerDisplayName
        }
        let username = authModel.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return username.isEmpty ? "TTB user" : username
    }

    private func shareList() {
        isCreating = true
        errorMessage = nil
        Task {
            do {
                let creationResult = try await sharedQuestionListStore.createShare(
                    for: list,
                    includeOwnerAnswers: includeOwnerAnswers
                )
                result = creationResult
                activityPayload = QuestionListShareActivityPayload.make(
                    senderDisplayName: currentSenderDisplayName,
                    listName: list.name,
                    questionCount: list.questionIds.count,
                    url: creationResult.shareURL
                )
            } catch {
                errorMessage = QuestionListShareService.userFacingMessage(for: error)
            }
            isCreating = false
        }
    }
}

private struct QuestionListShareActivityAnchor: UIViewRepresentable {
    @Binding var payload: QuestionListShareActivityPayload?

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.payload = $payload
        context.coordinator.presentIfNeeded(from: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(payload: $payload)
    }

    @MainActor
    final class Coordinator {
        var payload: Binding<QuestionListShareActivityPayload?>
        private var presentedPayloadID: String?

        init(payload: Binding<QuestionListShareActivityPayload?>) {
            self.payload = payload
        }

        func presentIfNeeded(from sourceView: UIView) {
            guard let payload = payload.wrappedValue else { return }
            guard presentedPayloadID != payload.id else { return }
            guard sourceView.window != nil else { return }
            guard let presenter = sourceView.nearestViewController else { return }
            guard presenter.presentedViewController == nil else { return }

            presentedPayloadID = payload.id

            let controller = UIActivityViewController(
                activityItems: payload.activityItems,
                applicationActivities: nil
            )
            controller.popoverPresentationController?.sourceView = sourceView
            controller.popoverPresentationController?.sourceRect = sourceView.bounds
            let payloadID = payload.id
            controller.completionWithItemsHandler = { [weak self] _, _, _, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if self.payload.wrappedValue?.id == payloadID {
                        self.payload.wrappedValue = nil
                    }
                    self.presentedPayloadID = nil
                }
            }

            presenter.present(controller, animated: true)
        }
    }
}

private extension UIView {
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }
}

struct QuestionListSharesHubView: View {
    @EnvironmentObject private var sharedQuestionListStore: SharedQuestionListStore

    private var isEmpty: Bool {
        sharedQuestionListStore.acceptedShares.isEmpty
            && sharedQuestionListStore.ownedShares.isEmpty
    }

    var body: some View {
        Group {
            if sharedQuestionListStore.isLoading && isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isEmpty {
                ContentUnavailableView {
                    Label("No Shared Lists", systemImage: "person.2")
                } description: {
                    Text("Lists you receive or send with others appear here.")
                }
                .padding()
            } else {
                List {
                    if !sharedQuestionListStore.acceptedShares.isEmpty {
                        Section("Received") {
                            ForEach(sharedQuestionListStore.acceptedShares) { acceptedShare in
                                NavigationLink {
                                    AcceptedQuestionListShareDetailView(acceptedShareID: acceptedShare.id)
                                } label: {
                                    SharedQuestionListRow(
                                        title: acceptedShare.share.listName,
                                        subtitle: "\(UserHandleFormatter.handle(acceptedShare.share.ownerDisplayName)) · \(acceptedShare.share.questionIds.count) questions",
                                        iconName: "tray.and.arrow.down.fill",
                                        badgeText: acceptedShare.recipient.repliedAt == nil ? "Open" : "Replied",
                                        showsUnreadDot: false
                                    )
                                }
                                .accessibilityIdentifier("shared-list-received-row-\(acceptedShare.id)")
                            }
                        }
                    }

                    if !sharedQuestionListStore.ownedShares.isEmpty {
                        Section("Sent") {
                            ForEach(sharedQuestionListStore.ownedShares) { share in
                                sentShareRow(for: share)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("question-list-shares-hub")
            }
        }
        .task(id: sharedQuestionListStore.ownedShares.map(\.id)) {
            for share in sharedQuestionListStore.ownedShares {
                await sharedQuestionListStore.fetchRecipients(for: share.id)
            }
        }
    }

    private func sentShareRow(for share: QuestionListShare) -> some View {
        NavigationLink {
            OwnedQuestionListShareDetailView(shareID: share.id)
        } label: {
            sentShareRowContent(for: share)
        }
        .accessibilityIdentifier("shared-list-sent-row-\(share.id)")
    }

    private func sentShareRowContent(for share: QuestionListShare) -> some View {
        SharedQuestionListRow(
            title: share.listName,
            subtitle: "\(share.questionIds.count) questions",
            iconName: "paperplane.fill",
            badgeText: badgeText(for: share),
            showsUnreadDot: hasUnreadReply(in: share.id)
        )
    }

    private func badgeText(for share: QuestionListShare) -> String {
        guard share.status == .active else { return "Revoked" }
        guard share.isLinkEnabled else { return "Link off" }
        return share.acceptedRecipientCount > 0 ? "Compare" : "Awaiting"
    }

    private func hasUnreadReply(in shareId: String) -> Bool {
        sharedQuestionListStore.recipientsByShareID[shareId]?.contains { $0.unreadByOwner } ?? false
    }
}

private struct SentShareDetailsRoute: Identifiable {
    let shareID: String

    var id: String { shareID }
}

struct OwnedQuestionListShareDetailView: View {
    @Environment(\.toastCenter) private var toastCenter
    @EnvironmentObject private var sharedQuestionListStore: SharedQuestionListStore
    @EnvironmentObject private var questionModel: QuestionModel

    let shareID: String

    @State private var errorMessage: String?
    @State private var selectedRecipientID: String?
    @State private var sentShareDetailsRoute: SentShareDetailsRoute?
    @State private var presentedQuestion: ExpandedQuestionState?

    private var share: QuestionListShare? {
        sharedQuestionListStore.ownedShare(withID: shareID)
    }

    private var recipients: [QuestionListShareRecipient] {
        sharedQuestionListStore.recipientsByShareID[shareID] ?? []
    }

    private var selectedRecipient: QuestionListShareRecipient? {
        guard let selectedRecipientID else { return nil }
        return recipients.first { $0.recipientId == selectedRecipientID }
    }

    var body: some View {
        content
            .navigationTitle(share?.listName ?? "Sent Share")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if let share {
                    ToolbarItem(placement: .topBarTrailing) {
                        shareActionsMenu(for: share)
                    }
                }
            }
            .task(id: shareID) {
                await sharedQuestionListStore.fetchRecipients(for: shareID)
                syncSelectedRecipient()
            }
            .onChange(of: recipients.map(\.recipientId)) { _, _ in
                syncSelectedRecipient()
            }
            .onChange(of: selectedRecipient?.recipientId) { _, newRecipientID in
                guard let newRecipientID,
                      let recipient = recipients.first(where: { $0.recipientId == newRecipientID }),
                      recipient.unreadByOwner else {
                    return
                }
                Task {
                    await sharedQuestionListStore.markReplySeen(
                        shareId: shareID,
                        recipientId: newRecipientID
                    )
                }
            }
            .sheet(item: $sentShareDetailsRoute) { route in
                SentShareDetailsSheet(shareID: route.shareID)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
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
        if let share {
            List {
                if recipients.count > 1 {
                    Section("Compare with") {
                        Picker("Recipient", selection: $selectedRecipientID) {
                            ForEach(recipients) { recipient in
                                Text(UserHandleFormatter.handle(recipient.recipientDisplayName))
                                    .tag(Optional(recipient.recipientId))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if let selectedRecipient {
                    SharedQuestionListComparisonList(
                        share: share,
                        recipient: selectedRecipient,
                        onOpenQuestion: openQuestion
                    )
                } else if !recipients.isEmpty {
                    ContentUnavailableView {
                        Label("Select a Recipient", systemImage: "person.2")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    SharedQuestionListComparisonList(
                        share: share,
                        leftTitle: "You",
                        rightTitle: "Recipient",
                        leftAnswersForQuestion: share.ownerTextSnapshot(for:),
                        rightAnswersForQuestion: { _ in [] },
                        onOpenQuestion: openQuestion
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.theme.background)
            .accessibilityIdentifier("owned-shared-list-detail")
        } else {
            ContentUnavailableView {
                Label("Share Not Found", systemImage: "exclamationmark.triangle")
            }
        }
    }

    @ViewBuilder
    private func shareActionsMenu(for share: QuestionListShare) -> some View {
        Menu("Share Options", systemImage: "ellipsis.circle") {
            if let url = share.shareURL, share.status == .active, share.isLinkEnabled {
                ShareLink(
                    item: url,
                    subject: Text(share.listName),
                    message: Text(
                        QuestionListShareActivityPayload.make(
                            senderDisplayName: share.ownerDisplayName,
                            listName: share.listName,
                            questionCount: share.questionIds.count,
                            url: url
                        ).text
                    )
                ) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
            }

            if let url = share.shareURL {
                Button {
                    copyLink(url)
                } label: {
                    Label("Copy Link", systemImage: "doc.on.doc")
                }
            }

            Button {
                sentShareDetailsRoute = SentShareDetailsRoute(shareID: share.id)
            } label: {
                Label("Details", systemImage: "info.circle")
            }

            Button {
                Task { await disableLink(share) }
            } label: {
                Label("Disable Link", systemImage: "minus.circle")
            }
            .disabled(!share.isLinkEnabled || share.status != .active)

            Button {
                Task { await regenerateLink(share) }
            } label: {
                Label("Regenerate Link", systemImage: "arrow.clockwise")
            }
            .disabled(share.status != .active)

            Button(role: .destructive) {
                Task { await revoke(share) }
            } label: {
                Label("Revoke Share", systemImage: "xmark.circle")
            }
            .disabled(share.status != .active)
        }
    }

    private func syncSelectedRecipient() {
        guard !recipients.isEmpty else {
            selectedRecipientID = nil
            return
        }

        if recipients.count == 1 {
            selectedRecipientID = recipients[0].recipientId
            return
        }

        if let selectedRecipientID,
           recipients.contains(where: { $0.recipientId == selectedRecipientID }) {
            return
        }

        selectedRecipientID = recipients.first { $0.unreadByOwner }?.recipientId
            ?? recipients[0].recipientId
    }

    private func openQuestion(_ question: Question) {
        presentedQuestion = ExpandedQuestionState(
            question: question,
            headerStyle: .plain
        )
    }

    private func disableLink(_ share: QuestionListShare) async {
        errorMessage = nil
        do {
            try await sharedQuestionListStore.disableLink(for: share)
        } catch {
            errorMessage = QuestionListShareService.userFacingMessage(for: error)
        }
    }

    private func regenerateLink(_ share: QuestionListShare) async {
        errorMessage = nil
        do {
            try await sharedQuestionListStore.regenerateLink(for: share)
        } catch {
            errorMessage = QuestionListShareService.userFacingMessage(for: error)
        }
    }

    private func revoke(_ share: QuestionListShare) async {
        errorMessage = nil
        do {
            try await sharedQuestionListStore.revoke(share)
        } catch {
            errorMessage = QuestionListShareService.userFacingMessage(for: error)
        }
    }

    private func copyLink(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        toastCenter.showSuccess(
            title: String(localized: "toast.copied"),
            accessibilityIdentifier: "question-list-copy-link-toast"
        )
    }
}

private struct SentShareDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sharedQuestionListStore: SharedQuestionListStore

    let shareID: String

    private var share: QuestionListShare? {
        sharedQuestionListStore.ownedShare(withID: shareID)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Share Details")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(String(localized: "common.done")) {
                            dismiss()
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let share {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(share.listName, systemImage: "paperplane.fill")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("\(share.questionIds.count) questions · \(share.acceptedRecipientCount)/\(share.recipientCap) accepted")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Label(linkStatusText(for: share), systemImage: linkStatusIcon(for: share))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Text("One link can be accepted by up to \(share.recipientCap) permanent-account recipients. Empty lists can be shared and filled in later.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("sent-share-details-sheet")
        } else {
            ContentUnavailableView {
                Label("Share Not Found", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func linkStatusText(for share: QuestionListShare) -> String {
        guard share.status == .active else { return "Share revoked" }
        return share.isLinkEnabled ? "Link active" : "Link disabled"
    }

    private func linkStatusIcon(for share: QuestionListShare) -> String {
        guard share.status == .active else { return "xmark.circle" }
        return share.isLinkEnabled ? "link" : "link.slash"
    }
}

struct AcceptedQuestionListShareDetailView: View {
    @Environment(\.toastCenter) private var toastCenter
    @EnvironmentObject private var sharedQuestionListStore: SharedQuestionListStore
    @EnvironmentObject private var questionModel: QuestionModel

    let acceptedShareID: String

    @State private var presentedQuestion: ExpandedQuestionState?
    @State private var errorMessage: String?
    @State private var isSendingReply = false
    @State private var isShowingSendConfirmation = false
    @State private var isShowingRemoveConfirmation = false

    private var acceptedShare: AcceptedQuestionListShare? {
        sharedQuestionListStore.acceptedShare(withID: acceptedShareID)
    }

    var body: some View {
        content
            .navigationTitle(acceptedShare?.share.listName ?? "Shared List")
            .toolbarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        isShowingRemoveConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel("Remove Shared List")
                    .popover(
                        isPresented: $isShowingRemoveConfirmation,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .top
                    ) {
                        SharedQuestionListConfirmationPopover(
                            title: "Remove shared list?",
                            message: "This removes the shared list from your account. The owner will no longer see future replies from you.",
                            actionTitle: "Remove Shared List",
                            actionRole: .destructive
                        ) {
                            isShowingRemoveConfirmation = false
                            leaveShare()
                        }
                    }
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()

                    Button {
                        isShowingSendConfirmation = true
                    } label: {
                        if isSendingReply {
                            ProgressView()
                        } else {
                            Label("Send Answers", systemImage: "paperplane.fill")
                        }
                    }
                    .disabled(isSendingReply)
                    .foregroundStyle(.blue)
                    .accessibilityIdentifier("shared-list-send-answers-button")
                    .popover(
                        isPresented: $isShowingSendConfirmation,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .bottom
                    ) {
                        SharedQuestionListConfirmationPopover(
                            title: "Send answers?",
                            message: "Your current answers for this shared list will be sent back to the list owner.",
                            actionTitle: "Send Answers"
                        ) {
                            isShowingSendConfirmation = false
                            sendReply()
                        }
                    }
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
        if let acceptedShare {
            List {
                Section {
                    Text("\(UserHandleFormatter.handle(acceptedShare.share.ownerDisplayName)) shared \(acceptedShare.share.questionIds.count) questions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                SharedQuestionListComparisonList(
                    share: acceptedShare.share,
                    leftTitle: UserHandleFormatter.handle(acceptedShare.share.ownerDisplayName),
                    rightTitle: "You",
                    leftAnswersForQuestion: acceptedShare.share.ownerTextSnapshot(for:),
                    rightAnswersForQuestion: { questionModel.myAnswers(for: $0) },
                    onOpenQuestion: { question in
                        presentedQuestion = ExpandedQuestionState(
                            question: question,
                            headerStyle: .plain
                        )
                    }
                )
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.theme.background)
            .accessibilityIdentifier("accepted-shared-list-detail")
        } else {
            ContentUnavailableView {
                Label("Shared List Not Found", systemImage: "exclamationmark.triangle")
            } description: {
                Text("This shared list may have been revoked.")
            }
        }
    }

    private func sendReply() {
        guard let acceptedShare else { return }
        isSendingReply = true
        errorMessage = nil
        Task {
            do {
                try await sharedQuestionListStore.sendReply(for: acceptedShare)
                toastCenter.showSuccess(
                    title: String(localized: "toast.answersSent"),
                    accessibilityIdentifier: "shared-list-reply-sent-toast"
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isSendingReply = false
        }
    }

    private func leaveShare() {
        guard let acceptedShare else { return }
        Task {
            do {
                try await sharedQuestionListStore.leave(acceptedShare)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SharedQuestionListConfirmationPopover: View {
    @Environment(\.dismiss) private var dismiss

    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    var actionRole: ButtonRole?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(role: actionRole, action: action) {
                Text(actionTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(actionRole == .destructive ? .red : .primary)

            Button(String(localized: "common.cancel")) {
                dismiss()
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(width: 320)
        .presentationCompactAdaptation(.popover)
    }
}

struct SharedQuestionListComparisonList: View {
    @EnvironmentObject private var sharedQuestionListStore: SharedQuestionListStore
    @EnvironmentObject private var questionModel: QuestionModel

    let share: QuestionListShare
    let leftTitle: String
    let rightTitle: String
    let leftAnswersForQuestion: (String) -> [String]
    let rightAnswersForQuestion: (String) -> [String]
    let onOpenQuestion: ((Question) -> Void)?

    private var questions: [Question] {
        sharedQuestionListStore.questions(in: share, using: questionModel)
    }

    var body: some View {
        Group {
            if questions.isEmpty {
                ContentUnavailableView {
                    Label("No Questions Yet", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("This shared list is empty. You can keep it accepted and answer questions after they are added to a future shared list.")
                }
                .listRowBackground(Color.clear)
            }

            ForEach(questions) { question in
                SharedQuestionComparisonCard(
                    question: question,
                    leftTitle: leftTitle,
                    leftAnswers: leftAnswersForQuestion(question.id),
                    rightTitle: rightTitle,
                    rightAnswers: rightAnswersForQuestion(question.id),
                    onOpen: onOpenQuestion.map { open in { open(question) } }
                )
                .padding(.vertical, 8)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
    }

    init(
        share: QuestionListShare,
        recipient: QuestionListShareRecipient,
        onOpenQuestion: ((Question) -> Void)?
    ) {
        self.share = share
        self.leftTitle = UserHandleFormatter.handle(share.ownerDisplayName)
        self.rightTitle = UserHandleFormatter.handle(recipient.recipientDisplayName)
        self.leftAnswersForQuestion = { share.ownerAnswerSnapshots[$0] ?? [] }
        self.rightAnswersForQuestion = { recipient.latestReplyAnswerSnapshots[$0] ?? [] }
        self.onOpenQuestion = onOpenQuestion
    }

    init(
        share: QuestionListShare,
        leftTitle: String,
        rightTitle: String,
        leftAnswersForQuestion: @escaping (String) -> [String],
        rightAnswersForQuestion: @escaping (String) -> [String],
        onOpenQuestion: ((Question) -> Void)?
    ) {
        self.share = share
        self.leftTitle = leftTitle
        self.rightTitle = rightTitle
        self.leftAnswersForQuestion = leftAnswersForQuestion
        self.rightAnswersForQuestion = rightAnswersForQuestion
        self.onOpenQuestion = onOpenQuestion
    }
}

struct SharedQuestionListComparisonView: View {
    @EnvironmentObject private var sharedQuestionListStore: SharedQuestionListStore

    let share: QuestionListShare
    let recipient: QuestionListShareRecipient

    var body: some View {
        List {
            SharedQuestionListComparisonList(
                share: share,
                recipient: recipient,
                onOpenQuestion: nil
            )
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.theme.background)
        .navigationTitle(UserHandleFormatter.handle(recipient.recipientDisplayName))
        .toolbarTitleDisplayMode(.inline)
        .task {
            if recipient.unreadByOwner {
                await sharedQuestionListStore.markReplySeen(
                    shareId: share.id,
                    recipientId: recipient.recipientId
                )
            }
        }
    }
}

struct SharedQuestionComparisonCard: View {
    let question: Question
    let leftTitle: String
    let leftAnswers: [String]
    let rightTitle: String
    let rightAnswers: [String]
    let onOpen: (() -> Void)?

    var body: some View {
        Group {
            if let onOpen {
                Button(action: onOpen) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
        .padding()
        .frame(minHeight: 220)
        .background(
            RoundedRectangle(
                cornerRadius: QuestionCardLayoutMetrics.compactCornerRadius,
                style: .continuous
            )
            .fill(Color.theme.secondaryBackground)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            categoryHeader

            Text(question.text)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text(leftTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                        .frame(height: 14)
                        .padding(.horizontal, 8)

                    Text(rightTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, 6)

                ForEach(0..<3, id: \.self) { index in
                    answerRow(index: index)
                }
            }
        }
    }

    private var categoryHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: Question.categoryIconName(question.category))
                .font(.caption.weight(.semibold))
                .frame(width: 18, alignment: .center)

            Text(Question.localizedCategoryTitle(question.category))
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                format: String(localized: "question.card.categoryAccessibility"),
                locale: AppLocalization.currentLocale,
                Question.localizedCategoryTitle(question.category)
            )
        )
    }

    private func answerRow(index: Int) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text(answer(leftAnswers, at: index))
                    .font(.subheadline)
                    .foregroundStyle(answer(leftAnswers, at: index) == "-" ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)

                Divider()
                    .padding(.horizontal, 8)

                Text(answer(rightAnswers, at: index))
                    .font(.subheadline)
                    .foregroundStyle(answer(rightAnswers, at: index) == "-" ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }

            Divider()
        }
    }

    private func answer(_ answers: [String], at index: Int) -> String {
        guard index < answers.count else { return "-" }
        let trimmed = answers[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }
}

private struct SharedQuestionListRow: View {
    let title: String
    let subtitle: String
    let iconName: String
    let badgeText: String
    let showsUnreadDot: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                if showsUnreadDot {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 9, height: 9)
                        .offset(x: 2, y: -2)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(badgeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
