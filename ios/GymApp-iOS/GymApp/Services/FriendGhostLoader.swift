import Foundation

/// Loads friends' latest results once when a workout starts. Only friends whose
/// workout-detail sharing is on (checked with a fresh capability request) are
/// read; every failure simply leaves that friend out. Account-bound through the
/// `AppState` social calls, which reject results that arrive after an account change.
@MainActor
enum FriendGhostLoader {
    static let maximumFriends = 10

    struct Key: Equatable {
        let draftID: UUID?
        let accountStorageKey: String
        let friendProfileIDs: [String]
    }

    static func friendsToQuery(_ friends: [SocialFriendSummary]) -> [SocialFriendSummary] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        func updatedAt(_ friend: SocialFriendSummary) -> Date {
            guard let raw = friend.progressUpdatedAt else { return .distantPast }
            return formatter.date(from: raw) ?? fallback.date(from: raw) ?? .distantPast
        }
        return Array(
            friends.enumerated()
                .sorted { left, right in
                    let leftDate = updatedAt(left.element)
                    let rightDate = updatedAt(right.element)
                    return leftDate == rightDate ? left.offset < right.offset : leftDate > rightDate
                }
                .map(\.element)
                .prefix(maximumFriends)
        )
    }

    static func load(friends: [SocialFriendSummary], appState: AppState) async -> [String: FriendGhost] {
        var pages: [SocialFriendWorkoutPage] = []
        for friend in friendsToQuery(friends) {
            guard !Task.isCancelled else { return [:] }
            do {
                let capability = try await appState.socialFriendWorkoutDetailCapability(profileID: friend.profileID)
                guard capability.available else { continue }
                if let page = try await appState.socialFriendWorkoutPage(profileID: friend.profileID) {
                    pages.append(page)
                }
            } catch AuthServiceError.sessionChanged {
                return [:]
            } catch {
                continue
            }
        }
        guard !Task.isCancelled else { return [:] }
        return FriendGhosts.ghosts(from: pages)
    }
}
