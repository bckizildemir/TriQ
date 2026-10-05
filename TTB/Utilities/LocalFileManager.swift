import Foundation
import UIKit

final class LocalFileManager: Sendable {
    static let shared = LocalFileManager()
    private init() {}
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func saveImage(_ image: UIImage, name: String) throws {
        guard let data = image.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "LocalFileManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not convert image to data"])
        }
        
        let filename = getDocumentsDirectory().appendingPathComponent("\(name).jpg")
        try data.write(to: filename)
    }
    
    /// Loads a saved image. Pass `maxPixelSize` to decode it downsampled, which matters for images
    /// written before a size cap existed — `UIImage(contentsOfFile:)` decodes at the stored size.
    func loadImage(name: String, maxPixelSize: Int? = nil) -> UIImage? {
        let filename = getDocumentsDirectory().appendingPathComponent("\(name).jpg")

        if let maxPixelSize,
           let data = try? Data(contentsOf: filename, options: .mappedIfSafe),
           let image = DownsampledImageDecoder.image(from: data, maxPixelSize: maxPixelSize) {
            return image
        }

        return UIImage(contentsOfFile: filename.path)
    }
    
    func deleteImage(name: String) {
        let filename = getDocumentsDirectory().appendingPathComponent("\(name).jpg")
        try? FileManager.default.removeItem(at: filename)
    }
}
