# GymApp for iOS

Native SwiftUI port of the Android GymApp. The project targets iOS 17 and is built with Xcode 26 / the iOS 26 SDK. It intentionally has no advertising, analytics, tracking, or third-party runtime SDKs.

## Included

- Five-tab phone experience: Workouts, Missions, Exercises, Progress, Profile.
- Workout, exercise and set CRUD; templates; Smart Coach; PRs; rest timers.
- Muscle mapping, activity heatmap, XP, levels, ranks, missions and summaries.
- Android-compatible GymApp JSON backup/import and PDF diagnostics.
- Email/password Supabase account, secure Keychain session storage, cloud state and owner-only protected progress.
- Offline account so core workout tracking never requires registration.
- Garmin cloud plan queue using the existing Supabase/Garmin Connect IQ path.
- English, Ukrainian and Russian UI, light/dark appearance, Dynamic Type and VoiceOver labels.
- In-app privacy/support links, password recovery and account-deletion UI.
- Privacy manifest, App Store metadata drafts, review notes and submission checklist.

## Build

```sh
xcodebuild \
  -project GymApp.xcodeproj \
  -scheme GymApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run tests:

```sh
xcodebuild \
  -project GymApp.xcodeproj \
  -scheme GymApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  test
```

### Latest verification

- iOS unit tests: **102/102 passed** on the iPhone 17 / iOS 26.5 simulator on
  2026-07-21, including localization, bounded-network, cloud compatibility,
  persistent password-recovery state, HTTPS auth-bridge, and unsolicited-callback rejection cases.
- Release `iphoneos` build: **passed** on 2026-07-11 as an unsigned arm64 app
  with deployment target iOS 17.0 and bundle ID `com.setforge.gymapp.ios`.
- Strict Swift 6 complete-concurrency warnings-as-errors build: **passed**.
- `deno check ../../supabase/functions/delete-account/index.ts`: **passed** against
  the canonical repository-root source with
  Deno 2.9.2 / TypeScript 6.0.3.
- Production Supabase RLS/deletion E2E and hosted policy/support URL checks:
  **passed**.
- Cross-platform Node regression suite: **206/206 passed** on 2026-07-21. The
  current PWA and native clients use the owner-only protected-progress contract.

## Before a real App Store upload

1. Open `GymApp.xcodeproj`, select your Apple Developer Team, and confirm the final bundle identifier.
2. Keep every canonical migration from the repository-root `supabase/migrations/` directory and both repository-root Edge Functions synchronized in every environment. Production matches all 22 migrations through `20260722013200`; `garmin-sync` version 6 and `delete-account` version 3 are active. The 2026-07-22 valid-device fetch/ack/replay/cutover smoke and disposable-account deletion/cascade E2E passed, and the [deployment gate](../../supabase/functions/delete-account/deployment-contract.json) is clear. Evidence and scope are recorded in [PRODUCTION_BACKEND_VERIFICATION.md](AppStore/PRODUCTION_BACKEND_VERIFICATION.md).
3. Keep `https://gymapptracker.com/confirmed.html?platform=ios&state=*` and
   `com.setforge.gymapp.ios://auth/callback/*` in the Supabase Auth redirect
   allowlist. The first-party HTTPS page accepts only a PKCE `code` plus the
   exact per-request state, then opens the custom-scheme callback after a user
   tap. Do not change the flow back to implicit access/refresh tokens.
4. Use `https://gymapptracker.com/support.html` and
   `https://gymapptracker.com/privacy-policy.html` in App Store Connect. Both
   English/Ukrainian/Russian pages are live over enforced HTTPS and were
   exact-content hash-verified on 2026-07-20.
5. Complete Apple Team/signing, register the configured bundle identifier, and
   add the review-contact phone listed in
   [APP_STORE_CHECKLIST.md](AppStore/APP_STORE_CHECKLIST.md).
6. Recheck cloud login, confirmation, password recovery and deletion against production immediately before submission. The automated backend Auth/deletion/RLS contract passed on 2026-07-22; physical-device PKCE testing remains a release task.

The configured support and privacy URLs are live and match the canonical source
copies. The policy covers iOS, Android, browser/PWA, and optional Garmin features
in English, Ukrainian, and Russian; re-verify the hosted copy after every policy
update.

### External verification status

The production database, Auth, RLS, state projection, Garmin gateway, and
account-deletion behavior were reverified on 2026-07-22:

- migrations `create_leaderboard_public`, `harden_gymapp_production_access`, and
  `fix_user_state_revision_trigger` are recorded in production migration history;
- all 22 repository migrations through `20260722013200` are recorded in
  production migration history;
- authenticated users receive the sanitized `leaderboard_public` projection,
  while anonymous base-table/view/report reads return `401` and the legacy
  `leaderboard` endpoint returns `404`;
- `delete-account` version 3 is `ACTIVE` with `verify_jwt=true`; the live-session
  contract and deletion cascade passed against a disposable account;
- `garmin-sync` version 6 is `ACTIVE`; invalid capabilities were denied and a
  real disposable v2 capability completed fetch, acknowledge, replay, rotation,
  and post-migration continuity; and
- the 37 existing states have 37 revision-bound projections, zero quarantined
  rows, and zero profile/projection mismatches.

The custom-domain iOS bridge and custom-scheme fallback are allowlisted in Auth.
The previous GitHub Pages callback remains allowlisted for older clients and
already-sent messages. Same-device signup confirmation and password recovery
still need final testing with the signed build on a physical iPhone.

The custom-domain site and combined privacy policy were published from GitHub
Pages commit `0147bade…`; the public HTTPS responses matched the reviewed local
SHA-256 values on 2026-07-11. Remaining
release work is Apple signing/App Store Connect configuration and final
physical-device/TestFlight testing. See
[PRODUCTION_BACKEND_VERIFICATION.md](AppStore/PRODUCTION_BACKEND_VERIFICATION.md)
for the backend evidence record and accepted advisor notices.

The publishable Supabase client key in the application is not a privileged secret. Never put a `service_role`/secret key, signing certificate, database dump or real user backup in this repository.
