# Deployment and release boundaries

GymApp spans public clients, native applications, wearable packages, and a
Supabase backend. A source push, GitHub release, browser-site deployment, database
migration, and Edge Function deployment are separate operations.

## Public surfaces

- Distribution and legal site: <https://gymapptracker.com/>
- Support: <https://gymapptracker.com/support.html>
- Privacy policy: <https://gymapptracker.com/privacy-policy.html>
- Releases: <https://github.com/Eduard047/GymApp/releases>

GitHub Pages publishes the reviewed full browser application, native callback,
legal pages, and shared-workout handoff files from `pwa/` through the dedicated
`gh-pages` branch. Canonical and immutable bundles, `index.html`, and the service
worker cache allowlist/version must move together. Deploy only an explicit file
allowlist and remove superseded cache assets deliberately; never use a broad
delete that could remove callback, legal, or compatibility routes. The branch
is deployment infrastructure and must not be deleted as stale source work.

## Authentication redirects

Browser authentication uses the first-party HTTPS page at
`https://gymapptracker.com/confirmed.html?platform=web`. Production native
authentication uses separately claimed HTTPS callbacks:
`https://gymapptracker.com/auth/android-callback.html` and
`https://gymapptracker.com/auth/ios-callback.html`. Native handlers accept only
their exact host/path plus a bounded, state-bound PKCE code. Reusable access or
refresh tokens and production authorization codes must never be placed in a
custom-scheme URL.

The required hosted Supabase Site URL and redirect allowlist are source-controlled
in `supabase/auth-redirect-allowlist.json`. Production needs the exact Android
and iOS HTTPS callback patterns recorded there, with separate `signup` and
`recovery` purposes. The Android QA build remains
test-signed and uses only the explicit `.dev` custom-scheme bridge; it cannot
claim the production App Link. A wildcard retains the per-request PKCE state,
bounded `purpose`, and one-time `code` that Supabase appends.

Use a two-phase cutover. First publish and read back only the new callback pages
and association files while the old production bridge still works; temporarily
add the new HTTPS patterns alongside the old live Supabase Auth entries. Then
ship and verify signed native clients. Only after both new clients claim their
HTTPS callbacks should the final phase publish `confirmed.v58.js`, remove the
old production custom-scheme entries from the live allowlist, and verify that
old bridge URLs fail closed with the update-required response. Do not publish a
client that points at a callback absent from the live allowlist, and do not ship
the final source state as an undifferentiated one-step PWA/Auth cutover. The JSON
file records the desired final contract, not the temporary rollout state or
proof that the Dashboard setting was changed.

The production Dashboard allowlist last read back on 2026-07-22 contained the
legacy custom-scheme/native bridge entries. The source contract now retires
those production entries, but this repository change does not alter the hosted
setting. Recheck and update that setting before release, then validate the final
handoff on a Play-signed Android build and a signed physical iPhone.

The legacy browser callback at
`https://eduard047.github.io/GymApp/confirmed.html` remains an intentional
web compatibility entry. Production `platform=android` and `platform=ios`
bridges fail closed with an update-required message and never translate a code
to a custom scheme. The test-only Android QA bridge remains isolated to the
`.dev` package and scheme.

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
in order and verified. At that historical checkpoint, local and production
matched through `20260722013200`; production contained 37 revision-bound state
projections, zero quarantined states, and zero profile/projection mismatches.
`garmin-sync` version 6 and `delete-account` version 3 were active; a real
disposable v2 device completed fetch, acknowledge, replay, rotation, and
post-cutover continuity checks.

Production Auth currently enforces the historical eight-character server
minimum. Android, iOS, and the browser client enforce the twelve-character
mixed-character policy. Any server policy change still requires a separately
reviewed three-client and backend release window. Email confirmation is enabled,
anonymous sign-in is disabled, and the 2026-07-22
registration/login/refresh/password-change/logout/deletion E2E passed with
disposable accounts.

On 2026-08-13 the production migration history was verified through
`20260813112014`. The social release added explicit default-off detailed-workout
consent, a bounded latest-five friend-workout view, atomic live-room activation,
and a guarded waiting-to-active transition. A rollback-only synthetic smoke
covered owner, friend, anonymous, non-friend, stale-revision, replay, revoke,
future-workout, zero-weight, and exact-two-participant cases without retaining
fixture rows.

On 2026-08-22 the production migration history was verified through
`20260822071247`. The workout-duration sidecar and its corrected friend-detail
enrichment retain private-table denial, exact live-session ownership, explicit
detail consent, and the bounded latest-five projection. A rollback-only
synthetic smoke covered owner sync, malformed input, cross-account isolation,
authorized friend read, consent revocation, and invalid-session denial; it
retained zero fixture rows.

On 2026-08-24 an approved production rollout brought the canonical history to
57 migrations through
`20260824180727_harden_remaining_supabase_boundaries`. It applied the
read-only exact-session predicate hotfix, the activity-only workout sidecar,
and the remaining default-ACL/private-projection hardening. Readback confirmed
the helper's non-locking read-only branch and key-share-locked write branch,
unchanged owner-table RLS policies, FORCE RLS with no client table grants for
the new/private projections, and no remaining local migration drift. A bounded
production smoke then covered owner reads/writes, cross-owner isolation,
wrong/expired/malformed/missing/revoked sessions, activity-only sync/replay,
and anonymous denial. A real authenticated PostgREST `GET`/`HEAD` of
`user_states` plus `GET profiles` returned HTTP 200; the matching API log was
200 and the current PostgreSQL log window contained no read-only key-share
error. The disposable account and every dependent fixture row were removed.
Active Edge Function metadata remained `garmin-sync` version 12
(`verify_jwt=false`),
`delete-account` version 14 (`verify_jwt=true`), `social-live-gateway` version 6
(`verify_jwt=true`), and `push-dispatch` version 5 (`verify_jwt=false`).

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
