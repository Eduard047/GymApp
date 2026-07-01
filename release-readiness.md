# GymApp release readiness

Last checked: 2026-06-30.

## Google Play

Publish difficulty: medium. The project is already an Android app, but a public Play release still needs store identity, signing, listing assets, privacy paperwork, and a release `.aab`.

Current project state:

- Phone module: `app`
- Wear OS module: `wear`
- Current Android package id: `com.setforge.gymapp`
- Target SDK: 36
- Release signing: expects local `keystore.properties`
- Play artifact script: `scripts/build-play-release-aab.ps1`

Before upload:

1. Create a Google Play Console developer account.
2. Keep the final package id stable. Play package ids cannot be changed after the first upload. Current id: `com.setforge.gymapp`.
3. Create a local upload keystore and `keystore.properties`.
4. Build the Play artifact:

```powershell
.\scripts\build-play-release-aab.ps1
```

Upload this file in Play Console:

```text
gymapp-play-release.aab
```

Play Console checklist:

- App name, short description, full description.
- App icon, feature graphic, phone screenshots.
- Privacy policy URL if cloud sync/account features are public.
- Data safety form for local workout data, Supabase sync/account data, and any diagnostics.
- Content rating questionnaire.
- Target audience.
- Closed testing track first, then production.

## Garmin Connect IQ

Publish difficulty: medium. The Connect IQ project exists and has a release export path, but the local machine still needs the Garmin SDK, device packages, and developer key configured.

Current project state:

- Garmin project: `garmin`
- Garmin app id: `A72A5B9F4E3D4E5A8B72C1D9F6123E40`
- Supported products in manifest: broad Garmin watch/wearable list from installed Connect IQ device packages
- Store artifact script: `scripts/build-garmin.ps1 -Release`

Before upload:

1. Create/sign in to a Garmin developer account.
2. Install Garmin Connect IQ SDK Manager.
3. Install the target device SDKs listed in `garmin/manifest.xml`.
4. Generate a Garmin developer key.
5. Set `GARMIN_DEVELOPER_KEY` to that key file.
6. Build the store export:

```powershell
.\\scripts\\build-garmin.ps1 -Release
```

Upload this file in the Connect IQ developer portal:

```text
garmin\build\gymapp-fenix8solar47mm.iq
```

Connect IQ checklist:

- App name, description, categories.
- Screenshots for supported watch models.
- Compatible devices matching the manifest.
- Privacy policy URL if the app sends workout data to the phone/cloud.
- Clear notes that the Android companion app and Garmin Connect pairing are required for sync.

## Local blockers found

- `keystore.properties` is missing, so Play release signing cannot run yet.
- `GARMIN_DEVELOPER_KEY` is not set.
- `monkeyc` was not found in PATH during the local check.

