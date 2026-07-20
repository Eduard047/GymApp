# GymApp — App Store release checklist

Status date: 2026-07-20. Apple changes requirements over time; recheck [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/) and the current [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) before every submission.

## 1. Manual ownership, team, signing, and identifiers

- [x] **Apple Developer legal owner:** Martynenko Eduard.
- [ ] **Apple Team ID:** replace `REPLACE_WITH_APPLE_TEAM_ID` in [ExportOptions.plist](ExportOptions.plist) and select the same Team in the GymApp target's Signing & Capabilities pane.
- [ ] **Bundle ID:** the project uses `com.setforge.gymapp.ios`; register it in the Apple Developer account and ensure the App Store Connect record matches exactly.
- [x] **SKU selected:** use permanent internal SKU `GYMAPP-IOS-2026` when creating the App Store Connect record.
- [ ] **Signing:** enable Automatically manage signing for Release, or create an App Store distribution certificate and matching provisioning profile. Archive must show no signing warnings.
- [x] **Version/build:** current source values are `2.1.0` (`5`). Increment the build before a replacement upload and never reuse a processed build number.
- [x] **Capabilities:** the project contains no ATT, HealthKit, Location, Camera, Microphone, Contacts, Push, Sign in with Apple, or IAP entitlement. Keep the signed target limited to capabilities actually used.
- [ ] **Agreements:** Account Holder accepts current agreements. If the app or IAP is paid, sign the Paid Apps Agreement and complete banking/tax details: [Apple agreements](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/).

Current upload minimum: builds uploaded after 2026-04-28 must use **Xcode 26 or later and the iOS 26 SDK or later**: [Apple SDK minimum](https://developer.apple.com/news/upcoming-requirements/?id=02032026a).

## 2. Final binary audit

- [x] `GymApp/Resources/PrivacyInfo.xcprivacy` is included in the GymApp target and was present in the built app on 2026-07-11. It declares first-party `UserDefaults` reason `CA92.1`, no tracking, and the server-collected Name, Email Address, Health, Fitness, Other User Content, User ID, and Garmin Device ID categories. Re-audit if code or SDKs change: [Required Reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
- [ ] Generate an Xcode privacy report and inspect every embedded framework/SDK. Update both the manifest and App Privacy answers if the final archive differs: [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files).
- [x] Source/archive audit found no analytics, advertising, IDFA access, fingerprinting, tracking domain, or ATT prompt. Re-audit if any dependency changes.
- [x] Source/archive audit found no protected-resource API references. Local rest-timer notifications use the system notification authorization flow but no Info.plist purpose string. If another protected resource is added, provide specific, localized purpose strings and just-in-time permission handling: [Protected resources](https://developer.apple.com/documentation/uikit/requesting-access-to-protected-resources).
- [x] Network traffic uses HTTPS/ATS and the production Supabase/support/privacy endpoints; no privileged secret is embedded in the app.
- [x] Supabase Auth uses `https://gymapptracker.com/` as Site URL. The redirect
  allowlist contains the Android, Web, and state-bound iOS HTTPS callbacks, the
  iOS custom-scheme fallback, and the previous GitHub callback for legacy
  clients/already-sent messages; Dashboard readback confirmed all five entries
  on 2026-07-11.
- [ ] Test signup and recovery PKCE exchange on the same physical device, an expired link, an unsolicited callback, and a callback containing raw access/refresh tokens (which the app must reject).
- [x] Production Supabase migrations `202607100001_create_leaderboard_public.sql`, `202607100002_harden_profile_reads.sql`, and `202607110003_fix_user_state_revision.sql` are deployed. A two-user production E2E run on 2026-07-11 verified sanitized leaderboard access, own-row RLS, anonymous/direct-delete denial, reporting, server-owned revisions, and cleanup. Evidence: [PRODUCTION_BACKEND_VERIFICATION.md](PRODUCTION_BACKEND_VERIFICATION.md).
- [x] No separate staging project is currently used. If one is introduced, apply the same three migrations in order and repeat the production verification runbook there.
- [ ] Complete the physical two-device client test: delete/edit on device A, then attempt a stale save from device B. The backend stale conditional `PATCH` and Android-style upsert contract passed on 2026-07-11, but the full device flow must still prove that removed workouts are not resurrected.
- [ ] Test Release on physical iPhone(s), supported iOS versions, dark/light appearance, Dynamic Type, VoiceOver basics, offline/slow network, fresh install, upgrade, login/logout, and account deletion.
- [ ] Test on an IPv6-only network and ensure backend services remain live during review.
- [ ] Run Analyze, unit/UI tests, Archive validation, and TestFlight internal/external testing. Resolve every crash and obvious UI defect.

## 3. Privacy and account deletion

- [x] The updated English/Ukrainian/Russian combined policy from [privacy-policy.html](privacy-policy.html) is published at `https://gymapptracker.com/privacy-policy.html`; HTTPS 200 and exact SHA-256 `a5c3dc078f30084cabdcbbbc3b043a6ceee5fb8be0339a1d5258cd10f75f9c04` were verified on 2026-07-20. It covers iOS, Android, browser/PWA, and optional Garmin features.
- [x] The updated English/Ukrainian/Russian [support.html](support.html) is published at `https://gymapptracker.com/support.html`; HTTPS 200 and exact SHA-256 `a22cd0d42fec7fc29bfa8e573ebe115d193fc352c473389bd07130253259ea14` were verified on 2026-07-20.
- [x] The support and privacy URLs in `GymAppConfiguration` resolve to the reviewed hosted content from `gh-pages` commit `f3edd58cbe1a255f1335c868ece6dafa7244b33c`. Enter the same URLs in App Store Connect.
- [x] Owner, support email, support URL, and privacy URL placeholders are resolved in both local HTML deliverables.
- [ ] In App Store Connect, answer App Privacy exactly as documented in `APP_PRIVACY.md`; reconcile it with the final binary, server, Supabase project, and all processors: [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).
- [x] Account deletion is exposed at **Exercises → Account → Delete Account** and uses irreversible confirmation: [Apple account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app).
- [x] Production `delete-account` version 1 is `ACTIVE` with `verify_jwt=true`. On 2026-07-11, two disposable users were hard-deleted and SQL verification found no remaining Auth identity, profile, state, Garmin, or report rows; production Storage contained no objects.
- [x] `deleteCurrentAccountAndData` clears the local account database, Supabase Keychain session, and account-specific preferences, then returns to signed-out state after successful server deletion.
- [ ] Repeat that complete cleanup path from the final signed build on a physical iPhone.
- [x] Sign in with Apple is not present, so token revocation is not applicable. If it is added later, implement revocation during deletion: [Apple TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple).

## 4. App Store Connect metadata and assets

- [ ] Create the iOS app record with the final Bundle ID, SKU, primary language, developer name, and category.
- [ ] Paste and proofread `METADATA.en-US.md` and `METADATA.uk.md`. Confirm every claim is visible in the submitted build.
- [x] Required URL values are ready and live: Privacy Policy `https://gymapptracker.com/privacy-policy.html`; Support `https://gymapptracker.com/support.html`. Enter them in the new App Store Connect record.
- [ ] Select the most accurate primary category (expected: Health & Fitness) and optional secondary category.
- [ ] Complete Content Rights. Upload written licenses/authorizations in Review attachments when needed.
- [ ] Complete the age-rating questionnaire honestly. `Unrated` cannot ship: [Age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating).
- [x] The asset catalog contains a square 1024×1024 RGB app icon with no transparency or pre-rounded corners; verified during final QA on 2026-07-11.
- [ ] Upload 1–10 screenshots that show real app use, not only splash/login. Provide current iPhone 6.9-inch assets (or accepted 6.5-inch fallback); if iPad is supported, provide required 13-inch assets: [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).
- [x] The 15 supplied screenshots contain fictional data, match the iOS UI, avoid Android imagery, and are appropriate for a 4+ storefront audience.
- [ ] Set Pricing and Availability, distribution countries, release method, and app tax category.
- [ ] Declare EU Digital Services Act trader/non-trader status; traders must verify displayed contact details: [DSA requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/).

## 5. Export compliance

- [ ] Re-run Apple's encryption questionnaire against the final app and every dependency: [Export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/).
- [x] The app uses only Apple-supplied URLSession/TLS and CryptoKit facilities and embeds no non-exempt crypto library; `ITSAppUsesNonExemptEncryption = NO` is present in the target Info.plist. Recheck the final dependency set: [Apple key reference](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).
- [x] No non-exempt encryption was found. If that changes, remove the NO declaration, upload required documentation, and use Apple's approved export-compliance code.
- [ ] Replace the Team ID placeholder in `ExportOptions.plist`, archive with the Release scheme, export/validate, and upload through Xcode Organizer or Transporter.

## 6. Review access — exact remaining manual fields

Complete these in App Store Connect and `REVIEW_NOTES.md` immediately before submission:

- [x] Review contact first name: `Eduard`
- [x] Review contact last name: `Martynenko`
- [ ] Review contact email: keep the real address in private App Store Connect notes
- [ ] Review contact phone including country code: `REPLACE_WITH_REVIEW_PHONE`
- [ ] Demo username/email: keep the real review account in `REVIEW_CREDENTIALS.private.md`
- [x] Demo password: stored only in ignored local file `REVIEW_CREDENTIALS.private.md`; paste it into App Store Connect immediately before submission.
- [x] OTP/2FA path or bypass: not applicable; the demo email/password account has no OTP or 2FA.
- [x] Demo account expiry: non-expiring and must remain active through review.
- [x] Required reviewer hardware, QR, sample data, region restrictions, or feature flags: none. Fictional workout history is preloaded in cloud state.
- [ ] Production backend status was verified on 2026-07-11; recheck immediately before submission and monitor it throughout review.
- [x] Account deletion path and confirmation text are implemented and the production server contract passed E2E; repeat once with the final signed physical-device build.

Apple requires a final, fully functional submission, complete metadata, live backend, and full reviewer access: [App Review submission guidance](https://developer.apple.com/app-store/review/guidelines/#before-you-submit) and [App Review information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).

## 7. Conditional gates

- [x] **Digital goods/subscriptions:** not present; the app is free with no IAP, subscriptions, paid unlocks, or external purchase links. Revisit if the business model changes: [App Review 3.1](https://developer.apple.com/app-store/review/guidelines/#business).
- [x] **Google/Facebook/other social login:** not present; only first-party email/password login is offered, so the Guideline 4.8 alternative-login rule is not triggered by this build.
- [x] **Leaderboard display names:** production filtering, Report/Block controls, fixed report reason, private queue, and RLS passed E2E. Queue ownership, daily monitoring, 24-hour target, actions, escalation, reporter feedback, and retention are documented in [MODERATION_RUNBOOK.md](MODERATION_RUNBOOK.md); the owner must keep the queue monitored throughout review and production.
- [x] **Personal data sent to third-party AI:** none. Smart Coach is deterministic on-device logic; no personal data is sent to an AI provider.
- [x] **Kids, medical, regulated health, gambling, finance, or crypto functionality:** none in this build. GymApp is a general workout log and makes no medical claim.

## 8. Submit

- [ ] Select the correct processed build and verify export compliance status is complete.
- [ ] Attach any required licenses/authorization documents.
- [ ] Paste final Review Notes and verify demo credentials from a clean device.
- [ ] Add the app version and any first IAP/subscription products for review, then submit.
- [ ] Monitor App Review messages and respond with exact reproduction steps and supporting evidence.
