import Foundation

/// How one exercise of the finished workout compares with its previous session.
enum VsLastStatus: String, Equatable, Sendable {
    case new
    case up
    case down
    case same
}

/// What decided the status: total volume, or total reps when both volumes are 0 (bodyweight only).
enum VsLastBasis: String, Equatable, Sendable {
    case volume
    case reps
}

struct VsLastSet: Equatable, Sendable {
    let weight: Double
    let reps: Int
}

/// One logged set, flattened for the "compared with last time" rules
/// (shared/exercise-vs-last-v1.json). Rows of the finished session carry `sessionID == currentSessionID`.
struct VsLastHistoryRow<ExerciseID: Hashable & Comparable & Sendable>: Sendable {
    let exerciseID: ExerciseID
    /// Tie-break between sessions with the same date: the higher value is the newer session.
    let sessionID: Int
    let date: Double
    let blockOrderIndex: Int
    let weight: Double
    let reps: Int
}

/// One "compared with last time" row. `delta` is current minus previous on `basis`
/// (nil for a new exercise, 0 for "same"); `previousBest` is nil for a new exercise.
struct ExerciseVsLast<ExerciseID: Hashable & Comparable & Sendable>: Equatable, Sendable {
    let exerciseID: ExerciseID
    let status: VsLastStatus
    let basis: VsLastBasis?
    let delta: Double?
    let best: VsLastSet
    let previousBest: VsLastSet?
}

enum GymExerciseVsLast {
    /// Rows shown in the "Compared with last time" card, like Android.
    static let maxExercises = 8
    private static let epsilon = 1e-9
    /// A volume delta smaller than this (kg) counts as "same" (shared rule 5), so the UI never shows "+0 kg".
    private static let volumeSameThreshold = 0.05

    private struct FirstBlock {
        let blockOrderIndex: Int
        let volume: Double
        let reps: Int
        let best: VsLastSet
    }

    /// Rows with reps <= 0 are dropped first; of the rest only the first block (lowest block index) counts.
    private static func firstBlock<ID>(_ rows: [VsLastHistoryRow<ID>]) -> FirstBlock? {
        let valid = rows.filter { $0.reps > 0 }
        guard let firstIndex = valid.map(\.blockOrderIndex).min() else { return nil }
        let sets = valid.filter { $0.blockOrderIndex == firstIndex }
        guard var best = sets.first else { return nil }
        for row in sets.dropFirst() where row.weight > best.weight || (row.weight == best.weight && row.reps > best.reps) {
            best = row
        }
        return FirstBlock(
            blockOrderIndex: firstIndex,
            volume: sets.reduce(0) { $0 + $1.weight * Double($1.reps) },
            reps: sets.reduce(0) { $0 + $1.reps },
            best: VsLastSet(weight: best.weight, reps: best.reps)
        )
    }

    /// Same ordering as Android `isWorkoutEarlier`: smaller date, same date -> smaller session id.
    private static func isEarlier(date: Double, sessionID: Int, thanDate: Double, sessionID current: Int) -> Bool {
        date != thanDate ? date < thanDate : sessionID < current
    }

    /// Per exercise of the finished session: how its first block compares with the first block of the
    /// latest earlier session that has the exercise. Rows are in workout order, at most `maxExercises`;
    /// empty (card hidden) when every shown exercise is new. `history` holds the finished session's
    /// sets too (`sessionID == currentSessionID`).
    static func rows<ID>(
        history: [VsLastHistoryRow<ID>],
        currentSessionID: Int,
        currentDate: Double
    ) -> [ExerciseVsLast<ID>] {
        var currentByExercise: [ID: [VsLastHistoryRow<ID>]] = [:]
        var previousByExercise: [ID: [VsLastHistoryRow<ID>]] = [:]
        for row in history where row.reps > 0 {
            if row.sessionID == currentSessionID {
                currentByExercise[row.exerciseID, default: []].append(row)
            } else if isEarlier(date: row.date, sessionID: row.sessionID, thanDate: currentDate, sessionID: currentSessionID) {
                previousByExercise[row.exerciseID, default: []].append(row)
            }
        }

        var entries: [(id: ID, current: FirstBlock, previous: FirstBlock?)] = []
        for (exerciseID, rows) in currentByExercise {
            guard let current = firstBlock(rows) else { continue }
            var previous: FirstBlock?
            if let candidates = previousByExercise[exerciseID],
               let latest = candidates.max(by: { lhs, rhs in
                   lhs.date != rhs.date ? lhs.date < rhs.date : lhs.sessionID < rhs.sessionID
               }) {
                previous = firstBlock(candidates.filter { $0.date == latest.date && $0.sessionID == latest.sessionID })
            }
            entries.append((exerciseID, current, previous))
        }
        entries.sort { lhs, rhs in
            lhs.current.blockOrderIndex != rhs.current.blockOrderIndex
                ? lhs.current.blockOrderIndex < rhs.current.blockOrderIndex
                : lhs.id < rhs.id
        }

        let result: [ExerciseVsLast<ID>] = entries.prefix(maxExercises).map { entry in
            guard let previous = entry.previous else {
                return ExerciseVsLast(
                    exerciseID: entry.id, status: .new, basis: nil, delta: nil,
                    best: entry.current.best, previousBest: nil
                )
            }
            let repsBasis = entry.current.volume <= epsilon && previous.volume <= epsilon
            let delta = repsBasis
                ? Double(entry.current.reps - previous.reps)
                : entry.current.volume - previous.volume
            let sameLimit = repsBasis ? epsilon : volumeSameThreshold - epsilon
            let isSame = abs(delta) < sameLimit || abs(delta) <= epsilon
            let status: VsLastStatus = isSame ? .same : (delta > 0 ? .up : .down)
            return ExerciseVsLast(
                exerciseID: entry.id,
                status: status,
                basis: repsBasis ? .reps : .volume,
                delta: status == .same ? 0 : delta,
                best: entry.current.best,
                previousBest: previous.best
            )
        }
        return result.allSatisfy { $0.status == .new } ? [] : result
    }

    /// Same rules over the store's flattened history: a workout's `workoutOrderIndex` is its session id,
    /// its `blockOrderIndex` the exercise's position in the workout. Exercise ids are UUID strings.
    static func rows(
        history: [ExerciseHistoryEntry],
        workoutID: UUID,
        currentDate: Date
    ) -> [ExerciseVsLast<String>] {
        guard let currentSessionID = history.first(where: { $0.workoutID == workoutID })?.workoutOrderIndex else {
            return []
        }
        let flattened = history.map {
            VsLastHistoryRow(
                exerciseID: $0.exerciseID.uuidString,
                sessionID: $0.workoutOrderIndex,
                date: $0.sessionDate.timeIntervalSinceReferenceDate,
                blockOrderIndex: $0.blockOrderIndex,
                weight: $0.weight,
                reps: $0.reps
            )
        }
        return rows(
            history: flattened,
            currentSessionID: currentSessionID,
            currentDate: currentDate.timeIntervalSinceReferenceDate
        )
    }
}
