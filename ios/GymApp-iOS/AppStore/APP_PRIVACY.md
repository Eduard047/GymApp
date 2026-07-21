# GymApp — App Privacy answers

Use this as the source of truth for App Store Connect **App Privacy**. It reflects source changes through 2026-07-21 and must be re-audited against the final signed archive and deployed backend before submission.

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
| Contact Info → **Name** | Account display name stored with the owner-only protected progress profile | Yes | No | App Functionality |
| Contact Info → **Email Address** | Supabase email/password account creation, confirmation, login, and session refresh | Yes | No | App Functionality |
| Health & Fitness → **Health** | Optional Garmin-import notes can contain heart-rate metrics | Yes | No | App Functionality; Product Personalization |
| Health & Fitness → **Fitness** | Workout dates, exercise names, sets, weights, repetitions, workout plans, duration, calories, progress, and derived XP/level/workout count | Yes | No | App Functionality; Product Personalization |
| User Content → **Other User Content** | Free-form workout notes and any legacy fixed-category leaderboard report retained for moderation | Yes | No | App Functionality |
| Identifiers → **User ID** | Supabase account UUID and UUID-free protected-progress profile ID | Yes | No | App Functionality |
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

Training Profile — split, 2–6 training days per week, goal, and energy balance — and any legacy list of leaderboard profiles blocked on this device stay in first-party app preferences. The app does not ask for body weight, height, sex, location, contacts, camera, microphone, or HealthKit access. The rest timer uses local notifications only; there is no remote push token collection.

## Visibility and processors

- Competitive cross-account standings are disabled because synchronized workout history is client-authored. The protected-progress projection returns only the signed-in owner’s random profile ID, display name, XP, level, and workout count. These fields, email, Supabase Auth UUID, workout details, notes, Garmin token, and heart-rate/calorie details are not shown to other users. Legacy moderation reports remain private; the clients no longer submit new cross-account reports while standings are disabled.
- Supabase is the hosting/authentication processor for account, cloud-state, profile, and Garmin cloud records. Data remains linked by the Supabase UUID.
- Garmin data is processed only when the user chooses the Garmin sync feature. The opaque device token is used only to pair and deliver/retrieve workout plans.
- No data is sold, shared with data brokers, used for targeted ads, or combined with other companies' app/site data.

## Retention and deletion

- Active account/cloud data is retained while the account is active so sync, protected progress, recommendations, and Garmin sync work. Legacy moderation reports remain only as long as needed to investigate abuse and are deleted when the reporter or reported profile is deleted.
- In-app deletion hard-deletes the authenticated Supabase Auth user. Production schema rows in `user_states`, `profiles`, `garmin_devices`, and `garmin_plans` reference `auth.users(id)` with `ON DELETE CASCADE`; related moderation reports also cascade through the reporter/target relationships.
- Production deletion was tested end-to-end with two disposable users on 2026-07-11. SQL verification found no remaining Auth identity, profile, state, Garmin, or report rows, and production Storage contained zero objects. Repeat this audit if uploads or another processor are added; Supabase warns that an Auth user owning Storage objects cannot be deleted.
- After success, the app must erase the local session/Keychain, account database, and account-specific preferences.
- Operational backups/security records may persist only for the processor's limited backup cycle or where law requires retention; they must not remain available as an active user account.

## Cross-checks before submission

- [x] Built-app `PrivacyInfo.xcprivacy` declares the same seven collected categories and `NSPrivacyTracking = false`.
- [x] Final source/dependency audit found no analytics, tracking, crash reporting, advertising, or another collected data type.
- [x] Production cascade behavior and zero orphan account data were verified with two disposable accounts on 2026-07-11.
- [ ] Publish the updated combined privacy policy describing owner-only protected progress, then verify the live/local SHA-256 before submission.
- [x] Change-control rule recorded: if any field or SDK changes, update the privacy manifest, this file, App Store Connect answers, and privacy policy before uploading the build.
