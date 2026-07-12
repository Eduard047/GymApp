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
        guard !plan.exercises.isEmpty,
              plan.exercises.contains(where: { !$0.sets.isEmpty }) else {
            throw GarminCloudError.invalidPlan
        }
        isWorking = true
        defer { isWorking = false }
        let session = try await auth.validCloudSession()
        let planData = try JSONEncoder().encode(plan)
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
