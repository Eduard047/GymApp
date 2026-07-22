# Garmin capability rollout

The gateway supports two explicit protocol versions during a bounded migration:

- `v2`: the released Connect IQ binaries send the existing 64-character random
  token. It is accepted only while `GARMIN_LEGACY_CAPABILITY_MODE=enabled`, then
  resolved by one indexed token-hash lookup. A nonexistent token creates or
  updates no database or limiter row. A valid token consumes only that device's
  durable bucket.
- `v3`: a 234-character `g3` capability authenticates its account binding,
  device UUID, and random nonce with HMAC before any database lookup. The
  database stores only the nonce hash.

Direct watch RPCs are service-role-only in both modes. The compatibility mode
does not restore anonymous PostgREST execution or shared pre-auth buckets.

## Required secrets and flags

- `GARMIN_CAPABILITY_HMAC_SECRET`: exactly 32 cryptographically random bytes,
  encoded as 64 lowercase hexadecimal characters. Create it in a secret
  manager, inject it directly into Supabase, and retain a protected backup.
  Never print it, put it in a shell-history argument, or write it in this
  repository.
- `SUPABASE_SERVICE_ROLE_KEY`: the Supabase-managed Edge environment value. It
  must never enter the PWA, Garmin package, logs, or diagnostics.
- `GARMIN_LEGACY_CAPABILITY_MODE`: exactly `enabled` for the compatibility
  phase or `disabled` after the retirement gate below. A missing or unknown
  value fails the function closed.

## Phase 1: compatible security rollout

This phase is safe for already-installed 64-character-token watches and is the
only phase to run while the historical Garmin signing key is unavailable.

1. Install the HMAC secret and set `GARMIN_LEGACY_CAPABILITY_MODE=enabled`.
   Confirm the managed service-role key exists in the Edge runtime.
2. Deploy `garmin-sync`. A missing `capabilityVersion` remains the released v2
   browser contract. Before the ACL migration, only an HMAC-valid or
   format-valid legacy request can reach the permission-error-only anonymous
   fallback.
3. Immediately apply
   `20260722012000_secure_garmin_capability_gateway.sql`. It revokes direct
   public/anonymous watch RPC execution, grants the gateway role only, removes
   shared pre-auth buckets, and installs per-device lookup plus hour-coalesced
   v2/v3 usage telemetry.
4. Smoke-test an existing released watch: fetch-empty, enqueue/fetch, exact ACK
   replay, and continued token rotation. Verify direct anonymous PostgREST RPCs
   receive permission denied. Send several random 64-hex tokens and verify no
   device, telemetry, or rate-limit rows are created or changed.
5. Release the matching PWA (`v61` worker). Its explicit
   `GARMIN_CAPABILITY_VERSION = 2` preserves existing bindings and never
   auto-rotates a released watch to `g3`. It still strips any accidentally
   persisted token field from browser storage.

Do not apply the ACL migration before the dual-mode Edge Function is healthy,
and do not deploy the Edge Function before the required flag is installed.

## Phase 2: signed-binary v3 migration and retirement

Do not start this phase until a release-signable Connect IQ binary that accepts
both the released 64-character token and the 234-character `g3` format has
passed device/simulator testing. Dual parsing makes Garmin-first and PWA-first
store rollout order safe.

1. Release that Garmin binary and confirm v3 validates the embedded account and
   device, while v2 validates every non-empty response against the active
   account and binds its returned device before applying or acknowledging it.
2. Change the PWA's `GARMIN_CAPABILITY_VERSION` to `3`, bump the static cache,
   test, and release it. Owner-authenticated create/recovery then rotates the
   stable device UUID to a signed capability and shows it once for re-pairing.
3. Monitor the private migration timestamps. An administrator can use:

   ```sql
   select
     count(*) filter (
       where revoked_at is null
         and legacy_capability_last_seen_at >= now() - interval '30 days'
     ) as legacy_active_30d,
     count(*) filter (
       where revoked_at is null
         and v3_capability_last_seen_at >= now() - interval '30 days'
     ) as v3_active_30d
   from public.garmin_devices;
   ```

4. Keep compatibility through the published support window. Disable legacy
   mode only after `legacy_active_30d` is zero, support has confirmed no
   unrecoverable watches, and the release owner explicitly approves retirement.
5. Set `GARMIN_LEGACY_CAPABILITY_MODE=disabled` and repeat the v2/v3 smoke
   matrix. Legacy create/rotate/fetch/ack then returns `426` before lookup.

## Rollback

During phase 1, keep legacy mode enabled. If the new Edge deployment is
unhealthy, redeploy the reviewed dual-mode bundle with the same HMAC secret;
do not restore anonymous RPC grants or the shared-bucket migration. The SQL
migration is forward-only because recreating those grants/buckets would reopen
the findings.

During phase 2, do not turn off legacy mode as a rollback mechanism. Pause new
v3 pairing, keep both gateway paths available, and roll forward the signed
Garmin/PWA clients. Devices already rotated to v3 must not be silently changed
back without a one-time owner-confirmed re-pair.

## Optional upstream volumetric control

For generic Edge-compute volumetric defense, place the function behind a
managed WAF rule for exact path `/functions/v1/garmin-sync`: allow `POST` and
`OPTIONS` only, cap request bodies at 8 KiB, and rate-limit each source to a
burst of 20 followed by 60 requests per minute. Return `429` without forwarding
blocked requests. This is defense in depth; authorization, isolation, and
write bounds remain enforced by the gateway and database ACL.
