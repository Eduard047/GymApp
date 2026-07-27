import CryptoKit
import Foundation
import UIKit

enum ExerciseMediaStore {
    private static let maximumInputBytes = 8 * 1024 * 1024
    private static let maximumOutputBytes = 1_600_000
    private static let maximumDimension: CGFloat = 8_192
    private static let maximumPixels: CGFloat = 40_000_000
    private static let maximumSavedDimension: CGFloat = 1_024

    static func bundledImages(exerciseName: String) -> [UIImage] {
        guard let key = BuiltInExerciseCatalog.canonicalKey(forName: exerciseName) else { return [] }
        return (0 ... 1).compactMap { index in
            Bundle.main.url(
                forResource: "\(key)_\(index)",
                withExtension: "jpg"
            ).flatMap { UIImage(contentsOfFile: $0.path) }
        }
    }

    static func customImage(ownerKey: String, exerciseID: UUID) -> UIImage? {
        UIImage(contentsOfFile: customURL(ownerKey: ownerKey, exerciseID: exerciseID).path)
    }

    static func saveCustomImage(_ data: Data, ownerKey: String, exerciseID: UUID) throws {
        guard data.count <= maximumInputBytes,
              let image = UIImage(data: data),
              let cgImage = image.cgImage else {
            throw MediaError.invalidImage
        }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width >= 32, height >= 32,
              width <= maximumDimension, height <= maximumDimension,
              width * height <= maximumPixels else {
            throw MediaError.invalidImage
        }

        let scale = min(1, maximumSavedDimension / max(width, height))
        let size = CGSize(width: width * scale, height: height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let normalized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let encoded = normalized.jpegData(compressionQuality: 0.82),
              encoded.count <= maximumOutputBytes else {
            throw MediaError.invalidImage
        }

        let target = customURL(ownerKey: ownerKey, exerciseID: exerciseID)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoded.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableTarget = target
        try mutableTarget.setResourceValues(values)
    }

    static func deleteCustomImage(ownerKey: String, exerciseID: UUID) {
        try? FileManager.default.removeItem(at: customURL(ownerKey: ownerKey, exerciseID: exerciseID))
    }

    private static func customURL(ownerKey: String, exerciseID: UUID) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("ExerciseMedia", isDirectory: true)
            .appendingPathComponent(ownerFingerprint(ownerKey), isDirectory: true)
            .appendingPathComponent("\(exerciseID.uuidString).jpg")
    }

    private static func ownerFingerprint(_ ownerKey: String) -> String {
        SHA256.hash(data: Data("gymapp-exercise-media-v1:\(ownerKey)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    enum MediaError: Error {
        case invalidImage
    }
}
