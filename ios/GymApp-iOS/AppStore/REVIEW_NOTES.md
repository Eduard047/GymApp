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

The demo account contains three fictional exercises and two fictional workouts so Review can inspect charts, missions, ranks, Smart Coach, profile, and protected progress without creating personal data. Its production login and cloud profile/state were verified on 2026-07-11. Verify the same credentials and the pending owner-only backend migration from a clean physical device immediately before submission.

## App overview and navigation

GymApp is an English/Ukrainian/Russian workout planner and strength-training log. Its five primary tabs are:

1. **Workouts** — monthly overview/history, heatmap, muscle map, recommendations, and create/edit workout sessions.
2. **Missions** — daily, weekly, and monthly training goals, with earned achievement badges at the bottom.
3. **Exercises** — exercise library, muscle mappings, favorites, and favorite-only filtering.
4. **Progress** — exercise/muscle summaries and strength/volume charts.
5. **Profile** — account/privacy/deletion, backup and diagnostics tools, and owner-only protected progress. Competitive cross-account standings are intentionally paused until scoring has a trusted server-side source.

To create a session, open Workouts and tap the add button. A reviewer can use templates, repeat/copy a prior workout, add exercises/sets, finish the workout, and view its summary. Smart Coach recommendations are derived from the demo account's training history.

## Authentication and backend

- GymApp uses first-party email/password authentication with Supabase. It has no Google/Facebook/social login and therefore no Guideline 4.8 alternative-login requirement.
- Email confirmation and recovery use a same-device PKCE exchange. The app rejects implicit raw-token callbacks and unsolicited/expired callback state.
- Production backend: active; migration state and access controls were reverified on 2026-07-21.
- Supabase Auth allowlists `com.setforge.gymapp.ios://auth/callback/*`; the final signed build still requires same-device confirmation/recovery testing on a physical iPhone before submission.
- Production history is verified through `20260721143853_retire_legacy_garmin_table_grants.sql`. All eight previously missing canonical migrations were applied in deployment order on 2026-07-21; structural/ACL, owner-isolation, and rollback-only pre-auth limiter checks passed. A valid-device Garmin fetch/ack smoke remains required before App Store submission.
- Production `garmin-sync` version 4 is active. OPTIONS, malformed input, unknown action, and random format-valid fetch/ack denial were verified over HTTP on 2026-07-21 without using a real capability; the valid-device smoke remains open.
- Required reviewer hardware/sample QR/feature flags: **None**
- Garmin sync is optional and is not required for App Review. All core workout, progress, mission, rank, backup, and owner-only protected-progress paths work without Garmin hardware.

## Account deletion

Path: **Profile → Account, privacy & deletion → Delete Account**. The app shows an irreversible-deletion confirmation and calls the authenticated `delete-account` Edge Function. The server derives the user UUID from the verified bearer token and does not accept an arbitrary user ID.

- Production function deployed and tested: `delete-account` version 1, `ACTIVE`, `verify_jwt=true`, verified 2026-07-11.
- Disposable account deletion test date/result: on 2026-07-11, two disposable users were deleted through the live function after positive and negative contract tests. SQL verification found zero remaining Auth users/identities, profiles, cloud states, Garmin devices/plans, and moderation reports for those users.

Deletion removes the Supabase Auth user and cascades `user_states`, `profiles`, `garmin_devices`, `garmin_plans`, and related moderation reports; the app then clears the local account database, Keychain session, and account preferences. Recheck this flow with the final signed physical-device build immediately before submission.

## Privacy and permissions

- No advertising, analytics, IDFA, cross-app/site tracking, fingerprinting, or ATT prompt.
- No camera, microphone, location, Contacts, Photos, Motion & Fitness, or HealthKit access.
- Rest-timer alerts use only local notifications. Notification authorization is requested contextually when the reviewer chooses an alert; declining it does not block workout logging or any paid/content feature.
- `PrivacyInfo.xcprivacy` declares no tracking, the actual server-collected data categories, and required-reason API `UserDefaults` with approved first-party reason `CA92.1`.
- Account/cloud data includes email, Supabase UUID, display name, workout logs, notes, derived XP/level/workout count, and optional Garmin token/plans/import metrics. The protected-progress projection returns the random profile ID, display name, XP, level, and workout count only to that signed-in owner; it does not return another user’s row or Auth UUID.

## Business model and content

- The app is free and contains no In-App Purchases, subscriptions, paid digital unlocks, external purchase links, or advertising.
- There is no public posting, chat, social feed, or active cross-account leaderboard. Display names and progress are owner-only while verified scoring is being designed. The private moderation queue remains only for reports submitted before this restriction and continues to follow [MODERATION_RUNBOOK.md](MODERATION_RUNBOOK.md).
- GymApp is not a medical device and makes no diagnostic or treatment claims.

## Export/import

The JSON/PDF tools under **Profile → Backup & diagnostics** intentionally invoke the iOS share sheet. Files are created only after the reviewer selects Export/Share. Auth tokens and private Keychain credentials are not included in exported workout backups.

## Review readiness gate

- [ ] All placeholders above replaced.
- [ ] Demo credentials confirmed from a clean device and remain active.
- [x] Production backend migration state and access controls reverified on 2026-07-21; the delete function was verified live on 2026-07-11. Monitor both throughout review.
- [x] Deployed `20260721143038_restrict_leaderboard_to_owner_until_verified_ingestion.sql`; owner-only access and anonymous denial passed structural and runtime checks. Operational moderation monitoring must remain active for legacy reports.
- [ ] `20260721143058_add_bounded_garmin_preauth_rate_limits.sql` is deployed and its random-token limiter passed a rollback-only runtime check. Verify a real valid watch still completes fetch/ack before submission.
- [ ] Publish the refreshed combined privacy policy/support source and shared assets to the separate `gh-pages` branch, then verify both live without login. The pre-redesign pages were last verified live on 2026-07-20; this source-only update intentionally did not deploy them.
- [x] Non-obvious functionality and the optional Garmin limitation are described above.
- [ ] No test, debug, staging, or hidden feature remains in the submitted build.

Official submission guidance: [App Review Guidelines — Before You Submit](https://developer.apple.com/app-store/review/guidelines/#before-you-submit) and [App Review information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).
