# `push-dispatch` Edge Function

Server-only dispatcher for the private provider-neutral notification outbox. It
claims bounded leased deliveries through service-role-only RPCs, sends a minimal
static notification through FCM HTTP v1, APNs, or Web Push, and then atomically
records success, retry, permanent failure, or invalid-registration revocation.
It is not a browser/client API.

A production metadata readback after the approved 2026-08-24 database rollout
found `push-dispatch` version 5 `ACTIVE` with `verify_jwt=false` and 57
migrations through `20260824180727`. The configured Vault/provider and
successful dispatcher/monitor empty-queue evidence was observed on 2026-08-10
against version 4; it
was not rerun merely because later metadata was read. The production tables then
contained no registered installations or queued deliveries, so that evidence
proved only the authenticated empty-queue path. Physical APNs/FCM/Web Push
receipt, account switching, revocation, and tap routing remain release-device
checks.

## Required server secrets

- `PUSH_DISPATCH_SERVER_KEY`: a dedicated 32-or-more-byte random value encoded
  as base64url (43-256 characters). Configure it as an Edge Function secret and
  store the exact same value in Vault as `gymapp_push_dispatch_server_key` for
  the scheduler's `apikey` header. It must never be a Supabase secret/service-
  role key or be copied into a browser or native client.
- `PUSH_DISPATCH_TOKEN`: 32 or more random bytes encoded base64url (43-256
  characters). Store the same independent value in Vault as
  `gymapp_push_dispatch_token`; the scheduler sends it only in
  `X-GymApp-Push-Dispatch-Token`. Never put it in a client or URL.
- `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`: Firebase project ID
  and a narrowly managed service-account identity/private PKCS#8 PEM capable of
  Firebase Cloud Messaging HTTP v1. Enable the Firebase Cloud Messaging API.
- `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`: Apple
  Developer team/key IDs, APNs `.p8` PKCS#8 PEM, and the exact app topic
  `com.setforge.gymapp.ios`. Keep the key in a secret manager; it is not the
  client provisioning profile.
- `WEBPUSH_VAPID_PUBLIC_KEY`, `WEBPUSH_VAPID_PRIVATE_KEY`, `WEBPUSH_CONTACT`:
  one durable P-256 VAPID key pair (raw 65-byte public and raw 32-byte private,
  base64url) and a valid `mailto:` or HTTPS operator contact. Only the public
  key is copied into the PWA subscription code.
- `SUPABASE_URL` and one of `SUPABASE_SECRET_KEY`, `SUPABASE_SECRET_KEYS`, or
  legacy `SUPABASE_SERVICE_ROLE_KEY`, supplied by the trusted Edge runtime and
  used only for the function's internal Supabase RPC calls. Never copy these
  internal credentials into Vault or a scheduler request header.

Provider configuration is loaded only for the providers actually present in a
claimed batch. A missing APNs or FCM setup therefore cannot block configured
Web Push deliveries (and vice versa); rows for the unavailable provider receive
a bounded retry without exposing configuration details.

## Scheduled request

Supabase `verify_jwt=false` is intentional for this server-only function. The
function itself compares the exact `apikey` to `PUSH_DISPATCH_SERVER_KEY` and
independently compares the dispatcher token in constant time before parsing or
claiming work. It fails closed if the dedicated server key is missing, malformed,
or equal to the internal Supabase service key. The Vault values are:

- `gymapp_push_dispatch_url`: the exact HTTPS function URL;
- `gymapp_push_dispatch_server_key`: the dedicated
  `PUSH_DISPATCH_SERVER_KEY`, not any Supabase API key;
- `gymapp_push_dispatch_token`: the independent `PUSH_DISPATCH_TOKEN`.

The scheduled call does not send an `Authorization` header because gateway JWT
verification is disabled and the function authenticates the dedicated key only
from `apikey`. A typical batch request is:

```http
POST /functions/v1/push-dispatch
apikey: <PUSH_DISPATCH_SERVER_KEY>
X-GymApp-Push-Dispatch-Token: <independent-random-secret>
Content-Type: application/json

{"version":1,"batchSize":10}
```

Invoke once per minute and alert on non-2xx responses. A batch is capped at ten
deliveries and processed by one global five-worker pool; its 240-second database
lease exceeds the scheduler's 120-second HTTP timeout. Database leases and
provider collapse keys make overlap/retry safe, but provider delivery is still
at-least-once. The bundled cron migration also re-enables/repairs the named job
deterministically and deletes at most 5,000 history rows older than seven days
per maintenance run.

The scheduler stores only request ID, timestamps, final status class, and HTTP
status in the RLS-enabled private `gymapp_private.push_dispatch_requests`
table. A second minute job resolves at most 100 asynchronous `pg_net` results;
requests without a response after five minutes are marked `missing`. No URL,
header, token, request/response body, or provider error string is copied. After
deployment, alert from trusted database monitoring on recent `failed`,
`timed_out`, or `missing` rows; a successful `cron.job_run_details` row alone
only proves that the asynchronous request was queued.

## Payload and privacy contract

The provider-visible data is deliberately opaque:

- live: `{version:1,bindingId,kind,roomId,roomRevision}` where `kind` is one of `invite`,
  `joined`, `started`, `participant_finished`, `room_closed`;
- other social events: `{version:1,bindingId,type,objectId,objectRevision}`.

`bindingId` is a random, revocable installation generation, not an account or
session identifier. The PWA service worker checks it against its account-bound
IndexedDB record before showing a notification and again before handling a
click. Titles/bodies are static English/Ukrainian/Russian strings selected from
the installation locale. Payloads never include a name, email, user/session
UUID, workout plan, exercise, weight, repetitions, progress, bearer, or
arbitrary URL. Clients route only allowlisted `kind`/`type` values to their own
social or live screen.

Each signed-in client should re-register its stable installation on launch/token
refresh. The dispatcher scrubs an address after 180 days without a heartbeat,
keeps terminal outbox diagnostics for 30 days, and removes an unreferenced
revoked installation tombstone after 30 days.

## Provider/client release state

Android contains the Firebase Messaging dependency, a private data-only
`FirebaseMessagingService`, account/session/installation/binding fencing,
durable token reconciliation, notification channel `gymapp_social`, and
allowlisted tap routing. The project-specific `google-services.json` remains an
external mode-0600 build input and is never committed. Both configured and
fail-closed unconfigured builds pass; a physical Android device is still needed
to prove FCM receipt, Android 13+ permission states, revocation, account switch,
and tap behavior.

iOS contains the Push Notifications capability, environment-selected
`aps-environment` entitlement, `remote-notification` background mode, APNs
registration/delegate, strict data-only parsing, account/binding fencing, local
notification display, and allowlisted tap routing. The App Store provisioning
profile and production provider key are configured outside source. No iPhone is
registered for a development profile, so sandbox and production delivery/tap
behavior remain unverified on a signed physical device; simulator and archive
success are not APNs delivery proof.

The PWA implements user-triggered `PushManager.subscribe`, account-bound
registration/revocation, strict service-worker `push` validation, and an
allowlisted same-origin `notificationclick` route. The reviewed public VAPID
key must match the private Edge secret before deployment. Subscription material
and authenticated registration responses are never cached by the service
worker.

Update the privacy policy/store disclosures before release to state that push
delivery addresses are processed by Google, Apple, Mozilla/Microsoft/browser
push services as applicable, are account-bound, and are deleted/scrubbed on
revocation/account deletion.

## Local verification

```sh
deno check --config supabase/functions/push-dispatch/deno.json \
  supabase/functions/push-dispatch/index.ts
deno test --config supabase/functions/push-dispatch/deno.json \
  supabase/functions/push-dispatch/providers_test.ts
node --test tests/push-backend-security.test.mjs
```

Before changing the deployed contract, run a fresh local Supabase reset and
synthetic owner/wrong-owner/session-revocation/lease/retry tests. The current
production deployment was verified with catalog/grant readback and bounded
empty-queue dispatcher smokes; the pgTAP suite has not yet run in a disposable
PostgreSQL environment. A source parser cannot prove grants, triggers, or
concurrency.
