# Snazy — v1.0.10
Gaming performance optimizer for Android 10+ (root & non-root modes)
Developer: SethikaDV

## What's real vs. what nothing can do (read this first)

Every feature below is implemented against a real Android API — there is
no simulated data or placebo animation pretending to do something it
doesn't. But a few things you originally described are **not possible on
any Android app**, by any developer, and I removed/adjusted them instead
of faking them:

| Requested | Reality | What Snazy does instead |
|---|---|---|
| Grant root to non-root users | No app can root a device from inside itself | Detects existing root (Magisk/su); non-root users get the honest standard-mode path |
| DirectX rendering option | DirectX doesn't exist on Android | Only OpenGL ES / Vulkan are offered |
| Kill other apps' background processes (non-root) | Blocked by Android since API 26 for privacy | Non-root "boost" whitelists the game from battery throttling via the real system settings screen, then launches it |
| Real per-app CPU/RAM stats (non-root) | Blocked since API 26 | Shows real **device-wide** CPU/RAM/battery instead |
| "Freeze" background apps (root) | — | Genuinely disables other apps via `pm disable-user` — they cannot run at all, foreground or background, until re-enabled |
| Restore | — | Runs `pm enable` on everything Snazy froze this session |
| Force a *different app's* graphics API | An app's renderer is compiled into it; nothing external can swap it | The picker sets a Snazy-side preference only; a game must itself support the chosen API |

## Project structure
```
lib/
  main.dart                     — entry point
  theme.dart                    — dark glass theme
  services/
    native_bridge.dart          — Dart <-> Kotlin platform channel
    apps_service.dart           — installed apps list (installed_apps plugin)
    optimizer_service.dart      — root freeze/restore + non-root boost logic + prefs
  screens/
    splash_screen.dart          — root detection on launch
    dashboard_screen.dart       — stats, boost button/animation, freeze toggle, graphics picker
    game_select_screen.dart     — pick the game to optimize
    safe_apps_screen.dart       — pick apps exempt from freeze
  widgets/
    glass_card.dart             — real BackdropFilter frosted glass
    stat_box.dart                — CPU/RAM/battery tile
android/app/src/main/kotlin/com/sethikadv/snazy/MainActivity.kt
    — root detection, su command execution, /proc/stat CPU read,
      ActivityManager RAM read, BatteryManager read, battery-opt intent
```

## Setup (do this locally — I can't run Flutter/Android SDK in this sandbox)

1. Install Flutter (stable channel) and Android SDK/NDK via Android Studio.
2. `flutter create --org com.sethikadv --project-name snazy .` in an empty
   folder is normally how you'd scaffold this — I've instead handed you
   the `lib/`, `android/app/src/main/...` files directly. Run:
   ```
   flutter create --platforms=android --org com.sethikadv .
   ```
   in this folder first if `android/` is missing the gradle wrapper /
   other boilerplate files (gradlew, settings.gradle, res/ icons, etc.),
   then drop these files back in — that generates the parts that are
   pure Flutter tooling boilerplate and don't affect app logic.
3. `flutter pub get`
4. Connect a device or emulator (Android 10+, i.e. API 29+) and run:
   ```
   flutter run
   ```
5. To test root features you need a **rooted physical device** or a
   rooted emulator image with Magisk — the Play Store / stock emulators
   are not rooted by default.

## Build a release APK
```
flutter build apk --release --split-per-abi
```
`--split-per-abi` keeps each APK small (separate arm64/armeabi builds)
which is what will actually keep you under the 150MB target on low-end
devices — a single universal "fat" APK bundling all architectures is
the main way Flutter apps blow past that size.

## Push to GitHub
```
git init
git add .
git commit -m "Snazy v1.0.10 - initial commit"
git branch -M main
git remote add origin https://github.com/<your-username>/snazy.git
git push -u origin main
```
Add a `.gitignore` for `/build/`, `.dart_tool/`, `.gradle/`, `local.properties`
before your first commit (a standard `flutter create` run generates one —
grab it from a fresh `flutter create` project if this repo doesn't have
one yet).

## Known limitations to test for on real hardware
- `/proc/stat` CPU reads are blocked by some OEM SELinux policies on
  Android 12+ (mainly some Xiaomi/Samsung builds) — the UI shows `--`
  rather than a fake number when this happens.
- `pm disable-user` on a small number of OEM skins requires the target
  package to not be the default launcher/dialer — Snazy already skips
  `android`, `com.google.android.gms`, and `com.android.*` to avoid
  bricking the freeze session, but test broadly before shipping.
- App icon, splash branding, and Play Store assets aren't included —
  add your own launcher icons under `android/app/src/main/res/mipmap-*`.
