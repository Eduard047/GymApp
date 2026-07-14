import Foundation

struct GarminPlanSet: Codable, Equatable, Sendable {
    let weight: Double
    let reps: Int
    let orderIndex: Int
}

struct GarminPlanExercise: Codable, Equatable, Sendable {
    let name: String
    let sets: [GarminPlanSet]
}

struct GarminWorkoutPlan: Codable, Equatable, Sendable {
    let source: String
    let version: Int
    let title: String
    let createdAt: String
    let startedAt: String
    let note: String
    let exercises: [GarminPlanExercise]
}

struct GarminDevice: Codable, Equatable, Sendable {
    let id: String
    let deviceToken: String
    let displayName: String
    let createdAt: String?
}

enum GarminPlanValidator {
    static let maximumExercises = 60
    static let maximumTotalSets = 60
    static let maximumPlanBytes = 64 * 1_024
    static let maximumTitleCharacters = 120
    static let maximumTitleBytes = 480
    static let maximumNameCharacters = 160
    static let maximumNameBytes = 640
    static let maximumFlattenedPlanNameBytes = 12_000
    static let maximumNoteCharacters = 2_000
    static let maximumNoteBytes = 8_000
    static let maximumTimestampBytes = 40
    static let maximumWeight = 1_000_000.0
    static let maximumReps = 10_000

    static func validate(_ plan: GarminWorkoutPlan) throws -> Data {
        guard plan.source == "gymapp-ios",
              plan.version == 1,
              bounded(
                plan.title,
                characters: maximumTitleCharacters,
                bytes: maximumTitleBytes
              ),
              !plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              bounded(plan.note, characters: maximumNoteCharacters, bytes: maximumNoteBytes),
              validTimestamp(plan.createdAt),
              validTimestamp(plan.startedAt),
              (1 ... maximumExercises).contains(plan.exercises.count) else {
            throw GarminCloudError.invalidPlan
        }

        var totalSets = 0
        var flattenedPlanNameBytes = 0
        for exercise in plan.exercises {
            guard bounded(
                    exercise.name,
                    characters: maximumNameCharacters,
                    bytes: maximumNameBytes
                  ),
                  !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !exercise.sets.isEmpty else {
                throw GarminCloudError.invalidPlan
            }
            guard exercise.sets.count <= maximumTotalSets - totalSets else {
                throw GarminCloudError.invalidPlan
            }
            let repeatedNameBytes = exercise.name.utf8.count * exercise.sets.count
            guard repeatedNameBytes <= maximumFlattenedPlanNameBytes - flattenedPlanNameBytes else {
                throw GarminCloudError.invalidPlan
            }
            totalSets += exercise.sets.count
            flattenedPlanNameBytes += repeatedNameBytes
            for (index, set) in exercise.sets.enumerated() {
                guard set.orderIndex == index,
                      set.weight.isFinite,
                      (0 ... maximumWeight).contains(set.weight),
                      (1 ... maximumReps).contains(set.reps) else {
                    throw GarminCloudError.invalidPlan
                }
            }
        }
        guard totalSets > 0 else { throw GarminCloudError.invalidPlan }

        let data = try JSONEncoder().encode(plan)
        guard data.count <= maximumPlanBytes else { throw GarminCloudError.invalidPlan }
        return data
    }

    private static func bounded(_ value: String, characters: Int, bytes: Int) -> Bool {
        guard value.utf8.prefix(bytes + 1).count <= bytes else { return false }
        return value.utf16.prefix(characters + 1).count <= characters &&
            !value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
    }

    private static func validTimestamp(_ value: String) -> Bool {
        guard value.utf8.prefix(maximumTimestampBytes + 1).count <= maximumTimestampBytes else {
            return false
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) else { return false }
        return date >= .distantPast && date <= .distantFuture
    }
}

enum GarminCloudError: LocalizedError {
    case invalidPlan
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPlan: return "Add at least one valid exercise set before syncing."
        case .invalidResponse: return "Garmin cloud sync returned an invalid response."
        case .requestFailed(let value): return value
        }
    }
}

@MainActor
final class GarminCloudService: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var lastMessage: String?

    private let auth: AuthService
    private let urlSession: URLSession

    init(auth: AuthService, urlSession: URLSession = .shared) {
        self.auth = auth
        self.urlSession = urlSession
    }

    func createDevice(displayName: String = "Garmin watch") async throws -> GarminDevice {
        isWorking = true
        defer { isWorking = false }
        let session = try await auth.validCloudSession()
        let object = try await requestObject(
            path: "/functions/v1/garmin-sync",
            method: "POST",
            token: session.accessToken,
            body: ["action": "createDevice", "displayName": displayName]
        )
        guard let device = object["device"] as? [String: Any],
              let id = device["id"] as? String,
              let token = device["device_token"] as? String else {
            throw GarminCloudError.invalidResponse
        }
        let value = GarminDevice(
            id: id,
            deviceToken: token,
            displayName: device["display_name"] as? String ?? displayName,
            createdAt: device["created_at"] as? String
        )
        lastMessage = "Device token created. Paste it into Garmin Connect IQ settings."
        return value
    }

    func submit(plan: GarminWorkoutPlan) async throws {
        let planData = try GarminPlanValidator.validate(plan)
        isWorking = true
        defer { isWorking = false }
        let session = try await auth.validCloudSession()
        guard let planObject = try JSONSerialization.jsonObject(with: planData) as? [String: Any] else {
            throw GarminCloudError.invalidPlan
        }
        _ = try await requestObject(
            path: "/rest/v1/garmin_plans",
            method: "POST",
            token: session.accessToken,
            prefer: "return=minimal",
            body: [["user_id": session.userID, "status": "pending", "plan": planObject]]
        )
        lastMessage = "Plan queued. Open GymApp on the Garmin watch and choose CLOUD / SYNC."
    }

    private func requestObject(
        path: String,
        method: String,
        token: String,
        prefer: String? = nil,
        body: Any
    ) async throws -> [String: Any] {
        guard let url = URL(string: path, relativeTo: GymAppConfiguration.supabaseURL) else {
            throw GarminCloudError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue(GymAppConfiguration.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GarminCloudError.invalidResponse }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            throw GarminCloudError.requestFailed(
                object["error"] as? String ?? "Garmin cloud sync failed (HTTP \(http.statusCode))."
            )
        }
        return object
    }
}
