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
    @Published var sharedQuestion: SharedQuestionDeepLink?
    @Published var sharedQuestionList: SharedQuestionListDeepLink?
    @Published var acceptedQuestionListShareDetail: AcceptedQuestionListShareNavigationRequest?

    func handle(_ url: URL) {
        if let shareCode = Self.questionListShareCode(from: url) {
            sharedQuestionList = SharedQuestionListDeepLink(shareCode: shareCode)
            return
        }

        guard let questionId = Self.questionId(from: url) else { return }
        sharedQuestion = SharedQuestionDeepLink(questionId: questionId)
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
