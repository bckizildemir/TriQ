import CoreGraphics

/// Decides whether a drag on the answer image viewer closes it.
///
/// Only a downward drag closes the viewer, the way the iOS Photos app does. It closes when it is
/// long, or when it is fast: `predictedEndTranslation` folds the release velocity in, so a short
/// flick closes it. The drag must end heading down, and either be long and still heading on past
/// the distance threshold, or be fast enough alone. A drag flicked back up stays open, and an
/// upward drag never closes.
enum AnswerImageViewerDismissal {
    static let distanceThreshold: CGFloat = 100
    static let predictedDistanceThreshold: CGFloat = 200

    static func shouldDismiss(translation: CGFloat, predictedEndTranslation: CGFloat) -> Bool {
        guard translation > 0, predictedEndTranslation > 0 else { return false }
        let isLongAndStillHeadingOn = translation > distanceThreshold
            && predictedEndTranslation > distanceThreshold
        return isLongAndStillHeadingOn
            || predictedEndTranslation > predictedDistanceThreshold
    }
}
