# `delete-account` Edge Function

Authenticated, irreversible deletion of the caller's own Supabase Auth user. The function has no runtime package dependencies.

This repository-root directory is the canonical source of truth. Do not add a
second function copy under a platform directory. The machine-readable
[deployment contract](deployment-contract.json) pins the reviewed source hash,
the last observed production version, and the release gate.

Last observed production deployment: version 13 was `ACTIVE` with
`verify_jwt=true` in project `owrcbsrectdgaotndtxy` on 2026-08-23. Its deployed
source has SHA-256
`18bf031b874e7efde9b9473979b173158b187b46c7f12ee5f023bcc51a5a4f3d`.
Repository contract 4 has canonical source SHA-256
`74617de1dbaba0b6103b04d1461a46ddd597d1df0e735b0a21a23d38d0556ab4`;
the release gate remains closed until that source is deployed and read back.
The one-time reauthentication grant, durable pre-authentication budget, HMAC
secret, and service-only wrapper were applied and read back; the deployment
contract release gate is open.

Security properties:

- accepts only `POST` with `Content-Type: application/json`;
- accepts only the exact prepare body `{ "action": "prepare" }` or delete body `{ "action": "delete", "confirmation": "DELETE", "grant": "<uuid>" }`;
- durably meters requests by an HMAC-pseudonymized network source before Auth validation;
- verifies the caller's bearer token and current Auth user with `GET /auth/v1/user` using a publishable/anon key;
- preparation requires a password-authenticated JWT no older than five minutes and issues a five-minute capability bound to the exact user and Auth session;
- deletion atomically consumes that one-time capability while locking and validating the same live Auth session;
- requires the Auth user UUID and consumed-grant RPC UUID to match exactly before deletion;
- hard-deletes that exact user through `DELETE /auth/v1/admin/users/{id}` with a new Supabase secret key or the legacy `SUPABASE_SERVICE_ROLE_KEY`;
- never logs tokens, keys, request bodies, email addresses, or upstream error bodies;
- returns bounded, generic errors with `Cache-Control: no-store`;
- rejects browser-origin requests unless one exact origin is configured and matched; native iOS requests do not send a browser `Origin` header.

Official references: [Supabase Edge Function auth](https://supabase.com/docs/guides/functions/auth), [authorization headers](https://supabase.com/docs/guides/functions/auth-headers), [function secrets](https://supabase.com/docs/guides/functions/secrets), [admin deleteUser](https://supabase.com/docs/reference/javascript/auth-admin-deleteuser), and [user deletion caveats](https://supabase.com/docs/guides/auth/managing-user-data#deleting-users).

## Environment

Required:

- `SUPABASE_URL`
- one of `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_PUBLISHABLE_KEYS` (JSON containing a `default` or other named key), or legacy `SUPABASE_ANON_KEY`
- one of `SUPABASE_SECRET_KEY`, `SUPABASE_SECRET_KEYS` (JSON containing a `default` or other named key), or legacy `SUPABASE_SERVICE_ROLE_KEY` — server-only; never put any of these values in the iOS app, source control, screenshots, Review Notes, or client logs
- `GATEWAY_PREAUTH_HMAC_SECRET` — 32 random bytes encoded as 64 hexadecimal characters; server-only

Optional:

- `DELETE_ACCOUNT_ALLOWED_ORIGIN=https://your-web-app.example` enables browser preflight for exactly that origin. Native iOS requests don't require CORS. When unset, browser preflight is denied.

Keep the platform's per-function `verify_jwt` setting enabled (the default). The
function retains its `/auth/v1/user` validation, then atomically consumes the
one-time grant immediately before the admin call. Both grant RPCs are available
only to `authenticated`, use an empty search path, and derive the user/session
identity exclusively from signed JWT claims.

## Request

```http
POST /functions/v1/delete-account
Authorization: Bearer <user-access-token>
Content-Type: application/json

{"action":"prepare"}
```

After a successful fresh password sign-in, preparation returns a five-minute
`grant`. Send it once with:

```json
{"action":"delete","confirmation":"DELETE","grant":"<uuid>"}
```

Success:

```json
{"deleted":true}
```

The client should then erase its local session and cached account data and return to the signed-out state. Supabase notes that deleting an Auth user does not automatically invalidate already-issued JWTs before they expire.

## Mandatory data-deletion preflight

This function deletes the Auth user. Before shipping the in-app deletion UI, verify all associated data is actually removed:

1. Foreign keys from app-owned rows to `auth.users(id)` use the intended `ON DELETE CASCADE`, or the server deletes those rows before the Auth user.
2. The user owns no Supabase Storage objects at deletion time. Supabase Auth refuses to delete a user who still owns Storage objects; add explicit cleanup if GymApp stores uploads.
3. Data in private schemas, logs, backups, email systems, support tools, analytics, and other processors follows the retention disclosed in the privacy policy.
4. A test account deletion removes Auth, profile, workout, progress, and storage records while preserving only data that law requires you to retain.
5. The app clears its local Keychain/session and UserDefaults account data after a successful response.

This production preflight passed again on 2026-07-22 with a disposable account
that owned a profile, cloud state/projection, Garmin device, and two plans. The
live function passed confirmation, browser-origin, missing/terminal JWT, replay,
login, and refresh checks before and after hard deletion. SQL checks then
confirmed zero remaining Auth user, profile, cloud-state/projection, Garmin, or
moderation-report rows. Production Storage contained zero objects. Repeat the
preflight after any schema, Storage, processor, Auth, or function change.

## Local development verification

Discover the installed CLI syntax first because it changes over time:

```sh
supabase --version
supabase functions serve --help
```

Then run a type check and serve locally:

```sh
deno check supabase/functions/delete-account/index.ts
node --test tests/delete-account-edge-contract.test.mjs
node --test tests/delete-account-session-security.test.mjs
supabase functions serve delete-account
```

The normal contract test checks the pinned production snapshot against the
repository contract. The enforced release check is expected to fail until the
new contract is deployed and read back:

```sh
GYMAPP_ENFORCE_SUPABASE_RELEASE_GATE=1 \
  node --test tests/delete-account-edge-contract.test.mjs
```

After any later explicitly authorized deployment, read back the migration
history, function version, source hash, and `verify_jwt` setting. Update
`deployment-contract.json` only from that evidence; the enforced release check
must keep passing.

Positive request (use a disposable local test account):

```sh
curl -i \
  -X POST 'http://127.0.0.1:54321/functions/v1/delete-account' \
  -H 'Authorization: Bearer <disposable-user-access-token>' \
  -H 'Content-Type: application/json' \
  --data '{"action":"prepare"}'
```

Also test missing/invalid bearer token, a globally signed-out or administratively
revoked session whose JWT has not yet expired, wrong method, non-JSON media type,
malformed JSON, wrong confirmation, extra fields, oversized body, grant RPC
failure, Storage ownership failure, and repeat deletion. Never use a real customer
account for these tests.
