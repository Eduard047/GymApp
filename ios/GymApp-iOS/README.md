# GymApp for iOS

Native SwiftUI port of the Android GymApp. The project targets iOS 17 and is built with Xcode 26 / the iOS 26 SDK. It intentionally has no advertising, analytics, tracking, or third-party runtime SDKs.

## Included

- Five-tab phone experience: Workouts, Missions, Exercises, Progress, Rating.
- Workout, exercise and set CRUD; templates; Smart Coach; PRs; rest timers.
- Muscle mapping, activity heatmap, XP, levels, ranks, missions and summaries.
- Android-compatible GymApp JSON backup/import and PDF diagnostics.
- Email/password Supabase account, secure Keychain session storage, cloud state and leaderboard.
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

- iOS unit tests: **84/84 passed** on the iPhone 17 / iOS 26.5 simulator on
  2026-07-20, including localization, bounded-network, cloud compatibility,
  HTTPS auth-bridge, and unsolicited-callback rejection cases.
- Release `iphoneos` build: **passed** on 2026-07-11 as an unsigned arm64 app
  with deployment target iOS 17.0 and bundle ID `com.setforge.gymapp.ios`.
- Strict Swift 6 complete-concurrency warnings-as-errors build: **passed**.
- `deno check supabase/functions/delete-account/index.ts`: **passed** with
  Deno 2.9.2 / TypeScript 6.0.3.
- Production Supabase RLS/deletion E2E and hosted policy/support URL checks:
  **passed**.
- Existing Android/PWA compatibility regression suite: **23/23 passed**; the
  hosted PWA uses the hardened leaderboard contract.

## Before a real App Store upload

1. Open `GymApp.xcodeproj`, select your Apple Developer Team, and confirm the final bundle identifier.
2. Keep the three ordered Supabase migrations and `delete-account` Edge Function synchronized in every environment. They are deployed and production-tested as recorded in [PRODUCTION_BACKEND_VERIFICATION.md](AppStore/PRODUCTION_BACKEND_VERIFICATION.md).
3. Keep `https://gymapptracker.com/confirmed.html?platform=ios&state=*` and
   `com.setforge.gymapp.ios://auth/callback/*` in the Supabase Auth redirect
   allowlist. The first-party HTTPS page accepts only a PKCE `code` plus the
   exact per-request state, then opens the custom-scheme callback after a user
   tap. Do not change the flow back to implicit access/refresh tokens.
4. Use `https://gymapptracker.com/support.html` and
   `https://gymapptracker.com/privacy-policy.html` in App Store Connect. Both
   pages are live over enforced HTTPS and were exact-content verified on
   2026-07-11.
5. Complete Apple Team/signing, register the configured bundle identifier, and
   add the review-contact phone listed in
   [APP_STORE_CHECKLIST.md](AppStore/APP_STORE_CHECKLIST.md).
6. Recheck cloud login, confirmation, password recovery and deletion against production immediately before submission. The automated backend deletion/RLS contract passed on 2026-07-11; physical-device PKCE testing remains a release task.

The configured support and privacy URLs are live and verified. The hosted policy
now covers iOS, Android, browser/PWA, Wear OS, and optional Garmin features.

### Verified external release status (2026-07-11)

The production database, RLS, leaderboard, and account-deletion server gates are
complete:

- migrations `create_leaderboard_public`, `harden_gymapp_production_access`, and
  `fix_user_state_revision_trigger` are recorded in production migration history;
- authenticated users receive the sanitized `leaderboard_public` projection,
  while anonymous base-table/view/report reads return `401` and the legacy
  `leaderboard` endpoint returns `404`;
- `delete-account` version 1 is `ACTIVE` with `verify_jwt=true`; and
- a two-user production E2E run passed RLS, reporting, stale-revision, deletion,
  and cascade checks, then confirmed zero disposable rows remained.

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
