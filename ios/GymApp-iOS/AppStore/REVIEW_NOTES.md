# GymApp — App Review Notes draft

Paste the reviewed content below into App Store Connect. Replace every `REPLACE_WITH_…` value and remove this instruction before submission.

## Review contact

- First name: `Eduard`
- Last name: `Martynenko`
- Email: enter the private App Review contact address in App Store Connect
- Phone, including country code: `REPLACE_WITH_REVIEW_PHONE`

## Demo account

- Email: copy from `REVIEW_CREDENTIALS.private.md` immediately before submission
- Password: paste the value from the private local `REVIEW_CREDENTIALS.private.md` file into App Store Connect immediately before submission.
- Email-confirmed: **Yes**
- OTP/2FA instructions or bypass: **Not applicable; email/password login has no OTP or 2FA.**
- Account expiry: **non-expiring**
- Required region/VPN: **None**

The demo account contains three fictional exercises and two fictional workouts so Review can inspect charts, missions, ranks, Smart Coach, profile, and leaderboard without creating personal data. Its production login, cloud profile/state, and current-user leaderboard row were verified on 2026-07-11. Verify the same credentials from a clean physical device immediately before submission.

## App overview and navigation

GymApp is an English/Ukrainian/Russian workout planner and strength-training log. Its five primary tabs are:

1. **Workouts** — monthly overview/history, heatmap, muscle map, recommendations, achievements, create and edit workout sessions.
2. **Missions** — daily, weekly, and monthly training goals.
3. **Exercises** — exercise library, muscle mappings, account tools, JSON import/export, and PDF sharing.
4. **Progress** — exercise/muscle summaries and strength/volume charts.
5. **Rating** — public leaderboard showing display name, XP, level, and workout count.

To create a session, open Workouts and tap the add button. A reviewer can use templates, repeat/copy a prior workout, add exercises/sets, finish the workout, and view its summary. Smart Coach recommendations are derived from the demo account's training history.

## Authentication and backend

- GymApp uses first-party email/password authentication with Supabase. It has no Google/Facebook/social login and therefore no Guideline 4.8 alternative-login requirement.
- Email confirmation and recovery use a same-device PKCE exchange. The app rejects implicit raw-token callbacks and unsolicited/expired callback state.
- Production backend: active and production-verified on 2026-07-11.
- Supabase Auth allowlists `com.setforge.gymapp.ios://auth/callback/*`; the final signed build still requires same-device confirmation/recovery testing on a physical iPhone before submission.
- Leaderboard/privacy migrations `202607100001`, `202607100002`, and revision fix `202607110003` are deployed. Production migration history records `20260711084556`, `20260711084559`, and `20260711090358`; the two-user authenticated RLS/report/revision suite passed.
- Required reviewer hardware/sample QR/feature flags: **None**
- Garmin sync is optional and is not required for App Review. All core workout, progress, mission, rank, backup, and leaderboard paths work without Garmin hardware.

## Account deletion

Path: **Exercises → Account → Delete Account**. The app shows an irreversible-deletion confirmation and calls the authenticated `delete-account` Edge Function. The server derives the user UUID from the verified bearer token and does not accept an arbitrary user ID.

- Production function deployed and tested: `delete-account` version 1, `ACTIVE`, `verify_jwt=true`, verified 2026-07-11.
- Disposable account deletion test date/result: on 2026-07-11, two disposable users were deleted through the live function after positive and negative contract tests. SQL verification found zero remaining Auth users/identities, profiles, cloud states, Garmin devices/plans, and moderation reports for those users.

Deletion removes the Supabase Auth user and cascades `user_states`, `profiles`, `garmin_devices`, `garmin_plans`, and related moderation reports; the app then clears the local account database, Keychain session, and account preferences. Recheck this flow with the final signed physical-device build immediately before submission.

## Privacy and permissions

- No advertising, analytics, IDFA, cross-app/site tracking, fingerprinting, or ATT prompt.
- No camera, microphone, location, Contacts, Photos, Motion & Fitness, or HealthKit access.
- Rest-timer alerts use only local notifications. Notification authorization is requested contextually when the reviewer chooses an alert; declining it does not block workout logging or any paid/content feature.
- `PrivacyInfo.xcprivacy` declares no tracking, the actual server-collected data categories, and required-reason API `UserDefaults` with approved first-party reason `CA92.1`.
- Account/cloud data includes email, Supabase UUID, display name, workout logs, notes, derived XP/level/workout count, and optional Garmin token/plans/import metrics. The leaderboard exposes only a random public profile ID, display name, XP, level, and workout count; it never returns another user’s Auth UUID.

## Business model and content

- The app is free and contains no In-App Purchases, subscriptions, paid digital unlocks, external purchase links, or advertising.
- There is no public posting, chat, or social feed. The only public user-generated field is the restricted display name on the leaderboard. The production database applies a display-name safety filter; every other-user row has visible **Safety options** to report the name to the moderation queue or block that athlete locally. Reports contain the fixed `inappropriate_name` reason rather than free-form text. Martynenko Eduard owns the private queue and daily monitoring process, with the normally-within-24-hours target, action/escalation, feedback, and retention steps documented in [MODERATION_RUNBOOK.md](MODERATION_RUNBOOK.md) and summarized on the Support URL.
- GymApp is not a medical device and makes no diagnostic or treatment claims.

## Export/import

The JSON/PDF tools intentionally invoke the iOS share sheet. Files are created only after the reviewer selects Export/Share. Auth tokens and private Keychain credentials are not included in exported workout backups.

## Review readiness gate

- [ ] All placeholders above replaced.
- [ ] Demo credentials confirmed from a clean device and remain active.
- [x] Production backend and delete function verified live on 2026-07-11; monitor them throughout review.
- [x] All three migrations deployed in order; `leaderboard_public`, own-row-only direct profile RLS, display-name filtering, report insertion/RLS, stale revisions, deletion cascades, and cleanup tested with two disposable accounts. Operational moderation monitoring must remain active throughout review.
- [x] Reviewed combined privacy policy and support page are live and reachable without login; both were verified on 2026-07-11.
- [x] Non-obvious functionality and the optional Garmin limitation are described above.
- [ ] No test, debug, staging, or hidden feature remains in the submitted build.

Official submission guidance: [App Review Guidelines — Before You Submit](https://developer.apple.com/app-store/review/guidelines/#before-you-submit) and [App Review information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).
