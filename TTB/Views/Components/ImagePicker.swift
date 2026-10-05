import SwiftUI
import PhotosUI
import UIKit
import os

// MARK: - ImagePicker (PHPicker — used for answer images, no authorization needed)

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "ImagePicker")
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    @MainActor
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        /// The picked item, kept here on the main actor so the provider's background
        /// completions never capture the non-`Sendable` `NSItemProvider`.
        private var provider: NSItemProvider?

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                parent.dismiss()
                return
            }
            self.provider = provider

            // Load the raw data and decode it downsampled rather than asking the provider for a
            // `UIImage`: a full-resolution answer photo is ~48 MB of bitmap held in view state, and
            // it gets compressed to 800 px on upload anyway.
            if let typeIdentifier = DownsampledImageDecoder.imageTypeIdentifier(
                in: provider.registeredTypeIdentifiers
            ) {
                let logger = parent.logger
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, error in
                    if let error {
                        logger.error("Error loading image data: \(error.localizedDescription)")
                    }

                    // Decode here, off the main actor; only the finished image hops back.
                    let image = data.flatMap { DownsampledImageDecoder.image(from: $0) }
                    Task { @MainActor in
                        guard let self else { return }
                        if let image {
                            self.finish(with: image)
                        } else {
                            // Fall back to the object representation so an undecodable-by-ImageIO
                            // asset still picks, rather than silently doing nothing.
                            self.loadObjectRepresentation()
                        }
                    }
                }
            } else {
                loadObjectRepresentation()
            }
        }

        private func loadObjectRepresentation() {
            guard let provider, provider.canLoadObject(ofClass: UIImage.self) else {
                parent.dismiss()
                return
            }

            let logger = parent.logger
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                if let error {
                    logger.error("Error loading image: \(error.localizedDescription)")
                    return
                }

                guard let image = object as? UIImage else { return }
                Task { @MainActor in
                    self?.finish(with: image)
                }
            }
        }

        private func finish(with image: UIImage) {
            provider = nil
            parent.image = image
            parent.dismiss()
        }
    }
}
