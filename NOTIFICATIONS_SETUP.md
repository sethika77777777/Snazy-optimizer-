# Adding "come back to the app" push notifications to Snazy

Two parts, because this can't be done from the app alone:

1. **Client (Flutter)** — registers the device with Firebase Cloud
   Messaging and records "last opened" in Firestore. Already wired up
   in this bundle.
2. **Server (Cloud Function)** — the part that actually notices "this
   device hasn't opened the app in 3 days" and fires the push, the way
   Instagram/WhatsApp do it. This *has* to run on a server on a
   schedule — nothing running only inside the app can wake itself up
   days after the user closed it.

## What's changed / added here

- `pubspec.yaml` — added `firebase_core`, `firebase_messaging`,
  `cloud_firestore`, `flutter_local_notifications`, `uuid`.
- `android/app/google-services.json` — your uploaded file, copied in.
- `android/app/build.gradle` — applies the Google Services plugin.
- `android/app/src/main/AndroidManifest.xml` — notification permission
  + default channel/icon for FCM.
- `lib/services/notification_service.dart` — new. Requests notification
  permission, gets the FCM token, and upserts
  `devices/{deviceId} = { fcmToken, lastActiveAt }` into Firestore on
  launch and every time the app is resumed.
- `lib/main.dart` — initializes Firebase, calls the service above, and
  marks the device "active" on every resume.
- `functions/index.js` + `functions/package.json` — a scheduled Cloud
  Function (`sendReengagementPush`) that runs daily, finds devices
  inactive for 3+ days, and pushes one of a couple of reminder
  messages to them. It also prunes dead tokens.
- `firestore.rules` — locks the `devices` collection down to
  write-only from the client (the function reads it via the Admin SDK,
  which isn't subject to these rules).
- `firebase.json` — points the Firebase CLI at the `functions` folder.

⚠️ **One thing I couldn't verify:** the zip you sent doesn't include a
project-level `android/build.gradle` or `android/settings.gradle` — only
`android/app/build.gradle`. I've included versions of both that match a
current `flutter create` project. If your real project already has
these files, don't overwrite them — just add the one
`com.google.gms.google-services` line from each into your existing
copies (shown in the diffs below).

## Steps

### 1. Merge the files into your project
Copy everything from this bundle into your actual project, keeping the
same relative paths. If you already had `android/build.gradle` /
`android/settings.gradle`, just add:
- In `settings.gradle`'s `plugins {}` block:
  `id "com.google.gms.google-services" version "4.4.2" apply false`
- In `app/build.gradle`'s `plugins {}` block: `id "com.google.gms.google-services"`

### 2. Install the new packages
```bash
flutter pub get
```
If the resolver complains about `flutter_local_notifications` needing a
newer Flutter SDK than you have, run
`flutter pub add flutter_local_notifications` instead and let it pick a
version that fits your SDK.

### 3. Enable Cloud Messaging + Firestore in the Firebase console
Project **snazy-optimizer** (from your `google-services.json`):
- Firestore Database → Create database (production mode is fine, the
  rules file above locks it down).
- Cloud Messaging is on by default — nothing to enable there.

### 4. Deploy the scheduled function
```bash
npm install -g firebase-tools   # one-time
firebase login
cd functions && npm install && cd ..
firebase use snazy-optimizer
firebase deploy --only functions,firestore:rules
```
The first deploy will ask you to enable the Cloud Scheduler and
Cloud Build APIs (and billing — Cloud Functions v2 requires the
Blaze/pay-as-you-go plan, though a daily job like this stays in the
free tier for any realistic user count).

### 5. Test it
- Run the app once on a device/emulator — it should prompt for
  notification permission and create a `devices/{id}` doc in
  Firestore.
- To test the push without waiting 3 days: in the Firestore console,
  edit that doc's `lastActiveAt` to a timestamp 4+ days in the past,
  then in the Firebase console under **Functions**, find
  `sendReengagementPush` and use **Run now** (or wait for 10:00
  Asia/Colombo, or change the `schedule` string in `index.js`).

## Tuning
In `functions/index.js`:
- `INACTIVE_AFTER_DAYS` — how many days of silence before a nudge (3 by
  default).
- `COOLDOWN_DAYS` — minimum gap between repeat nudges to the same
  device.
- `NUDGE_MESSAGES` — the actual notification text; add more variants if
  you want it to rotate.
- `schedule` — a `every day HH:MM` string; change the time or switch to
  e.g. `every 12 hours` if you want two passes a day.
