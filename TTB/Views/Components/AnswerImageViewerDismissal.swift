import CoreGraphics

/// Decides whether a vertical drag on the answer image viewer closes it.
///
/// A drag closes the viewer when it is long, or when it is fast: `predictedEndTranslation`
/// folds the release velocity in, so a short flick closes it the way iOS photo viewers do.
/// Either way the drag must end heading the way it went: a drag flicked back toward where it
/// started stays open.
enum AnswerImageViewerDismissal {
    static let distanceThreshold: CGFloat = 100
    static let predictedDistanceThreshold: CGFloat = 200

    static func shouldDismiss(translation: CGFloat, predictedEndTranslation: CGFloat) -> Bool {
        let sameDirection = translation * predictedEndTranslation > 0
        guard sameDirection else { return false }
        return abs(translation) > distanceThreshold
            || abs(predictedEndTranslation) > predictedDistanceThreshold
    }
}
