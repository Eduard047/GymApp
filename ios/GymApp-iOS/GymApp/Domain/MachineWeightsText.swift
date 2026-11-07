import Foundation

/// Text form of a machine's allowed-weights list, shared with Android (shared/machine-weights-v1.json).
///
/// Tokens are separated by ASCII whitespace, newlines, ';', or a comma followed by whitespace or the
/// end of the text. A comma between digits is always a decimal separator ("12,5" is 12.5), so
/// "10,20,30" is invalid. A token is ASCII digits with one optional '.' or ',' and 1 to 2 decimals.
enum MachineWeightsText {
    static let maximumTextBytes = 2_048

    private static let separators: Set<Unicode.Scalar> = [" ", "\t", "\n", "\r", "\u{0B}", "\u{0C}"]

    /// Sorted, distinct weights, or nil when the text is not a valid list.
    static func parse(_ raw: String) -> [Double]? {
        guard raw.utf8.count <= maximumTextBytes else { return nil }
        let tokens = tokens(raw)
        guard !tokens.isEmpty, tokens.count <= MachineLoadProfile.maximumAllowedWeightCount else {
            return nil
        }
        var parsed: [Double] = []
        for token in tokens {
            guard let weight = weight(token),
                  (0 ... MachineLoadProfile.maximumAllowedWeightKg).contains(weight) else {
                return nil
            }
            parsed.append(weight)
        }
        return Array(Set(parsed)).sorted()
    }

    /// Evenly stepped preset weights `step, 2*step, ...` up to `maximum`, capped at the profile's
    /// weight count. Empty (never a trap) for a non-positive or non-finite step or maximum.
    static func presetWeights(step: Double, maximum: Double) -> [Double] {
        guard step.isFinite, step > 0, maximum.isFinite, maximum >= step else { return [] }
        let count = min(MachineLoadProfile.maximumAllowedWeightCount, Int(floor(maximum / step)))
        guard count >= 1 else { return [] }
        return (1 ... count).map { Double($0) * step }
    }

    private static func weight(_ token: String) -> Double? {
        // Work on unicode scalars: "\r\n" is one Character in Swift but two ASCII separators.
        let scalars = Array(token.unicodeScalars)
        func isDigit(_ scalar: Unicode.Scalar) -> Bool { scalar.value >= 0x30 && scalar.value <= 0x39 }
        var integerDigits = 0
        while integerDigits < scalars.count, isDigit(scalars[integerDigits]) { integerDigits += 1 }
        guard integerDigits > 0 else { return nil }
        if integerDigits == scalars.count { return Double(token) }
        guard scalars[integerDigits] == "." || scalars[integerDigits] == "," else { return nil }
        let fraction = scalars[(integerDigits + 1)...]
        guard (1 ... 2).contains(fraction.count), fraction.allSatisfy(isDigit) else { return nil }
        return Double(token.replacingOccurrences(of: ",", with: "."))
    }

    private static func tokens(_ raw: String) -> [String] {
        var result: [String] = []
        var current = String.UnicodeScalarView()
        let scalars = Array(raw.unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            let endsToken = scalar == ";" || separators.contains(scalar)
                || (scalar == "," && (index + 1 == scalars.count || separators.contains(scalars[index + 1])))
            if endsToken {
                if !current.isEmpty { result.append(String(current)); current = String.UnicodeScalarView() }
            } else {
                current.append(scalar)
            }
        }
        if !current.isEmpty { result.append(String(current)) }
        return result
    }
}
