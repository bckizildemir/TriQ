import SwiftUI

struct QuestionDetailView: View {
    let question: Question
    @ObservedObject var model: QuestionModel
    var badgeModel: BadgeModel?
    var showQuestionHeader: Bool = true
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        QuestionCardExpandedView(
            expandedState: ExpandedQuestionState(
                question: question,
                headerStyle: .plain
            ),
            model: model,
            badgeModel: badgeModel,
            onClose: {
                if let onSaved {
                    onSaved()
                } else {
                    dismiss()
                }
            }
        )
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct QuestionDetailModalShell: View {
    let expandedState: ExpandedQuestionState
    let model: QuestionModel
    var badgeModel: BadgeModel?
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QuestionCardExpandedView(
                expandedState: expandedState,
                model: model,
                badgeModel: badgeModel,
                onClose: handleClose
            )
        }
    }

    private func handleClose() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

struct QuestionDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            QuestionDetailView(
                question: Question.sampleQuestions[0],
                model: QuestionModel()
            )
        }
        .environmentObject(AuthModel())
        .environmentObject(FavoriteStore.previews)
        .environmentObject(GuestFavoriteModel())
        .environmentObject(QuestionListStore(localLists: []))
    }
}
