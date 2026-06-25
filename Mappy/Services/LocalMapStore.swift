import Foundation
import PDFKit
import UIKit

/// Centralizes file IO so views and view models do not need to know where map assets live.
enum LocalMapStore {
    static let mapsDirectoryName = "Maps"

    /// Ensures SwiftData's default Application Support folder exists before the model container opens.
    static func prepareApplicationSupportDirectory() {
        guard let applicationSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return
        }

        if !FileManager.default.fileExists(atPath: applicationSupport.path) {
            try? FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        }
    }

    /// Returns the app-local Maps directory and creates it when needed.
    static func mapsDirectory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = documents.appendingPathComponent(mapsDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Builds a stable file URL for a stored asset filename.
    static func url(for filename: String) throws -> URL {
        try mapsDirectory().appendingPathComponent(filename)
    }

    /// Saves image data as JPEG and returns the generated filenames used by SwiftData.
    static func saveImage(_ image: UIImage, originalFilename: String) throws -> (assetFilename: String, thumbnailFilename: String?) {
        let normalizedImage = image.normalizedForMappyStorage()
        let id = UUID().uuidString
        let assetFilename = "\(id).jpg"
        let thumbnailFilename = "\(id)-thumb.jpg"
        let imageData = normalizedImage.jpegData(compressionQuality: 0.92) ?? Data()
        let thumbnailData = makeThumbnail(from: normalizedImage)?.jpegData(compressionQuality: 0.78)

        try imageData.write(to: url(for: assetFilename), options: [.atomic])
        if let thumbnailData {
            try thumbnailData.write(to: url(for: thumbnailFilename), options: [.atomic])
        }

        return (assetFilename, thumbnailData == nil ? nil : thumbnailFilename)
    }

    /// Loads a stored image from Documents for display in lists, viewers, and the editor.
    static func loadImage(filename: String?) -> UIImage? {
        guard let filename, let imageURL = try? url(for: filename) else {
            return nil
        }
        return UIImage(contentsOfFile: imageURL.path)
    }

    /// Renders the first PDF page into a UIImage so all alignment code can treat PDFs and images the same way.
    static func renderFirstPDFPage(from url: URL) -> UIImage? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else {
            return nil
        }

        let pageRect = page.bounds(for: .mediaBox)
        let maxSide: CGFloat = 2_400
        let scale = min(maxSide / max(pageRect.width, pageRect.height), 2)
        let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
    }

    /// Produces a small thumbnail that keeps the map list fast even with large imported files.
    private static func makeThumbnail(from image: UIImage) -> UIImage? {
        let targetSize = CGSize(width: 320, height: 220)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            UIColor.secondarySystemBackground.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()

            let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(
                x: (targetSize.width - drawSize.width) / 2,
                y: (targetSize.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

extension UIImage {
    /// Renders image data into an `.up` UIImage so EXIF orientation does not flip later Core Graphics drawing.
    func normalizedForMappyStorage() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
