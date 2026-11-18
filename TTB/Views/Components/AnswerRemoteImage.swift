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
/// - `placeholder` is shown while the network copy is not ready (the Home card right after Save,
///   before the upload finishes) and stays up if the download fails. The network copy replaces it
///   inside the same view, so nothing blank appears between the two.
/// - A failed load is retried with backoff (`ImageLoadRetryPolicy`), then handed to the content as
///   `.failed`.
///
/// `url` may be `nil` while only the placeholder exists.
///
/// `LazyImage` binds its completion closure when it appears and keeps it while its identity lasts,
/// so the identity includes the URL and the attempt: a new URL or a retry builds a fresh `LazyImage`
/// whose `onRemoteLoaded` is the current one.
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
                .id(AnswerImageLoadIdentity(url: url, attempt: retryModel.attempt))
            } else if let placeholder {
                content(.image(placeholder))
            }
        }
        // `.task(id:)` is cancelled when the view goes away, which abandons a pending retry. It runs
        // again when the view comes back; the model ignores a failure token it has already handled.
        .task(id: failureToken) {
            guard failureToken > 0 else { return }
            await retryModel.loadFailed(token: failureToken)
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

/// The remove button on an answer image: the same look in the loaded and the failed state.
struct AnswerImageRemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.black.opacity(0.46)))
                .padding(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "question.image.delete"))
    }
}

/// The error state of an answer image in the editor: a message, a way to try again, and the remove
/// button, so a broken image can still be taken off the answer.
struct AnswerImageFailedView: View {
    let retry: () -> Void
    let remove: () -> Void

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
        .padding()
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            AnswerImageRemoveButton(action: remove)
        }
    }
}
