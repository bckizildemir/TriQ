import Foundation

struct SharedQuestionDeepLink: Identifiable, Equatable {
    let questionId: String

    var id: String {
        questionId
    }
}

struct SharedQuestionListDeepLink: Identifiable, Equatable {
    let shareCode: String

    var id: String {
        shareCode
    }
}

struct AcceptedQuestionListShareNavigationRequest: Identifiable, Equatable {
    let shareId: String

    var id: String {
        shareId
    }
}

@MainActor
final class AppDeepLinkRouter: ObservableObject {
    /// The link on screen. Presentation binds to these two; only one is ever set at a time.
    @Published var sharedQuestion: SharedQuestionDeepLink? {
        didSet { promotePendingLinkIfIdle() }
    }
    @Published var sharedQuestionList: SharedQuestionListDeepLink? {
        didSet { promotePendingLinkIfIdle() }
    }
    @Published var acceptedQuestionListShareDetail: AcceptedQuestionListShareNavigationRequest?

    private enum PendingLink {
        case question(SharedQuestionDeepLink)
        case questionList(SharedQuestionListDeepLink)
    }

    /// A link that arrived while another one was on screen. The latest one wins.
    private var pendingLink: PendingLink?

    /// A link that arrives while another is on screen waits here, so the open screen is never torn
    /// down under the user (its draft guard needs a normal close). It shows when that one closes.
    func handle(_ url: URL) {
        if let shareCode = Self.questionListShareCode(from: url) {
            present(.questionList(SharedQuestionListDeepLink(shareCode: shareCode)))
            return
        }

        guard let questionId = Self.questionId(from: url) else { return }
        present(.question(SharedQuestionDeepLink(questionId: questionId)))
    }

    private func present(_ link: PendingLink) {
        if sharedQuestion != nil || sharedQuestionList != nil {
            pendingLink = link
            return
        }
        show(link)
    }

    private func show(_ link: PendingLink) {
        switch link {
        case .question(let deepLink):
            sharedQuestion = deepLink
        case .questionList(let deepLink):
            sharedQuestionList = deepLink
        }
    }

    private func promotePendingLinkIfIdle() {
        guard sharedQuestion == nil, sharedQuestionList == nil, let link = pendingLink else { return }
        pendingLink = nil
        show(link)
    }

    func requestAcceptedQuestionListShareDetail(shareId: String) {
        let shareId = shareId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shareId.isEmpty else { return }
        acceptedQuestionListShareDetail = AcceptedQuestionListShareNavigationRequest(shareId: shareId)
    }

    func consumeAcceptedQuestionListShareDetail(_ request: AcceptedQuestionListShareNavigationRequest) {
        guard acceptedQuestionListShareDetail == request else { return }
        acceptedQuestionListShareDetail = nil
    }

    static func questionId(from url: URL) -> String? {
        guard isSupportedWebHost(url.host) || url.scheme == "ttbp" else {
            return nil
        }

        let components = routeComponents(from: url)
        guard components.count >= 2, components[0] == "q" else {
            return nil
        }

        let questionId = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return questionId.isEmpty ? nil : questionId
    }

    static func questionListShareCode(from url: URL) -> String? {
        guard isSupportedWebHost(url.host) || url.scheme == "ttbp" else {
            return nil
        }

        let components = routeComponents(from: url)
        let rawShareCode: String?
        if components.count >= 3, components[0] == "share", components[1] == "lists" {
            rawShareCode = components[2]
        } else if components.count >= 2, components[0] == "l" {
            rawShareCode = components[1]
        } else {
            rawShareCode = nil
        }

        let shareCode = (rawShareCode?.removingPercentEncoding ?? rawShareCode ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return shareCode.isEmpty ? nil : shareCode
    }

    private static func isSupportedWebHost(_ host: String?) -> Bool {
        host == "ttbp-9d652.web.app" || host == "ttbp-9d652.firebaseapp.com"
    }

    private static func routeComponents(from url: URL) -> [String] {
        var components = url.pathComponents.filter { $0 != "/" }
        if url.scheme == "ttbp", let host = url.host, !host.isEmpty {
            components.insert(host, at: 0)
        }
        return components
    }
}
