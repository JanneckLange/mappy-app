import CoreGraphics
import UIKit

/// Converts map-like images into small edge masks that can be compared quickly on device.
enum LineFeatureExtractor {
    static func extract(from image: UIImage, sampleSize: Int = 96) -> FeatureMask {
        guard sampleSize > 2, let cgImage = image.cgImage else {
            return FeatureMask(width: sampleSize, height: sampleSize, pixels: [])
        }

        let width = sampleSize
        let height = sampleSize
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return FeatureMask(width: width, height: height, pixels: [])
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var luminance = [Double](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let byteIndex = index * 4
            let red = Double(rgba[byteIndex])
            let green = Double(rgba[byteIndex + 1])
            let blue = Double(rgba[byteIndex + 2])
            luminance[index] = 0.299 * red + 0.587 * green + 0.114 * blue
        }

        var pixels = Set<Int>()
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let centerIndex = y * width + x
                let horizontal = abs(luminance[centerIndex - 1] - luminance[centerIndex + 1])
                let vertical = abs(luminance[centerIndex - width] - luminance[centerIndex + width])
                let diagonalA = abs(luminance[centerIndex - width - 1] - luminance[centerIndex + width + 1])
                let diagonalB = abs(luminance[centerIndex - width + 1] - luminance[centerIndex + width - 1])
                let gradient = max(horizontal, vertical, diagonalA, diagonalB)

                // Road and trail linework usually survives a modest contrast threshold while soft map fills do not.
                if gradient > 24 {
                    pixels.insert(centerIndex)
                }
            }
        }

        return FeatureMask(width: width, height: height, pixels: removeSparseNoise(from: pixels, width: width, height: height))
    }

    /// Keeps small isolated texture pixels from dominating the alignment score.
    private static func removeSparseNoise(from pixels: Set<Int>, width: Int, height: Int) -> Set<Int> {
        var filtered = Set<Int>()
        for pixel in pixels {
            let x = pixel % width
            let y = pixel / width
            var neighbors = 0
            for candidateY in max(0, y - 1)...min(height - 1, y + 1) {
                for candidateX in max(0, x - 1)...min(width - 1, x + 1) {
                    if candidateX == x, candidateY == y {
                        continue
                    }
                    if pixels.contains(candidateY * width + candidateX) {
                        neighbors += 1
                    }
                }
            }
            if neighbors >= 1 {
                filtered.insert(pixel)
            }
        }
        return filtered
    }
}
