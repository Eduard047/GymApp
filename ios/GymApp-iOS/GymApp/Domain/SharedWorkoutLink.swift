import CoreFoundation
import Foundation

enum SharedWorkoutLinkError: Error, Equatable, Sendable {
    case invalidURL
    case invalidPayload
    case unsupportedVersion
    case invalidExerciseCount
    case duplicateExercise
    case missingExercise
    case invalidExerciseName
    case invalidCatalogKey
    case invalidSetCount
    case tooManySets
    case invalidWeight
    case invalidRepetitions
    case payloadTooLarge
    case encodingFailed
}

struct SharedWorkoutPlanSet: Equatable, Sendable {
    let weight: Double
    let repetitions: Int
}

struct SharedWorkoutPlanExercise: Equatable, Sendable {
    let catalogKey: String?
    let name: String
    let sets: [SharedWorkoutPlanSet]
}

struct SharedWorkoutPlan: Equatable, Sendable {
    let exercises: [SharedWorkoutPlanExercise]

    var totalSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }
}

enum SharedWorkoutLinkEncoder {
    static let maximumEncodedLength = 12_000
    static let maximumDecodedBytes = 9_000
    static let maximumExercises = 20
    static let maximumSetsPerExercise = 12
    static let maximumTotalSets = 120
    static let maximumExerciseNameCharacters = 120
    static let maximumExerciseNameBytes = 480
    static let maximumCatalogKeyCharacters = 64
    static let maximumWeight = 1_000_000.0
    static let maximumRepetitions = 10_000

    static func makeURL(
        workout: WorkoutSession,
        exercises: [UUID: Exercise]
    ) throws -> URL {
        try makeURL(plan: makePlan(workout: workout, exercises: exercises))
    }

    static func makePlan(
        workout: WorkoutSession,
        exercises: [UUID: Exercise]
    ) throws -> SharedWorkoutPlan {
        let blocks = workout.exercises.filter { !$0.sets.isEmpty }
        guard !blocks.isEmpty, blocks.count <= maximumExercises else {
            throw SharedWorkoutLinkError.invalidExerciseCount
        }

        let sharedExercises = try blocks.map { block -> SharedWorkoutPlanExercise in
            guard let exercise = exercises[block.exerciseID] else {
                throw SharedWorkoutLinkError.missingExercise
            }
            return SharedWorkoutPlanExercise(
                catalogKey: exercise.catalogKey,
                name: exercise.name,
                sets: block.sets.map {
                    SharedWorkoutPlanSet(weight: $0.weight, repetitions: $0.reps)
                }
            )
        }
        return try SharedWorkoutLinkValidator.validate(
            SharedWorkoutPlan(exercises: sharedExercises)
        )
    }

    static func makeURL(plan: SharedWorkoutPlan) throws -> URL {
        try makeURL(
            plan: plan,
            prefix: "https://gymapptracker.com/workout/#workout="
        )
    }

    static func makeWebsiteURL(plan: SharedWorkoutPlan) throws -> URL {
        try makeURL(
            plan: plan,
            prefix: "https://gymapptracker.com/#workout="
        )
    }

    static func makeCustomSchemeURL(plan: SharedWorkoutPlan) throws -> URL {
        try makeURL(
            plan: plan,
            prefix: "com.setforge.gymapp.ios://workout/#workout="
        )
    }

    static func encodedPayload(for plan: SharedWorkoutPlan) throws -> String {
        let validated = try SharedWorkoutLinkValidator.validate(plan)
        let compactExercises: [[Any]] = validated.exercises.map { exercise in
            let compactSets: [[Any]] = exercise.sets.map {
                [$0.weight, $0.repetitions]
            }
            return [exercise.catalogKey ?? "", exercise.name, compactSets]
        }
        let compactPayload: [String: Any] = ["v": 1, "e": compactExercises]
        guard JSONSerialization.isValidJSONObject(compactPayload),
              let data = try? JSONSerialization.data(withJSONObject: compactPayload),
              data.count <= maximumDecodedBytes else {
            throw SharedWorkoutLinkError.payloadTooLarge
        }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=+$", with: "", options: .regularExpression)
        guard !encoded.isEmpty, encoded.count <= maximumEncodedLength else {
            throw SharedWorkoutLinkError.payloadTooLarge
        }
        return encoded
    }

    private static func makeURL(plan: SharedWorkoutPlan, prefix: String) throws -> URL {
        let encoded = try encodedPayload(for: plan)
        guard let url = URL(string: prefix + encoded) else {
            throw SharedWorkoutLinkError.encodingFailed
        }
        return url
    }
}

enum SharedWorkoutLinkDecoder {
    private enum Destination {
        case canonicalHTTPS
        case customScheme
        case legacyHTTPSRoot
    }

    static func isRecognizedDestination(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else {
            return false
        }
        if scheme == "com.setforge.gymapp.ios", host == "workout" {
            // Claim the whole custom-scheme namespace so malformed workout links
            // fail closed instead of falling through to Garmin or authentication.
            return true
        }
        if scheme == "https", host == "gymapptracker.com" {
            let path = components.path
            return path == "/workout" || path.hasPrefix("/workout/")
        }
        return false
    }

    static func decode(
        _ url: URL,
        allowLegacyHTTPSRoot: Bool = false
    ) throws -> SharedWorkoutPlan {
        guard let destination = destination(
            for: url,
            allowLegacyHTTPSRoot: allowLegacyHTTPSRoot
        ), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SharedWorkoutLinkError.invalidURL
        }
        guard components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil else {
            throw SharedWorkoutLinkError.invalidURL
        }
        switch destination {
        case .canonicalHTTPS:
            guard components.scheme?.lowercased() == "https",
                  components.percentEncodedHost?.lowercased() == "gymapptracker.com",
                  components.percentEncodedPath == "/workout/" else {
                throw SharedWorkoutLinkError.invalidURL
            }
        case .customScheme:
            guard components.scheme?.lowercased() == "com.setforge.gymapp.ios",
                  components.percentEncodedHost?.lowercased() == "workout",
                  components.percentEncodedPath == "/" else {
                throw SharedWorkoutLinkError.invalidURL
            }
        case .legacyHTTPSRoot:
            guard allowLegacyHTTPSRoot,
                  components.scheme?.lowercased() == "https",
                  components.percentEncodedHost?.lowercased() == "gymapptracker.com",
                  components.percentEncodedPath == "/" else {
                throw SharedWorkoutLinkError.invalidURL
            }
        }

        guard let fragment = components.percentEncodedFragment,
              fragment.hasPrefix("workout=") else {
            throw SharedWorkoutLinkError.invalidURL
        }
        let encoded = String(fragment.dropFirst("workout=".count))
        guard !encoded.isEmpty,
              encoded.count <= SharedWorkoutLinkEncoder.maximumEncodedLength,
              encoded.unicodeScalars.allSatisfy({ scalar in
                  (scalar.value >= 0x41 && scalar.value <= 0x5A) ||
                      (scalar.value >= 0x61 && scalar.value <= 0x7A) ||
                      (scalar.value >= 0x30 && scalar.value <= 0x39) ||
                      scalar.value == 0x2D || scalar.value == 0x5F
              }) else {
            throw SharedWorkoutLinkError.invalidPayload
        }

        guard encoded.count % 4 != 1 else {
            throw SharedWorkoutLinkError.invalidPayload
        }
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              data.count <= SharedWorkoutLinkEncoder.maximumDecodedBytes,
              data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=+$", with: "", options: .regularExpression) == encoded,
              String(data: data, encoding: .utf8) != nil else {
            throw SharedWorkoutLinkError.invalidPayload
        }

        try StrictSharedWorkoutJSONScanner.validate(data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set(["v", "e"]),
              let version = root["v"] as? NSNumber,
              !numberIsBoolean(version),
              version.doubleValue.isFinite,
              version.doubleValue.rounded(.towardZero) == version.doubleValue,
              version.doubleValue >= Double(Int.min),
              version.doubleValue <= Double(Int.max),
              let compactExercises = root["e"] as? [Any] else {
            throw SharedWorkoutLinkError.invalidPayload
        }
        guard version.intValue == 1 else {
            throw SharedWorkoutLinkError.unsupportedVersion
        }

        var exercises: [SharedWorkoutPlanExercise] = []
        exercises.reserveCapacity(compactExercises.count)
        for value in compactExercises {
            guard let compactExercise = value as? [Any],
                  compactExercise.count == 3,
                  let catalogKey = compactExercise[0] as? String,
                  let name = compactExercise[1] as? String,
                  let compactSets = compactExercise[2] as? [Any] else {
                throw SharedWorkoutLinkError.invalidPayload
            }
            var sets: [SharedWorkoutPlanSet] = []
            sets.reserveCapacity(compactSets.count)
            for setValue in compactSets {
                guard let compactSet = setValue as? [Any],
                      compactSet.count == 2,
                      let weight = compactSet[0] as? NSNumber,
                      let repetitions = compactSet[1] as? NSNumber,
                      !numberIsBoolean(weight),
                      !numberIsBoolean(repetitions),
                      repetitions.doubleValue.isFinite,
                      repetitions.doubleValue.rounded(.towardZero) == repetitions.doubleValue,
                      repetitions.doubleValue >= Double(Int.min),
                      repetitions.doubleValue <= Double(Int.max) else {
                    throw SharedWorkoutLinkError.invalidPayload
                }
                sets.append(
                    SharedWorkoutPlanSet(
                        weight: weight.doubleValue,
                        repetitions: repetitions.intValue
                    )
                )
            }
            exercises.append(
                SharedWorkoutPlanExercise(
                    catalogKey: catalogKey.isEmpty ? nil : catalogKey,
                    name: name,
                    sets: sets
                )
            )
        }
        return try SharedWorkoutLinkValidator.validate(
            SharedWorkoutPlan(exercises: exercises)
        )
    }

    private static func destination(
        for url: URL,
        allowLegacyHTTPSRoot: Bool
    ) -> Destination? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else {
            return nil
        }
        if scheme == "https", host == "gymapptracker.com" {
            if components.path == "/workout/" { return .canonicalHTTPS }
            if allowLegacyHTTPSRoot, components.path == "/" { return .legacyHTTPSRoot }
        }
        if scheme == "com.setforge.gymapp.ios",
           host == "workout",
           components.path == "/" {
            return .customScheme
        }
        return nil
    }

    private static func numberIsBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}

enum SharedWorkoutLinkValidator {
    static func validate(_ plan: SharedWorkoutPlan) throws -> SharedWorkoutPlan {
        guard !plan.exercises.isEmpty,
              plan.exercises.count <= SharedWorkoutLinkEncoder.maximumExercises else {
            throw SharedWorkoutLinkError.invalidExerciseCount
        }

        var totalSets = 0
        var exerciseIdentities = Set<String>()
        var validatedExercises: [SharedWorkoutPlanExercise] = []
        validatedExercises.reserveCapacity(plan.exercises.count)
        for exercise in plan.exercises {
            let name = exercise.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping
            guard !name.isEmpty,
                  name.unicodeScalars.count <= SharedWorkoutLinkEncoder.maximumExerciseNameCharacters,
                  name.utf8.count <= SharedWorkoutLinkEncoder.maximumExerciseNameBytes,
                  !name.unicodeScalars.contains(where: isUnsafeNameScalar) else {
                throw SharedWorkoutLinkError.invalidExerciseName
            }

            let canonicalNameKey = BuiltInExerciseCatalog.canonicalKey(forName: name)
            if let catalogKey = exercise.catalogKey,
               !validCatalogKey(catalogKey) {
                    throw SharedWorkoutLinkError.invalidCatalogKey
            }
            // The reviewed name decides local catalog identity. A syntactically valid
            // cross-platform key is retained for forwarding, but never upgrades a custom
            // name into a built-in exercise on this device.
            let validatedCatalogKey = canonicalNameKey ?? exercise.catalogKey
            let identity = canonicalNameKey.map { "catalog:\($0)" }
                ?? "custom:\(normalizeExerciseIdentityName(name))"
            guard exerciseIdentities.insert(identity).inserted else {
                throw SharedWorkoutLinkError.duplicateExercise
            }

            guard !exercise.sets.isEmpty,
                  exercise.sets.count <= SharedWorkoutLinkEncoder.maximumSetsPerExercise else {
                throw SharedWorkoutLinkError.invalidSetCount
            }
            totalSets += exercise.sets.count
            guard totalSets <= SharedWorkoutLinkEncoder.maximumTotalSets else {
                throw SharedWorkoutLinkError.tooManySets
            }
            for set in exercise.sets {
                guard set.weight.isFinite,
                      (0 ... SharedWorkoutLinkEncoder.maximumWeight).contains(set.weight) else {
                    throw SharedWorkoutLinkError.invalidWeight
                }
                guard (1 ... SharedWorkoutLinkEncoder.maximumRepetitions)
                    .contains(set.repetitions) else {
                    throw SharedWorkoutLinkError.invalidRepetitions
                }
            }
            validatedExercises.append(
                SharedWorkoutPlanExercise(
                    catalogKey: validatedCatalogKey,
                    name: name,
                    sets: exercise.sets
                )
            )
        }
        return SharedWorkoutPlan(exercises: validatedExercises)
    }

    private static func validCatalogKey(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.count <= SharedWorkoutLinkEncoder.maximumCatalogKeyCharacters else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 0x61 && scalar.value <= 0x7A) ||
                (scalar.value >= 0x30 && scalar.value <= 0x39) ||
                scalar.value == 0x5F
        }
    }

    private static func isUnsafeNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        // Keep preview validation aligned with WorkoutStore: all Unicode control
        // and format scalars (including zero-width/bidi controls) are rejected.
        // Line/paragraph separators are not in that CharacterSet, so reject them
        // explicitly as well.
        return CharacterSet.controlCharacters.contains(scalar) ||
            value == 0x2028 || value == 0x2029
    }
}

private struct StrictSharedWorkoutJSONScanner {
    private let bytes: [UInt8]
    private var index = 0

    static func validate(_ data: Data) throws {
        var scanner = Self(bytes: Array(data))
        try scanner.parseValue(depth: 0)
        scanner.skipWhitespace()
        guard scanner.index == scanner.bytes.count else {
            throw SharedWorkoutLinkError.invalidPayload
        }
    }

    private mutating func parseValue(depth: Int) throws {
        guard depth <= 8 else { throw SharedWorkoutLinkError.invalidPayload }
        skipWhitespace()
        guard let byte = current else { throw SharedWorkoutLinkError.invalidPayload }
        switch byte {
        case 0x7B: try parseObject(depth: depth + 1)
        case 0x5B: try parseArray(depth: depth + 1)
        case 0x22: _ = try parseString()
        case 0x74: try consumeLiteral("true")
        case 0x66: try consumeLiteral("false")
        case 0x6E: try consumeLiteral("null")
        case 0x2D, 0x30 ... 0x39: try parseNumber()
        default: throw SharedWorkoutLinkError.invalidPayload
        }
    }

    private mutating func parseObject(depth: Int) throws {
        try consume(0x7B)
        skipWhitespace()
        if current == 0x7D {
            index += 1
            return
        }
        var keys = Set<String>()
        while true {
            skipWhitespace()
            let key = try parseString()
            guard keys.insert(key).inserted else {
                throw SharedWorkoutLinkError.invalidPayload
            }
            skipWhitespace()
            try consume(0x3A)
            try parseValue(depth: depth)
            skipWhitespace()
            if current == 0x7D {
                index += 1
                return
            }
            try consume(0x2C)
        }
    }

    private mutating func parseArray(depth: Int) throws {
        try consume(0x5B)
        skipWhitespace()
        if current == 0x5D {
            index += 1
            return
        }
        while true {
            try parseValue(depth: depth)
            skipWhitespace()
            if current == 0x5D {
                index += 1
                return
            }
            try consume(0x2C)
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        try consume(0x22)
        while let byte = current {
            if byte == 0x22 {
                index += 1
                let token = Data(bytes[start ..< index])
                guard let decoded = try JSONSerialization.jsonObject(
                    with: token,
                    options: [.fragmentsAllowed]
                ) as? String else {
                    throw SharedWorkoutLinkError.invalidPayload
                }
                return decoded
            }
            if byte < 0x20 { throw SharedWorkoutLinkError.invalidPayload }
            if byte == 0x5C {
                index += 1
                guard let escaped = current else {
                    throw SharedWorkoutLinkError.invalidPayload
                }
                if escaped == 0x75 {
                    index += 1
                    for _ in 0 ..< 4 {
                        guard let hexadecimal = current,
                              (0x30 ... 0x39).contains(hexadecimal) ||
                                (0x41 ... 0x46).contains(hexadecimal) ||
                                (0x61 ... 0x66).contains(hexadecimal) else {
                            throw SharedWorkoutLinkError.invalidPayload
                        }
                        index += 1
                    }
                    continue
                }
                guard [0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74]
                    .contains(escaped) else {
                    throw SharedWorkoutLinkError.invalidPayload
                }
            }
            index += 1
        }
        throw SharedWorkoutLinkError.invalidPayload
    }

    private mutating func parseNumber() throws {
        if current == 0x2D { index += 1 }
        guard let first = current else { throw SharedWorkoutLinkError.invalidPayload }
        if first == 0x30 {
            index += 1
            if let next = current, (0x30 ... 0x39).contains(next) {
                throw SharedWorkoutLinkError.invalidPayload
            }
        } else {
            guard (0x31 ... 0x39).contains(first) else {
                throw SharedWorkoutLinkError.invalidPayload
            }
            index += 1
            while let byte = current, (0x30 ... 0x39).contains(byte) { index += 1 }
        }
        if current == 0x2E {
            index += 1
            guard let digit = current, (0x30 ... 0x39).contains(digit) else {
                throw SharedWorkoutLinkError.invalidPayload
            }
            while let byte = current, (0x30 ... 0x39).contains(byte) { index += 1 }
        }
        if current == 0x65 || current == 0x45 {
            index += 1
            if current == 0x2B || current == 0x2D { index += 1 }
            guard let digit = current, (0x30 ... 0x39).contains(digit) else {
                throw SharedWorkoutLinkError.invalidPayload
            }
            while let byte = current, (0x30 ... 0x39).contains(byte) { index += 1 }
        }
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let expected = Array(String(describing: literal).utf8)
        guard index + expected.count <= bytes.count,
              Array(bytes[index ..< index + expected.count]) == expected else {
            throw SharedWorkoutLinkError.invalidPayload
        }
        index += expected.count
    }

    private mutating func consume(_ expected: UInt8) throws {
        guard current == expected else { throw SharedWorkoutLinkError.invalidPayload }
        index += 1
    }

    private mutating func skipWhitespace() {
        while let byte = current, [0x20, 0x09, 0x0A, 0x0D].contains(byte) {
            index += 1
        }
    }

    private var current: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }
}
