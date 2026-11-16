import CoreGraphics

/// Decides whether a vertical drag on the answer image viewer closes it.
///
/// A drag closes the viewer when it is long, or when it is fast: `predictedEndTranslation`
/// folds the release velocity in, so a short flick closes it the way iOS photo viewers do.
enum AnswerImageViewerDismissal {
    static let distanceThreshold: CGFloat = 100
    static let predictedDistanceThreshold: CGFloat = 240

    static func shouldDismiss(translation: CGFloat, predictedEndTranslation: CGFloat) -> Bool {
        abs(translation) > distanceThreshold
            || abs(predictedEndTranslation) > predictedDistanceThreshold
    }
}
