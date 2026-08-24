# Supabase deployment notes

## Canonical repository sources

The iOS subtree contains historical migrations only. The canonical account
deletion Edge Function now lives at the repository root:
[delete-account](../../../supabase/functions/delete-account/README.md). Do not
restore a platform-local function copy.

## Current production metadata snapshot — read-only 2026-08-24

The canonical production history contains 54 migrations through
`20260823162119_fix_security_hardening_coalesce_calls`. Active Edge Function
metadata is `garmin-sync` version 12 (`verify_jwt=false`), `delete-account`
version 14 (`verify_jwt=true`), `social-live-gateway` version 6
(`verify_jwt=true`), and `push-dispatch` version 5 (`verify_jwt=false`). The
repository-root chain has two reviewed local-only forward migrations:
`20260824120000_sync_activity_only_workouts.sql` and
`20260824123000_harden_remaining_supabase_boundaries.sql`. Neither is deployed;
production therefore does not yet match the complete canonical local chain.

This metadata readback does not replace the dated functional evidence below.
After any backend release, rerun the exact-session, cross-account, replay,
account-switch, deletion-cascade, Garmin-device, and physical-device gates that
apply to the changed boundary.

## Historical production deployment record — 2026-07-22

> The canonical current migrations live in the repository-root
> `supabase/migrations/` directory. On 2026-07-22 production history was
> reconciled and read back with all 22 repository versions through
> `20260722013200_activate_bounded_user_state_projection.sql`. The live Auth,
> state projection, Garmin delivery, and account-deletion E2E passed with
> disposable data.

GymApp production project `owrcbsrectdgaotndtxy` has the verified baseline
below:

- `20260711084556` — `create_leaderboard_public`;
- `20260711084559` — `harden_gymapp_production_access`;
- `20260711090358` — `fix_user_state_revision_trigger`;
- `20260721142924` — `canonical_profile_progression`;
- `20260721142935` — `harden_garmin_pairing_and_plans`;
- `20260721142942` — `reconcile_canonical_progression`;
- `20260721142951` — `add_garmin_device_rate_limits`;
- `20260721143010` — `create_exercise_catalog`;
- `20260721143038` — `restrict_leaderboard_to_owner_until_verified_ingestion`;
- `20260721143058` — `add_bounded_garmin_preauth_rate_limits`;
- `20260721143853` — `retire_legacy_garmin_table_grants`;
- `20260721201016` through `20260722013200` — catalog, RLS guard,
  live-session deletion, bounded reports, Garmin capability gateway, and
  bounded state-projection updates;
- Edge Function `garmin-sync` version 6 is `ACTIVE` with `verify_jwt=false` by
  design: account-management actions validate the bearer user inside the
  function, while watch fetch/ack actions authenticate a bounded device
  capability; and
- Edge Function `delete-account` version 3 is `ACTIVE` with `verify_jwt=true`;
  its live-session migration and canonical deployment are verified and the
  repository release gate passes.

A live two-user E2E run passed authenticated leaderboard access, own-row RLS,
cross-user mutation denial, display-name/public-ID guards, report isolation,
stale-revision behavior, Android-style upsert, Edge Function negative cases,
hard deletion, and cascade cleanup. Both disposable accounts and every dependent
test row were removed. The repeatable evidence record is
[PRODUCTION_BACKEND_VERIFICATION.md](../AppStore/PRODUCTION_BACKEND_VERIFICATION.md).
The iOS Auth callback is also allowlisted; same-device confirmation/recovery still
requires final testing on a physical iPhone.

The files in this local [migrations](migrations/) directory preserve the iOS
deployment history from 2026-07-11. They are not the current canonical migration
set. For any new environment, apply every migration in the repository-root
`supabase/migrations/` directory in timestamp order, including the owner-only
compatibility migration.

The historical iOS migration copies are:

1. [202607100001_create_leaderboard_public.sql](migrations/202607100001_create_leaderboard_public.sql)
2. [202607100002_harden_profile_reads.sql](migrations/202607100002_harden_profile_reads.sql)
3. [202607110003_fix_user_state_revision.sql](migrations/202607110003_fix_user_state_revision.sql)

The third corrects the server-owned revision trigger and must not be omitted.
Do not treat this three-file list as sufficient for a fresh deployment. Use the
normal Supabase migration workflow from the repository root and never put a
service-role/secret key in either native app or this repository.

## Historical leaderboard privacy and moderation migration

`202607100001_create_leaderboard_public.sql` adds the server pieces needed for a
UUID-free, reportable leaderboard, and
`202607100002_harden_profile_reads.sql` removes cross-user reads from the base
profile table:

- a random immutable `profiles.public_id` such as
  `p_88edfa8180314e209821cc9e208ae641`, unrelated to `auth.users.id`;
- authenticated read-only `public.leaderboard_public`;
- server-side display-name normalization and safety filtering;
- server-only `leaderboard_blocked_terms` that moderators can extend; and
- authenticated insert-only `leaderboard_reports`, with no client read/update/
  delete access.

The leaderboard endpoint is:

```http
GET /rest/v1/leaderboard_public
  ?select=profile_id,display_name,xp,level,workouts,is_current_user
```

`profile_id` is safe to use for report and on-device hide actions. It is not the
Supabase Auth UUID and is not derived from it. The caller UUID is used inside the
database solely to calculate `is_current_user`; no Auth UUID is returned.

The public view is backed by a fixed `SECURITY DEFINER` function with no arguments
or dynamic SQL, then wrapped in a `security_invoker`/`security_barrier` view. This
lets the projection remain available after cross-user direct `profiles` reads are
removed, while limiting its output to the six reviewed fields. Anonymous access
is revoked and authenticated clients receive `SELECT` only.

### Display-name safety behavior

The profile trigger applies on every new profile and every `display_name` change.
For authenticated client writes it:

- trims and collapses whitespace;
- requires 2–40 characters and at least one letter or number;
- rejects control/zero-width characters, links, email/social handles, and names
  containing seven or more digits;
- rejects seeded high-risk English, Ukrainian/Russian, and brand-impersonation
  terms; and
- prevents clients from choosing or changing `profiles.public_id`.

If an internal `auth.users` signup trigger creates a profile before an authenticated
JWT exists and supplies an unsafe/missing name, the guard stores `GymApp user`
instead of aborting the Auth transaction. It never stores the unreviewed value.

Existing Android names are not destructively rewritten during migration. The new
view replaces a legacy unsafe name with `GymApp user`; the next attempt to save
that profile requires a safe name. `leaderboard_blocked_terms` has RLS enabled and
no `anon`/`authenticated` privileges. Only trusted moderation code using the
service role may maintain it. A static blocklist is one moderation layer, not a
substitute for in-app report/hide controls and an operational response process.

### Report API contract

The client submits only the stable public profile ID and one fixed reason:

```http
POST /rest/v1/leaderboard_reports
Prefer: return=minimal
Content-Type: application/json

{"reported_profile_id":"p_...","reason":"inappropriate_name"}
```

Allowed reasons are:

- `inappropriate_name`
- `hate_or_harassment`
- `impersonation`
- `spam_or_scam`
- `personal_information`
- `other`

The database derives `reporter_user_id` from `auth.uid()`, rejects self-reports,
snapshots the server-filtered display name, and forces a new report to `pending`.
A uniqueness constraint limits each reporter to one report per target, reason, and
snapshotted name, while allowing a later changed name to be reported again.
Both reporter deletion (`auth.users`) and target profile deletion cascade to the
report. Client roles have `INSERT` on only `reported_profile_id` and `reason`; RLS
allows only rows bound to the caller, and there is deliberately no client `SELECT`,
`UPDATE`, or `DELETE` policy/grant. `return=representation` will therefore fail;
native clients must use `return=minimal`.

Trusted moderation tooling may use `service_role` to read pending reports and set
`status` to `reviewed`, `actioned`, or `dismissed`. Keep that key server-side.
The queue owner, daily/24-hour response target, action/escalation steps, reporter
feedback path, and 90-day resolved-report retention procedure are documented in
[MODERATION_RUNBOOK.md](../AppStore/MODERATION_RUNBOOK.md). The assigned owner must
continue monitoring; the database alone does not satisfy App Review guideline 1.2.

### Prerequisites

The existing `public.profiles` table must contain:

- `user_id` (the Supabase Auth UUID),
- `display_name`,
- `xp`,
- `level`, and
- `workouts`.

The migration fails with an explicit message if the table or a required column is
missing. It adds rather than replaces schema, so current Android profile writes
that omit `public_id` continue to receive a server-generated value. It does revoke
direct client `DELETE` on `profiles`, because delete/recreate would rotate the
public ID and bypass reports or local hides. Account deletion must use the existing
privileged server flow; deleting `auth.users` still cascades through profile and
report foreign keys.

### Historical deployment and verification

1. Back up production and inspect the migration command supported by the installed
   CLI (`supabase --version` and `supabase db push --help`).
2. Apply every canonical migration from the repository-root
   `supabase/migrations/` directory in timestamp order with the project's normal
   migration workflow. Do not deploy only these historical iOS copies. Reload
   the PostgREST schema cache if the project does not do so automatically.
3. Verify every existing profile has a unique `p_` public ID and the view exposes
   exactly: `profile_id`, `display_name`, `xp`, `level`, `workouts`, and
   `is_current_user`.
4. With two disposable users, verify `leaderboard_public` returns only the
   caller's own row with `is_current_user = true`; neither user can discover the
   other's row through the view or direct `profiles` reads. Verify legacy report
   rows remain private, neither user can change either public ID or directly
   delete its profile, and anonymous `SELECT`, `INSERT`, `UPDATE`, and `DELETE`
   against `profiles` remain denied at the table privilege layer.
5. Verify unsafe names are rejected on insert/update and legacy unsafe names are
   replaced by `GymApp user` in the view. Add and remove a harmless test term with
   trusted SQL to verify blocklist updates take effect.
6. Delete each disposable account in turn and confirm related report rows cascade.
7. Test iOS protected progress and confirm a legacy Android build can still
   read/upsert its own profile while the compatibility view returns only the
   signed-in user's row. The public-leaderboard behavior described earlier in
   this document passed production testing on 2026-07-11. The owner-only
   structural/ACL and rollback-only runtime checks passed on 2026-07-21; native
   client end-to-end coverage remains a separate release check.

Useful database checks:

```sql
select count(*) as profiles,
       count(public_id) as with_public_id,
       count(distinct public_id) as distinct_public_ids
from public.profiles;

select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'leaderboard_public'
order by ordinal_position;

select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in (
    'profiles',
    'leaderboard_public',
    'leaderboard_reports',
    'leaderboard_blocked_terms'
  )
order by table_name, grantee, privilege_type;
```

Expected leaderboard smoke test (use a disposable user's short-lived token):

```sh
curl --fail-with-body \
  "$SUPABASE_URL/rest/v1/leaderboard_public?select=profile_id,display_name,xp,level,workouts,is_current_user&order=xp.desc&limit=50" \
  -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
  -H "Authorization: Bearer $DISPOSABLE_USER_ACCESS_TOKEN"
```

Legacy-only report smoke test for unresolved rows created before cross-account
standings were disabled; this is not part of the current client acceptance flow:

```sh
curl --fail-with-body \
  -X POST "$SUPABASE_URL/rest/v1/leaderboard_reports" \
  -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
  -H "Authorization: Bearer $DISPOSABLE_USER_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=minimal" \
  --data '{"reported_profile_id":"<other-profile-id>","reason":"inappropriate_name"}'
```

## Required UUID hardening and legacy Android behavior

`202607100002_harden_profile_reads.sql` is the required second migration, not a
deferred cleanup. It removes the known broad `Leaderboard is public` policy,
revokes every anonymous base-table privilege, and recreates authenticated
own-profile `SELECT`, `INSERT`, and `UPDATE` policies using
`auth.uid() = user_id`. It fails closed if any other `public.profiles` policy is
present or one of those policies is assigned to another role; review and narrow
the policy before retrying instead of bypassing the audit. Direct legacy
column-level grants are revoked too; effective-privilege checks also fail the
migration if `anon` or `authenticated` inherits a forbidden capability through
an unexpected group role.

### Behavior before the owner-only forward migration

After only historical migrations `001`, `002`, and `003` are deployed:

- iOS reads the complete sanitized cross-user leaderboard from
  `leaderboard_public`, keyed by random `profile_id`; it never needs another
  user's Auth UUID;
- an already-installed legacy Android build that still reads `public.profiles`
  receives only the signed-in user's own row, so its old leaderboard temporarily
  degrades to a single current-user entry instead of exposing other users' UUIDs;
  current Android source was updated in commit `63e47f3e…`; and
- legacy Android profile writes can continue because authenticated users retain
  `INSERT`/`UPDATE`, subject to the existing ownership RLS policies.

Android source now reads `leaderboard_public` and uses `profile_id` plus
`is_current_user`; the hosted PWA was updated in `gh-pages` commit
`a3d9a7b9…`. Until an updated Android release is distributed, the one-row
installed-client leaderboard is an intentional privacy-safe degradation. Do not
restore broad profile reads as a compatibility workaround.

After the canonical forward migration
`20260721143038_restrict_leaderboard_to_owner_until_verified_ingestion.sql` is
deployed, `leaderboard_public` preserves the same six fields but returns only the
authenticated owner's row. Current Android, iOS, and PWA clients additionally
filter out any non-owner row. Competitive standings remain disabled until GymApp
has a trusted append-only award source.

Before any deployment or release, verify that authenticated profile writes remain limited to
`auth.uid() = user_id`, with both `USING` and `WITH CHECK` on the update policy,
and that the `user_id` uniqueness constraint used by `on_conflict=user_id`
remains. Run the real `return=minimal` upsert in staging because PostgREST
permissions depend on the exact query shape. Confirm `anon` and `PUBLIC` have no
table privileges on `profiles`, authenticated clients have no direct `DELETE`,
and a disposable user cannot select a second user's `user_id` directly.

## Optimistic cloud-state writes

The iOS sync client loads `user_states.updated_at` as a revision and updates with
both `user_id` and the exact prior revision in the `PATCH` filter. The production
`public.user_states` schema must therefore satisfy all of these:

- `user_id` has a unique or primary-key constraint (so concurrent first inserts
  conflict instead of creating two rows);
- `updated_at` is a non-null timestamp revision, changes on every successful write
  without truncating away the change, and every write returns its stored value;
- `authenticated` has only the required `SELECT`, `INSERT`, and `UPDATE` grants;
- RLS permits selecting and inserting only `auth.uid() = user_id`; and
- the update policy has both `USING ((select auth.uid()) = user_id)` and
  `WITH CHECK ((select auth.uid()) = user_id)`.

In staging, load one row from two independent sessions, save from the first, and
then issue the second session's stale conditional `PATCH` with
`Prefer: return=representation`. The second response must contain zero rows, which
the client treats as a conflict; it must not overwrite the first save. Also test
two simultaneous first writes: one insert must succeed and the other must conflict.

Official background: [Supabase Data API security](https://supabase.com/docs/guides/api/securing-your-api),
[views and `security_invoker`](https://supabase.com/docs/guides/database/tables#view-security),
and [row-level security](https://supabase.com/docs/guides/database/postgres/row-level-security).
