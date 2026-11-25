import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import GymApp

final class ExerciseMediaNormalizationTests: XCTestCase {
    /// A portrait camera photo is stored as landscape sensor pixels plus EXIF orientation `.right`.
    /// The saved photo must be upright portrait, long side exactly 1024 px (scale 1), under the cap.
    func testPortraitOrientedPhotoIsSavedUprightAtExactPixelSizeUnderTheCap() throws {
        let input = try noisyJPEG(pixelWidth: 2_000, pixelHeight: 1_500, exifOrientation: .right)
        XCTAssertLessThanOrEqual(input.count, 8 * 1024 * 1024, "fixture must be a valid upload")

        let mediaDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppMediaNormalize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: mediaDirectory) }
        let owner = "local_\(UUID().uuidString.lowercased())"
        let exerciseID = UUID()

        try ExerciseMediaStore.saveCustomImage(
            input,
            ownerKey: owner,
            exerciseID: exerciseID,
            mediaDirectoryURL: mediaDirectory
        )

        let stored = try XCTUnwrap(
            FileManager.default.enumerator(at: mediaDirectory, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .first { $0.lastPathComponent == "\(exerciseID.uuidString).jpg" }
        )
        let data = try Data(contentsOf: stored)
        XCTAssertLessThanOrEqual(data.count, 1_600_000)
        let properties = try imageProperties(data)
        XCTAssertEqual(properties.width, 768)
        XCTAssertEqual(properties.height, 1_024)
        XCTAssertEqual(properties.orientation, 1, "pixels must already be upright")

        let loaded = try XCTUnwrap(ExerciseMediaStore.customImage(
            ownerKey: owner, exerciseID: exerciseID, mediaDirectoryURL: mediaDirectory
        ))
        XCTAssertGreaterThan(loaded.size.height, loaded.size.width)
    }

    /// The output size never depends on the screen scale: a landscape photo becomes 1024 px wide.
    func testLandscapePhotoIsDownsampledToRealPixelsIndependentOfScreenScale() throws {
        let input = try noisyJPEG(pixelWidth: 3_000, pixelHeight: 2_000, exifOrientation: .up)

        let output = try ExerciseMediaStore.normalizedCustomImageData(input)

        XCTAssertLessThanOrEqual(output.count, 1_600_000)
        let properties = try imageProperties(output)
        XCTAssertEqual(properties.width, 1_024)
        XCTAssertEqual(properties.height, 683)
    }

    func testSmallPhotoIsNotUpscaled() throws {
        let input = try noisyJPEG(pixelWidth: 400, pixelHeight: 300, exifOrientation: .right)

        let properties = try imageProperties(try ExerciseMediaStore.normalizedCustomImageData(input))

        XCTAssertEqual(properties.width, 300)
        XCTAssertEqual(properties.height, 400)
    }

    func testUndecodableDataIsRejected() {
        XCTAssertThrowsError(try ExerciseMediaStore.normalizedCustomImageData(Data("not an image".utf8)))
    }

    // MARK: - Helpers

    private func noisyJPEG(
        pixelWidth: Int,
        pixelHeight: Int,
        exifOrientation: CGImagePropertyOrientation
    ) throws -> Data {
        let bytesPerRow = pixelWidth * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * pixelHeight)
        var seed: UInt32 = 0x2545_F491
        // Photo-like content: smooth gradients plus mild grain (pure noise is not a photo).
        for y in 0 ..< pixelHeight {
            for x in 0 ..< pixelWidth {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let grain = Int(seed >> 27)
                let index = y * bytesPerRow + x * 4
                pixels[index] = UInt8(clamping: x * 200 / pixelWidth + grain)
                pixels[index + 1] = UInt8(clamping: y * 200 / pixelHeight + grain)
                pixels[index + 2] = UInt8(clamping: (x + y) * 100 / (pixelWidth + pixelHeight) + grain)
            }
        }
        let image: CGImage = try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ))
            return try XCTUnwrap(context.makeImage())
        }
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.6,
            kCGImagePropertyOrientation: exifOrientation.rawValue
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func imageProperties(_ data: Data) throws -> (width: Int, height: Int, orientation: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try XCTUnwrap((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue)
        let height = try XCTUnwrap((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue)
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (width, height, orientation)
    }
}
