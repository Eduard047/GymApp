# Gym Workout Tracker

Cross-platform Gym Workout Tracker with native Android and iOS applications,
plus Garmin and browser companions.

## Public URLs

- Marketing site and PWA: https://gymapptracker.com/
- Support: https://gymapptracker.com/support.html
- Privacy policy: https://gymapptracker.com/privacy-policy.html

GitHub Releases remain the distribution source for downloadable Android, iOS
Simulator, and Garmin test artifacts.

The Android, native iOS, Garmin, and browser interfaces support English,
Ukrainian, and Russian.

Current source release: **GymApp 2.1.0** (PWA cache generation **v50**).

## Current Feature Set

### Phone app

- Workout logging with multiple exercises, multiple sets, notes, and fast set shortcuts.
- Copy a previous workout day into a new draft, then adjust weights, reps, or remove/add sets during the workout.
- Repeat the latest workout as a quick template.
- Post-workout summary with XP gained, level progress, loaded muscle groups, top muscle of the day, and new PRs.
- Activity heatmap, rank/achievement progression, missions, and recent workout history.

### Native iOS app

- SwiftUI application in `ios/GymApp-iOS` with the same Supabase account and workout data.
- Password recovery, cloud sync, canonical XP/rank rules, muscle maps, activity heatmap, missions, and leaderboards.
- App Store privacy manifest, localized metadata, support/privacy pages, release validation, and archive scripts.
- The release workflow produces a universal Release-configuration iOS Simulator build; an App Store IPA requires the matching Apple Distribution identity and provisioning profile.

### Muscle Map

- Muscle load map with `All time`, `Month`, and `Week` filters.
- Tap a muscle group to see which exercises loaded it.
- Unmapped/new exercise list for exercises the app cannot confidently classify.
- Manual exercise-to-muscle mapping stored in the local Room database.
- Automatic recommendations based on training history:
  - stale muscle groups,
  - posterior-chain imbalance,
  - next suggested workout type such as push, pull, or legs with the actual muscles explained in the card.

### Backup, Import, And Diagnostics

Open `Exercises` and use `Backup and diagnostics`.

- `Export JSON` creates an importable backup of exercises and workouts.
- `Import JSON` restores workouts from an exported GymApp JSON backup.
- `Export redacted diagnostics` creates an aggregate-only support report without workout rows,
  exercise names, notes, account identifiers, or other backup content.
- `Share PDF report` creates a readable diagnostics report for sharing/debugging.

Important: diagnostics and PDF reports are for support only and cannot restore data. Only the
separate `Export JSON` backup is the source of truth for import/restore; review it before sharing
because it contains private workout data.

### Garmin Connect IQ app

- Native Connect IQ app for compatible Garmin watches and wearables running Connect IQ 3.2 or newer.
- Record exercises, weight, reps, and sets with hardware buttons or touch gestures, depending on the device.
- 90-second rest timer with vibration.
- Offline workout queue and two-way sync through Garmin Connect and the Android app.
- Source and build instructions: `garmin/README.md`.

## Downloads

- Releases page: https://github.com/Eduard047/GymApp/releases
- Latest published release: https://github.com/Eduard047/GymApp/releases/latest
- Web app: https://gymapptracker.com/

Each release documents exactly which artifacts were produced and how they were
signed. Production Android APK/AAB files require the existing private Android
release key. App Store IPA files require the matching Apple Distribution identity
and provisioning profile. Debug, QA, unsigned, and Simulator-only files must not
be presented as store binaries.

Publishing release assets does not deploy Supabase migrations or Edge Functions.
Backend deployment is a separate privileged operation and must be reviewed before
it is run.

## Releases

Release assets use stable, platform-neutral names such as
`gymapp-phone-release.apk`, `gymapp-play-release.aab`,
`gymapp-garmin-connect-iq.iq`, and `gymapp-pwa-v50.zip`. Checksums and exact
build metadata are attached as `SHA256SUMS.txt` and `BUILD-INFO.txt` when those
assets are available.

The Garmin IQ is a developer-signed Connect IQ Store upload package exported
from this source revision for every compatible target in `manifest.xml`. It is
not a direct sideload file and has not been physically tested on every device.

For the native iOS source, open:

```sh
open ios/GymApp-iOS/GymApp.xcodeproj
```

## Build the QA APK

Use the helper to build a non-debuggable, test-signed Phone QA APK with a
timestamp-based version code:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-update-apk.ps1
```

The script builds `:app:assembleQa`, then writes the ignored local artifact
`gymapp-phone-qa.apk` and SHA-256 build metadata under `tmp/`. QA uses package
ID `com.setforge.gymapp.dev`, a separate authentication callback scheme,
release source behavior, and a local test key. It must never be uploaded to Play
Console.

Direct Gradle equivalent:

```text
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
.\gradlew.bat :app:assembleQa -PappVersionCode=<version> -PappVersionName=<name>
```

## Install the QA build

```powershell
adb install -r gymapp-phone-qa.apk
```

Data is preserved only if:

- The app keeps the same `applicationId`.
- The APK is signed with the same signing key as the installed app.
- The new APK has a higher `versionCode` than the installed one.

The new Phone QA APK can update the immediately preceding public Phone test
build because both use the same signer.

Module-output install commands:

```powershell
adb install -r .\app\build\outputs\apk\qa\app-qa.apk
```

For wireless debugging:

```powershell
adb pair <phone-ip>:<pairing-port> <pairing-code>
adb connect <phone-ip>:<connect-port>
adb -s <phone-ip>:<connect-port> install -r .\app\build\outputs\apk\qa\app-qa.apk
```

## iPhone PWA

The Android app cannot be installed on iPhone as an APK, so this repo also includes a standalone PWA in `pwa/`.

The PWA is a browser port of the phone app experience: workouts, workout detail, post-workout summary, exercises, exercise history, progress, missions, ranks, solo XP, activity heatmap, muscle map, smart workout generation, templates, local timers, JSON backup/import, and diagnostics export.

Run it locally:

```powershell
python -m http.server 4173 --directory .\pwa
```

Open:

```text
http://127.0.0.1:4173
```

To install on iPhone, host the `pwa/` folder over HTTPS, open the URL in Safari, then use `Share` -> `Add to Home Screen`.

The PWA stores workouts locally in the browser, syncs through Supabase when cloud login is enabled, and supports JSON export/import from the Exercises backup tools.

### Public-site and Auth cutover

The custom-domain cutover is already live: `pwa/CNAME` makes GitHub Pages serve
the first-party PWA at `https://gymapptracker.com/`, and the legacy
`https://eduard047.github.io/GymApp/` origin currently responds with a
cross-origin `301` to the custom domain.

GitHub Pages does not support repository-defined response headers. The PWA uses
a fail-closed frame guard on the first visit; once its service worker is active,
HTML responses also receive `frame-ancestors 'none'` and `X-Frame-Options: DENY`.
Enforcing those headers on the very first response requires moving the custom
domain behind a header-capable CDN or host. Do not add Netlify/Cloudflare header
files while GitHub Pages remains the actual origin because Pages ignores them.

Cloud access and refresh tokens use tab-scoped `sessionStorage`, not persistent
`localStorage`. The first hardened load migrates and deletes a valid legacy
session once; closing the browser/PWA session requires a fresh cloud login. An
explicit account switch also attempts Supabase `scope=local` revocation so it
does not sign Android, iOS, or other devices out. If that network revocation
cannot be confirmed, local credentials are still erased and the UI warns that
the old server session can remain valid until server expiry or administrative
revocation. Sign-out completes only after browser storage confirms that the
current tab's credential and any legacy persistent copy are gone; if storage
denies removal, the account stays open in that tab and the user is told to
restore storage access and retry.

Configure the Supabase Auth redirect allow-list with:

- Site URL: `https://gymapptracker.com/`
- Production Android redirect base:
  `https://gymapptracker.com/confirmed.html?platform=android`
- QA/debug Android redirect base:
  `https://gymapptracker.com/confirmed.html?platform=android&variant=qa`
- Web redirect: `https://gymapptracker.com/confirmed.html?platform=web`
- iOS PKCE redirect allow-list pattern:
  `https://gymapptracker.com/confirmed.html?platform=ios&state=*`

The bridge accepts exactly one optional `variant=qa` only for Android and sends
that flow to `com.setforge.gymapp.dev://auth/callback`. An absent variant uses
the production `com.setforge.gymapp://auth/callback`; duplicate, unknown, iOS,
or web variants fail closed. The state, purpose, and one-time PKCE code remain
bound to the initiating app flow.

Keep `https://eduard047.github.io/GymApp/confirmed.html` in the redirect allow
list while released builds or already-sent confirmation emails can still use it.
The cleanup worker deliberately excludes `confirmed.html` callbacks. The bridge
rejects implicit bearer-token fragments; Android and iOS routes require a bound
PKCE `code` plus one 32-character base64url `state`, and forward only the
single-use code or bounded error fields through the exact platform callback.

#### Legacy-origin cleanup is a staged operation

The current `301` strands any already-installed v44 service worker and old
browser session under `eduard047.github.io`: a service worker update is not
allowed to follow that cross-origin redirect. Therefore a normal commit, Pages
deployment, or custom-domain release does **not** deliver the included
`legacy-origin-cleanup.html` or the v45 legacy cleanup branch to those clients.
Those artifacts are dormant until the old origin can temporarily serve them as
a same-origin `200` response.

Do not call legacy cleanup complete until one of these separately reviewed
remediations is performed:

1. Administratively revoke sessions issued before the cutover and instruct
   affected users to clear site data for `eduard047.github.io`; or
2. With explicit release approval, temporarily make `/GymApp/` serve this exact
   build from the legacy origin, keep `confirmed.html` callbacks exempt, wait for
   the v45 worker to activate and verify credential/cache/worker removal, then
   restore the CNAME/custom domain and re-verify every auth redirect.

The second option can interrupt the public custom domain and authentication
callbacks, so it must not be performed as part of an ordinary source release.

### Garmin cloud sync POC

The iPhone/PWA Garmin path uses Supabase as a queue and Garmin Connect Mobile as the watch network bridge:

1. Apply every ordered SQL file in `supabase/migrations/` through the normal
   Supabase migration workflow. The root `supabase-schema.sql` is a retired,
   fail-closed stub and must not be used.
2. Deploy the Edge Function:

```powershell
supabase functions deploy garmin-sync --project-ref owrcbsrectdgaotndtxy
```

The migration and Edge Function must be deployed before publishing the matching
PWA release. The hardened client requires `listDevices`, `token_revision`, and
CAS-based `rotateDeviceToken`; it deliberately fails closed against an older
Edge Function rather than creating a duplicate watch identity.

3. In the PWA Add Workout screen, tap `Sync Watch`. The first run creates a
   Garmin device token and shows it once.
4. Paste that token into the GymApp `Cloud Token` setting in Garmin Connect IQ Mobile.
5. On the watch, open settings and select `CLOUD / SYNC` to download the latest pending plan.

Token recovery keeps the existing watch UUID. The browser generates the
replacement with 32 bytes of CSPRNG entropy, sends it with the expected server
token revision, and retries only the exact same CAS request when the outcome is
unknown. Raw tokens are never stored; a revision conflict refreshes device
metadata and requires explicit retry.

Device creation and plan enqueue run under an account-scoped Web Lock so two
GymApp tabs cannot mint competing watch identities or independent enqueue IDs.
Browsers that do not provide this cross-tab security primitive fail closed and
must not be used for PWA Garmin pairing/sync.

Run the no-device Garmin cloud sync checks:

```powershell
npm run test:garmin-cloud
```

### Supabase migration safety

Production is migration-managed. The exact privacy-hardening versions recorded in
production history are:

- `20260711084556_create_leaderboard_public.sql`
- `20260711084559_harden_gymapp_production_access.sql`
- `20260711090358_fix_user_state_revision_trigger.sql`

All three must remain ordered after the existing Garmin migrations. The first
adds the sanitized authenticated leaderboard and moderation tables; the second
removes cross-user direct `profiles` reads and anonymous table grants; the third
fixes the server-owned cloud-state revision trigger. Do not restore a
`Leaderboard is public` policy on `profiles`, the old `public.leaderboard`
view, or direct anonymous Garmin table access.
