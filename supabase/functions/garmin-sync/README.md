# Garmin capability gateway

## Active protocol: signed v3 only

Legacy v2 capability support is removed from the Edge handler. There is no
deployment flag that can restore it. A missing or explicit v2 pairing/rotation
request and a raw 64-character watch token return `426` before authentication,
SDK client construction, PostgREST, or database access.

The supported `g3` capability authenticates its account binding, device UUID,
and random nonce with HMAC before any database lookup. PostgreSQL stores only
the nonce hash. Direct watch RPCs remain service-role-only.

Required server secrets:

- `GARMIN_CAPABILITY_HMAC_SECRET`: exactly 32 cryptographically random bytes,
  encoded as 64 lowercase hexadecimal characters. Keep it in a secret manager,
  retain a protected backup, and never print or store it in this repository.
- `SUPABASE_SERVICE_ROLE_KEY`: the Supabase-managed Edge value. It must never
  enter the PWA, Garmin package, logs, or diagnostics.

Retirement does not delete devices, pending plans, or workout history. The
owner of a retired token must use device recovery in a current client and move
the replacement signed capability to a compatible Garmin app. Recovery keeps
the device UUID and remains bound to the current account and exact Auth session.

Before deployment, verify all of the following:

1. Raw tokens and missing/explicit v2 create or rotate requests return `426`
   without any SDK or RPC call.
2. Forged or malformed v3 capabilities fail before database access.
3. A dedicated account completes v3 idempotent create, enqueue, fetch, exact
   ACK replay, rotation, recovery, and revocation.
4. Direct anonymous/authenticated execution of watch capability RPCs remains
   denied.
5. A revoked exact Auth session cannot commit owner mutation or mint/rotate a
   durable capability after the revocation transaction.

The executable handler regressions live in
`tests/garmin-legacy-retirement.test.mjs`. Unit tests cannot prove deployed
secrets, database ACLs, or a physical watch handoff, so repeat the signed-client
smoke after the database migration and Edge bundle are deployed.

## Rollback

Do not restore v2 parsing, a legacy flag, anonymous RPC grants, or shared
pre-auth buckets. Pause new pairing and roll forward the signed Garmin/PWA
clients. A v3 capability must never be silently downgraded.

## Optional upstream volumetric control

For generic Edge-compute defense in depth, place exact path
`/functions/v1/garmin-sync` behind a managed rule: allow only `POST` and
`OPTIONS`, cap bodies at 8 KiB, and apply a source rate limit before Edge
execution. Authorization, owner isolation, input bounds, and per-device limits
remain enforced by the gateway and database.
