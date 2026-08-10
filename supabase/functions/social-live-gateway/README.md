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

The function validates an exact JSON allowlist, calls Supabase Auth `getUser`,
extracts the `session_id` only from that already-verified JWT, commits a durable
service-only perimeter debit in a separate PostgREST transaction, and then:

- calls legacy social RPCs with the same user bearer so their existing
  `auth.uid()`/live-session checks remain authoritative;
- calls live RPCs with the service client and explicit verified
  `(p_caller_user_id,p_session_id)`, which every live RPC rechecks against the
  exact `auth.sessions(id,user_id)` pair.

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
are applied. Legacy direct social grants deliberately remain for released 3.0.4
clients; new clients should use this gateway so rejected-body/domain-error spam
is durably bounded before the domain transaction.
