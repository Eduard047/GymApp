# `delete-account` Edge Function

Authenticated, irreversible deletion of the caller's own Supabase Auth user. The function has no runtime package dependencies.

Production deployment record: version 1 is `ACTIVE` with `verify_jwt=true` in
project `owrcbsrectdgaotndtxy` as of 2026-07-11. Its deployed source hash is
`aefae8ab079463f2f3b13c7267b7f3f8073198340a7ad442253e5efed97a53d7`.

Security properties:

- accepts only `POST` with `Content-Type: application/json`;
- requires the exact body `{ "confirmation": "DELETE" }` and rejects extra fields;
- verifies the caller's bearer token with `GET /auth/v1/user` using a publishable/anon key;
- obtains the user ID only from that verified response — no user ID is accepted from the client;
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

Optional:

- `DELETE_ACCOUNT_ALLOWED_ORIGIN=https://your-web-app.example` enables browser preflight for exactly that origin. Native iOS requests don't require CORS. When unset, browser preflight is denied.

Keep the platform's per-function `verify_jwt` setting enabled (the default). The function still performs the requested authoritative `/auth/v1/user` verification before the admin call.

## Request

```http
POST /functions/v1/delete-account
Authorization: Bearer <user-access-token>
Content-Type: application/json

{"confirmation":"DELETE"}
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

This production preflight passed on 2026-07-11 with two disposable accounts.
The live function passed wrong-method, missing/invalid JWT, media-type, body-shape,
confirmation, size, and browser-origin checks before hard deletion. SQL checks
then confirmed zero remaining Auth identity, profile, cloud-state, Garmin, or
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
supabase functions serve delete-account
```

Positive request (use a disposable local test account):

```sh
curl -i \
  -X POST 'http://127.0.0.1:54321/functions/v1/delete-account' \
  -H 'Authorization: Bearer <disposable-user-access-token>' \
  -H 'Content-Type: application/json' \
  --data '{"confirmation":"DELETE"}'
```

Also test missing/invalid bearer token, wrong method, non-JSON media type, malformed JSON, wrong confirmation, extra fields, oversized body, upstream Auth failure, Storage ownership failure, and repeat deletion. Never use a real customer account for these tests.
