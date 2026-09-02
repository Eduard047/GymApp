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

The demo account contains three fictional exercises and two fictional workouts so Review can inspect charts, missions, ranks, Smart Coach, profile, and its own synchronized progress without creating personal data. Friend and two-person live-workout flows require a second confirmed account by design. Provide a second fictional credential in the private App Review fields, and verify mutual friendship, standard plan sharing, live-room reconnect/progress, and notification-permission states from clean physical devices immediately before submission.

## App overview and navigation

GymApp is an English/Ukrainian/Russian workout planner and strength-training log. Its five primary tabs are:

1. **Workouts** — monthly overview/history, heatmap, muscle map, recommendations, and create/edit workout sessions.
2. **Missions** — daily, weekly, and monthly training goals, with earned achievement badges at the bottom.
3. **Exercises** — exercise library, muscle mappings, favorites, and favorite-only filtering.
4. **Progress** — exercise/muscle summaries and strength/volume charts.
5. **Profile** — account/privacy/deletion, backup and diagnostics tools, mutual friend requests, per-category friend visibility, friends-only self-reported progress, recent shared summaries/records, standard workout-plan invitations, and two-person live-workout invitations. The former global leaderboard is removed because device-entered history is not verified competition.

To create a session, open Workouts and tap the add button. A reviewer can use templates, repeat/copy a prior workout, add exercises/sets, finish the workout, and view its summary. Smart Coach recommendations are derived from the demo account's training history.

## Authentication and backend

- GymApp uses first-party email/password authentication with Supabase. It has no Google/Facebook/social login and therefore no Guideline 4.8 alternative-login requirement.
- Email confirmation and recovery use a same-device PKCE exchange. The app rejects implicit raw-token callbacks and unsolicited/expired callback state.
- Production backend: active. An approved 2026-08-24 rollout and readback found 57 production migrations through `20260824180727`, including the read-only exact-session hotfix, activity-only workout sidecar, remaining boundary hardening, friends, live rooms, Realtime invalidation, provider-neutral notifications, and dispatcher scheduling. Repeat final Auth, Garmin, deletion, live-room, and physical-device checks before submission.
- Supabase Auth must allowlist the associated-domain callback patterns `https://gymapptracker.com/auth/ios-callback.html?state=*&purpose=signup` and `purpose=recovery`; the hosted fallback scrubs the callback instead of forwarding its PKCE code to a custom scheme. The final signed build still requires same-device confirmation/recovery testing on a physical iPhone before submission.
- Production migration history matches the repository; every non-quarantined cloud state retains revision-bound progression and bounded social-activity projections.
- Production `social-live-gateway` version 6 and `push-dispatch` version 5 are `ACTIVE` by read-only metadata. APNs, FCM, Web Push, the dedicated dispatcher authorization, and the dispatcher/monitor schedules are configured outside all clients. Production scheduler calls returned HTTP 200 on 2026-08-10 against `push-dispatch` version 4 with zero registered installations or queued deliveries. This proves only that historical deployment, authorization, and empty-queue path; real APNs receipt, revocation/account-switch fencing, and notification taps remain unverified on a signed physical iPhone.
- Production `garmin-sync` version 12 is active by read-only metadata. OPTIONS, malformed/unknown capability denial, valid-device fetch/ack/replay, token rotation, and post-cutover v2 continuity were historically verified against version 6 over HTTP on 2026-07-22; repeat them against the deployed activity-only database release.
- Required reviewer hardware/sample QR/feature flags: **None**
- Garmin sync is optional and is not required for App Review. All core workout, progress, mission, rank, backup, friend, and workout-invitation paths work without Garmin hardware.

## Account deletion

Path: **Profile → Account, privacy & deletion → Delete Account**. The app shows an irreversible-deletion confirmation and calls the authenticated `delete-account` Edge Function. The server derives the user UUID from the verified bearer token and does not accept an arbitrary user ID.

- Production version 14 is `ACTIVE` with `verify_jwt=true` by the 2026-08-24
  metadata readback. Rerun the repository deployment gate and verify that the
  live-session RPC rejects revoked/terminal sessions before submission.
- Historical deletion result: on 2026-07-22, a disposable user with a profile, cloud state/projection, Garmin device, and two plans was deleted through the live function after positive and negative contract tests. Re-run deletion after the friends migration with synthetic friendships, blocks, privacy settings, projections, and workout invitations, then verify zero rows across every new social table before submission.

Deletion removes the Supabase Auth user and cascades `user_states`, `profiles`, private social settings/friendships/blocks/projections/invitations, `garmin_devices`, `garmin_plans`, and related moderation reports; the app then clears the local account database, Keychain session, account preferences, and in-memory friend caches. Recheck this flow with the final signed physical-device build immediately before submission.

## Privacy and permissions

- No advertising, analytics, IDFA, cross-app/site tracking, fingerprinting, or ATT prompt.
- No camera, microphone, location, Contacts, Photos, Motion & Fitness, or HealthKit access.
- Rest-timer alerts remain local notifications. Where system social/live alerts are supported and configured, notification authorization is requested contextually when the reviewer enables them; declining it prevents those system alerts but does not block workout logging, friendships, or an opened live workout.
- `PrivacyInfo.xcprivacy` declares no tracking, the actual server-collected data categories, and required-reason API `UserDefaults` with approved first-party reason `CA92.1`.
- Account/cloud data includes email, Supabase UUID, display name, workout logs, notes, derived XP/level/workout count, friend/request/block/privacy/invitation/live-room state, optional notification delivery address, and optional Garmin token/plans/import metrics. Friend RPCs use a random UUID-free profile code and return only mutually authorized, enabled categories: XP/level/workout count, up to five date-only summaries, and up to 100 entered exercise bests. They never return email, Auth UUID, raw cloud state, notes, full set history, Garmin token, or health metrics.
- Standard direct workout invitations contain only bounded exercise names/identities and planned weight/repetition sets. An unanswered invitation expires after seven days. Acceptance opens a separate editable draft; it does not join or live-synchronize either person's active workout.
- A live invitation is separate and limited to one mutually confirmed, unblocked friend. After acceptance, the owner starts the frozen plan; each participant can see the other's committed set completion, entered weight, and repetitions through Supabase Realtime. The live snapshot contains no notes, email, Auth UUID, Garmin/health data, or credentials. Per-set progress never travels by push.
- Optional provider delivery uses APNs, FCM, or Web Push as applicable. The provider receives the installation token/endpoint and a static localized notification carrying only a bounded opaque event kind, room/object ID, and revision—not a profile/workout name, exercise, weight, repetitions, notes, email, Auth UUID, session, or arbitrary URL. System alerts are limited to lifecycle events such as invite/join/start/finish/close and require user permission.

## Business model and content

- The app is free and contains no In-App Purchases, subscriptions, paid digital unlocks, external purchase links, or advertising.
- There is no public posting, chat, social feed, or global leaderboard. Social visibility is limited to mutually confirmed, unblocked friends and each owner's explicit category toggles; progress is clearly identified as synchronized/self-reported rather than verified competition. Live set data is visible only to the accepted participant in that two-person room. Removing or blocking immediately revokes friend detail and closes pending invitations/live rooms. The private moderation queue remains only for legacy leaderboard reports and continues to follow [MODERATION_RUNBOOK.md](MODERATION_RUNBOOK.md).
- GymApp is not a medical device and makes no diagnostic or treatment claims.

## Export/import

The JSON/PDF tools under **Profile → Backup & diagnostics** intentionally invoke the iOS share sheet. Files are created only after the reviewer selects Export/Share. Auth tokens and private Keychain credentials are not included in exported workout backups.

## Review readiness gate

- [ ] All placeholders above replaced.
- [ ] Demo credentials confirmed from a clean device and remain active.
- [x] Production backend migration state, access controls, Garmin path, Auth lifecycle, and delete function reverified live on 2026-07-22. Monitor them throughout review.
- [x] Deployment of `20260809202407`–`20260809202432` verified on production. Metadata checks confirmed private RLS/no direct grants, authenticated-only RPCs, 59/59 current social projections, zero quarantine/stale projections, revoked-session denial, wrong-member denial, and a rolled-back friend request/accept → workout invite/accept → remove/revoke flow with zero residual synthetic users. The legacy owner-only leaderboard RPC remains only for released-client compatibility.
- [ ] Before App Store submission, repeat malformed/oversized, replay, stale-revision, block/privacy, account-deletion cascade, and two-device invitation recovery tests with disposable signed-in accounts and the final physical-device build.
- [ ] Production is verified through `20260824180727`, with `social-live-gateway` version 6 and `push-dispatch` version 5 active by read-only metadata. The canonical database chain is deployed and read back; repeat focused contract/security and physical-client checks. APNs/FCM/Web Push credentials and dispatcher/monitor schedules are configured; the successful empty-queue production smoke was against historical `push-dispatch` version 4 and sent no customer notifications.
- [ ] Verify two-account Realtime reconnect/wrong-user denial and notification opt-in/denial/revocation/account-switch fencing plus invite/join/start/finish/close delivery on clean physical devices. Real APNs production receipt and tap behavior must be tested on a signed physical iPhone; a simulator, signed archive, empty-queue smoke, or provider mock is insufficient.
- [x] The Garmin limiter/capability migrations are deployed and a disposable valid device completed fetch/ack/replay plus the v2 gateway cutover on 2026-07-22.
- [x] Published the refreshed privacy policy, support page, and PWA assets to the separate `gh-pages` branch on 2026-08-10. Verified both pages live without login and byte-checked the production `app.v82.js`, `supabase-config.v58.js`, `russian-text.v75.js`, and `sw.js` (cache `gymapp-pwa-v118`) against the reviewed source.
- [x] Non-obvious functionality and the optional Garmin limitation are described above.
- [ ] No test, debug, staging, or hidden feature remains in the submitted build.

Official submission guidance: [App Review Guidelines — Before You Submit](https://developer.apple.com/app-store/review/guidelines/#before-you-submit) and [App Review information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).
