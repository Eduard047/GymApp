import CryptoKit
import Foundation
import UIKit

enum ExerciseMediaStore {
    private static let maximumInputBytes = 8 * 1024 * 1024
    private static let maximumOutputBytes = 1_600_000
    private static let maximumDimension: CGFloat = 8_192
    private static let maximumPixels: CGFloat = 40_000_000
    private static let maximumSavedDimension: CGFloat = 1_024
    private static let maximumOwnerKeyLength = 128

    static func bundledImages(catalogKey: String?, rawExerciseName: String) -> [UIImage] {
        // The persisted raw name remains authoritative for imported and legacy data.
        // A mismatched catalog key must never make a custom exercise inherit trusted media.
        guard let key = BuiltInExerciseCatalog.resolvedKey(
            catalogKey: catalogKey,
            name: rawExerciseName
        ) else { return [] }
        return (0 ... 1).compactMap { index in
            Bundle.main.url(
                forResource: "\(key)_\(index)",
                withExtension: "jpg"
            ).flatMap { UIImage(contentsOfFile: $0.path) }
        }
    }

    static func customImage(
        ownerKey: String,
        exerciseID: UUID,
        mediaDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> UIImage? {
        guard let target = try? customURL(
            ownerKey: ownerKey,
            exerciseID: exerciseID,
            mediaDirectoryURL: mediaDirectoryURL,
            fileManager: fileManager
        ) else { return nil }
        return UIImage(contentsOfFile: target.path)
    }

    static func saveCustomImage(
        _ data: Data,
        ownerKey: String,
        exerciseID: UUID,
        mediaDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
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

        let root = try rootDirectoryURL(
            mediaDirectoryURL: mediaDirectoryURL,
            fileManager: fileManager
        )
        let ownerDirectory = try ownerDirectoryURL(
            ownerKey: ownerKey,
            mediaDirectoryURL: mediaDirectoryURL,
            fileManager: fileManager
        )
        let target = ownerDirectory.appendingPathComponent(
            "\(exerciseID.uuidString).jpg",
            isDirectory: false
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try excludeFromBackup(root)
        try fileManager.createDirectory(
            at: ownerDirectory,
            withIntermediateDirectories: true
        )
        try excludeFromBackup(ownerDirectory)
        do {
            try encoded.write(
                to: target,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            try excludeFromBackup(target)
        } catch {
            // Never leave a private photo behind if its backup exclusion could not be proven.
            try? fileManager.removeItem(at: target)
            throw MediaError.persistenceFailure
        }
    }

    static func deleteCustomImage(
        ownerKey: String,
        exerciseID: UUID,
        mediaDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let target = try customURL(
            ownerKey: ownerKey,
            exerciseID: exerciseID,
            mediaDirectoryURL: mediaDirectoryURL,
            fileManager: fileManager
        )
        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
    }

    static func clearAccount(
        ownerKey: String,
        mediaDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let ownerDirectory = try ownerDirectoryURL(
            ownerKey: ownerKey,
            mediaDirectoryURL: mediaDirectoryURL,
            fileManager: fileManager
        )
        guard fileManager.fileExists(atPath: ownerDirectory.path) else { return }
        try fileManager.removeItem(at: ownerDirectory)
    }

    private static func customURL(
        ownerKey: String,
        exerciseID: UUID,
        mediaDirectoryURL: URL?,
        fileManager: FileManager
    ) throws -> URL {
        try ownerDirectoryURL(
            ownerKey: ownerKey,
            mediaDirectoryURL: mediaDirectoryURL,
            fileManager: fileManager
        )
            .appendingPathComponent("\(exerciseID.uuidString).jpg")
    }

    private static func rootDirectoryURL(
        mediaDirectoryURL: URL?,
        fileManager: FileManager
    ) throws -> URL {
        let root = mediaDirectoryURL ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExerciseMedia", isDirectory: true)
        guard root.isFileURL else { throw MediaError.invalidOwner }
        return root.standardizedFileURL
    }

    private static func ownerDirectoryURL(
        ownerKey: String,
        mediaDirectoryURL: URL?,
        fileManager: FileManager
    ) throws -> URL {
        let trimmed = ownerKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == ownerKey,
              !ownerKey.isEmpty,
              ownerKey.count <= maximumOwnerKeyLength else {
            throw MediaError.invalidOwner
        }
        let root = try rootDirectoryURL(
            mediaDirectoryURL: mediaDirectoryURL,
            fileManager: fileManager
        )
        let ownerDirectory = root
            .appendingPathComponent(ownerFingerprint(ownerKey), isDirectory: true)
            .standardizedFileURL
        guard ownerDirectory.deletingLastPathComponent() == root else {
            throw MediaError.invalidOwner
        }
        return ownerDirectory
    }

    private static func excludeFromBackup(_ url: URL) throws {
        do {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try mutableURL.setResourceValues(values)
            guard try mutableURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true else {
                throw MediaError.persistenceFailure
            }
        } catch {
            throw MediaError.persistenceFailure
        }
    }

    private static func ownerFingerprint(_ ownerKey: String) -> String {
        SHA256.hash(data: Data("gymapp-exercise-media-v1:\(ownerKey)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    enum MediaError: Error, Equatable {
        case invalidImage
        case invalidOwner
        case persistenceFailure
    }
}
