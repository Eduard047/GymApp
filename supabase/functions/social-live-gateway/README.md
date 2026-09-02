# `social-live-gateway` Edge Function

Authenticated bounded gateway for the friend/static-workout API and the new
service-only live-workout API. The exact request envelope is:

```json
{
  "version": 1,
  "action": "live_snapshot",
  "payload": { "roomId": "lr_<32hex>" }
}
```

After method, content-type, origin, and bearer-shape checks, the function calls
Supabase Auth `getUser`, extracts the `session_id` only from that
already-verified JWT, and commits a durable SHA-256-pseudonymized per-session
gateway-validation debit in a separate PostgREST transaction. Only then does it
read the byte/chunk-bounded JSON body and validate the exact route/payload
allowlist, so over-size, malformed, and semantically rejected authenticated
requests consume the same perimeter budget. It then:

- calls legacy social RPCs with the same user bearer so their existing
  `auth.uid()`/live-session checks remain authoritative and debit the same
  shared domain aggregate and gateway-action budgets inside the domain
  transaction;
- calls live RPCs with the service client and explicit verified
  `(p_caller_user_id,p_session_id)`, which every live RPC rechecks against the
  exact `auth.sessions(id,user_id)` pair after a separate shared aggregate and
  action debit.

Success is gateway-wrapped as `{ "version": 1, "result": <DB JSON> }`. Stale CAS
is `409 {"error":"conflict"}`; a hidden/unavailable private object is 404;
validation rejection is 400; perimeter exhaustion is 429 with a bounded
`retryAfter`. Responses and errors contain no internal IDs or exception text.

Required environment:

- `SUPABASE_URL`;
- a publishable/anon key for the user-context client;
- a secret/service-role key for only the debit and service-only live RPCs;
- `SOCIAL_LIVE_ALLOWED_ORIGIN` set to the exact production PWA origin. Native
  requests have no `Origin`; browser origins fail closed when it is absent or
  different.

Keep `verify_jwt=true`. Deploy only after the perimeter and live API migrations
are applied. Direct social grants remain for released clients, but their
database authorization boundary now debits the same per-session aggregate and
gateway-action buckets used by service-only live routes. Direct PostgREST calls
therefore cannot bypass the shared resource allowance. Expected validation and
domain rejections retain one aggregate debit instead of rolling it back; the
existing domain authorization and per-action limits remain defense in depth.
