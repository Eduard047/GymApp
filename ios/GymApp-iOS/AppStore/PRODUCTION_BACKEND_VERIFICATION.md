# GymApp production backend verification

Status: **production backend update and disposable-account E2E passed on
2026-07-22**
Supabase project: `owrcbsrectdgaotndtxy` (`GymApp`, `eu-west-1`)

> On 2026-07-22 all 22 repository migrations were reconciled with production,
> the two canonical Edge Functions were deployed, and live Auth, state, Garmin,
> and account-deletion paths were exercised with disposable data. No customer
> account or customer row was changed by the E2E.

This record contains no access tokens, passwords, secret/service-role keys, real
user identifiers, or customer data. All destructive tests used two generated
`example.invalid` disposable accounts, and final SQL assertions confirmed that
both accounts and every dependent test row were removed.

## Deployed production versions

| Component | Production version | Result |
| --- | --- | --- |
| Existing Garmin schema | `20260629120000` — `garmin_cloud_sync` | Present |
| Existing Garmin RPC | `20260630000100` — `garmin_fetch_pending_plan_rpc` | Present |
| Sanitized leaderboard/moderation | `20260711084556` — `create_leaderboard_public` | Applied |
| RLS/grant/privacy hardening | `20260711084559` — `harden_gymapp_production_access` | Applied |
| Server revision correction | `20260711090358` — `fix_user_state_revision_trigger` | Applied and live-probed |
| Canonical profile progression | `20260721142924` — `canonical_profile_progression` | Applied 2026-07-21 |
| Garmin pairing/plan hardening | `20260721142935` — `harden_garmin_pairing_and_plans` | Applied 2026-07-21 |
| Progression reconciliation | `20260721142942` — `reconcile_canonical_progression` | Applied 2026-07-21 |
| Per-device Garmin limits | `20260721142951` — `add_garmin_device_rate_limits` | Applied 2026-07-21 |
| Exercise catalog | `20260721143010` — `create_exercise_catalog` | Applied 2026-07-21 |
| Owner-only protected progress | `20260721143038` — `restrict_leaderboard_to_owner_until_verified_ingestion` | Applied 2026-07-21 |
| Bounded Garmin pre-auth limits | `20260721143058` — `add_bounded_garmin_preauth_rate_limits` | Applied 2026-07-21 |
| Retired anonymous Garmin table grants | `20260721143853` — `retire_legacy_garmin_table_grants` | Applied 2026-07-21 |
| Hip-abduction catalog entry | `20260721201016` — `add_hip_abduction_to_exercise_catalog` | Applied; 52 catalog rows |
| Fail-closed RLS guard | `20260722005900` — `fail_closed_public_rls_guard` | Applied and live-probed |
| Live-session deletion gate | `20260722010000` — `require_live_session_for_account_deletion` | Applied and live-probed |
| Bounded leaderboard reports | `20260722011000` — `bound_leaderboard_reports` | Applied |
| Garmin capability gateway cutover | `20260722012000` — `secure_garmin_capability_gateway` | Applied; v2 continuity smoke passed |
| Bounded state projection | `20260722013000` through `20260722013200` | Applied; 37/37 projected, zero quarantine/mismatch |
| Garmin bridge | `garmin-sync` version 6 | `ACTIVE`, `verify_jwt=false`; user JWTs and device capabilities are validated by the function's explicit request paths |
| Account deletion | `delete-account` version 3 | `ACTIVE`, `verify_jwt=true`; repository contract v2 and live-session RPC verified |
| Auth redirects | Seven production URLs | Web, legacy Android/GitHub, iOS custom scheme, and state-bound iOS/Android production/QA entries read back from Dashboard |

The authoritative ordered migration source is the repository-root
`supabase/migrations/` directory. The linked migration list was read back after
deployment and contains the same 22 versions through `20260722013200`. The
current account-deletion evidence and release gate are pinned in
[deployment-contract.json](../../../supabase/functions/delete-account/deployment-contract.json).

## Live E2E coverage

The production run verified:

- public email signup acceptance with a state-bound Android PKCE redirect;
- wrong-password rejection, password login, refresh-token rotation, password
  change with the current password, local-session logout/revocation, and
  survival of a separate live session;
- password login for two isolated disposable Auth users;
- own profile/state creation and Garmin device/plan creation;
- own-row direct `profiles` reads and empty cross-user direct reads;
- full sanitized `leaderboard_public` results with one correct
  `is_current_user`, random `p_…` IDs, and no Auth UUID field;
- denial of cross-user insert/update, direct profile delete, public-ID mutation,
  unsafe display name, report reads, self-reporting, duplicate reporting, and
  attempts to set protected report columns;
- successful insert-only reporting with a server-bound reporter;
- a successful conditional state update, rejection of the stale revision, and a
  successful Android-style upsert whose revision advanced on the server;
- `delete-account` rejection of wrong method, non-JSON content, wrong
  confirmation, extra fields, oversized body, disallowed browser origin, missing
  JWT, and repeat deletion;
- hard deletion of user A while user B remained authenticated and isolated;
- hard deletion of user B; and
- zero remaining Auth users/identities, profiles, states, Garmin devices/plans,
  or report rows for either disposable account. Production Storage had zero
  objects at verification time.

## Anonymous HTTP smoke test

| Request | Expected/observed status |
| --- | --- |
| `GET /rest/v1/profiles` | `401` |
| `GET /rest/v1/leaderboard_public` | `401` |
| `GET /rest/v1/leaderboard_reports` | `401` |
| `GET /rest/v1/leaderboard` (removed legacy view) | `404` |
| `GET /functions/v1/delete-account` without JWT | `401` |
| `POST /functions/v1/delete-account` without JWT | `401` |
| `OPTIONS /functions/v1/garmin-sync` | `200` |
| `POST /functions/v1/garmin-sync` with unknown action | `400` |
| `POST /functions/v1/garmin-sync` with malformed device token | `400` |
| `POST /functions/v1/garmin-sync` fetch/ack with a random format-valid token | `401` |

The negative Garmin smoke used a generated non-persistent token. A separate
disposable authenticated user then created and rotated a real v2 device
capability, queued two plans, fetched and acknowledged them through the Edge
Function, replayed the acknowledgement idempotently, and fetched/acknowledged a
plan across the capability-gateway migration cutover.

## Auth and App Review account

- Supabase Dashboard readback showed the expected seven-entry redirect
  allowlist on 2026-07-22. The Site URL remains
  `https://gymapptracker.com/`.
- Email confirmation is enabled, anonymous sign-in is disabled, and the server
  minimum password length is eight to match the currently hosted PWA. The
  repository clients already enforce the next twelve-character mixed-character
  policy; the server policy must be raised in the same release window as those
  clients are published.
- A non-expiring, email-confirmed App Review account was created in production
  with three fictional exercises and two fictional workouts.
- Password login, own profile, cloud state, and exactly one
  `is_current_user=true` leaderboard row were verified for that account. The
  credentials are kept only in the gitignored local
  `REVIEW_CREDENTIALS.private.md` file.
- Same-device signup confirmation and password recovery still require a final
  signed-build test on a physical iPhone; allowlisting alone does not certify the
  PKCE/deep-link UI flow.

## Existing Android/PWA compatibility

The RLS hardening intentionally prevents legacy direct cross-user `profiles`
reads. Repository clients use the owner-only protected-progress contract and
the canonical Edge Function paths. The source changes in this verification are
not a PWA or mobile publication:

- repository `Eduard047/GymApp` master commit
  `63e47f3ebfb0d4a6db969375b1b6b26fa24e0749` updates Android and PWA to
  authenticated `leaderboard_public`, removes Auth UUIDs from leaderboard rows,
  trusts `is_current_user`, and retires the unsafe monolithic schema entrypoint;
- master commit `2729f4dc2e601be1e4c369c4638d889e9c9fa5f9` moves the
  Android/PWA auth callbacks and public legal URLs to the verified custom domain
  while retaining platform-specific redirect behavior;
- production and repository migration histories now match exactly through
  `20260722013200`; and
- the live site still serves its previously published `app.v52.js`, whose hash
  differs from the updated repository copy. Publish and reverify the PWA in a
  separate authorized release before raising the server password policy to the
  repository's twelve-character contract.

Already-installed legacy Android builds remain privacy-safe but show only their
own leaderboard row until an updated APK/AAB is built and distributed. Android
Gradle compilation could not run on this Mac because no Android SDK is installed;
Gradle configuration reached the expected `SDK location not found` environment
gate, while the Kotlin change and cross-client contract are covered by static
regression tests.

## Remaining advisor notices

Supabase reports no error-level security advisor item. The remaining notices are
reviewed exceptions or owner-level configuration:

- `leaderboard_blocked_terms`: RLS is enabled with no policies intentionally;
  all client grants are revoked and only trusted server/moderation access is
  allowed. [Advisor reference](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
- The former anonymous `garmin_fetch_pending_plan(text)` exception is resolved:
  direct anonymous/authenticated execution is revoked and only the Edge backend
  role may call the delivery RPCs.
- `leaderboard_public_rows()`: authenticated execution is intentional and
  returns only the reviewed six-field sanitized leaderboard projection, with no
  UUID or dynamic SQL. [Advisor reference](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
- Leaked-password protection is disabled. Supabase documents this as a paid-plan
  Auth option; enabling or changing the project plan requires an explicit owner
  billing/configuration decision. [Supabase password-security guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)

Two performance INFO notices currently flag
`leaderboard_reports_status_created_idx` and `garmin_devices_user_id_idx` as
unused. They support moderation ordering and user-owned Garmin lookup/cascade
paths and are retained; low current usage is not evidence that either is unsafe
or unnecessary.

## Recheck before App Review

Repeat the smoke/E2E checks after any schema, RLS, grant, Auth, Storage, Edge
Function, Garmin RPC, or secret rotation. Also test PKCE confirmation/recovery and
the full delete flow from the final signed build on a physical iPhone immediately
before submission.

## Hosted release URLs

- Site: `https://gymapptracker.com/` — HTTPS 200 from GitHub Pages; HTTP-to-HTTPS
  enforcement enabled. `www.gymapptracker.com` redirects to the apex domain.
- Support: `https://gymapptracker.com/support.html` — HTTPS 200; live/local
  SHA-256 `a22cd0d42fec7fc29bfa8e573ebe115d193fc352c473389bd07130253259ea14`,
  exact-content verified on 2026-07-20.
- Privacy: `https://gymapptracker.com/privacy-policy.html` — HTTPS 200; the
  English/Ukrainian/Russian combined policy has live/local SHA-256
  `a5c3dc078f30084cabdcbbbc3b043a6ceee5fb8be0339a1d5258cd10f75f9c04`,
  exact-content verified on 2026-07-20.
- The current legal pages were deployed from `gh-pages` commit
  `f3edd58cbe1a255f1335c868ece6dafa7244b33c`; the first-party confirmation
  bridge remains part of the same hosted site.
- Supabase Auth Site URL is `https://gymapptracker.com/`. Its seven-entry
  redirect allowlist retains the previous GitHub callback and legacy Android
  exact URL alongside the web, iOS custom-scheme, and state-bound iOS/Android
  production/QA callbacks.
