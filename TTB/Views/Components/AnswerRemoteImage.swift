import NukeUI
import SwiftUI

/// What `AnswerRemoteImage` hands its content closure.
enum AnswerImagePhase {
    case image(UIImage)
    case loading
    /// Retries are used up. `retry` starts a fresh set of attempts.
    case failed(retry: () -> Void)
}

/// A remote image that retries on its own, and can show a picture the device already has.
///
/// Two jobs, one view, so the swap between them keeps one identity and cannot flicker:
/// - `placeholder` is shown while the network copy is not ready (the Home card right after Save,
///   before the upload finishes), and stays up if the download fails.
/// - A failed load is retried with backoff (`ImageLoadRetryPolicy`), then shown as `.failed`.
///
/// `url` may be `nil` while only the placeholder exists.
struct AnswerRemoteImage<Content: View>: View {
    let url: URL?
    var placeholder: UIImage?
    /// Called with the network copy once it has loaded.
    var onRemoteLoaded: ((UIImage) -> Void)?
    @ViewBuilder let content: (AnswerImagePhase) -> Content

    @State private var retryModel = ImageLoadRetryModel()
    @State private var failureToken = 0

    var body: some View {
        Group {
            if let url {
                LazyImage(url: url) { state in
                    content(phase(for: state))
                }
                .onCompletion { result in
                    switch result {
                    case let .success(response):
                        retryModel.loadSucceeded()
                        onRemoteLoaded?(response.image)
                    case .failure:
                        failureToken += 1
                    }
                }
                .id(retryModel.attempt)
            } else if let placeholder {
                content(.image(placeholder))
            }
        }
        // `.task(id:)` is cancelled when the view goes away, which abandons a pending retry.
        .task(id: failureToken) {
            guard failureToken > 0 else { return }
            await retryModel.loadFailed()
        }
        .onChange(of: url) {
            retryModel.reset()
        }
    }

    private func phase(for state: LazyImageState) -> AnswerImagePhase {
        let remote = state.imageContainer?.image
        let source = AnswerImageSource.resolve(
            hasRemoteImage: remote != nil,
            hasPlaceholder: placeholder != nil,
            retryStatus: retryModel.status
        )

        switch source {
        case .remote:
            if let remote { return .image(remote) }
            return .loading
        case .placeholder:
            if let placeholder { return .image(placeholder) }
            return .loading
        case .loading:
            return .loading
        case .failed:
            return .failed(retry: { retryModel.retryNow() })
        }
    }
}

/// The error state of an answer image in the editor: a message and a way to try again.
struct AnswerImageFailedView: View {
    let height: CGFloat
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(String(localized: "question.image.loadFailed"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(String(localized: "question.image.tryAgain"), action: retry)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 16))
    }
}
