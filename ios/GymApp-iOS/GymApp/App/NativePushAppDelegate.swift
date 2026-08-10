import UIKit
import UserNotifications

@MainActor
final class NativePushAppDelegate: NSObject, UIApplicationDelegate,
    @preconcurrency UNUserNotificationCenterDelegate {
    static weak var manager: NativePushManager?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Apple requires the notification-center delegate before launch completes.
        // Remote APNs content is never presented here; only locally rebuilt,
        // account-bound GymApp notifications are eligible for a banner.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Self.manager?.didReceiveDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Self.manager?.didFailToRegisterForRemoteNotifications()
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let manager = Self.manager else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            let outcome = await manager.handleRemoteNotification(userInfo)
            completionHandler(outcome.backgroundFetchResult)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let identifier = notification.request.identifier
        guard identifier.hasPrefix(NativePushSystemController.notificationIdentifierPrefix),
              notification.request.content.categoryIdentifier ==
                NativePushSystemController.categoryIdentifier,
              notification.request.trigger is UNTimeIntervalNotificationTrigger else {
            // In particular, suppress any provider-rendered remote alert while the app
            // is foregrounded. Background safety still requires a data-only APNs payload.
            completionHandler([])
            return
        }
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Self.manager?.handleLocalNotificationTap(
            identifier: response.notification.request.identifier,
            userInfo: response.notification.request.content.userInfo
        )
        completionHandler()
    }
}
