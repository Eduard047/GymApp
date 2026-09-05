import Foundation

enum TrainingTools {
    static func stepWeight(_ weight: Double, direction: Int, allowed: [Double] = []) -> Double {
        guard weight.isFinite, (0 ... 1_000_000).contains(weight), [-1, 1].contains(direction),
              allowed.count <= 128,
              allowed.allSatisfy({ $0.isFinite && (0 ... 1_000_000).contains($0) }),
              zip(allowed, allowed.dropFirst()).allSatisfy({ $0 < $1 }) else { return weight }
        if !allowed.isEmpty {
            return direction > 0
                ? allowed.first(where: { $0 > weight }) ?? weight
                : allowed.last(where: { $0 < weight }) ?? weight
        }
        return min(1_000_000, max(0, weight + Double(direction) * 2.5))
    }
}
