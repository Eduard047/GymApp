import Foundation

/// The running workout snapshot (active-workout.json), written after every change.
final class ActiveWorkoutStore {
    private let files: WatchFileStore
    private static let name = "active-workout.json"
    private static let maximumBytes = 256 * 1_024

    init(files: WatchFileStore) {
        self.files = files
    }

    func load() -> WatchActiveWorkout? {
        guard let data = files.read(name: Self.name, maximumBytes: Self.maximumBytes),
              let workout = try? JSONDecoder().decode(WatchActiveWorkout.self, from: data),
              WatchSync.isValidRequestID(workout.requestId),
              WatchSync.isValidHash(workout.accountBinding) else { return nil }
        return workout
    }

    func save(_ workout: WatchActiveWorkout) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try files.write(try encoder.encode(workout), name: Self.name)
    }

    func clear() {
        try? files.delete(name: Self.name)
    }
}
