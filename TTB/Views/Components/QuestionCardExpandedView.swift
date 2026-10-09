import NukeUI
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
}

struct QuestionCardExpandedView: View {
    let expandedState: ExpandedQuestionState
    let model: QuestionModel
    let badgeModel: BadgeModel?
    let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.answerDraftStore) private var answerDraftStore
    @Environment(\.toastCenter) private var toastCenter
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
    @State private var isLoadingQuickSuggestions = false
    @FocusState private var focusedField: AnswerField?
    @GestureState private var isImageMenuPressed = false

    @State private var imageSuggestions: [[AnswerImageSuggestion]] = [[], [], []]
    @State private var imageSuggestionLoadingIndex: Int? = nil
    @State private var imageSuggestionMessages: [String?] = [nil, nil, nil]
    @State private var showingImagePicker = false
    @State private var activeImageSlot = 0
    @State private var isUploading = false
    @State private var uploadError: String?

    @State private var presentedAnswerImage: PresentedAnswerImage?
    @State private var showingGuestUpgradeSheet = false
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
                showingGuestUpgradeSheet = true
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
            .animation(.easeInOut(duration: 0.2), value: isFavorite)
        }
        .accessibilityIdentifier("question-card-fullscreen-favorite")
        .accessibilityLabel(
            String(localized: isFavorite ? "common.favorite.remove" : "common.favorite.add")
        )
    }

    private func toggleFavorite() {
        Task {
            await toastCenter.toggleFavorite(currentQuestion, using: favoriteStore)
        }
    }

    private var currentAnswers: [String] {
        draft.normalized().texts
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
        .sheet(isPresented: $showingGuestUpgradeSheet) {
            GuestUpgradeView()
                .environmentObject(authModel)
        }
        .sheet(isPresented: $isShowingQuestionLists) {
            QuestionListSelectionSheet(question: currentQuestion)
        }
        .fullScreenCover(item: $presentedAnswerImage) { presentedImage in
            AnswerImageFullscreenView(presentedImage: presentedImage)
        }
        .overlay { savingOverlay }
        .interactiveDismissDisabled(isUploading)
        .task(id: question.id) {
            await loadQuickAnswerSuggestions()
        }
        .onChange(of: authModel.isAnonymous) { _, isAnonymous in
            if !isAnonymous {
                showingGuestUpgradeSheet = false
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: dismissFullscreen) {
                    Label(String(localized: "common.close"), systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("question-card-fullscreen-close")
                .accessibilityLabel(String(localized: "common.close"))
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: saveAnswers) {
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
                showingGuestUpgradeSheet = true
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
            }
        }
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
            // sees the touch. When the menu wins the touch, it cancels the drag and `onEnded` never
            // runs; `@GestureState` resets on end and on cancel, so the touch-up hook is its reset.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isImageMenuPressed) { _, isPressed, _ in isPressed = true }
            )
            .onChange(of: isImageMenuPressed) { _, isPressed in
                if !isPressed {
                    setFocusedField(nil)
                }
            }
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
            return PresentedAnswerImage(source: .local(localImage))

        case let .pendingSuggestion(suggestion):
            if let url = suggestion.previewImageURL {
                return PresentedAnswerImage(source: .remote(url))
            }

        case let .saved(urlString, _):
            if let url = URL(string: urlString) {
                return PresentedAnswerImage(source: .remote(url))
            }

        case .none:
            break
        }

        return PresentedAnswerImage(source: .local(fallbackImage))
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
                isLoadingQuickSuggestions = false
            }
        } catch {
            await MainActor.run {
                quickAnswerSuggestions = localCandidates
                isLoadingQuickSuggestions = false
            }
        }
    }

    /// Hands the draft to `AnswerDraftStore` and closes.
    ///
    /// Everything this used to do — the optimistic write, the upload fan-out, the compare-and-swap
    /// re-persist, the rollback and the orphan cleanup — lives in the store now, tested. What is left
    /// here is the editor's own business: reflect the handoff in local state, then dismiss.
    private func saveAnswers() {
        guard !isUploading else { return }

        uploadError = nil

        let started = answerDraftStore.save(draft, baseline: baseline, for: question.id, in: model)

        // The images are the store's problem now, so stop showing them as this editor's pending work.
        if started, draft.hasPendingUploads {
            draft = draft.clearingPendingImages()
        }

        dismissFullscreen()
    }

    private func dismissFullscreen() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

private struct AnswerImageFullscreenView: View {
    let presentedImage: PresentedAnswerImage

    @Environment(\.dismiss) private var dismiss
    @GestureState private var zoomScale: CGFloat = 1.0
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            imageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(max(1.0, zoomScale))
                .offset(y: dragOffset)
                .gesture(
                    MagnifyGesture()
                        .updating($zoomScale) { value, state, _ in
                            state = value.magnification
                        }
                )
                .gesture(dragGesture)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "question.image.fullscreen"))
                .accessibilityHint(String(localized: "question.image.fullscreenHint"))

            closeButton
        }
        .opacity(1 - (abs(dragOffset) / 300.0))
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private var imageContent: some View {
        switch presentedImage.source {
        case let .local(image):
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        case let .remote(url):
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                case .empty:
                    ProgressView()
                        .tint(.white)
                @unknown default:
                    EmptyView()
                }
            }
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
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

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomScale <= 1.0 else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                guard zoomScale <= 1.0 else { return }
                if abs(value.translation.height) > 100 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = 0
                    }
                }
            }
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
