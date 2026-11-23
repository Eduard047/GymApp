# GymApp Android — Play Console privacy answers for optional analytics

Source of truth for what to change in Play Console when the Android app ships optional Google Analytics for Firebase (Google Ads conversion measurement). Covers only what this feature changes; no earlier Data safety record exists in the repository, so answers for data types that already existed (account, health and fitness, user content, push identifiers, and so on) are not restated here and must be kept as they are. The iPhone app and browser version do not collect analytics; see `ios/GymApp-iOS/AppStore/APP_PRIVACY.md`.

Reference: Play's definitions — *collect* = data sent off the device (including by an SDK); *share* = transfer to a third party, where a service provider processing only on your behalf is generally not sharing; *optional* = the user can choose whether to provide it and still use the app. Re-check against the current form at submission: [Data safety help](https://support.google.com/googleplay/android-developer/answer/10787469).

## What the feature does (facts the answers rest on)

- Asked once at first launch; off by default; changeable in Settings. If declined, nothing is collected.
- If allowed: app-instance ID, Android advertising ID, device/app info, approximate location derived from IP by Google, and two events: `sign_up` (method=email) and `first_workout`. No email, name, workout content, or health data.
- Consent Mode: `analytics_storage`, `ad_storage`, `ad_user_data` granted; `ad_personalization` denied. Purpose: measure which Google Ads campaigns bring app users and optimize them.
- On revoke: collection stops and the app resets its analytics data and identifier.
- Retention: Google Analytics setting, stated publicly as up to 14 months.

## Data safety form — changes

Top-level questions stay: collects/shares required user data types = **Yes**; data encrypted in transit = **Yes** (HTTPS); users can request data deletion = unchanged (account deletion already offered).

For each type below add the listed answer. If the type is already declared for another purpose, keep the existing purposes and add the new ones.

| Play category → type | Collected | Shared | Optional | Purposes to add |
|---|---|---|---|---|
| App activity → **App interactions** (`sign_up`, `first_workout`, plus Firebase automatic events such as first open and session start) | Yes | No (see uncertain point 1) | **Optional** (user can choose) | Analytics; Advertising or marketing |
| Device or other IDs → **Device or other IDs** (app-instance ID, Android advertising ID) | Yes | No (see uncertain point 1) | **Optional** | Analytics; Advertising or marketing |
| Location → **Approximate location** (derived from IP by Google) | Yes (see uncertain point 2) | No (see uncertain point 1) | **Optional** | Analytics; Advertising or marketing |

Not collected by the analytics feature, so do not add these for the analytics purposes: Personal info (email, name), Precise location, Health and fitness data, workout content, Financial info, Contacts, Photos/videos, Audio, Web browsing, Messages. Health and fitness data is collected by other features (Health Connect import and the Wear OS app) and is declared for App functionality; see "Health Connect import and Wear OS heart rate" below.

Ephemeral processing does not apply: the data is stored by Google Analytics and used for advertising measurement.

## Advertising ID declaration (App content)

- Does your app use advertising ID? **Yes**.
- Purposes to select: **Analytics** and **Advertising or marketing** (conversion measurement for Google Ads).
- The manifest must keep `com.google.android.gms.permission.AD_ID`. The Firebase Analytics library adds it through manifest merge; verify it is present in the merged manifest of the release AAB (otherwise the advertising ID is returned as zeros and the declaration would not match the app).
- The app must not be declared as designed for children. The privacy policy says it is not directed to children under 13.

## Privacy policy

Play Console privacy policy URL stays `https://gymapptracker.com/privacy-policy.html`. The updated policy (section 6, "Optional Android analytics and ad measurement", English/Ukrainian/Russian) must be live on that URL before the Android release that contains analytics reaches users. Source: `ios/GymApp-iOS/AppStore/privacy-policy.html`, published through the `gh-pages` branch.

## Firebase / Google Ads console settings to match the answers (not Play Console)

1. Google Analytics → Admin → Data collection and retention: event data retention **14 months** (the policy text says up to 14 months).
2. Google Analytics → Admin → Data sharing settings: turn **off** sharing with Google products and services, benchmarking, technical support, and account specialists unless you are prepared to declare the data as shared.
3. Do not enable Google signals / ad personalization for this property; the app denies `ad_personalization` and the policy says ads are not personalized from this data.
4. Link the Firebase project to the Google Ads account and import `sign_up` and `first_workout` as conversions.

## Uncertain points — confirm before submitting

1. **Shared vs not shared.** Google generally treats a service provider that processes data only for you as not sharing. Google Analytics data used by Google for its own purposes (the data sharing settings above, Google signals, or cross-customer advertising profiles) would count as sharing. The table assumes the console settings above are off. If any is on, change "Shared" to Yes for all three rows.
2. **Approximate location.** The app does not request location permission; Google derives it from the IP address on its servers. Google's guidance on whether this must be declared as "collected" is not confirmed here. The conservative answer (declare it) is used and matches the privacy policy.
3. **Device and app info** (model, OS version, app version, language) are collected by Analytics. No exact Play type is confirmed here; the nearest are Device or other IDs and App info and performance → Other app performance data. Check Google's current Analytics data-disclosure guidance for Firebase and add App info and performance if it lists it.
4. **Deletion question.** Account deletion removes the Supabase account but cannot delete data already held in Google Analytics, which is not tied to an account and expires with the retention setting. Confirm how Play wants this answered for the new data types; the privacy policy says the data is kept up to 14 months after collection.
5. **Existing answers.** There is no earlier Data safety record in the repository. Also note that the Android manifest declares `RECORD_AUDIO` (voice workout draft), while the privacy policy says phone apps do not ask for microphone access; reconcile the policy and the existing Data safety answer separately.
6. **Android app strings.** `account_privacy_caption` in `app/src/main/res/values*/strings.xml` says GymApp has no advertising, cross-app tracking, or sale of personal data. This should be reviewed by the app code owner now that optional analytics exists.

## Optional tips (Google Play Billing)

The Profile > Help > "Support the developer" screen sells six optional, consumable in-app products (`support_tip_1`, `support_tip_2`, `support_tip_3`, `support_tip_5`, `support_tip_10`, `support_tip_20`; contract in `shared/support-tips-v1.json`). Nothing is unlocked or changed by a purchase.

- Payments are processed entirely by Google Play. The app never receives or stores card or other payment details, has no server-side purchase validation, and does not send, log or store purchase tokens (they are used only to consume the purchase).
- The app adds no new data collection or sharing of its own, so no new Data safety data type is expected. **Check in Play Console:** whether the "Financial info > Purchase history" type should be answered for in-app purchases made through Google Play Billing (Google processes it; the app does not collect it). Treat this as unconfirmed until reviewed in the Data safety form.
- Play Console steps (not done by code): create the six in-app products with the ids above, type consumable / managed one-time product, price roughly 0.99 / 1.99 / 2.99 / 4.99 / 9.99 / 19.99 USD, status Active; add the license testers; the first release containing the Billing library must be uploaded to a testing track before the products can load.
- The privacy policy gets one short paragraph about optional tips (see `ios/GymApp-iOS/AppStore/privacy-policy.html`); it must be live before the Android release that contains the tip screen.

## Health Connect import and Wear OS heart rate

Two features handle health data. Neither is used for advertising or analytics, and nothing from them is sent to Google Analytics.

- **Health Connect import (phone app).** Off until the user connects Health Connect in the app and grants access. Read-only: the app reads exercise sessions, heart rate, and total calories burned and saves them as workouts in the user's own GymApp workouts. It never writes to Health Connect. Manifest permissions: `android.permission.health.READ_EXERCISE`, `android.permission.health.READ_HEART_RATE`, `android.permission.health.READ_TOTAL_CALORIES_BURNED`.
- **Wear OS app (same applicationId).** During a workout the user starts on the watch, it reads heart rate on the watch through Health Services and sends the average and maximum heart rate with the workout to the user's own phone over the Wearable Data Layer. Manifest permissions: `android.permission.BODY_SENSORS` / `android.permission.health.READ_HEART_RATE`, `android.permission.ACTIVITY_RECOGNITION`, `android.permission.FOREGROUND_SERVICE_HEALTH` (foreground service type `health`), `android.permission.WAKE_LOCK`.

Data safety form: keep the existing Health and fitness answers and make sure they cover this data.

| Play category → type | Collected | Shared | Optional | Purposes |
|---|---|---|---|---|
| Health and fitness → **Health info** (heart rate) and **Fitness info** (exercise sessions, calories) | Yes | No | **Optional** (only after the user connects Health Connect or starts a workout on the watch) | App functionality |

- Linked to the user only through their own synchronized workouts. Not shared, not used for advertising or marketing, not used for analytics.
- **Play Console (not done by code):** complete the Health Connect permissions declaration (App content → Health apps) for the three read permissions above before the release that contains the import; the privacy policy must describe the import, which `ios/GymApp-iOS/AppStore/privacy-policy.html` now does in English/Ukrainian/Russian and which must be live first.
- **Check in Play Console:** whether the Wear OS release also needs the foreground service (health) declaration and a body-sensors permission declaration, and the exact Health and fitness type names in the current form. Treat these as unconfirmed until reviewed there.
