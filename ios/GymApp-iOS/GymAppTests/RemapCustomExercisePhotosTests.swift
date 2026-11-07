import UIKit
import XCTest
@testable import GymApp

@MainActor
final class RemapCustomExercisePhotosTests: XCTestCase {
    func testPhotoLessDuplicateListedFirstDoesNotStarveTheOneWithAPhoto() throws {
        let mediaDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppRemapPhotos-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: mediaDirectory) }
        let owner = "local_\(UUID().uuidString.lowercased())"
        let store = try WorkoutStore(
            accountStorageKey: owner,
            directoryURL: mediaDirectory.appendingPathComponent("store", isDirectory: true)
        )
        store.exerciseMediaDirectoryURL = mediaDirectory

        // Both old names are different persisted names but the same portable name as the
        // single new exercise, so they compete for one target. The photo-less one is first.
        let photoLess = Exercise(name: "Sled  Drag Custom")
        let withPhoto = Exercise(name: "SLED  DRAG  CUSTOM")
        let target = Exercise(name: "Sled Drag Custom")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
            UIColor.systemGreen.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        try ExerciseMediaStore.saveCustomImage(
            try XCTUnwrap(image.jpegData(compressionQuality: 0.9)),
            ownerKey: owner,
            exerciseID: withPhoto.id,
            mediaDirectoryURL: mediaDirectory
        )

        store.remapCustomExercisePhotos(from: [photoLess, withPhoto], to: [target])

        XCTAssertNotNil(ExerciseMediaStore.customImage(
            ownerKey: owner, exerciseID: target.id, mediaDirectoryURL: mediaDirectory
        ), "the photo must survive on the new exercise id")
        XCTAssertNil(ExerciseMediaStore.customImage(
            ownerKey: owner, exerciseID: withPhoto.id, mediaDirectoryURL: mediaDirectory
        ))
    }
}
