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

The demo account contains three fictional exercises and two fictional workouts so Review can inspect charts, missions, ranks, Smart Coach, profile, and its own synchronized progress without creating personal data. Friend requests require a second confirmed account by design; if this feature is part of the submitted review path, provide a second fictional credential in the private App Review fields and verify the mutual-friend/invitation flow from clean physical devices immediately before submission.

## App overview and navigation

GymApp is an English/Ukrainian/Russian workout planner and strength-training log. Its five primary tabs are:

1. **Workouts** — monthly overview/history, heatmap, muscle map, recommendations, and create/edit workout sessions.
2. **Missions** — daily, weekly, and monthly training goals, with earned achievement badges at the bottom.
3. **Exercises** — exercise library, muscle mappings, favorites, and favorite-only filtering.
4. **Progress** — exercise/muscle summaries and strength/volume charts.
5. **Profile** — account/privacy/deletion, backup and diagnostics tools, mutual friend requests, per-category friend visibility, friends-only self-reported progress, recent shared summaries/records, and workout invitations. The former global leaderboard is removed because device-entered history is not verified competition.

To create a session, open Workouts and tap the add button. A reviewer can use templates, repeat/copy a prior workout, add exercises/sets, finish the workout, and view its summary. Smart Coach recommendations are derived from the demo account's training history.

## Authentication and backend

- GymApp uses first-party email/password authentication with Supabase. It has no Google/Facebook/social login and therefore no Guideline 4.8 alternative-login requirement.
- Email confirmation and recovery use a same-device PKCE exchange. The app rejects implicit raw-token callbacks and unsolicited/expired callback state.
- Production backend: active. On 2026-08-09 the three friends migrations were deployed; their RLS/grants, revision-bound projections, revoked-session denial, and a rolled-back three-user friend/workout-invitation flow were verified on production. Repeat the final Auth, Garmin, deletion, and physical-device checks immediately before submission.
- Supabase Auth allowlists `com.setforge.gymapp.ios://auth/callback/*`; the final signed build still requires same-device confirmation/recovery testing on a physical iPhone before submission.
- Production migration history must match the repository through the three `20260809202407`–`20260809202432` social migrations; every non-quarantined cloud state must have revision-bound progression and bounded social-activity projections.
- Production `garmin-sync` version 6 is active. OPTIONS, malformed/unknown capability denial, valid-device fetch/ack/replay, token rotation, and post-cutover v2 continuity were verified over HTTP on 2026-07-22.
- Required reviewer hardware/sample QR/feature flags: **None**
- Garmin sync is optional and is not required for App Review. All core workout, progress, mission, rank, backup, friend, and workout-invitation paths work without Garmin hardware.

## Account deletion

Path: **Profile → Account, privacy & deletion → Delete Account**. The app shows an irreversible-deletion confirmation and calls the authenticated `delete-account` Edge Function. The server derives the user UUID from the verified bearer token and does not accept an arbitrary user ID.

- Production version 3 is `ACTIVE` with `verify_jwt=true` and matches repository
  contract v2. The live-session RPC rejects revoked/terminal sessions.
- Historical deletion result: on 2026-07-22, a disposable user with a profile, cloud state/projection, Garmin device, and two plans was deleted through the live function after positive and negative contract tests. Re-run deletion after the friends migration with synthetic friendships, blocks, privacy settings, projections, and workout invitations, then verify zero rows across every new social table before submission.

Deletion removes the Supabase Auth user and cascades `user_states`, `profiles`, private social settings/friendships/blocks/projections/invitations, `garmin_devices`, `garmin_plans`, and related moderation reports; the app then clears the local account database, Keychain session, account preferences, and in-memory friend caches. Recheck this flow with the final signed physical-device build immediately before submission.

## Privacy and permissions

- No advertising, analytics, IDFA, cross-app/site tracking, fingerprinting, or ATT prompt.
- No camera, microphone, location, Contacts, Photos, Motion & Fitness, or HealthKit access.
- Rest-timer alerts use only local notifications. Notification authorization is requested contextually when the reviewer chooses an alert; declining it does not block workout logging or any paid/content feature.
- `PrivacyInfo.xcprivacy` declares no tracking, the actual server-collected data categories, and required-reason API `UserDefaults` with approved first-party reason `CA92.1`.
- Account/cloud data includes email, Supabase UUID, display name, workout logs, notes, derived XP/level/workout count, friend/request/block/privacy/invitation state, and optional Garmin token/plans/import metrics. Friend RPCs use a random UUID-free profile code and return only mutually authorized, enabled categories: XP/level/workout count, up to five date-only summaries, and up to 100 entered exercise bests. They never return email, Auth UUID, raw cloud state, notes, full set history, Garmin token, or health metrics.
- Direct workout invitations contain only bounded exercise names/identities and planned weight/repetition sets. An unanswered invitation expires after seven days. Acceptance opens a separate editable draft; it does not join or live-synchronize either person’s active workout.

## Business model and content

- The app is free and contains no In-App Purchases, subscriptions, paid digital unlocks, external purchase links, or advertising.
- There is no public posting, chat, social feed, or global leaderboard. Social visibility is limited to mutually confirmed, unblocked friends and each owner’s explicit category toggles; progress is clearly identified as synchronized/self-reported rather than verified competition. Removing or blocking immediately revokes friend detail and closes pending invitations. The private moderation queue remains only for legacy leaderboard reports and continues to follow [MODERATION_RUNBOOK.md](MODERATION_RUNBOOK.md).
- GymApp is not a medical device and makes no diagnostic or treatment claims.

## Export/import

The JSON/PDF tools under **Profile → Backup & diagnostics** intentionally invoke the iOS share sheet. Files are created only after the reviewer selects Export/Share. Auth tokens and private Keychain credentials are not included in exported workout backups.

## Review readiness gate

- [ ] All placeholders above replaced.
- [ ] Demo credentials confirmed from a clean device and remain active.
- [x] Production backend migration state, access controls, Garmin path, Auth lifecycle, and delete function reverified live on 2026-07-22. Monitor them throughout review.
- [x] Deployment of `20260809202407`–`20260809202432` verified on production. Metadata checks confirmed private RLS/no direct grants, authenticated-only RPCs, 59/59 current social projections, zero quarantine/stale projections, revoked-session denial, wrong-member denial, and a rolled-back friend request/accept → workout invite/accept → remove/revoke flow with zero residual synthetic users. The legacy owner-only leaderboard RPC remains only for released-client compatibility.
- [ ] Before App Store submission, repeat malformed/oversized, replay, stale-revision, block/privacy, account-deletion cascade, and two-device invitation recovery tests with disposable signed-in accounts and the final physical-device build.
- [x] The Garmin limiter/capability migrations are deployed and a disposable valid device completed fetch/ack/replay plus the v2 gateway cutover on 2026-07-22.
- [ ] Publish the refreshed combined privacy policy/support source and shared assets to the separate `gh-pages` branch, then verify both live without login. The pre-redesign pages were last verified live on 2026-07-20; this source-only update intentionally did not deploy them.
- [x] Non-obvious functionality and the optional Garmin limitation are described above.
- [ ] No test, debug, staging, or hidden feature remains in the submitted build.

Official submission guidance: [App Review Guidelines — Before You Submit](https://developer.apple.com/app-store/review/guidelines/#before-you-submit) and [App Review information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).
