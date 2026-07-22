# Deployment and release boundaries

GymApp spans public clients, native applications, wearable packages, and a
Supabase backend. A source push, GitHub release, PWA deployment, database
migration, and Edge Function deployment are separate operations.

## Public surfaces

- Web app: <https://gymapptracker.com/>
- Support: <https://gymapptracker.com/support.html>
- Privacy policy: <https://gymapptracker.com/privacy-policy.html>
- Releases: <https://github.com/Eduard047/GymApp/releases>

GitHub Pages publishes the reviewed contents of `pwa/` through the dedicated
`gh-pages` branch. That branch is deployment infrastructure and must not be
deleted as stale source work.

## Authentication redirects

Production authentication uses the first-party HTTPS bridge at
`https://gymapptracker.com/confirmed.html`. Native callbacks accept a bounded,
state-bound PKCE code; reusable access or refresh tokens must never be placed in
a custom-scheme URL.

The required hosted Supabase Site URL and redirect allowlist are source-controlled
in `supabase/auth-redirect-allowlist.json`. In particular, Android needs both
`https://gymapptracker.com/confirmed.html?platform=android&state=*` and
`https://gymapptracker.com/confirmed.html?platform=android&variant=qa&state=*`.
The wildcard retains the per-request PKCE state plus the bounded `purpose` and
one-time `code` that Supabase appends; an exact `?platform=android` entry does not
cover those URLs.

The production Dashboard allowlist was updated and read back on 2026-07-22. It
contains the legacy GitHub callback, the iOS custom-scheme callback, exact web
and legacy Android callbacks, and the iOS, Android production, and Android QA
state wildcards (seven URLs total). Registration with a state-bound Android PKCE
redirect was accepted by the live Auth service. Recheck the final handoff on
physical production and QA builds before release.

The legacy callback at
`https://eduard047.github.io/GymApp/confirmed.html` remains an intentional
compatibility entry for older released clients and previously sent emails.
Removing it requires a separately reviewed client and session migration.

## Supabase

- Apply the ordered files in `supabase/migrations/`; do not use the retired root
  `supabase-schema.sql` stub as a deployment source.
- Local resets are pinned to PostgreSQL 17 in `supabase/config.toml` because the
  bounded user-state projection uses PostgreSQL 17 SQL/JSON behavior. Keep
  staging and production on the same major version before applying that chain.
- Review RLS, grants, security-definer functions, owner binding, replay handling,
  and concurrency before every migration deployment.
- Treat `supabase/functions/` as the only canonical Edge Function source. Deploy
  `garmin-sync` separately from client publication. Deploy `delete-account` only
  after its required live-session migration; its pinned local/production contract
  is recorded in `supabase/functions/delete-account/deployment-contract.json`.
- Complete a valid paired-device fetch/ack smoke before promoting a Garmin cloud
  change to production.

Before any database release, compare local and linked histories with the current
CLI and inspect `supabase db push --dry-run`. On 2026-07-22 the pre-existing RLS
bootstrap objects were compared with their repository definition before their
missing history row was repaired. The eight pending migrations were then applied
in order and verified. Local and production histories now match through
`20260722013200`; production contains 37 revision-bound state projections, zero
quarantined states, and zero profile/projection mismatches. `garmin-sync` version
6 and `delete-account` version 3 are active; a real disposable v2 device completed
fetch, acknowledge, replay, rotation, and post-cutover continuity checks.

Production Auth currently enforces an eight-character server minimum, matching
the already-hosted PWA. The repository clients enforce the new twelve-character
mixed-character policy. Raise the server requirement and enable current-password
enforcement only in the same reviewed release window as publication of those
updated clients; changing them earlier would make the still-hosted client promise
different behavior from the backend. Email confirmation is enabled, anonymous
sign-in is disabled, and the 2026-07-22 registration/login/refresh/password-change/
logout/deletion E2E passed with disposable accounts.

Public Supabase client identifiers are not privileged credentials. Secret keys,
service-role keys, connection strings, raw device tokens, and real account data
must never enter clients, logs, Git, or release assets.

## Store packages

| File | Destination |
| --- | --- |
| `gymapp-phone-release.apk` | Direct Android installation |
| `gymapp-play-release.aab` | Google Play Console |
| `gymapp-garmin-connect-iq.iq` | Garmin Connect IQ Developer Dashboard |
| iOS `.ipa` | App Store Connect; requires Apple Distribution signing |

Android and Garmin updates must retain their historical signing identities.
Signing files stay outside the repository and outside release archives. An iOS
Simulator archive is never an App Store package.

## Security checks

The default branch runs Gitleaks, Semgrep, CodeQL, dependency/SBOM scanning,
Android validation, iOS validation, and cross-platform contract tests. Failed,
cancelled, or skipped security jobs must not be treated as a passing release.

Report vulnerabilities through a
[private GitHub security advisory](https://github.com/Eduard047/GymApp/security/advisories/new).
The full policy is in [`.github/SECURITY.md`](../.github/SECURITY.md).
