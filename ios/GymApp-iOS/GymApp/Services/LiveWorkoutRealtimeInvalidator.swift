import Foundation
import Realtime

/// Private Supabase Broadcast is a low-latency invalidation path only. Every event is
/// parsed strictly and then followed by the authenticated gateway snapshot; Broadcast
/// content is never applied directly to a local workout or its durable operation queue.
@MainActor
final class LiveWorkoutRealtimeInvalidator {
    private weak var coordinator: LiveWorkoutCoordinator?
    private weak var auth: AuthService?
    private let expectedUserID: String

    private var task: Task<Void, Never>?
    private var client: RealtimeClientV2?
    private var channel: RealtimeChannelV2?

    init(
        auth: AuthService,
        expectedUserID: String,
        coordinator: LiveWorkoutCoordinator
    ) {
        self.auth = auth
        self.expectedUserID = expectedUserID
        self.coordinator = coordinator
    }

    func start() {
        guard task == nil, !expectedUserID.isEmpty else { return }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.connectAndListen()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        coordinator?.setRealtimeConnectionState(false)
        if let channel, let client {
            Task { await client.removeChannel(channel) }
        } else {
            client?.disconnect()
        }
        channel = nil
        client = nil
    }

    private func connectAndListen() async {
        guard let auth, let coordinator else { return }
        do {
            let cloud = try await auth.validCloudSession(expectedUserID: expectedUserID)
            guard cloud.userID == expectedUserID,
                  auth.session?.cloud?.userID == expectedUserID else {
                throw AuthServiceError.sessionChanged
            }
            let realtimeURL = GymAppConfiguration.supabaseURL
                .appendingPathComponent("realtime/v1", isDirectory: false)
            let realtime = RealtimeClientV2(
                url: realtimeURL,
                options: RealtimeClientOptions(
                    headers: ["apikey": GymAppConfiguration.supabasePublishableKey],
                    reconnectDelay: 5,
                    timeoutInterval: 12,
                    disconnectOnSessionLoss: true,
                    maxRetryAttempts: 3,
                    disconnectOnEmptyChannelsAfter: 0,
                    accessToken: { [weak auth] in
                        guard let auth else { return nil }
                        return try await auth.validCloudSession(
                            expectedUserID: self.expectedUserID
                        ).accessToken
                    }
                )
            )
            await realtime.setAuth(cloud.accessToken)
            let privateChannel = realtime.channel("gymapp:user:\(expectedUserID)") { config in
                config.isPrivate = true
            }
            let events = privateChannel.broadcastStream(event: "gymapp_live_changed")
            let socialEvents = privateChannel.broadcastStream(event: "gymapp_social_changed")
            client = realtime
            channel = privateChannel
            try await privateChannel.subscribeWithError()
            guard !Task.isCancelled,
                  auth.session?.cloud?.userID == expectedUserID else {
                throw AuthServiceError.sessionChanged
            }
            coordinator.setRealtimeConnectionState(true)

            let socialTask = Task { @MainActor [weak auth, weak coordinator] in
                for await payload in socialEvents {
                    guard !Task.isCancelled,
                          auth?.session?.cloud?.userID == self.expectedUserID else { break }
                    let value = payload.mapValues(\.value)
                    guard (try? SocialPayloadParser.realtimeHint(from: value)) != nil else {
                        continue
                    }
                    NotificationCenter.default.post(
                        name: .gymAppSocialChanged,
                        object: self.expectedUserID
                    )
                    await coordinator?.receiveSocialInvalidation()
                }
            }

            for await payload in events {
                guard !Task.isCancelled,
                      auth.session?.cloud?.userID == expectedUserID else { break }
                let value = payload.mapValues(\.value)
                await coordinator.receiveRealtimeInvalidation(value)
            }
            socialTask.cancel()
        } catch is CancellationError {
            // Normal shutdown.
        } catch {
            // Polling remains active and authoritative while Broadcast reconnects.
        }
        coordinator.setRealtimeConnectionState(false)
        if let channel, let client {
            await client.removeChannel(channel)
        } else {
            client?.disconnect()
        }
        channel = nil
        client = nil
    }
}

extension Notification.Name {
    static let gymAppSocialChanged = Notification.Name("GymAppSocialChanged")
}
