# Security policy

## Reporting a vulnerability

Do not disclose vulnerabilities, credentials, personal data, or reproduction data in a public issue. Use a [private GitHub security advisory](https://github.com/Eduard047/GymApp/security/advisories/new) instead. Include the affected version, impact, reproduction steps, and the smallest safe proof of concept. Remove real user data and reusable credentials before attaching logs or diagnostics.

The current release line and the default branch receive security fixes. Older builds may be asked to upgrade before a report is investigated.

## Required release security checks

Before merging or releasing:

1. Require the `Security Gate` status check on the protected default branch. Do not bypass failed, cancelled, or skipped scanner jobs.
2. Review Gitleaks, Semgrep, CodeQL, and Trivy output. Any exception must be narrowly scoped, documented, and reviewed; never allowlist a whole source or test directory.
3. Review the generated CycloneDX SBOM and investigate new high or critical dependency findings.
4. Keep GitHub Actions pinned to full commit SHAs and review every Dependabot update before merging.
5. Enable GitHub secret scanning, push protection, Dependabot alerts, and Supabase leaked-password protection in their respective service settings.
6. Deploy ordered database migrations and the Edge Function to a non-production Supabase project first. Verify anonymous, owner, other-user, revoked-device, replay, and concurrent-request behavior against the hosted service before production deployment.
7. Configure the PWA host to return `Content-Security-Policy: frame-ancestors 'none'` and `X-Frame-Options: DENY`. Do not cache authenticated responses or user data.
8. Build Android production artifacts only through the signed release process. Never publish debug APKs, debug components, diagnostics, local databases, backups, or signing material.
9. Verify application IDs, version codes, signing identity, included components, and artifact checksums before uploading release assets.
10. Complete phone and Garmin physical-device tests for account switching, replay, interrupted synchronization, and re-pairing before promoting a release.

The automated pipeline intentionally has no DAST job until a dedicated staging URL exists. Automated scanners complement, but do not replace, hosted authorization tests and manual security review.
