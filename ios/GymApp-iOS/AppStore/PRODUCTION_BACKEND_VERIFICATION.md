# GymApp production backend verification

Status: **passed on 2026-07-11**
Supabase project: `owrcbsrectdgaotndtxy` (`GymApp`, `eu-west-1`)

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
| Account deletion | `delete-account` version 1 | `ACTIVE`, `verify_jwt=true` |
| iOS Auth redirect | `com.setforge.gymapp.ios://auth/callback/*` | Allowlisted in Dashboard |

The local migration files are, in deployment order:

1. [202607100001_create_leaderboard_public.sql](../supabase/migrations/202607100001_create_leaderboard_public.sql)
2. [202607100002_harden_profile_reads.sql](../supabase/migrations/202607100002_harden_profile_reads.sql)
3. [202607110003_fix_user_state_revision.sql](../supabase/migrations/202607110003_fix_user_state_revision.sql)

Migration `003` fixes a runtime issue found by E2E testing in the original
server-owned revision trigger. The corrected function was first tested inside a
rolled-back transaction, then deployed, then exercised again through the live
PostgREST conditional-update path.

## Live E2E coverage

The production run verified:

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
| `GET /functions/v1/delete-account` | `405` |
| `POST /functions/v1/delete-account` without JWT | `401` |

## Auth and App Review account

- Supabase Dashboard showed the existing web confirmation URL plus the iOS
  callback wildcard, with a successful-save notification and total URL count of
  two on 2026-07-11.
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

The RLS hardening intentionally prevents legacy direct cross-user
`profiles` reads. Existing source clients were updated so this privacy change
does not remain a product regression:

- repository `Eduard047/GymApp` master commit
  `63e47f3ebfb0d4a6db969375b1b6b26fa24e0749` updates Android and PWA to
  authenticated `leaderboard_public`, removes Auth UUIDs from leaderboard rows,
  trusts `is_current_user`, and retires the unsafe monolithic schema entrypoint;
- master commit `2729f4dc2e601be1e4c369c4638d889e9c9fa5f9` moves the
  Android/PWA auth callbacks and public legal URLs to the verified custom domain
  while retaining platform-specific redirect behavior;
- the three migrations copied into that repository use the exact versions from
  production history, preventing migration drift;
- GitHub Pages commit `0147badeb5e8a4d140236af22c8911e699a3429b`
  publishes the current PWA/auth bridge with `app.js?v=28`, `styles.css?v=27`,
  and cache `v37`; and
- the live PWA was verified to contain the new endpoint/tie-break and no old
  direct leaderboard query. Node regression/syntax checks passed 23/23.

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
- `garmin_fetch_pending_plan(text)`: anonymous execution is intentional for the
  Garmin bridge and is gated by an opaque 256-bit device token; the function has
  a fixed empty search path and does not expose broad table access. [Advisor reference](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable)
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
- Supabase Auth Site URL is `https://gymapptracker.com/`. Its five-entry
  redirect allowlist retains the previous GitHub callback and iOS custom-scheme
  fallback alongside the Android, Web, and state-bound iOS HTTPS callbacks.
