# GymApp — App Privacy answers

Use this as the source of truth for App Store Connect **App Privacy**. It reflects source changes through 2026-08-10 and must be re-audited against the final signed archive, deployed backend, and configured notification providers before submission.

Apple references: [App privacy details](https://developer.apple.com/app-store/app-privacy-details/), [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/), [privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), and [User Privacy and Data Use](https://developer.apple.com/app-store/user-privacy-and-data-use/).

## Top-level answers

- **Does this app or its third-party partners collect data from this app?** Yes.
- **Is any data used to track users?** No.
- **Does the app use IDFA or AppTrackingTransparency?** No.
- **Advertising / marketing purposes?** No.
- **Analytics purposes?** No.
- **Third-party advertising?** No.

In Apple's terminology, data is “collected” when it is transmitted off the device and retained beyond what is necessary to service the immediate request. Local-only Training Profile preferences and notification scheduling are therefore not listed as collected data.

## Data types to declare

| App Store Connect category | What GymApp sends or stores | Linked to user | Tracking | Purpose(s) |
|---|---|---:|---:|---|
| Contact Info → **Name** | Account display name stored with the protected profile and shown to confirmed friends, request recipients, and workout-invite recipients | Yes | No | App Functionality |
| Contact Info → **Email Address** | Supabase email/password account creation, confirmation, login, and session refresh | Yes | No | App Functionality |
| Health & Fitness → **Health** | Optional Garmin-import notes can contain heart-rate metrics | Yes | No | App Functionality; Product Personalization |
| Health & Fitness → **Fitness** | Workout dates, exercise names, sets, weights, repetitions, workout plans, duration, calories, progress, derived XP/level/workout count, bounded friend-visible summaries/records, direct workout invitations, and accepted two-person live-workout plans/progress | Yes | No | App Functionality; Product Personalization |
| User Content → **Other User Content** | Free-form workout notes; friend requests, privacy/block choices, workout-invite/live-room lifecycle; and any legacy fixed-category leaderboard report retained for moderation | Yes | No | App Functionality |
| Identifiers → **User ID** | Supabase account UUID and random UUID-free friend/profile code | Yes | No | App Functionality |
| Identifiers → **Device ID** | Opaque Garmin device token when Garmin sync is connected; and, when optional system alerts are enabled, a random installation ID plus the APNs/FCM token or Web Push endpoint and subscription keys needed for delivery | Yes | No | App Functionality |

“Product Personalization” applies because stored workout/health history is used to tailor Smart Coach recommendations, progress, muscle-load views, missions, and related in-app guidance for that user. It is not advertising personalization.

## Data not collected by this release

- phone number or physical address;
- payment, credit, purchase history, or other financial information;
- precise or coarse location;
- sensitive demographic data;
- Contacts, emails/text messages, photos/videos, or audio;
- browsing history or search history;
- advertising data;
- generic tap/click analytics or other cross-app usage analytics;
- crash, performance, or diagnostic telemetry;
- camera, microphone, HealthKit, Motion & Fitness, or advertising identifier data.

Training Profile — split, 2–6 training days per week, goal, and energy balance — and any legacy list of leaderboard profiles blocked on this device stay in first-party app preferences. Friend dashboards and friend details are held only in memory by the clients and cleared on account change; the authoritative request, friendship, block, privacy, invitation, and live-room state is protected in Supabase. The app does not ask for body weight, height, sex, location, contacts, camera, microphone, or HealthKit access. Rest-timer alerts remain local. A remote notification delivery address is registered only after the user enables optional system alerts and grants the platform/browser notification permission.

## Visibility and processors

- The global cross-account leaderboard is removed because synchronized workout history is client-authored and is not trustworthy as competitive scoring. A signed-in user may instead add another account by its random friend code. Only mutually confirmed, unblocked friends can see fields the account owner has enabled: XP/level/workout count, up to five date-only recent-workout summaries, and up to 100 per-exercise entered bests. The UI labels this as self-reported/synchronized data, not verified athletic performance.
- A standard direct friend workout invitation contains only exercise identity/name and bounded planned weight/repetition sets, expires after seven days if unanswered, and imports as an editable independent local draft after acceptance. It does not synchronize later set changes.
- A separate two-person live workout is available only to one mutually confirmed, unblocked friend who accepts the invitation. The room shares the frozen plan and, while it is open, each participant's committed set completion, entered weight, and repetitions with the other participant through Supabase Realtime. The live room never includes workout notes, email addresses, Supabase Auth UUIDs, Garmin/health data, or credentials. Removing or blocking the friend closes the room and revokes access.
- Optional system notifications cover bounded lifecycle events such as a friend request, workout invitation, friend joining, live start, participant finish, or room close. Per-set live progress is Realtime-only and is never sent as push. APNs, FCM, or the browser's Web Push service receives the installation delivery token/endpoint and a static localized message with only a minimal opaque event kind, room/object ID, and revision—never a profile/workout name, exercise, weight, repetitions, notes, email, or Auth UUID. Availability depends on platform support, deployed provider configuration, and notification permission.
- Legacy leaderboard moderation reports remain private; the clients no longer submit new cross-account leaderboard reports.
- Supabase is the hosting/authentication processor for account, cloud-state, profile, and Garmin cloud records. Data remains linked by the Supabase UUID.
- Depending on platform and only when system alerts are enabled, Apple Push Notification service, Firebase Cloud Messaging, or the browser's push service processes the account-bound delivery address and minimal notification payload described above.
- Garmin data is processed only when the user chooses the Garmin sync feature. The opaque device token is used only to pair and deliver/retrieve workout plans.
- No data is sold, shared with data brokers, used for targeted ads, or combined with other companies' app/site data.

## Retention and deletion

- Active account/cloud data is retained while the account is active so sync, protected progress, recommendations, friends, workout invitations, live workouts, notifications, and Garmin sync work. Standard unanswered workout invitations expire after seven days. Their exercise/plan payload becomes eligible for tombstoning 24 hours after decline/cancellation/expiry or 30 days after acceptance; bounded cleanup runs when either participant next refreshes Friends or the workout-invitation inbox, so a fully dormant row may retain its payload until that cleanup or account deletion. The standard-invitation ID/status/revision/idempotency tombstone and other friend/request/block/privacy lifecycle rows remain account data until removed by product lifecycle rules or account deletion.
- A waiting/ready live room expires seven days after creation, and an active room expires 24 hours after the owner starts it. Scheduled bounded cleanup runs every five minutes: the frozen plan, summary, and per-participant progress become eligible for purge 24 hours after a room is cancelled or expires, or 30 days after completion; the terminal room and its dependent rows become eligible for deletion 31 days after it ends. A backlog can delay a bounded cleanup pass beyond the eligibility threshold.
- A notification address remains active while alerts are enabled and the signed-in client refreshes it. An authenticated revoke scrubs the raw token/endpoint and Web Push keys immediately. An active installation not refreshed for 180 days is scrubbed by bounded dispatcher cleanup; a scrubbed installation tombstone is eligible for deletion after 30 days once no delivery row refers to it. Completed/dead/expired notification intents and their delivery rows are eligible for deletion 30 days after completion. Pending live lifecycle alerts expire after one day, except a live invitation which may remain pending only until its seven-day room invitation deadline; no pending delivery window exceeds seven days.
- In-app deletion hard-deletes the authenticated Supabase Auth user. Production schema rows in `user_states`, `profiles`, the private social graph/projections/invitations/live rooms/notification installations and outbox, `garmin_devices`, and `garmin_plans` reference the account with cascading lifecycle cleanup; related moderation reports also cascade through the reporter/target relationships.
- Production deletion was tested end-to-end with two disposable users on 2026-07-11. SQL verification found no remaining Auth identity, profile, state, Garmin, or report rows, and production Storage contained zero objects. Repeat this audit if uploads or another processor are added; Supabase warns that an Auth user owning Storage objects cannot be deleted.
- After success, the app must erase the local session/Keychain, account database, and account-specific preferences.
- Operational backups/security records may persist only for the processor's limited backup cycle or where law requires retention; they must not remain available as an active user account.

## Cross-checks before submission

- [x] Built-app `PrivacyInfo.xcprivacy` declares the same seven collected categories and `NSPrivacyTracking = false`.
- [x] Final source/dependency audit found no analytics, tracking, crash reporting, advertising, or another collected data type.
- [x] Production cascade behavior and zero orphan account data were verified with two disposable accounts on 2026-07-11.
- [ ] Publish the updated combined privacy policy describing mutual friends, live-room data, notification providers/permission, and exact retention, then verify the live/local SHA-256 before submission.
- [x] Change-control rule recorded: if any field or SDK changes, update the privacy manifest, this file, App Store Connect answers, and privacy policy before uploading the build.
