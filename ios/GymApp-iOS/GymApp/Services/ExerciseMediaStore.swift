import CryptoKit
import Foundation
import ImageIO
import UIKit

struct ExerciseMediaThumbnailResult: @unchecked Sendable {
    let image: UIImage?
    let hasCustomImage: Bool
    let bundledFrameCount: Int
}

final class ExerciseMediaThumbnailCache: @unchecked Sendable {
    struct Lookup: @unchecked Sendable {
        let image: UIImage?
        let generation: UInt64
    }

    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var generation: UInt64 = 0

    init(countLimit: Int, totalCostLimit: Int) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func lookup(for key: String) -> Lookup {
        lock.lock()
        defer { lock.unlock() }
        return Lookup(
            image: cache.object(forKey: key as NSString),
            generation: generation
        )
    }

    @discardableResult
    func insert(
        _ image: UIImage,
        for key: String,
        ifGeneration expectedGeneration: UInt64
    ) -> Bool {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        lock.lock()
        defer { lock.unlock() }
        guard generation == expectedGeneration else { return false }
        cache.setObject(image, forKey: key as NSString, cost: cost)
        return true
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        cache.removeAllObjects()
    }
}

enum ExerciseMediaStore {
    private static let maximumInputBytes = 8 * 1024 * 1024
    private static let maximumOutputBytes = 1_600_000
    private static let maximumDimension: CGFloat = 8_192
    private static let maximumPixels: CGFloat = 40_000_000
    private static let maximumSavedDimension: CGFloat = 1_024
    private static let maximumOwnerKeyLength = 128
    private static let bundledThumbnailCache = ExerciseMediaThumbnailCache(
        countLimit: 128,
        totalCostLimit: 24 * 1_024 * 1_024
    )
    private static let customThumbnailCache = ExerciseMediaThumbnailCache(
        countLimit: 64,
        totalCostLimit: 16 * 1_024 * 1_024
    )

    private struct SendableImage: @unchecked Sendable {
        let value: UIImage
    }

    static func bundledImages(catalogKey: String?, rawExerciseName: String) -> [UIImage] {
        bundledImageURLs(
            catalogKey: catalogKey,
            name: rawExerciseName
        ).compactMap {
            UIImage(contentsOfFile: $0.path)
        }
    }

    /// Loads the compact list thumbnail off the main thread and bounds decoded pixels.
    /// Custom cache keys contain the hashed owner directory and are invalidated after
    /// every file mutation, so an account switch cannot reuse another owner's image.
    @MainActor
    static func thumbnail(
        ownerKey: String,
        exerciseID: UUID,
        catalogKey: String?,
        rawExerciseName: String,
        maximumPixelSize: Int,
        mediaDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) async -> ExerciseMediaThumbnailResult {
        let pixelSize = min(max(maximumPixelSize, 32), 2_048)
        let customTarget = try? customURL(
            ownerKey: ownerKey,
            exerciseID: exerciseID,
            mediaDirectoryURL: mediaDirectoryURL,
            fileManager: fileManager
        )
        let hasCustomImage = customTarget.map {
            fileManager.fileExists(atPath: $0.path)
        } ?? false
        let bundledURLs = bundledImageURLs(
            catalogKey: catalogKey,
            name: rawExerciseName
        )
        let sourceURL = hasCustomImage ? customTarget : bundledURLs.first
        let resultWithoutImage = ExerciseMediaThumbnailResult(
            image: nil,
            hasCustomImage: hasCustomImage,
            bundledFrameCount: bundledURLs.count
        )
        guard let sourceURL else { return resultWithoutImage }

        let cache = hasCustomImage ? customThumbnailCache : bundledThumbnailCache
        let cacheScope = hasCustomImage
            ? "custom:\(ownerFingerprint(ownerKey)):\(exerciseID.uuidString)"
            : "bundled"
        let cacheKey = thumbnailCacheKey(
            scope: cacheScope,
            sourceURL: sourceURL,
            maximumPixelSize: pixelSize
        )
        let cacheLookup = cache.lookup(for: cacheKey)
        if let image = cacheLookup.image {
            return ExerciseMediaThumbnailResult(
                image: image,
                hasCustomImage: hasCustomImage,
                bundledFrameCount: bundledURLs.count
            )
        }

        let decodeTask = Task.detached(priority: .utility) { () -> SendableImage? in
            guard !Task.isCancelled,
                  let image = downsampledImage(
                    at: sourceURL,
                    maximumPixelSize: pixelSize
                  ),
                  !Task.isCancelled else { return nil }
            return SendableImage(value: image)
        }
        let decoded = await withTaskCancellationHandler {
            await decodeTask.value
        } onCancel: {
            decodeTask.cancel()
        }
        guard !Task.isCancelled, let image = decoded?.value else {
            return resultWithoutImage
        }
        guard cache.insert(
            image,
            for: cacheKey,
            ifGeneration: cacheLookup.generation
        ) else {
            // A save/delete/account clear completed while the detached decode was in
            // flight. Never publish or re-cache the now-stale owner-private bitmap.
            let currentHasCustomImage = customTarget.map {
                fileManager.fileExists(atPath: $0.path)
            } ?? false
            return ExerciseMediaThumbnailResult(
                image: nil,
                hasCustomImage: currentHasCustomImage,
                bundledFrameCount: bundledURLs.count
            )
        }
        return ExerciseMediaThumbnailResult(
            image: image,
            hasCustomImage: hasCustomImage,
            bundledFrameCount: bundledURLs.count
        )
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
            customThumbnailCache.removeAll()
        } catch {
            // Never leave a private photo behind if its backup exclusion could not be proven.
            try? fileManager.removeItem(at: target)
            customThumbnailCache.removeAll()
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
        guard fileManager.fileExists(atPath: target.path) else {
            customThumbnailCache.removeAll()
            return
        }
        do {
            try fileManager.removeItem(at: target)
            customThumbnailCache.removeAll()
        } catch {
            customThumbnailCache.removeAll()
            throw error
        }
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
        guard fileManager.fileExists(atPath: ownerDirectory.path) else {
            customThumbnailCache.removeAll()
            return
        }
        do {
            try fileManager.removeItem(at: ownerDirectory)
            customThumbnailCache.removeAll()
        } catch {
            customThumbnailCache.removeAll()
            throw error
        }
    }

    private static func bundledImageURLs(
        catalogKey: String?,
        name rawExerciseName: String
    ) -> [URL] {
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
            )
        }
    }

    private static func thumbnailCacheKey(
        scope: String,
        sourceURL: URL,
        maximumPixelSize: Int
    ) -> String {
        SHA256.hash(data: Data(
            "\(scope):\(sourceURL.standardizedFileURL.path):\(maximumPixelSize)".utf8
        ))
        .map { String(format: "%02x", $0) }
        .joined()
    }

    private static func downsampledImage(
        at url: URL,
        maximumPixelSize: Int
    ) -> UIImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions
        ) else { return nil }
        return UIImage(cgImage: image)
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
