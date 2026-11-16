import NukeUI
import OSLog
import SwiftUI

/// Only the card's view code reads or writes this, so it lives on the main actor with it.
@MainActor
private enum GuestWarningDismissalSession {
    static var dismissedQuestionIDs = Set<String>()
}

private enum AnswerField: Hashable {
    case slot(Int)
}

private struct PresentedAnswerImage: Identifiable {
    enum Source {
        case local(UIImage)
        case remote(URL)
    }

    let id = UUID()
    let source: Source
    /// The slot the image came from; the viewer zooms out of that slot's thumbnail.
    let slotIndex: Int
}

struct QuestionCardExpandedView: View {
    let expandedState: ExpandedQuestionState
    let model: QuestionModel
    let badgeModel: BadgeModel?
    let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.answerDraftStore) private var answerDraftStore
    @Environment(\.toastCenter) private var toastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Read rather than built. The editor used to ask `UITestLaunchOptions` whether it was allowed
    /// to construct one, which made a production view aware of the test harness. `nil` still means
    /// the app's no-AI mode, and it still comes from whoever wired the app.
    @Environment(\.aiService) private var aiService
    @Environment(\.answerImageSuggestionService) private var answerImageSuggestionService
    @EnvironmentObject private var authModel: AuthModel
    @EnvironmentObject private var favoriteStore: FavoriteStore
    @EnvironmentObject private var guestFavoriteModel: GuestFavoriteModel
    @EnvironmentObject private var questionListStore: QuestionListStore
    /// The answer being edited. One value, three slots, each slot's image in exactly one state.
    @State private var draft: AnswerDraft
    @State private var aiLoadingIndex: Int? = nil
    @State private var aiError: String?
    @State private var quickAnswerSuggestions: [String] = []
    @State private var quickSuggestionsIncludeAI = false
    @State private var aiFilledAnswers = AIFilledAnswers()
    @State private var isLoadingQuickSuggestions = false
    @FocusState private var focusedField: AnswerField?

    @State private var imageSuggestions: [[AnswerImageSuggestion]] = [[], [], []]
    @State private var imageSuggestionLoadingIndex: Int? = nil
    @State private var imageSuggestionMessages: [String?] = [nil, nil, nil]
    @State private var showingImagePicker = false
    @State private var activeImageSlot = 0
    @State private var isUploading = false
    /// Bumped each time the answer becomes ready to save; replays the haptic and, before iOS 26, the tick's bounce.
    @State private var saveTickReplayCount = 0
    @State private var uploadError: String?
    /// Raised when X is tapped with unsaved changes; drives the save-or-drop dialog on X.
    @State private var isConfirmingClose = false

    @State private var presentedAnswerImage: PresentedAnswerImage?
    @Namespace private var answerImageZoomNamespace
    @State private var isShowingQuestionLists = false
    @State private var dismissedGuestWarningQuestionID: String?

    /// What the editor opened with, for deciding whether anything changed and which images went away.
    private let baseline: NormalizedAnswer

    private var question: Question { expandedState.question }
    private var currentQuestion: Question {
        model.questions.first(where: { $0.id == question.id }) ?? question
    }

    private var currentQuestionLanguageCode: String {
        AppLocalization.languageCode(forText: currentQuestion.text) ?? AppLocalization.currentLanguageCode
    }

    private var preferredAnswerLanguageCode: String {
        AppLocalization.currentLanguageCode
    }

    private var headerStyle: ExpandedQuestionHeaderStyle { expandedState.headerStyle }

    private var isFavorite: Bool {
        favoriteStore.state(of: currentQuestion)
    }

    private var isInQuestionList: Bool {
        !questionListStore.listsContaining(questionId: question.id).isEmpty
    }

    private var questionListAccessibilityLabel: String {
        String(localized: isInQuestionList ? "question.card.lists.manageSaved" : "question.card.lists.add")
    }

    private var shouldShowGuestWarningBanner: Bool {
        authModel.isAnonymous &&
            dismissedGuestWarningQuestionID != question.id &&
            !GuestWarningDismissalSession.dismissedQuestionIDs.contains(question.id)
    }

    private var questionListButton: some View {
        Button {
            if authModel.isAnonymous {
                guestFavoriteModel.requestGuestUpgrade()
            } else {
                isShowingQuestionLists = true
            }
        } label: {
            Label(questionListAccessibilityLabel, systemImage: isInQuestionList ? "bookmark.fill" : "bookmark")
                .labelStyle(.iconOnly)
                .foregroundStyle(isInQuestionList ? Color.accentColor : .primary)
        }
        .accessibilityIdentifier("question-card-fullscreen-list")
        .accessibilityLabel(questionListAccessibilityLabel)
    }

    private var favoriteButton: some View {
        Button {
            toggleFavorite()
        } label: {
            Label(
                String(localized: isFavorite ? "common.favorite.remove" : "common.favorite.add"),
                systemImage: isFavorite ? "star.fill" : "star"
            )
            .labelStyle(.iconOnly)
            .foregroundStyle(isFavorite ? .yellow : .primary)
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            .animation(.easeOut(duration: 0.2), value: isFavorite)
        }
        .accessibilityIdentifier("question-card-fullscreen-favorite")
        .accessibilityLabel(
            String(localized: isFavorite ? "common.favorite.remove" : "common.favorite.add")
        )
    }

    private func toggleFavorite() {
        // On the tap, not on `isFavorite`: a server snapshot or a rollback stays silent.
        Haptics.playLightImpact(for: "favorite-tap")
        Task {
            await toastCenter.toggleFavorite(currentQuestion, using: favoriteStore)
        }
    }

    private var currentAnswers: [String] {
        draft.normalized().texts
    }

    /// Whether closing now would drop an edit. The same rule the store uses to skip a no-op save.
    private var hasUnsavedChanges: Bool {
        draft.hasChanges(against: baseline)
    }

    /// A Complete Answer that saving would change. Its false-to-true edge replays the save tick.
    private var isReadyToSave: Bool {
        draft.isReadyToSave(against: baseline)
    }

    private var visibleQuickAnswerSuggestions: [String] {
        QuickAnswerSuggestionResolver.merge(
            localCandidates: quickAnswerSuggestions,
            aiCandidates: [],
            excluding: currentAnswers,
            limit: 5
        )
    }

    private var shouldShowQuickSuggestions: Bool {
        quickSuggestionTargetIndex() != nil
    }

    init(
        expandedState: ExpandedQuestionState,
        model: QuestionModel,
        badgeModel: BadgeModel? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.expandedState = expandedState
        self.model = model
        self.badgeModel = badgeModel
        self.onClose = onClose

        // One normalizer, not three local copies of the same padding and trimming.
        let questionId = expandedState.question.id
        let opened = NormalizedAnswer(
            texts: model.myAnswers(for: questionId),
            urls: model.myImageURLs(for: questionId),
            attributions: model.myImageAttributions(for: questionId)
        )

        baseline = opened
        _draft = State(initialValue: AnswerDraft(opened))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.theme.background
                    .ignoresSafeArea()

                fullscreenAccessibilityMarker

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            headerSection

                            VStack(alignment: .leading, spacing: 18) {
                                ForEach(0 ..< 3, id: \.self) { index in
                                    answerSlot(at: index)
                                        .id("slot_\(index)")
                                }
                            }

                            if showsWandNotice {
                                AIGeneratedNotice(surface: .wandFill)
                            }

                            if let error = aiError {
                                editorError(error)
                            }

                            if let error = uploadError {
                                editorError(error)
                            }

                            if shouldShowQuickSuggestions {
                                quickSuggestionsSection
                            }

                            if shouldShowGuestWarningBanner {
                                guestWarningBanner
                            }

                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 28)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: geometry.size.height,
                            alignment: .topLeading
                        )
                        // A tap outside the answer fields closes the keyboard; the scroll view only
                        // closes it on a drag. The fields, buttons, and menus inside keep their own
                        // taps. Not a `Button`: the whole content cannot be one control.
                        .contentShape(.rect)
                        .onTapGesture {
                            setFocusedField(nil)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: focusedField) { _, newValue in
                        if case let .slot(index) = newValue {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo("slot_\(index)", anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(
                image: Binding(
                    get: { draft[activeImageSlot].image.pendingLocalImage },
                    // Picking an image replaces whatever the slot held. No need to clear a
                    // suggestion or its attribution by hand — one slot cannot hold both.
                    set: { newImage in
                        draft[activeImageSlot].image = newImage.map(SlotImage.pendingLocal) ?? .none
                    }
                )
            )
        }
        .sheet(isPresented: $isShowingQuestionLists) {
            QuestionListSelectionSheet(question: currentQuestion)
        }
        .fullScreenCover(item: $presentedAnswerImage) { presentedImage in
            AnswerImageFullscreenView(presentedImage: presentedImage)
                .modifier(AnswerImageZoomTransition(
                    sourceID: presentedImage.slotIndex,
                    namespace: answerImageZoomNamespace
                ))
        }
        .overlay { savingOverlay }
        .draftDismissalGuard(
            hasUnsavedChanges: hasUnsavedChanges,
            onSave: { _ = commitDraft() }
        )
        .task(id: question.id) {
            await loadQuickAnswerSuggestions()
        }
        .onChange(of: isReadyToSave) { wasReady, isReady in
            if !wasReady && isReady {
                saveTickReplayCount += 1
            }
        }
        // Light impact, not `.success`: nothing is saved yet.
        .sensoryFeedback(.impact(weight: .light), trigger: saveTickReplayCount)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: requestClose) {
                    Label(String(localized: "common.close"), systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("question-card-fullscreen-close")
                .accessibilityLabel(String(localized: "common.close"))
                // On the X itself, so iOS 26 anchors the dialog to it like Mail's draft menu.
                .confirmationDialog(
                    String(localized: "question.expanded.unsavedChangesTitle"),
                    isPresented: $isConfirmingClose,
                    titleVisibility: .hidden
                ) {
                    Button(String(localized: "question.expanded.saveAndClose"), action: saveAndClose)
                    Button(
                        String(localized: "question.expanded.closeWithoutSaving"),
                        role: .destructive,
                        action: dismissFullscreen
                    )
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Group {
                    if isUploading {
                        ProgressView()
                    } else {
                        Label(
                            String(localized: "question.expanded.saveAccessibility"),
                            systemImage: "checkmark"
                        )
                        .labelStyle(.iconOnly)
                    }
                }
                .saveTickButton(replayCount: saveTickReplayCount, action: saveAndClose)
                .disabled(isUploading)
                .accessibilityIdentifier("question-card-fullscreen-save")
                .accessibilityLabel(String(localized: "question.expanded.saveAccessibility"))
                .accessibilityHint(String(localized: "question.expanded.saveHint"))
            }

            ToolbarItemGroup(placement: .bottomBar) {
                QuestionCreatorAttributionView(question: currentQuestion, textAlignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer()

                HStack(spacing: 14) {
                    ShareLink(item: currentQuestion.shareURL) {
                        Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityIdentifier("question-card-fullscreen-share")
                    .accessibilityLabel(String(localized: "common.share"))

                    questionListButton

                    favoriteButton
                }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Button {
                    moveFocus(by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(focusedField == .slot(0))

                Button {
                    moveFocus(by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(focusedField == .slot(2))

                Spacer()

                Button(String(localized: "common.done")) {
                    setFocusedField(nil)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var fullscreenAccessibilityMarker: some View {
        Text(" ")
            .font(.system(size: 1))
            .foregroundStyle(.clear)
            .padding(.top, 1)
            .padding(.leading, 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityIdentifier("question-card-fullscreen-root")
            .accessibilityLabel(question.text)
            .accessibilityAddTraits(.isModal)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            QuestionCardHeaderRow(question: currentQuestion, headerStyle: headerStyle)
            headerTitle
        }
    }

    private var guestWarningBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .systemOrange).opacity(0.82))
                    .accessibilityHidden(true)

                Text(String(localized: "question.guestWarning.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .systemOrange).opacity(0.9))
            }

            Text(String(localized: "question.guestWarning.body"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(String(localized: "question.guestWarning.cta")) {
                guestFavoriteModel.requestGuestUpgrade()
            }
            .buttonStyle(.bordered)
            .tint(Color(uiColor: .systemOrange))
            .controlSize(.small)
            .accessibilityLabel(String(localized: "question.guestWarning.cta"))
            .accessibilityHint(String(localized: "question.guestWarning.ctaHint"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 40)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .systemYellow).opacity(0.11))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(uiColor: .systemOrange).opacity(0.22), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                GuestWarningDismissalSession.dismissedQuestionIDs.insert(question.id)
                dismissedGuestWarningQuestionID = question.id
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .padding(.trailing, 2)
            .accessibilityLabel(String(localized: "question.guestWarning.dismiss"))
            .accessibilityHint(String(localized: "question.guestWarning.dismiss"))
        }
    }

    private var headerTitle: some View {
        Text(currentQuestion.text)
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editorError(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .transition(.opacity)
    }

    @ViewBuilder
    private func answerSlot(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                TextField(
                    Question.answerPlaceholders[index],
                    text: $draft[index].text,
                    axis: .vertical
                )
                .focused($focusedField, equals: .slot(index))
                .lineLimit(1 ... 3)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.sentences)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                .accessibilityIdentifier("question-card-input-\(index)")

                slotActionRail(at: index)
            }

            if let message = imageSuggestionMessages[index] {
                imageSuggestionMessage(message, index: index)
            }

            if imageSuggestionLoadingIndex == index {
                imageSuggestionLoadingView
            } else if !imageSuggestions[index].isEmpty {
                imageSuggestionRow(for: index)
            }

            switch draft[index].image {
            case .none:
                EmptyView()

            case let .pendingLocal(localImage):
                imagePreview(uiImage: localImage, index: index)

            case let .pendingSuggestion(suggestion):
                if let url = suggestion.previewImageURL {
                    suggestedImagePreview(url: url, index: index)
                }

            case let .saved(urlString, _):
                if let url = URL(string: urlString) {
                    LazyImage(url: url) { state in
                        if let uiImage = state.imageContainer?.image {
                            imagePreview(uiImage: uiImage, index: index)
                        } else if state.error != nil {
                            EmptyView()
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.secondary.opacity(0.18))
                                .frame(height: Self.imagePreviewMaxHeight)
                                .overlay(ProgressView())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(answerSlotBorderColor(for: index), lineWidth: answerSlotBorderWidth(for: index))
        }
    }

    private var quickSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isLoadingQuickSuggestions && quickAnswerSuggestions.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(String(localized: "ai.input.quickSuggestionsTitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if !visibleQuickAnswerSuggestions.isEmpty {
                Text(String(localized: "ai.input.quickSuggestionsTitle"))
                    .font(.headline)
                    .foregroundStyle(.primary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(visibleQuickAnswerSuggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                applyQuickSuggestion(suggestion)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.regular)
                            .disabled(!canApplyQuickSuggestion)
                            .accessibilityIdentifier(
                                "question-card-quick-suggestion-\(QuickAnswerSuggestionResolver.normalizedKey(for: suggestion))"
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }

                if quickSuggestionsIncludeAI {
                    AIGeneratedNotice(surface: .quickAnswers)
                }
            }
        }
    }

    /// True while a slot still holds text the wand wrote.
    private var showsWandNotice: Bool {
        let texts: [String] = (0 ..< AnswerDraft.slotCount).map { draft[$0].text }
        return aiFilledAnswers.hasAIText(in: texts)
    }

    private var canApplyQuickSuggestion: Bool {
        quickSuggestionTargetIndex() != nil
    }

    private func setFocusedField(_ field: AnswerField?) {
        guard focusedField != field else { return }
        focusedField = field
    }

    @ViewBuilder
    private func slotActionRail(at index: Int) -> some View {
        HStack(spacing: 8) {
            if aiLoadingIndex == index {
                ProgressView()
                    .frame(width: 36, height: 36)
                    .accessibilityLabel(String(localized: "question.ai.fill"))
            } else if shouldShowAIAction(for: index) {
                Button {
                    Task { await fillWithAI(at: index) }
                } label: {
                    slotActionIcon("wand.and.sparkles")
                }
                .buttonStyle(.plain)
                .disabled(aiLoadingIndex != nil)
                .opacity(aiLoadingIndex == nil ? 1 : 0.45)
                .accessibilityLabel(String(localized: "question.ai.fill"))
                .accessibilityHint(String(localized: "question.ai.fillHint"))
            } else {
                Color.clear
                    .frame(width: 36, height: 36)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            Menu {
                Button {
                    activeImageSlot = index
                    showingImagePicker = true
                } label: {
                    Label(String(localized: "question.image.chooseFromLibrary"), systemImage: "photo")
                }

                Button {
                    Task { await findImages(at: index) }
                } label: {
                    Label(String(localized: "question.image.find"), systemImage: "magnifyingglass")
                }
            } label: {
                imageActionIcon(at: index)
            }
            // Drop focus as the menu opens. A focused answer field keeps first responder under the
            // menu, the menu installs its type-select key input as the keyboard's delegate, and
            // every keyboard-toolbar reload makes it install a fresh one: the loop pegs the CPU and
            // floods the log until the menu closes. The menu content's `onAppear` is no hook for
            // this; it fires on the first open only. Drop it on touch-up, not touch-down: the
            // keyboard leaving scrolls this button out from under the finger, and a touch-down
            // dismissal moves it before the menu sees the tap, so the menu never opens.
            // `TapGesture` never fires here: the menu claims the tap. A zero-distance drag still
            // sees the touch.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).onEnded { _ in setFocusedField(nil) }
            )
            .disabled(imageSuggestionLoadingIndex == index)
            .accessibilityLabel(
                hasActiveImage(at: index)
                    ? String(localized: "question.image.change")
                    : String(localized: "question.image.add")
            )
            .accessibilityHint(String(localized: "question.image.pickHint"))
        }
        .frame(width: 80, alignment: .trailing)
        .accessibilityElement(children: .contain)
    }

    private func slotActionIcon(
        _ systemName: String,
        foreground: Color = Color.accentColor,
        background: Color = Color.accentColor.opacity(0.16),
        size: CGFloat = 36
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(background)
            )
            .contentShape(Circle())
    }

    private func imageActionIcon(at index: Int) -> some View {
        let hasImage = hasActiveImage(at: index)

        return slotActionIcon(
            hasImage ? "photo.fill" : "photo.on.rectangle.angled",
            foreground: hasImage ? Color.primary.opacity(0.72) : Color.secondary,
            background: hasImage ? Color.primary.opacity(0.10) : Color.secondary.opacity(0.10),
            size: 34
        )
    }

    private func answerSlotBorderColor(for index: Int) -> Color {
        focusedField == .slot(index) ? Color.accentColor.opacity(0.45) : Color.theme.border.opacity(0.22)
    }

    private func answerSlotBorderWidth(for index: Int) -> CGFloat {
        focusedField == .slot(index) ? 1.4 : 1
    }

    private func shouldShowAIAction(for index: Int) -> Bool {
        guard draft.indices.contains(index) else { return false }
        return draft[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func hasActiveImage(at index: Int) -> Bool {
        draft[index].image.isPresent
    }

    private static let imagePreviewMaxHeight: CGFloat = 160
    private static let imageSuggestionSpacing: CGFloat = 10

    private func imagePreview(uiImage: UIImage, index: Int) -> some View {
        let aspect = uiImage.size.width / uiImage.size.height
        let displayHeight = min(uiImage.size.height, Self.imagePreviewMaxHeight)
        let displayWidth = displayHeight * aspect

        return Image(uiImage: uiImage)
            .resizable()
            .frame(width: displayWidth, height: displayHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .matchedTransitionSource(id: index, in: answerImageZoomNamespace)
            .overlay(alignment: .topTrailing) {
                Button {
                    // Whatever the slot held, removing it is one assignment. The caller used to have
                    // to say which of three arrays its image came from so the right ones got cleared.
                    draft[index].image = .none
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.46))
                        )
                        .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "question.image.delete"))
            }
            .onTapGesture {
                presentedAnswerImage = presentedImage(at: index, fallbackImage: uiImage)
            }
            .accessibilityLabel(String(localized: "question.image.open"))
            .accessibilityHint(String(localized: "question.image.openHint"))
            .accessibilityAddTraits(.isButton)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func suggestedImagePreview(url: URL, index: Int) -> some View {
        LazyImage(url: url) { state in
            if let uiImage = state.imageContainer?.image {
                imagePreview(uiImage: uiImage, index: index)
            } else if state.error != nil {
                EmptyView()
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: Self.imagePreviewMaxHeight)
                    .overlay(ProgressView())
            }
        }
    }

    private var imageSuggestionLoadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(String(localized: "question.image.searching"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func imageSuggestionMessage(_ message: String, index: Int) -> some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !currentAnswers[index].isEmpty {
                Button(String(localized: "common.retry")) {
                    Task { await findImages(at: index) }
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private func imageSuggestionRow(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let side = imageSuggestionSide(for: proxy.size.width)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Self.imageSuggestionSpacing) {
                        ForEach(imageSuggestions[index]) { suggestion in
                            Button {
                                selectSuggestedImage(suggestion, at: index)
                            } label: {
                                suggestionThumbnail(suggestion, side: side)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                String(
                                    format: String(localized: "question.image.suggestionAccessibility"),
                                    locale: AppLocalization.currentLocale,
                                    suggestion.photographer.isEmpty ? suggestion.photoId : suggestion.photographer
                                )
                            )
                        }
                    }
                    .padding(.trailing, side * 0.5)
                }
            }
            .frame(height: 104)

            Text(String(localized: "question.image.pexelsAttribution"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func imageSuggestionSide(for availableWidth: CGFloat) -> CGFloat {
        let preferredVisibleCount: CGFloat = availableWidth < 310 ? 2.5 : 3.5
        let totalSpacing = Self.imageSuggestionSpacing * (preferredVisibleCount - 1)
        return max(76, min(104, (availableWidth - totalSpacing) / preferredVisibleCount))
    }

    private func suggestionThumbnail(_ suggestion: AnswerImageSuggestion, side: CGFloat) -> some View {
        LazyImage(url: suggestion.thumbnailImageURL) { state in
            if let image = state.image {
                image
                    .resizable()
                    .scaledToFill()
            } else if state.error != nil {
                Image(systemName: "photo")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.12))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.secondary.opacity(0.14))
                    .overlay(ProgressView())
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.theme.border.opacity(0.18), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var savingOverlay: some View {
        if isUploading {
            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()

                ProgressView()
                    .controlSize(.large)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel(String(localized: "common.loading"))
            }
        }
    }

    private func presentedImage(at index: Int, fallbackImage: UIImage) -> PresentedAnswerImage {
        switch draft[index].image {
        case let .pendingLocal(localImage):
            return PresentedAnswerImage(source: .local(localImage), slotIndex: index)

        case let .pendingSuggestion(suggestion):
            if let url = suggestion.previewImageURL {
                return PresentedAnswerImage(source: .remote(url), slotIndex: index)
            }

        case let .saved(urlString, _):
            if let url = URL(string: urlString) {
                return PresentedAnswerImage(source: .remote(url), slotIndex: index)
            }

        case .none:
            break
        }

        return PresentedAnswerImage(source: .local(fallbackImage), slotIndex: index)
    }

    private var shareText: String {
        var text = String(
            format: String(localized: "share.questionLine"),
            locale: AppLocalization.currentLocale,
            currentQuestion.text
        ) + "\n\n"
        for (index, answer) in currentAnswers.enumerated() where !answer.isEmpty {
            text += String(
                format: String(localized: "share.answerLine"),
                locale: AppLocalization.currentLocale,
                index + 1,
                answer
            ) + "\n"
        }
        return text
    }

    private func moveFocus(by delta: Int) {
        guard case let .slot(current) = focusedField else { return }
        let next = current + delta
        if next >= 0 && next < 3 {
            setFocusedField(.slot(next))
        }
    }

    private func quickSuggestionTargetIndex() -> Int? {
        draft.indices.first {
            draft[$0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func applyQuickSuggestion(_ suggestion: String) {
        guard let targetIndex = quickSuggestionTargetIndex() else { return }

        draft[targetIndex].text = suggestion
        setFocusedField(nil)
    }

    @MainActor
    private func findImages(at index: Int) async {
        guard draft.indices.contains(index) else { return }

        let answerText = currentAnswers[index]
        guard !answerText.isEmpty else {
            imageSuggestions[index] = []
            imageSuggestionMessages[index] = String(localized: "question.image.emptyAnswerMessage")
            return
        }

        guard let answerImageSuggestionService else {
            imageSuggestions[index] = []
            imageSuggestionMessages[index] = nil
            return
        }

        imageSuggestionMessages[index] = nil
        imageSuggestionLoadingIndex = index

        do {
            let suggestions = try await answerImageSuggestionService.suggestImages(
                questionId: question.id,
                slotIndex: index,
                answerText: answerText
            )
            imageSuggestions[index] = suggestions
            imageSuggestionMessages[index] = nil
        } catch AnswerImageSuggestionServiceError.noResults {
            imageSuggestions[index] = []
            imageSuggestionMessages[index] = String(localized: "question.image.noResults")
        } catch {
            imageSuggestions[index] = []
            imageSuggestionMessages[index] = error.localizedDescription
        }

        if imageSuggestionLoadingIndex == index {
            imageSuggestionLoadingIndex = nil
        }
    }

    private func selectSuggestedImage(_ suggestion: AnswerImageSuggestion, at index: Int) {
        // Was four assignments: set the suggestion and its attribution, then clear the local image and
        // the saved URL so the slot did not appear to hold three images at once.
        draft[index].image = .pendingSuggestion(suggestion)
        imageSuggestions[index] = []
        imageSuggestionMessages[index] = nil
    }

    private func fillWithAI(at index: Int) async {
        guard let aiService else { return }

        aiError = nil
        aiLoadingIndex = index
        defer { aiLoadingIndex = nil }
        do {
            let suggestions = try await aiService.suggestAnswers(for: currentQuestion.text)
            if index < suggestions.count {
                draft[index].text = suggestions[index]
                aiFilledAnswers.record(suggestions[index], at: index)
            }
        } catch {
            aiError = error.localizedDescription
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                aiError = nil
            }
        }
    }

    private func loadQuickAnswerSuggestions() async {
        guard shouldShowQuickSuggestions else {
            await MainActor.run {
                quickAnswerSuggestions = []
                isLoadingQuickSuggestions = false
            }
            return
        }

        let existingAnswers = currentAnswers.filter { !$0.isEmpty }
        let answerLanguageCode = preferredAnswerLanguageCode
        let localCandidates = currentQuestion.quickAnswerCandidates(
            limit: 5,
            excluding: existingAnswers,
            preferredLanguageCode: answerLanguageCode
        )

        await MainActor.run {
            quickAnswerSuggestions = localCandidates
            quickSuggestionsIncludeAI = false
            isLoadingQuickSuggestions = localCandidates.count < 5
        }

        guard localCandidates.count < 5 else {
            await MainActor.run {
                isLoadingQuickSuggestions = false
            }
            return
        }

        guard let aiService else {
            await MainActor.run {
                isLoadingQuickSuggestions = false
            }
            return
        }

        do {
            let aiCandidates = try await aiService.suggestQuickAnswers(
                for: currentQuestion.text,
                category: currentQuestion.category,
                excluding: existingAnswers + localCandidates,
                languageName: AppLocalization.promptLanguageName(forLanguageCode: answerLanguageCode),
                limit: 5 - localCandidates.count
            )

            await MainActor.run {
                quickAnswerSuggestions = QuickAnswerSuggestionResolver.merge(
                    localCandidates: localCandidates,
                    aiCandidates: aiCandidates,
                    excluding: existingAnswers,
                    limit: 5
                )
                quickSuggestionsIncludeAI = !aiCandidates.isEmpty
                isLoadingQuickSuggestions = false
            }
        } catch {
            await MainActor.run {
                quickAnswerSuggestions = localCandidates
                isLoadingQuickSuggestions = false
            }
        }
    }

    /// Closes at once when nothing changed; otherwise asks whether to save or drop the draft.
    private func requestClose() {
        if hasUnsavedChanges {
            isConfirmingClose = true
        } else {
            dismissFullscreen()
        }
    }

    /// Saves the draft, then closes once.
    private func saveAndClose() {
        guard !isUploading else { return }

        // `.success` belongs to a save that really started (#56); a tap with nothing changed stays
        // silent. A UIKit generator, because this view is dismissed in the same call.
        if commitDraft() {
            Haptics.playSuccess(for: "save-success")
        }
        dismissFullscreen()
    }

    /// Hands the draft to `AnswerDraftStore` without closing.
    ///
    /// Everything this used to do — the optimistic write, the upload fan-out, the compare-and-swap
    /// re-persist, the rollback and the orphan cleanup — lives in the store now, tested. What is left
    /// here is the editor's own business: reflect the handoff in local state. The iOS 27 sheet
    /// dismissal dialog calls this alone, because the system finishes that dismissal itself.
    @discardableResult
    private func commitDraft() -> Bool {
        uploadError = nil

        let started = answerDraftStore.save(draft, baseline: baseline, for: question.id, in: model)

        // The images are the store's problem now, so stop showing them as this editor's pending work.
        if started, draft.hasPendingUploads {
            draft = draft.clearingPendingImages()
        }
        return started
    }

    private func dismissFullscreen() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

/// Zooms the viewer out of its thumbnail. Reduce Motion drops the zoom: it cross-fades on
/// iOS 27 (the same shim as the question card zoom) and keeps the plain cover before that.
private struct AnswerImageZoomTransition: ViewModifier {
    let sourceID: Int
    let namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The setting the viewer opened with: a change while it is open must not swap the branch
    /// below and rebuild the viewer.
    @State private var reduceMotionAtOpen: Bool?

    @ViewBuilder
    func body(content: Content) -> some View {
        Group {
            if reduceMotionAtOpen ?? reduceMotion {
                content.backport.crossFadeNavigationTransition()
            } else {
                content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
            }
        }
        .onAppear { reduceMotionAtOpen = reduceMotion }
    }
}

// TEMPORARY DEBUG (chore(debug) commit, dropped before merge): why a double tap does not zoom.
private let imageViewerLog = Logger(subsystem: "com.ttb.debug", category: "ImageViewer")

private struct AnswerImageFullscreenView: View {
    let presentedImage: PresentedAnswerImage

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The zoom. It stays when the fingers lift; it eases back to 1 only when a pinch ends near
    /// 1x, on a double tap, or when the pinch goes back out.
    @State private var zoomScale: CGFloat = 1.0
    /// The pan while zoomed, in screen points from centre. It follows the finger directly.
    @State private var panOffset: CGSize = .zero
    /// `zoomScale` and `panOffset` when the running pinch or pan began; `nil` between gestures.
    /// `isPinching` and `isDragging` are `@GestureState`, so they fall back to `false` when a
    /// gesture is cancelled (system close gesture, interruption) as well as when it ends; the
    /// `onChange` below then clears the start values.
    @State private var pinchStartScale: CGFloat?
    @State private var panStartOffset: CGSize?
    @GestureState private var isPinching = false
    @GestureState private var isDragging = false
    /// What the running drag does, fixed when it begins: a drag that began zoomed, or saw a pinch,
    /// never feeds `dragOffset` and never closes the viewer.
    @State private var dragMode = ImageViewerPanMath.DragMode.idle
    /// The full screen, safe area included: the pan clamp and the tap test measure against it.
    @State private var containerFrame: CGRect = .zero
    /// The safe-area region the image is fitted to at 1x.
    @State private var imageAreaFrame: CGRect = .zero
    @State private var fittedSize: CGSize = .zero
    /// The finger's vertical drag at 1x. A `@GestureState`, so a cancelled drag (the system zoom-dismiss
    /// gesture takes the touch) falls back to 0; the `animation(value:)` below eases it.
    @GestureState private var dragOffset: CGFloat = 0
    /// Holds the drag's last offset once it closes the viewer, so the image does not snap back
    /// while the cover animates away.
    @State private var dismissOffset: CGFloat = 0

    private var totalOffset: CGFloat { dragOffset + dismissOffset }

    private var isZoomed: Bool { zoomScale > 1.0 }

    /// The image rests in the safe area, the clamp measures the full screen; the two centres can
    /// differ by a few points.
    private var panMath: ImageViewerPanMath {
        let shift = imageAreaFrame == .zero
            ? CGSize.zero
            : CGSize(
                width: imageAreaFrame.midX - containerFrame.midX,
                height: imageAreaFrame.midY - containerFrame.midY
            )
        return ImageViewerPanMath(
            containerSize: containerFrame.size,
            fittedSize: fittedSize,
            restCenterShift: shift
        )
    }

    /// The snap-back of a short or cancelled 1x drag. Reduce Motion: a short ease-out.
    private var snapBackAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // Measures the safe-area region the image is fitted to, away from the transforms below.
            Color.clear
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { imageAreaFrame = $0 }

            imageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(zoomScale)
                .offset(x: panOffset.width, y: panOffset.height + totalOffset)
                .accessibilityHidden(true)

            // One static, full-screen layer takes every gesture, so the transforms above never move
            // the touch area. A tap outside the visible image closes the viewer (not while zoomed);
            // a double tap on it zooms.
            Color.clear
                .contentShape(.rect)
                .ignoresSafeArea()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { containerFrame = $0 }
                .gesture(tapGesture)
                .gesture(magnifyGesture)
                .gesture(dragGesture)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel(String(localized: "question.image.fullscreen"))
                .accessibilityHint(String(localized: "question.image.fullscreenHint"))
                // VoiceOver's activate: the same whether or not the image has loaded.
                .accessibilityAction { toggleZoom() }
                .accessibilityZoomAction { action in
                    withAnimation(resetAnimation) {
                        zoomScale = ImageViewerPanMath.steppedScale(
                            from: zoomScale,
                            zoomingIn: action.direction == .zoomIn
                        )
                        panOffset = panMath.clamp(panOffset, at: zoomScale)
                    }
                }

            closeButton
        }
        .opacity(1 - (abs(totalOffset) / 300.0))
        .animation(dragOffset == 0 ? snapBackAnimation : nil, value: dragOffset)
        .accessibilityAddTraits(.isModal)
        // Zoomed, a swipe down pans the image; it must not also close the viewer.
        .interactiveDismissDisabled(isZoomed)
        .onChange(of: panMath) {
            panOffset = panMath.clamp(panOffset, at: zoomScale)
        }
        .onChange(of: zoomScale) { old, new in
            debugLog("onChange zoomScale \(old) -> \(new)")
        }
        .onAppear { logGeometry("onAppear") }
        .task {
            try? await Task.sleep(for: .seconds(1))
            logGeometry("after 1s")
        }
        .onChange(of: isPinching) {
            guard !isPinching else { return }
            pinchStartScale = nil
            if zoomScale < ImageViewerPanMath.restScaleTolerance {
                resetZoom()
            }
        }
        .onChange(of: isDragging) {
            guard !isDragging else { return }
            // `onEnded` already ran for a finished drag and left `.idle`; this is a cancelled one.
            if dragMode == .pan {
                withAnimation(settleAnimation()) { panOffset = panMath.clamp(panOffset, at: zoomScale) }
            }
            panStartOffset = nil
            dragMode = .idle
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        switch presentedImage.source {
        case let .local(image):
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { fittedSize = $0 }
        case let .remote(url):
            // Nuke, like the thumbnail: the zoom carries the picture the thumbnail already cached.
            LazyImage(url: url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { fittedSize = $0 }
                } else if state.error != nil {
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    closeViewer()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white, Color.black.opacity(0.5))
                        .padding(16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "common.close"))
                .accessibilityHint(String(localized: "question.image.closeHint"))
            }
            Spacer()
        }
    }

    /// Zoom in and out. Reduce Motion swaps the spring for a short ease-out.
    private var resetAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0)
    }

    /// Glide after a release, without bounce. Reduce Motion drops the spring and the momentum.
    /// `initialVelocity` is the release speed along the glide, as a share of its distance per second.
    private func settleAnimation(initialVelocity: Double = 0) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.2)
            : .interpolatingSpring(duration: 0.45, bounce: 0, initialVelocity: initialVelocity)
    }

    private func resetZoom() {
        withAnimation(resetAnimation) {
            zoomScale = 1.0
            panOffset = .zero
        }
    }

    private func toggleZoom() {
        debugLog("toggleZoom entry zoomScale=\(zoomScale)")
        if isZoomed {
            resetZoom()
        } else {
            withAnimation(resetAnimation) { zoomScale = ImageViewerPanMath.doubleTapScale }
        }
        debugLog("toggleZoom result zoomScale=\(zoomScale)")
    }

    private func debugLog(_ message: String) {
        imageViewerLog.notice("\(message, privacy: .public)")
    }

    private func logGeometry(_ when: String) {
        let rect = panMath.visibleImageRect(at: zoomScale, offset: panOffset)
        debugLog(
            "geometry \(when): container=\(containerFrame.debugDescription) "
                + "imageArea=\(imageAreaFrame.debugDescription) fitted=\(fittedSize.debugDescription) "
                + "visibleRect=\(rect.debugDescription) shift=\(panMath.restCenterShift.debugDescription)"
        )
    }

    /// Closes the viewer. A zoomed image drops to 1x first, with no animation, so the zoom back to
    /// the thumbnail shrinks the whole picture.
    private func closeViewer() {
        if isZoomed || panOffset != .zero {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                zoomScale = 1.0
                panOffset = .zero
            }
        }
        dismiss()
    }

    /// A double tap on the image toggles the zoom; a single tap outside it closes the viewer.
    /// The system waits a moment after a first tap to see if a second follows, so a close tap
    /// lands about 0.3 s late, as in Photos. Zoomed, a tap outside the image closes nothing: it
    /// would throw the zoom away. Zoom out, or use the Close button.
    private var tapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let inside = panMath.imageContains(value.location, at: zoomScale, offset: panOffset)
                debugLog("count-2 onEnded location=\(value.location.debugDescription) inside=\(inside) zoomScale=\(zoomScale)")
                guard inside else { return }
                toggleZoom()
            }
            .exclusively(
                before: SpatialTapGesture()
                    .onEnded { value in
                        let inside = panMath.imageContains(value.location, at: zoomScale, offset: panOffset)
                        debugLog("count-1 onEnded location=\(value.location.debugDescription) inside=\(inside) zoomScale=\(zoomScale)")
                        guard !inside, !isZoomed
                        else { return }
                        closeViewer()
                    }
            )
    }

    /// Pinch zooms around the current offset: the offset scales with the zoom and is re-clamped.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($isPinching) { _, state, _ in state = true }
            .onChanged { value in
                if pinchStartScale == nil {
                    debugLog("magnify first onChanged magnification=\(value.magnification) zoomScale=\(zoomScale)")
                }
                let start = pinchStartScale ?? zoomScale
                pinchStartScale = start
                let newScale = ImageViewerPanMath.clampedScale(start * value.magnification)
                panOffset = panMath.rescaledOffset(panOffset, from: zoomScale, to: newScale)
                zoomScale = newScale
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($isDragging) { _, state, _ in state = true }
            .updating($dragOffset) { value, state, _ in
                // Only a drag that began at 1x and has seen no pinch feeds the dismiss offset.
                let mode = dragMode == .idle
                    ? ImageViewerPanMath.dragMode(isZoomed: isZoomed, isPinching: isPinching)
                    : dragMode
                state = mode == .dismiss && !isZoomed && !isPinching ? value.translation.height : 0
            }
            .onChanged { value in
                if dragMode == .idle {
                    dragMode = ImageViewerPanMath.dragMode(isZoomed: isZoomed, isPinching: isPinching)
                    debugLog("drag first onChanged translation=\(value.translation.debugDescription) mode=\(String(describing: dragMode))")
                }
                if dragMode == .dismiss, isZoomed || isPinching {
                    dragMode = .ignored
                }
                guard dragMode == .pan, !isPinching else { return }
                let start = panStartOffset ?? panOffset
                panStartOffset = start
                panOffset = panMath.clamp(
                    CGSize(
                        width: start.width + value.translation.width,
                        height: start.height + value.translation.height
                    ),
                    at: zoomScale
                )
            }
            .onEnded { value in
                let mode = dragMode
                debugLog("drag onEnded translation=\(value.translation.debugDescription) mode=\(String(describing: mode)) zoomScale=\(zoomScale)")
                dragMode = .idle
                switch mode {
                case .pan:
                    settlePan(after: value)
                case .dismiss:
                    guard !isZoomed,
                          AnswerImageViewerDismissal.shouldDismiss(
                              translation: value.translation.height,
                              predictedEndTranslation: value.predictedEndTranslation.height
                          )
                    else { return }  // `dragOffset` eases back to 0 on its own
                    dismissOffset = value.translation.height
                    dismiss()
                case .idle, .ignored:
                    break
                }
            }
    }

    /// Carries a released pan a little further and settles it inside the clamp.
    private func settlePan(after value: DragGesture.Value) {
        // No start value: the drag never moved the image (it ran under a pinch), so settle in place.
        let moved = panStartOffset != nil
        let start = panStartOffset ?? panOffset
        let current = panOffset
        panStartOffset = nil
        let settled = panMath.settledOffset(
            offset: start,
            translation: moved ? value.translation : .zero,
            predictedEndTranslation: moved ? value.predictedEndTranslation : .zero,
            at: zoomScale,
            withMomentum: !reduceMotion
        )
        let velocity = ImageViewerPanMath.initialVelocity(
            from: current,
            to: settled,
            releaseVelocity: value.velocity
        )
        withAnimation(settleAnimation(initialVelocity: velocity)) { panOffset = settled }
    }
}

#Preview {
    QuestionCardExpandedView(
        expandedState: ExpandedQuestionState(
            question: Question.sampleQuestions[0],
            headerStyle: .plain
        ),
        model: QuestionModel(),
        badgeModel: nil
    )
    .environmentObject(AuthModel())
    .environmentObject(FavoriteStore.previews)
    .environmentObject(GuestFavoriteModel())
    .environmentObject(QuestionListStore(localLists: []))
}
