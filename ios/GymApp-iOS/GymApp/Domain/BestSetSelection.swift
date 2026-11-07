import Foundation

/// One completed set of a saved exercise, as the best-set picker sees it.
struct BestSetCandidate: Equatable, Sendable {
    let weight: Double
    let reps: Int
    let isPersonalRecord: Bool
}

/// Picks the set to tag "Best" in a past workout. Same rules as Android
/// (shared/best-set-v1.json): needs at least two completed sets (reps above
/// zero); the best set has the highest estimated one-rep max, ties go to the
/// heavier weight, then the earlier set; 0 kg sets are ignored unless every set
/// is 0 kg, in which case the most reps wins. A set already marked as a personal
/// record keeps its record badge, so nothing is tagged then.
enum BestSetSelection {
    private static let estimateTolerance = 1e-9

    /// Index into `sets` of the best set, or nil when no set should be tagged.
    static func bestIndex(of sets: [BestSetCandidate]) -> Int? {
        let completed = sets.enumerated().filter { $0.element.reps > 0 && $0.element.weight >= 0 }
        guard completed.count >= 2 else { return nil }
        let allBodyweight = completed.allSatisfy { $0.element.weight <= 0 }
        let pool = allBodyweight ? completed : completed.filter { $0.element.weight > 0 }
        var best: (offset: Int, element: BestSetCandidate)?
        for entry in pool {
            if let current = best {
                if beats(entry.element, current.element, byReps: allBodyweight) { best = entry }
            } else {
                best = entry
            }
        }
        guard let winner = best, !winner.element.isPersonalRecord else { return nil }
        return winner.offset
    }

    /// True when `candidate` strictly beats `incumbent`; equal sets keep the earlier one.
    private static func beats(_ candidate: BestSetCandidate, _ incumbent: BestSetCandidate, byReps: Bool) -> Bool {
        if byReps { return candidate.reps > incumbent.reps }
        let candidateEstimate = GymOneRepMax.estimate(weight: candidate.weight, reps: candidate.reps)
        let incumbentEstimate = GymOneRepMax.estimate(weight: incumbent.weight, reps: incumbent.reps)
        if candidateEstimate > incumbentEstimate + estimateTolerance { return true }
        if candidateEstimate < incumbentEstimate - estimateTolerance { return false }
        return candidate.weight > incumbent.weight
    }
}
