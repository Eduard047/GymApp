# GymApp — App Privacy answers

Use this as the source of truth for App Store Connect **App Privacy**. It reflects source changes through 2026-08-09 and must be re-audited against the final signed archive and deployed backend before submission.

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
| Health & Fitness → **Fitness** | Workout dates, exercise names, sets, weights, repetitions, workout plans, duration, calories, progress, derived XP/level/workout count, bounded friend-visible summaries/records, and direct workout invitations | Yes | No | App Functionality; Product Personalization |
| User Content → **Other User Content** | Free-form workout notes; friend requests, privacy/block choices, and workout-invite lifecycle; and any legacy fixed-category leaderboard report retained for moderation | Yes | No | App Functionality |
| Identifiers → **User ID** | Supabase account UUID and random UUID-free friend/profile code | Yes | No | App Functionality |
| Identifiers → **Device ID** | Opaque Garmin device token, only when the user connects Garmin sync | Yes | No | App Functionality |

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

Training Profile — split, 2–6 training days per week, goal, and energy balance — and any legacy list of leaderboard profiles blocked on this device stay in first-party app preferences. Friend dashboards and friend details are held only in memory by the clients and cleared on account change; the authoritative request, friendship, block, privacy, and invitation state is protected in Supabase. The app does not ask for body weight, height, sex, location, contacts, camera, microphone, or HealthKit access. The rest timer uses local notifications only; there is no remote push token collection.

## Visibility and processors

- The global cross-account leaderboard is removed because synchronized workout history is client-authored and is not trustworthy as competitive scoring. A signed-in user may instead add another account by its random friend code. Only mutually confirmed, unblocked friends can see fields the account owner has enabled: XP/level/workout count, up to five date-only recent-workout summaries, and up to 100 per-exercise entered bests. The UI labels this as self-reported/synchronized data, not verified athletic performance.
- Direct friend workout invitations contain only exercise identity/name and bounded planned weight/repetition sets, expire after seven days if unanswered, and import as an editable local draft after acceptance. They do not contain notes, dates, account identifiers, Garmin/health data, or live set updates. Email, Supabase Auth UUID, raw cloud state, full set history, workout notes, Garmin token, and heart-rate/calorie details are never returned through the friend API. Removing or blocking a friend immediately revokes friend-detail access and closes pending invitations.
- Legacy leaderboard moderation reports remain private; the clients no longer submit new cross-account leaderboard reports.
- Supabase is the hosting/authentication processor for account, cloud-state, profile, and Garmin cloud records. Data remains linked by the Supabase UUID.
- Garmin data is processed only when the user chooses the Garmin sync feature. The opaque device token is used only to pair and deliver/retrieve workout plans.
- No data is sold, shared with data brokers, used for targeted ads, or combined with other companies' app/site data.

## Retention and deletion

- Active account/cloud data is retained while the account is active so sync, protected progress, recommendations, friends, workout invitations, and Garmin sync work. Unanswered workout invitations expire after seven days. The exercise/plan payload becomes eligible for tombstoning 24 hours after decline/cancellation/expiry or 30 days after acceptance; bounded cleanup runs when either participant next refreshes Friends or the workout-invitation inbox, so a fully dormant row may retain its payload until that cleanup or account deletion. The ID/status/revision/idempotency tombstone and other friend/request/block/privacy lifecycle rows remain account data until removed by product lifecycle rules or account deletion. Legacy moderation reports remain only as long as needed to investigate abuse and are deleted when the reporter or reported profile is deleted.
- In-app deletion hard-deletes the authenticated Supabase Auth user. Production schema rows in `user_states`, `profiles`, the private social graph/projections/invitations, `garmin_devices`, and `garmin_plans` reference the account with `ON DELETE CASCADE`; related moderation reports also cascade through the reporter/target relationships.
- Production deletion was tested end-to-end with two disposable users on 2026-07-11. SQL verification found no remaining Auth identity, profile, state, Garmin, or report rows, and production Storage contained zero objects. Repeat this audit if uploads or another processor are added; Supabase warns that an Auth user owning Storage objects cannot be deleted.
- After success, the app must erase the local session/Keychain, account database, and account-specific preferences.
- Operational backups/security records may persist only for the processor's limited backup cycle or where law requires retention; they must not remain available as an active user account.

## Cross-checks before submission

- [x] Built-app `PrivacyInfo.xcprivacy` declares the same seven collected categories and `NSPrivacyTracking = false`.
- [x] Final source/dependency audit found no analytics, tracking, crash reporting, advertising, or another collected data type.
- [x] Production cascade behavior and zero orphan account data were verified with two disposable accounts on 2026-07-11.
- [ ] Publish the updated combined privacy policy describing mutual friends, visibility controls, and workout invitations, then verify the live/local SHA-256 before submission.
- [x] Change-control rule recorded: if any field or SDK changes, update the privacy manifest, this file, App Store Connect answers, and privacy policy before uploading the build.
