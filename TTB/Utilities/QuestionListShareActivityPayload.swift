import Foundation

struct QuestionListShareActivityPayload: Identifiable, Equatable {
    let text: String
    let url: URL

    var id: String {
        "\(url.absoluteString)#\(text)"
    }

    var activityItems: [Any] {
        [text, url]
    }

    static func make(
        senderDisplayName: String,
        listName: String,
        questionCount: Int,
        url: URL
    ) -> QuestionListShareActivityPayload {
        let senderHandle = UserHandleFormatter.handle(senderDisplayName)
        let questionCopy = questionCount == 1 ? "1 question" : "\(questionCount) questions"
        let text = "\(senderHandle) shared \"\(listName)\" with \(questionCopy) on TTB.\n\(url.absoluteString)"
        return QuestionListShareActivityPayload(text: text, url: url)
    }
}
