# Deployment and release boundaries

GymApp spans public clients, native applications, wearable packages, and a
Supabase backend. A source push, GitHub release, PWA deployment, database
migration, and Edge Function deployment are separate operations.

## Public surfaces

- Web app: <https://gymapptracker.com/>
- Support: <https://gymapptracker.com/support.html>
- Privacy policy: <https://gymapptracker.com/privacy-policy.html>
- Releases: <https://github.com/Eduard047/GymApp/releases>

GitHub Pages publishes the reviewed contents of `pwa/` through the dedicated
`gh-pages` branch. That branch is deployment infrastructure and must not be
deleted as stale source work.

## Authentication redirects

Production authentication uses the first-party HTTPS bridge at
`https://gymapptracker.com/confirmed.html`. Native callbacks accept a bounded,
state-bound PKCE code; reusable access or refresh tokens must never be placed in
a custom-scheme URL.

The legacy callback at
`https://eduard047.github.io/GymApp/confirmed.html` remains an intentional
compatibility entry for older released clients and previously sent emails.
Removing it requires a separately reviewed client and session migration.

## Supabase

- Apply the ordered files in `supabase/migrations/`; do not use the retired root
  `supabase-schema.sql` stub as a deployment source.
- Review RLS, grants, security-definer functions, owner binding, replay handling,
  and concurrency before every migration deployment.
- Deploy `garmin-sync` separately from client publication.
- Complete a valid paired-device fetch/ack smoke before promoting a Garmin cloud
  change to production.

Public Supabase client identifiers are not privileged credentials. Secret keys,
service-role keys, connection strings, raw device tokens, and real account data
must never enter clients, logs, Git, or release assets.

## Store packages

| File | Destination |
| --- | --- |
| `gymapp-phone-release.apk` | Direct Android installation |
| `gymapp-play-release.aab` | Google Play Console |
| `gymapp-garmin-connect-iq.iq` | Garmin Connect IQ Developer Dashboard |
| iOS `.ipa` | App Store Connect; requires Apple Distribution signing |

Android and Garmin updates must retain their historical signing identities.
Signing files stay outside the repository and outside release archives. An iOS
Simulator archive is never an App Store package.

## Security checks

The default branch runs Gitleaks, Semgrep, CodeQL, dependency/SBOM scanning,
Android validation, iOS validation, and cross-platform contract tests. Failed,
cancelled, or skipped security jobs must not be treated as a passing release.

Report vulnerabilities through a
[private GitHub security advisory](https://github.com/Eduard047/GymApp/security/advisories/new).
The full policy is in [`.github/SECURITY.md`](../.github/SECURITY.md).
